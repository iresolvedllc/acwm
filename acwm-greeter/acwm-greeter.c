/*
 * acwm-greeter — greetd greeter client for acwm sessions.
 *
 * House-style standalone client next to acwm-launch: a layer-shell overlay
 * that talks to greetd over $GREETD_SOCK (JSON, newline framed), renders a
 * minimal username/password prompt with pangocairo, and hands the
 * authenticated session back to greetd via start_session.
 *
 * It runs as a normal client of the acwm greeter session (the compositor
 * itself is the greeter UI host; see docs/configuration/greetd.md for the
 * greetd config and the greeter user's acwm config).
 *
 * Environment:
 *   GREETD_SOCK        greetd IPC socket (set by greetd)
 *   ACWM_GREETER_FONT  pango font description (default "sans 11")
 *
 * Keys: type, Enter to continue, Escape cancels the current auth attempt,
 * Ctrl+U clears the field.
 */
#define _GNU_SOURCE

#include <cairo.h>
#include <errno.h>
#include <fcntl.h>
#include <pango/pangocairo.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include <cjson/cJSON.h>
#include <xkbcommon/xkbcommon-names.h>
#include <xkbcommon/xkbcommon.h>
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#define GREETER_NAMESPACE "acwm-greeter"

/* visual constants */
#define GREETER_PAD 18
#define GREETER_PANEL_W 480
#define GREETER_INPUT_H 46
#define GREETER_ROW_H 34
#define GREETER_MAX_INPUT 128

/* palette (RGBA8888) */
#define GREETER_COL_BACKDROP 0x050505b8
#define GREETER_COL_PANEL 0x111318f2
#define GREETER_COL_BORDER 0x2a2e37ff
#define GREETER_COL_TEXT 0xd7dae2ff
#define GREETER_COL_DIM 0x8a8f9cff
#define GREETER_COL_ACCENT 0x7aa2f7ff
#define GREETER_COL_ERROR 0xf7768eff

enum greeter_ui_state {
	ST_USERNAME,
	ST_PASSWORD,
	ST_WAIT, /* waiting for greetd (authenticating) */
};

enum greeter_auth_kind {
	AUTH_KIND_NONE = 0,
	AUTH_KIND_ERROR,
	AUTH_KIND_INFO,
	AUTH_KIND_AUTH_MSG,
};

static void rgba_to_cairo(uint32_t color, double *r, double *g, double *b,
						  double *a) {
	*r = ((color >> 24) & 0xff) / 255.0;
	*g = ((color >> 16) & 0xff) / 255.0;
	*b = ((color >> 8) & 0xff) / 255.0;
	*a = (color & 0xff) / 255.0;
}

struct greeter_buffer {
	struct wl_buffer *wl_buffer;
	void *data;
	size_t size;
	int width, height;
	struct wl_buffer_listener release;
};

struct greeter_output {
	struct wl_output *wl_output;
	uint32_t global_name;
	int32_t scale;
	struct wl_list link;
};

static struct greeter_state {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct zwlr_layer_shell_v1 *layer_shell;
	struct wl_seat *seat;
	struct wl_keyboard *keyboard;

	struct wl_list outputs;
	int32_t scale;

	struct wl_surface *surface;
	struct zwlr_layer_surface_v1 *layer_surface;

	uint32_t width, height;
	bool configured;

	struct xkb_context *xkb_ctx;
	struct xkb_keymap *xkb_keymap;
	struct xkb_state *xkb_state;

	char *font;

	int greetd_fd;
	char greetd_buf[8192];
	size_t greetd_len;

	enum greeter_ui_state state;
	char username[GREETER_MAX_INPUT];
	size_t username_len;
	char password[GREETER_MAX_INPUT];
	size_t password_len;

	char message[512];
	enum greeter_auth_kind message_kind;

	bool running;
} m;

static void greeter_refresh(void);

/* ------------------------------------------------------------------ */
/* wayland buffers + drawing helpers                                   */
/* ------------------------------------------------------------------ */

static void handle_buffer_release(void *data, struct wl_buffer *wl_buffer) {
	struct greeter_buffer *buffer = data;
	wl_buffer_destroy(buffer->wl_buffer);
	munmap(buffer->data, buffer->size);
	free(buffer);
}

static struct greeter_buffer *greeter_buffer_create(int width, int height) {
	int stride = width * 4;
	int size = stride * height;

	int fd = memfd_create(GREETER_NAMESPACE, MFD_CLOEXEC);
	if (fd < 0)
		return NULL;
	if (ftruncate(fd, size) < 0) {
		close(fd);
		return NULL;
	}

	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		close(fd);
		return NULL;
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(m.shm, fd, size);
	struct wl_buffer *wl_buffer = wl_shm_pool_create_buffer(
		pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);

	if (!wl_buffer) {
		munmap(data, size);
		return NULL;
	}

	struct greeter_buffer *buffer = calloc(1, sizeof(*buffer));
	if (!buffer) {
		wl_buffer_destroy(wl_buffer);
		munmap(data, size);
		return NULL;
	}
	buffer->wl_buffer = wl_buffer;
	buffer->data = data;
	buffer->size = size;
	buffer->width = width;
	buffer->height = height;
	buffer->release.release = handle_buffer_release;
	wl_buffer_add_listener(wl_buffer, &buffer->release, buffer);
	return buffer;
}

static PangoLayout *greeter_layout(cairo_t *cr, const char *text) {
	PangoLayout *layout = pango_cairo_create_layout(cr);
	PangoFontDescription *desc =
		pango_font_description_from_string(m.font);
	pango_layout_set_font_description(layout, desc);
	pango_font_description_free(desc);
	pango_layout_set_text(layout, text ? text : "", -1);
	pango_layout_set_single_paragraph_mode(layout, true);
	pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
	return layout;
}

static void greeter_draw_text(cairo_t *cr, const char *text, double x,
							  double y, uint32_t color) {
	double r, g, b, a;
	rgba_to_cairo(color, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	PangoLayout *layout = greeter_layout(cr, text);
	cairo_move_to(cr, x, y);
	pango_cairo_show_layout(cr, layout);
	g_object_unref(layout);
}

static int greeter_text_width(cairo_t *cr, const char *text) {
	PangoLayout *layout = greeter_layout(cr, text);
	int w = 0;
	pango_layout_get_pixel_size(layout, &w, NULL);
	g_object_unref(layout);
	return w;
}

/* ------------------------------------------------------------------ */
/* greetd IPC                                                          */
/* ------------------------------------------------------------------ */

/* Greetd frames are one JSON object per line. Returns a malloc'd line
 * (without the newline) or NULL. */
static char *greetd_readline(void) {
	for (;;) {
		char *nl = memchr(m.greetd_buf, '\n', m.greetd_len);
		if (nl) {
			size_t line_len = (size_t)(nl - m.greetd_buf);
			char *line = malloc(line_len + 1);
			if (!line)
				return NULL;
			memcpy(line, m.greetd_buf, line_len);
			line[line_len] = '\0';
			memmove(m.greetd_buf, nl + 1,
					m.greetd_len - line_len - 1);
			m.greetd_len -= line_len + 1;
			return line;
		}

		if (m.greetd_len >= sizeof(m.greetd_buf) - 1) {
			fprintf(stderr, "acwm-greeter: greetd line too long\n");
			return NULL;
		}

		ssize_t n = recv(m.greetd_fd, m.greetd_buf + m.greetd_len,
						 sizeof(m.greetd_buf) - 1 - m.greetd_len, 0);
		if (n <= 0) {
			fprintf(stderr, "acwm-greeter: greetd closed: %s\n",
					n < 0 ? strerror(errno) : "eof");
			return NULL;
		}
		m.greetd_len += (size_t)n;
	}
}

static cJSON *greetd_exchange(const char *req) {
	size_t len = strlen(req);
	char *buf = malloc(len + 2);
	if (!buf)
		return NULL;
	memcpy(buf, req, len);
	buf[len] = '\n';
	buf[len + 1] = '\0';

	size_t off = 0;
	while (off <= len) {
		ssize_t n = send(m.greetd_fd, buf + off, len + 1 - off,
						 MSG_NOSIGNAL);
		if (n <= 0) {
			fprintf(stderr, "acwm-greeter: greetd send failed: %s\n",
					strerror(errno));
			free(buf);
			return NULL;
		}
		off += (size_t)n;
	}
	free(buf);

	char *line = greetd_readline();
	if (!line)
		return NULL;

	cJSON *json = cJSON_Parse(line);
	if (!json) {
		fprintf(stderr, "acwm-greeter: invalid greetd reply: %s\n", line);
	}
	free(line);
	return json;
}

static const char *greetd_str(const cJSON *obj, const char *key) {
	cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
	return cJSON_IsString(v) && v->valuestring ? v->valuestring : NULL;
}

static bool greetd_bool(const cJSON *obj, const char *key) {
	cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
	return cJSON_IsBool(v) && cJSON_IsTrue(v);
}

/* Handles one greetd response to create_session/post_auth_message_response.
 * Returns: 0 = advance (needs input), 1 = authenticated, -1 = fatal. */
static int greetd_handle_auth_response(cJSON *resp) {
	const char *type = greetd_str(resp, "type");
	if (!type) {
		snprintf(m.message, sizeof(m.message),
				 "greetd: malformed reply");
		m.message_kind = AUTH_KIND_ERROR;
		return -1;
	}

	if (strcmp(type, "success") == 0)
		return 1;

	if (strcmp(type, "auth_message") == 0) {
		const char *msg = greetd_str(resp, "auth_message");
		const char *kind = greetd_str(resp, "auth_message_type");
		bool wants_response = greetd_bool(resp, "auth_response");

		snprintf(m.message, sizeof(m.message), "%s",
				 msg ? msg : "Authentication required");
		m.message_kind = AUTH_KIND_AUTH_MSG;

		if (!wants_response) {
			/* informational/error message: acknowledge immediately */
			cJSON *ack = cJSON_CreateObject();
			cJSON_AddStringToObject(ack, "type",
									"post_auth_message_response");
			cJSON_AddStringToObject(ack, "response", "");
			cJSON *reply = greetd_exchange(cJSON_PrintUnformatted(ack));
			cJSON_Delete(ack);
			if (!reply)
				return -1;
			int r = greetd_handle_auth_response(reply);
			cJSON_Delete(reply);
			return r;
		}

		m.state = ST_PASSWORD;
		m.password_len = 0;
		m.password[0] = '\0';
		if (kind && strcmp(kind, "secret") == 0)
			m.message_kind = AUTH_KIND_AUTH_MSG;
		else
			m.message_kind = AUTH_KIND_INFO;
		return 0;
	}

	if (strcmp(type, "error") == 0) {
		const char *err_type = greetd_str(resp, "error_type");
		const char *desc = greetd_str(resp, "description");
		snprintf(m.message, sizeof(m.message), "%s",
				 desc ? desc : "authentication failed");
		m.message_kind = AUTH_KIND_ERROR;

		if (err_type && strcmp(err_type, "auth_error") == 0) {
			/* wrong password/username: start over */
			m.state = ST_USERNAME;
			m.username_len = 0;
			m.username[0] = '\0';
			m.password_len = 0;
			m.password[0] = '\0';
			return 0;
		}
		return -1; /* protocol error: fatal for this greeter run */
	}

	snprintf(m.message, sizeof(m.message), "greetd: unknown reply '%s'",
			 type);
	m.message_kind = AUTH_KIND_ERROR;
	return -1;
}

static bool greetd_start_session(void) {
	cJSON *req = cJSON_CreateObject();
	cJSON_AddStringToObject(req, "type", "start_session");
	cJSON *env = cJSON_CreateArray();
	cJSON_AddItemToArray(env, cJSON_CreateString("XDG_SESSION_TYPE=wayland"));
	cJSON_AddItemToArray(env,
						 cJSON_CreateString("XDG_CURRENT_DESKTOP=acwm"));
	cJSON_AddItemToArray(env,
						 cJSON_CreateString("XDG_SESSION_DESKTOP=acwm"));
	cJSON_AddItemToObject(req, "env", env);

	cJSON *resp = greetd_exchange(cJSON_PrintUnformatted(req));
	cJSON_Delete(req);
	if (!resp)
		return false;

	const char *type = greetd_str(resp, "type");
	bool ok = type && strcmp(type, "success") == 0;
	if (!ok) {
		const char *desc = greetd_str(resp, "description");
		snprintf(m.message, sizeof(m.message), "%s",
				 desc ? desc : "failed to start session");
		m.message_kind = AUTH_KIND_ERROR;
	}
	cJSON_Delete(resp);
	return ok;
}

/* Full auth attempt from the current username. */
static void greetd_authenticate(void) {
	cJSON *req = cJSON_CreateObject();
	cJSON_AddStringToObject(req, "type", "create_session");
	cJSON_AddStringToObject(req, "username", m.username);
	cJSON *resp = greetd_exchange(cJSON_PrintUnformatted(req));
	cJSON_Delete(req);
	if (!resp) {
		snprintf(m.message, sizeof(m.message), "greetd unreachable");
		m.message_kind = AUTH_KIND_ERROR;
		m.state = ST_USERNAME;
		greeter_refresh();
		return;
	}

	int r = greetd_handle_auth_response(resp);
	cJSON_Delete(resp);

	if (r == 1) {
		if (greetd_start_session()) {
			m.running = false;
			greeter_refresh();
			return;
		}
		m.state = ST_USERNAME;
		greeter_refresh();
		return;
	}
	if (r < 0) {
		/* fatal: reset to username with the error visible */
		m.state = ST_USERNAME;
	}
	greeter_refresh();
}

static void greetd_post_response(const char *response) {
	cJSON *req = cJSON_CreateObject();
	cJSON_AddStringToObject(req, "type", "post_auth_message_response");
	cJSON_AddStringToObject(req, "response", response);
	cJSON *resp = greetd_exchange(cJSON_PrintUnformatted(req));
	cJSON_Delete(req);
	if (!resp) {
		snprintf(m.message, sizeof(m.message), "greetd unreachable");
		m.message_kind = AUTH_KIND_ERROR;
		m.state = ST_USERNAME;
		greeter_refresh();
		return;
	}

	int r = greetd_handle_auth_response(resp);
	cJSON_Delete(resp);

	if (r == 1) {
		if (greetd_start_session()) {
			m.running = false;
			greeter_refresh();
			return;
		}
		m.state = ST_USERNAME;
		greeter_refresh();
		return;
	}
	if (r < 0)
		m.state = ST_USERNAME;
	greeter_refresh();
}

static bool greetd_connect(void) {
	const char *sock = getenv("GREETD_SOCK");
	if (!sock || !*sock) {
		fprintf(stderr,
				"acwm-greeter: GREETD_SOCK is not set. Start this client "
				"from a greetd greeter session.\n");
		return false;
	}

	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return false;

	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	if (strlen(sock) >= sizeof(addr.sun_path) ||
		connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		fprintf(stderr, "acwm-greeter: cannot connect to greetd: %s\n",
				strerror(errno));
		close(fd);
		return false;
	}

	m.greetd_fd = fd;
	return true;
}

static void greetd_cancel(void) {
	cJSON *req = cJSON_CreateObject();
	cJSON_AddStringToObject(req, "type", "cancel_session");
	cJSON *resp = greetd_exchange(cJSON_PrintUnformatted(req));
	cJSON_Delete(resp);
}

/* ------------------------------------------------------------------ */
/* rendering                                                           */
/* ------------------------------------------------------------------ */

static void greeter_render(void) {
	if (!m.configured || !m.width || !m.height)
		return;

	struct greeter_buffer *buffer =
		greeter_buffer_create((int)m.width, (int)m.height);
	if (!buffer)
		return;

	cairo_surface_t *surface = cairo_image_surface_create_for_data(
		buffer->data, CAIRO_FORMAT_ARGB32, (int)m.width, (int)m.height,
		(int)m.width * 4);
	cairo_t *cr = cairo_create(surface);

	double r, g, b, a;

	/* backdrop */
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
	rgba_to_cairo(GREETER_COL_BACKDROP, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_rectangle(cr, 0, 0, m.width, m.height);
	cairo_fill(cr);

	/* centered panel */
	uint32_t panel_h = GREETER_PAD + GREETER_INPUT_H + GREETER_ROW_H * 2 +
					   GREETER_PAD;
	uint32_t panel_w = GREETER_PANEL_W;
	uint32_t panel_x = (m.width - panel_w) / 2;
	uint32_t panel_y = (m.height - panel_h) / 2;

	rgba_to_cairo(GREETER_COL_PANEL, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_rectangle(cr, panel_x, panel_y, panel_w, panel_h);
	cairo_fill(cr);
	rgba_to_cairo(GREETER_COL_BORDER, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_rectangle(cr, panel_x, panel_y, panel_w, panel_h);
	cairo_set_line_width(cr, 1.0);
	cairo_stroke(cr);

	double tx = panel_x + GREETER_PAD;
	double ty = panel_y + GREETER_PAD;

	/* title + brand */
	greeter_draw_text(cr, "acwm", tx, ty, GREETER_COL_ACCENT);

	/* prompt */
	const char *prompt =
		m.state == ST_PASSWORD ? "Password:" : "Username:";
	double pw = greeter_text_width(cr, prompt);
	double in_x = tx + pw + 14;
	double in_y = ty + GREETER_ROW_H;

	/* input row background */
	rgba_to_cairo(GREETER_COL_BORDER, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_rectangle(cr, tx, ty + GREETER_ROW_H, panel_w - 2 * GREETER_PAD,
					GREETER_INPUT_H);
	cairo_fill(cr);

	greeter_draw_text(cr, prompt, tx, in_y + (GREETER_INPUT_H - 16) / 2.0,
					  GREETER_COL_DIM);

	/* input text (password masked) */
	char shown[GREETER_MAX_INPUT * 2];
	if (m.state == ST_PASSWORD) {
		size_t shown_len = 0;
		for (size_t i = 0; i < m.password_len && shown_len + 2 < sizeof(shown);
			 i++) {
			shown[shown_len++] = '*';
		}
		shown[shown_len] = '\0';
	} else {
		snprintf(shown, sizeof(shown), "%s", m.username);
	}

	char *display_text = shown;
	if (!*display_text)
		display_text = m.state == ST_PASSWORD ? "" : "type your username…";
	greeter_draw_text(cr, display_text, in_x,
					  in_y + (GREETER_INPUT_H - 16) / 2.0,
					  GREETER_COL_TEXT);

	/* block cursor */
	double text_w = greeter_text_width(cr, display_text);
	if (strcmp(display_text, "type your username…") != 0) {
		rgba_to_cairo(GREETER_COL_ACCENT, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r, g, b, a);
		cairo_rectangle(cr, in_x + text_w + 2.0,
						in_y + (GREETER_INPUT_H - 16) / 2.0, 2.0, 16);
		cairo_fill(cr);
	}

	/* message line */
	const char *msg = m.message[0] ? m.message : "";
	if (msg[0]) {
		uint32_t color = GREETER_COL_DIM;
		if (m.message_kind == AUTH_KIND_ERROR)
			color = GREETER_COL_ERROR;
		else if (m.message_kind == AUTH_KIND_AUTH_MSG)
			color = GREETER_COL_TEXT;
		greeter_draw_text(cr, msg, tx,
						  panel_y + GREETER_PAD + GREETER_INPUT_H +
							  GREETER_ROW_H + 8,
						  color);
	} else if (m.state == ST_WAIT) {
		greeter_draw_text(cr, "Authenticating…", tx,
						  panel_y + GREETER_PAD + GREETER_INPUT_H +
							  GREETER_ROW_H + 8,
						  GREETER_COL_DIM);
	}

	/* hints */
	greeter_draw_text(
		cr, "Enter continue   Esc cancel   Ctrl+U clear", tx,
		panel_y + panel_h - 24, GREETER_COL_DIM);

	cairo_destroy(cr);
	cairo_surface_flush(surface);

	wl_surface_set_buffer_scale(m.surface, m.scale);
	wl_surface_attach(m.surface, buffer->wl_buffer, 0, 0);
	wl_surface_damage_buffer(m.surface, 0, 0, m.width * m.scale,
							 m.height * m.scale);
	wl_surface_commit(m.surface);

	cairo_surface_destroy(surface);
}

static void greeter_refresh(void) {
	greeter_render();
}

/* ------------------------------------------------------------------ */
/* input                                                               */
/* ------------------------------------------------------------------ */

static void greeter_input_append(char *buf, size_t *len, size_t max,
								 const char *text, size_t n) {
	if (*len + n >= max)
		return;
	memcpy(buf + *len, text, n);
	*len += n;
	buf[*len] = '\0';
}

static void greeter_input_backspace(char *buf, size_t *len) {
	if (*len == 0)
		return;
	while (*len > 0 && (buf[--*len] & 0xC0) == 0x80)
		;
	buf[*len] = '\0';
}

static void greeter_submit(void) {
	if (m.state == ST_USERNAME) {
		if (m.username_len == 0)
			return;
		m.state = ST_WAIT;
		m.message[0] = '\0';
		greeter_refresh();
		greetd_authenticate();
	} else if (m.state == ST_PASSWORD) {
		m.state = ST_WAIT;
		greeter_refresh();
		greetd_post_response(m.password);
		memset(m.password, 0, sizeof(m.password));
	}
}

static void greeter_cancel_auth(void) {
	if (m.state != ST_USERNAME) {
		greetd_cancel();
		m.state = ST_USERNAME;
		m.password_len = 0;
		m.password[0] = '\0';
		m.message[0] = '\0';
	}
	greeter_refresh();
}

static bool greeter_mod_active(const char *name) {
	if (!m.xkb_state)
		return false;
	return xkb_state_mod_name_is_active(m.xkb_state, name,
										XKB_STATE_MODS_EFFECTIVE) > 0;
}

static void greeter_handle_key(xkb_keysym_t sym) {
	if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
		if (m.state != ST_WAIT)
			greeter_submit();
		return;
	}
	if (sym == XKB_KEY_Escape) {
		greeter_cancel_auth();
		return;
	}
	if (sym == XKB_KEY_BackSpace) {
		char *buf = m.state == ST_PASSWORD ? m.password : m.username;
		size_t *len = m.state == ST_PASSWORD ? &m.password_len
											 : &m.username_len;
		greeter_input_backspace(buf, len);
		greeter_refresh();
		return;
	}

	if (greeter_mod_active(XKB_MOD_NAME_CTRL)) {
		if (sym == XKB_KEY_u) {
			char *buf = m.state == ST_PASSWORD ? m.password : m.username;
			size_t *len = m.state == ST_PASSWORD ? &m.password_len
												 : &m.username_len;
			*len = 0;
			buf[0] = '\0';
			greeter_refresh();
		}
		return;
	}

	if (m.state == ST_WAIT)
		return;

	char buffer[8] = {0};
	int n = xkb_keysym_to_utf8(sym, buffer, sizeof(buffer));
	if (n > 0) {
		if (m.state == ST_PASSWORD)
			greeter_input_append(m.password, &m.password_len,
								 sizeof(m.password), buffer, (size_t)n - 1);
		else
			greeter_input_append(m.username, &m.username_len,
								 sizeof(m.username), buffer, (size_t)n - 1);
		greeter_refresh();
	}
}

/* ------------------------------------------------------------------ */
/* wayland events                                                      */
/* ------------------------------------------------------------------ */

static void greeter_keyboard_keymap(void *data, struct wl_keyboard *keyboard,
									uint32_t format, int32_t fd,
									uint32_t size) {
	(void)data;
	(void)keyboard;
	if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
		close(fd);
		return;
	}
	char *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (map == MAP_FAILED)
		return;

	if (m.xkb_keymap)
		xkb_keymap_unref(m.xkb_keymap);
	m.xkb_keymap = xkb_keymap_new_from_buffer(m.xkb_ctx, map, size,
											  XKB_KEYMAP_FORMAT_TEXT_V1,
											  XKB_KEYMAP_COMPILE_NO_FLAGS);
	munmap(map, size);

	if (m.xkb_state)
		xkb_state_unref(m.xkb_state);
	m.xkb_state = m.xkb_keymap ? xkb_state_new(m.xkb_keymap) : NULL;
}

static void greeter_keyboard_enter(void *data, struct wl_keyboard *keyboard,
								   uint32_t serial, struct wl_surface *surface,
								   struct wl_array *keys) {
	(void)data;
	(void)keyboard;
	(void)serial;
	(void)surface;
	(void)keys;
}

static void greeter_keyboard_leave(void *data, struct wl_keyboard *keyboard,
								   uint32_t serial,
								   struct wl_surface *surface) {
	(void)data;
	(void)keyboard;
	(void)serial;
	(void)surface;
}

static void greeter_keyboard_key(void *data, struct wl_keyboard *keyboard,
								 uint32_t serial, uint32_t time, uint32_t key,
								 uint32_t state) {
	(void)data;
	(void)keyboard;
	if (state != WL_KEYBOARD_KEY_STATE_PRESSED)
		return;

	xkb_keysym_t sym = xkb_state_key_get_one_sym(m.xkb_state, key + 8);
	if (sym == XKB_KEY_NoSymbol)
		return;
	greeter_handle_key(sym);
}

static void greeter_keyboard_modifiers(
	void *data, struct wl_keyboard *keyboard, uint32_t serial,
	uint32_t mods_depressed, uint32_t mods_latched, uint32_t mods_locked,
	uint32_t group) {
	(void)data;
	(void)keyboard;
	(void)serial;
	if (m.xkb_state)
		xkb_state_update_mask(m.xkb_state, mods_depressed, mods_latched,
							  mods_locked, 0, 0, group);
}

static void greeter_keyboard_repeat_info(void *data,
										 struct wl_keyboard *keyboard,
										 int32_t rate, int32_t delay) {
	(void)data;
	(void)keyboard;
	(void)rate;
	(void)delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = greeter_keyboard_keymap,
	.enter = greeter_keyboard_enter,
	.leave = greeter_keyboard_leave,
	.key = greeter_keyboard_key,
	.modifiers = greeter_keyboard_modifiers,
	.repeat_info = greeter_keyboard_repeat_info,
};

static void seat_handle_capabilities(void *data, struct wl_seat *seat,
									 uint32_t capabilities) {
	(void)data;
	if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && !m.keyboard) {
		m.keyboard = wl_seat_get_keyboard(seat);
		wl_keyboard_add_listener(m.keyboard, &keyboard_listener, NULL);
	}
}

static void seat_handle_name(void *data, struct wl_seat *seat,
							 const char *name) {
	(void)data;
	(void)seat;
	(void)name;
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_handle_capabilities,
	.name = seat_handle_name,
};

static void output_handle_geometry(void *data, struct wl_output *wl_output,
								   int32_t x, int32_t y, int32_t pw, int32_t ph,
								   int32_t subpixel, const char *make,
								   const char *model, int32_t transform) {
	(void)data;
	(void)wl_output;
	(void)x;
	(void)y;
	(void)pw;
	(void)ph;
	(void)subpixel;
	(void)make;
	(void)model;
	(void)transform;
}

static void output_handle_mode(void *data, struct wl_output *wl_output,
							   uint32_t flags, int32_t width, int32_t height,
							   int32_t refresh) {
	(void)data;
	(void)wl_output;
	(void)flags;
	(void)width;
	(void)height;
	(void)refresh;
}

static void output_handle_scale(void *data, struct wl_output *wl_output,
								int32_t factor) {
	struct greeter_output *o = data;
	if (factor > m.scale) {
		m.scale = factor > 1 ? factor : 1;
		greeter_refresh();
	}
	(void)o;
}

static void output_handle_done(void *data, struct wl_output *wl_output) {
	(void)data;
	(void)wl_output;
}

static void output_handle_name(void *data, struct wl_output *wl_output,
							   const char *name) {
	(void)data;
	(void)wl_output;
	(void)name;
}

static void output_handle_description(void *data, struct wl_output *wl_output,
									  const char *description) {
	(void)data;
	(void)wl_output;
	(void)description;
}

static const struct wl_output_listener output_listener = {
	.geometry = output_handle_geometry,
	.mode = output_handle_mode,
	.done = output_handle_done,
	.scale = output_handle_scale,
	.name = output_handle_name,
	.description = output_handle_description,
};

static void layer_surface_configure(void *data,
									struct zwlr_layer_surface_v1 *ls,
									uint32_t serial, uint32_t width,
									uint32_t height) {
	(void)data;
	zwlr_layer_surface_v1_ack_configure(ls, serial);
	if (width > 0)
		m.width = width;
	if (height > 0)
		m.height = height;
	m.configured = true;
	greeter_render();
}

static void layer_surface_closed(void *data,
								 struct zwlr_layer_surface_v1 *ls) {
	(void)data;
	(void)ls;
	m.running = false;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_configure,
	.closed = layer_surface_closed,
};

static void registry_handle_global(void *data, struct wl_registry *reg,
								   uint32_t name, const char *interface,
								   uint32_t version) {
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		m.compositor =
			wl_registry_bind(reg, name, &wl_compositor_interface,
							 version < 5 ? version : 5);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		m.shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
		m.layer_shell =
			wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface,
							 version < 4 ? version : 4);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		m.seat = wl_registry_bind(reg, name, &wl_seat_interface,
								  version < 7 ? version : 7);
		wl_seat_add_listener(m.seat, &seat_listener, NULL);
	} else if (strcmp(interface, wl_output_interface.name) == 0) {
		struct greeter_output *o = calloc(1, sizeof(*o));
		if (!o)
			return;
		o->global_name = name;
		o->wl_output = wl_registry_bind(reg, name, &wl_output_interface,
										version < 2 ? version : 2);
		wl_output_add_listener(o->wl_output, &output_listener, o);
		wl_list_insert(&m.outputs, &o->link);
	}
}

static void registry_handle_global_remove(void *data, struct wl_registry *reg,
										  uint32_t name) {
	(void)data;
	(void)reg;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_handle_global,
	.global_remove = registry_handle_global_remove,
};

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

static void greeter_signal(int signal_number) {
	(void)signal_number;
	m.running = false;
}

static int usage(void) {
	printf("acwm-greeter — greetd greeter client for acwm\n\n"
		   "  Runs inside the acwm greeter session and provides the\n"
		   "  username/password UI over greetd. Requires GREETD_SOCK.\n\n"
		   "  Environment:\n"
		   "    GREETD_SOCK         greetd IPC socket (required)\n"
		   "    ACWM_GREETER_FONT   pango font (default \"sans 11\")\n");
	return 0;
}

int main(int argc, char **argv) {
	if (argc > 1 && (strcmp(argv[1], "-h") == 0 ||
					 strcmp(argv[1], "--help") == 0))
		return usage();

	signal(SIGINT, greeter_signal);
	signal(SIGTERM, greeter_signal);
	signal(SIGPIPE, SIG_IGN);

	memset(&m, 0, sizeof(m));
	m.font = getenv("ACWM_GREETER_FONT");
	if (!m.font || !*m.font)
		m.font = "sans 11";
	wl_list_init(&m.outputs);

	if (!greetd_connect())
		return EXIT_FAILURE;

	m.display = wl_display_connect(NULL);
	if (!m.display) {
		fprintf(stderr, "acwm-greeter: cannot connect to Wayland: %s\n",
				strerror(errno));
		return EXIT_FAILURE;
	}

	m.xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!m.xkb_ctx) {
		fprintf(stderr, "acwm-greeter: xkb_context_new failed\n");
		return EXIT_FAILURE;
	}

	m.registry = wl_display_get_registry(m.display);
	wl_registry_add_listener(m.registry, &registry_listener, NULL);
	wl_display_roundtrip(m.display);

	if (!m.compositor || !m.shm || !m.layer_shell || !m.seat) {
		fprintf(stderr,
				"acwm-greeter: missing Wayland globals "
				"(compositor/shm/layer-shell/seat)\n");
		return EXIT_FAILURE;
	}

	m.surface = wl_compositor_create_surface(m.compositor);
	m.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
		m.layer_shell, m.surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
		GREETER_NAMESPACE);
	if (!m.layer_surface) {
		fprintf(stderr, "acwm-greeter: layer surface creation failed\n");
		return EXIT_FAILURE;
	}

	zwlr_layer_surface_v1_set_anchor(
		m.layer_surface, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
							 ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
							 ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
							 ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
	zwlr_layer_surface_v1_set_exclusive_zone(m.layer_surface, -1);
	zwlr_layer_surface_v1_set_keyboard_interactivity(
		m.layer_surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
	zwlr_layer_surface_v1_add_listener(m.layer_surface,
									   &layer_surface_listener, NULL);
	wl_surface_commit(m.surface);
	wl_display_roundtrip(m.display);

	m.state = ST_USERNAME;
	m.message[0] = '\0';
	m.scale = 1;
	greeter_refresh();

	while (m.running) {
		if (wl_display_dispatch(m.display) < 0)
			break;
	}

	zwlr_layer_surface_v1_destroy(m.layer_surface);
	wl_surface_destroy(m.surface);
	wl_display_disconnect(m.display);
	if (m.greetd_fd >= 0)
		close(m.greetd_fd);
	return EXIT_SUCCESS;
}
