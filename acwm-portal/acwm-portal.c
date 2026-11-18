#define _GNU_SOURCE

/*
 * acwm-portal — screenshot portal backend for acwm.
 *
 * House-style standalone service next to acwm-msg/acwm-nag/acwm-launch:
 * implements org.freedesktop.impl.portal.Screenshot over the session bus
 * (sd-bus) and captures frames from acwm via zwlr_screencopy_v1, writing
 * PNGs under $XDG_RUNTIME_DIR/acwm-portal/.
 *
 * The captured output is the one under the pointer, resolved by querying
 * acwm's IPC ("get cursorpos") and matching against the wl_output name.
 * Override with ACWM_PORTAL_OUTPUT=<output name>.
 *
 * Responds synchronously: (handle, 0, {"uri": "file://..."}) on success,
 * (handle, 2, {}) on capture failure. Non-interactive.
 */
#include <cairo.h>
#include <errno.h>
#include <fcntl.h>
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
#include <time.h>
#include <unistd.h>

#include <cjson/cJSON.h>
#include <systemd/sd-bus.h>
#include <wayland-client.h>

#include "wlr-screencopy-unstable-v1-client-protocol.h"

#define PORTAL_DBUS_NAME "org.freedesktop.impl.portal.desktop.acwm"
#define PORTAL_OBJECT_PATH "/org/freedesktop/portal/desktop"
#define SCREENSHOT_IFACE "org.freedesktop.impl.portal.Screenshot"

/* Portal response codes: 0 = success, 1 = cancelled by user, 2 = other error. */
#define PORTAL_RESPONSE_OK 0
#define PORTAL_RESPONSE_ERROR 2

struct Output {
	struct wl_output *wl_output;
	uint32_t global_name;
	int32_t x, y, width, height;
	char name[64];
	bool geometry_done;
	struct wl_list link;
};

struct Capture {
	int32_t width, height, stride;
	uint32_t wl_shm_format;
	bool buffer_params_done;
	bool ready;
	bool failed;
	bool y_invert;
	int fd;
	off_t size;
	void *data;
	struct wl_shm_pool *pool;
	struct wl_buffer *buffer;
	struct zwlr_screencopy_frame_v1 *frame;
};

static struct wl_display *display;
static struct wl_registry *registry;
static struct wl_shm *shm;
static struct zwlr_screencopy_manager_v1 *screencopy_manager;
static struct wl_list outputs;

static struct Capture capture;

static void capture_reset(void) {
	if (capture.frame)
		zwlr_screencopy_frame_v1_destroy(capture.frame);
	if (capture.buffer)
		wl_buffer_destroy(capture.buffer);
	if (capture.pool)
		wl_shm_pool_destroy(capture.pool);
	if (capture.data)
		munmap(capture.data, capture.size);
	if (capture.fd >= 0)
		close(capture.fd);

	memset(&capture, 0, sizeof(capture));
	capture.fd = -1;
}

/* ------------------------------------------------------------------ */
/* Wayland client                                                      */
/* ------------------------------------------------------------------ */

static void output_handle_geometry(void *data, struct wl_output *wl_output,
								   int32_t x, int32_t y, int32_t pw, int32_t ph,
								   int32_t subpixel, const char *make,
								   const char *model, int32_t transform) {
	struct Output *o = data;
	o->x = x;
	o->y = y;
}

static void output_handle_mode(void *data, struct wl_output *wl_output,
							   uint32_t flags, int32_t width, int32_t height,
							   int32_t refresh) {
	struct Output *o = data;
	if (flags & WL_OUTPUT_MODE_CURRENT) {
		o->width = width;
		o->height = height;
	}
}

static void output_handle_done(void *data, struct wl_output *wl_output) {
	struct Output *o = data;
	o->geometry_done = true;
}

static void output_handle_scale(void *data, struct wl_output *wl_output,
								int32_t factor) {
}

static void output_handle_name(void *data, struct wl_output *wl_output,
							   const char *name) {
	struct Output *o = data;
	snprintf(o->name, sizeof(o->name), "%s", name);
}

static void output_handle_description(void *data, struct wl_output *wl_output,
									  const char *description) {
}

static const struct wl_output_listener output_listener = {
	.geometry = output_handle_geometry,
	.mode = output_handle_mode,
	.done = output_handle_done,
	.scale = output_handle_scale,
	.name = output_handle_name,
	.description = output_handle_description,
};

static void frame_handle_buffer(void *data,
								struct zwlr_screencopy_frame_v1 *frame,
								uint32_t format, uint32_t width,
								uint32_t height, uint32_t stride) {
	capture.wl_shm_format = format;
	capture.width = (int32_t)width;
	capture.height = (int32_t)height;
	capture.stride = (int32_t)stride;
}

static void frame_handle_flags(void *data,
							   struct zwlr_screencopy_frame_v1 *frame,
							   uint32_t flags) {
	capture.y_invert = (flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT);
}

static void frame_handle_ready(void *data,
							   struct zwlr_screencopy_frame_v1 *frame,
							   uint32_t tv_sec_hi, uint32_t tv_sec_lo,
							   uint32_t tv_nsec) {
	capture.ready = true;
}

static void frame_handle_failed(void *data,
								struct zwlr_screencopy_frame_v1 *frame) {
	capture.failed = true;
}

static void frame_handle_damage(void *data,
								struct zwlr_screencopy_frame_v1 *frame,
								uint32_t x, uint32_t y, uint32_t width,
								uint32_t height) {
}

static void frame_handle_linux_dmabuf(void *data,
									  struct zwlr_screencopy_frame_v1 *frame,
									  uint32_t format, uint32_t width,
									  uint32_t height) {
}

static void frame_handle_buffer_done(void *data,
									 struct zwlr_screencopy_frame_v1 *frame) {
	/* All buffer parameters (from the buffer event) are known: allocate and
	 * request the copy. */
	capture.size = (off_t)capture.stride * capture.height;

	capture.fd = memfd_create("acwm-portal-screenshot", MFD_CLOEXEC);
	if (capture.fd < 0 || ftruncate(capture.fd, capture.size) < 0) {
		capture.failed = true;
		return;
	}

	capture.pool = wl_shm_create_pool(shm, capture.fd, capture.size);
	capture.buffer = wl_shm_pool_create_buffer(
		capture.pool, 0, capture.width, capture.height, capture.stride,
		capture.wl_shm_format);

	zwlr_screencopy_frame_v1_copy(capture.frame, capture.buffer);
}

static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
	.buffer = frame_handle_buffer,
	.flags = frame_handle_flags,
	.ready = frame_handle_ready,
	.failed = frame_handle_failed,
	.damage = frame_handle_damage,
	.linux_dmabuf = frame_handle_linux_dmabuf,
	.buffer_done = frame_handle_buffer_done,
};

static void registry_handle_global(void *data, struct wl_registry *reg,
								   uint32_t name, const char *interface,
								   uint32_t version) {
	if (strcmp(interface, wl_output_interface.name) == 0) {
		struct Output *o = calloc(1, sizeof(*o));
		if (!o)
			return;
		o->global_name = name;
		o->wl_output =
			wl_registry_bind(reg, name, &wl_output_interface,
							 version < 4 ? version : 4);
		wl_output_add_listener(o->wl_output, &output_listener, o);
		wl_list_insert(&outputs, &o->link);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
	} else if (strcmp(interface,
					  zwlr_screencopy_manager_v1_interface.name) == 0) {
		screencopy_manager = wl_registry_bind(
			reg, name, &zwlr_screencopy_manager_v1_interface,
			version < 3 ? version : 3);
	}
}

static void registry_handle_global_remove(void *data,
										  struct wl_registry *reg,
										  uint32_t name) {
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_handle_global,
	.global_remove = registry_handle_global_remove,
};

/* ------------------------------------------------------------------ */
/* acwm IPC (cursor position -> output name)                           */
/* ------------------------------------------------------------------ */

static bool ipc_get_cursor_monitor(char *monitor_out, size_t len) {
	const char *socket_path = getenv("ACWM_INSTANCE_SIGNATURE");
	if (!socket_path || !*socket_path)
		return false;

	int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return false;

	struct sockaddr_un addr;
	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	if (strlen(socket_path) >= sizeof(addr.sun_path) ||
		connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return false;
	}

	const char *cmd = "get cursorpos\n";
	if (send(fd, cmd, strlen(cmd), MSG_NOSIGNAL) < 0) {
		close(fd);
		return false;
	}

	char buf[4096];
	size_t got = 0;
	while (got < sizeof(buf) - 1) {
		ssize_t n = recv(fd, buf + got, sizeof(buf) - 1 - got, 0);
		if (n <= 0)
			break;
		got += (size_t)n;
		if (memchr(buf, '\n', got))
			break;
	}
	close(fd);
	buf[got] = '\0';

	cJSON *json = cJSON_Parse(buf);
	if (!json) {
		return false;
	}

	cJSON *monitor = cJSON_GetObjectItemCaseSensitive(json, "monitor");
	bool ok = cJSON_IsString(monitor) && monitor->valuestring &&
			  monitor->valuestring[0];
	if (ok)
		snprintf(monitor_out, len, "%s", monitor->valuestring);

	cJSON_Delete(json);
	return ok;
}

static struct Output *pick_output(void) {
	const char *preferred = getenv("ACWM_PORTAL_OUTPUT");
	char monitor[64] = "";

	if (!preferred || !*preferred) {
		if (!ipc_get_cursor_monitor(monitor, sizeof(monitor)))
			return NULL;
		preferred = monitor;
	}

	struct Output *o;
	wl_list_for_each(o, &outputs, link) {
		if (o->name[0] && strcmp(o->name, preferred) == 0)
			return o;
	}
	return NULL;
}

/* ------------------------------------------------------------------ */
/* Capture + PNG                                                       */
/* ------------------------------------------------------------------ */

static bool wayland_connect(void) {
	display = wl_display_connect(NULL);
	if (!display)
		return false;

	wl_list_init(&outputs);
	registry = wl_display_get_registry(display);
	wl_registry_add_listener(registry, &registry_listener, NULL);

	/* Two roundtrips: bind globals, then receive geometry/name/done events. */
	if (wl_display_roundtrip(display) < 0 ||
		wl_display_roundtrip(display) < 0) {
		return false;
	}

	return shm && screencopy_manager && !wl_list_empty(&outputs);
}

static void wayland_disconnect(void) {
	struct Output *o, *tmp;
	wl_list_for_each_safe(o, tmp, &outputs, link) {
		wl_output_destroy(o->wl_output);
		wl_list_remove(&o->link);
		free(o);
	}
	if (screencopy_manager)
		zwlr_screencopy_manager_v1_destroy(screencopy_manager);
	if (shm)
		wl_shm_destroy(shm);
	if (registry)
		wl_registry_destroy(registry);
	if (display)
		wl_display_disconnect(display);
	display = NULL;
	registry = NULL;
	shm = NULL;
	screencopy_manager = NULL;
}

static bool capture_run(struct Output *out) {
	capture_reset();

	capture.frame = zwlr_screencopy_manager_v1_capture_output(
		screencopy_manager, 1 /* overlay cursor */, out->wl_output);
	if (!capture.frame)
		return false;

	zwlr_screencopy_frame_v1_add_listener(capture.frame, &frame_listener,
										  NULL);

	while (!capture.ready && !capture.failed) {
		if (wl_display_dispatch(display) < 0) {
			return false;
		}
	}

	return capture.ready;
}

static bool capture_to_file(const char *file) {
	struct Output *out = NULL;
	cairo_surface_t *surface = NULL;
	bool ok = false;

	if (!wayland_connect()) {
		fprintf(stderr, "acwm-portal: no usable Wayland display\n");
		return false;
	}

	out = pick_output();
	if (!out) {
		fprintf(stderr, "acwm-portal: no output to capture\n");
		goto out;
	}

	if (!capture_run(out)) {
		fprintf(stderr, "acwm-portal: capture failed on %s\n", out->name);
		goto out;
	}

	/* wl_shm formats map to cairo formats with the same layout; XRGB has
	 * undefined alpha bytes, which must be forced opaque for PNG. */
	if (capture.wl_shm_format == WL_SHM_FORMAT_XRGB8888) {
		for (int32_t y = 0; y < capture.height; y++) {
			unsigned char *row = (unsigned char *)capture.data +
								 (size_t)y * capture.stride;
			for (int32_t x = 0; x < capture.width; x++)
				row[x * 4 + 3] = 0xff;
		}
	} else if (capture.wl_shm_format != WL_SHM_FORMAT_ARGB8888) {
		fprintf(stderr, "acwm-portal: unsupported buffer format %u\n",
				capture.wl_shm_format);
		goto out;
	}

	int stride = capture.stride;
	unsigned char *data = (unsigned char *)capture.data;
	if (capture.y_invert) {
		/* Negative-stride trick: point at the last row and walk upwards. */
		data += (size_t)(capture.height - 1) * capture.stride;
		stride = -capture.stride;
	}

	surface = cairo_image_surface_create_for_data(
		data, CAIRO_FORMAT_ARGB32, capture.width, capture.height, stride);
	if (!surface) {
		fprintf(stderr, "acwm-portal: failed to create cairo surface\n");
		goto out;
	}

	if (cairo_surface_write_to_png(surface, file) != CAIRO_STATUS_SUCCESS) {
		fprintf(stderr, "acwm-portal: failed to write %s\n", file);
		goto out;
	}

	ok = true;

out:
	if (surface)
		cairo_surface_destroy(surface);
	wayland_disconnect();
	return ok;
}

/* ------------------------------------------------------------------ */
/* sd-bus service                                                      */
/* ------------------------------------------------------------------ */

static char *screenshot_to_uri(void) {
	const char *runtime = getenv("XDG_RUNTIME_DIR");
	if (!runtime) {
		fprintf(stderr, "acwm-portal: XDG_RUNTIME_DIR not set\n");
		return NULL;
	}

	char *dir = NULL;
	if (asprintf(&dir, "%s/acwm-portal", runtime) < 0)
		return NULL;

	mkdir(dir, 0700); /* exists-ok */

	time_t now = time(NULL);
	char *file = NULL;
	if (asprintf(&file, "%s/screenshot-%ld-%d.png", dir, (long)now,
				 (int)getpid()) < 0) {
		free(dir);
		return NULL;
	}
	free(dir);

	/* cairo writes the file; umask(077) in main keeps it user-only. */
	if (!capture_to_file(file)) {
		free(file);
		return NULL;
	}

	char *uri = NULL;
	if (asprintf(&uri, "file://%s", file) < 0) {
		free(file);
		return NULL;
	}

	free(file);
	return uri;
}

static int method_screenshot(sd_bus_message *m, void *userdata,
							 sd_bus_error *ret_error) {
	const char *handle = NULL, *app_id = NULL, *parent_window = NULL;
	int r = sd_bus_message_read(m, "oss", &handle, &app_id, &parent_window);
	if (r < 0)
		return r;

	/* options: a{sv} — "interactive" and "cursor_mode" are ignored for now. */
	r = sd_bus_message_skip(m, "a{sv}");
	if (r < 0)
		return r;

	char *uri = screenshot_to_uri();

	sd_bus_message *reply = NULL;
	r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) {
		free(uri);
		return r;
	}

	r = sd_bus_message_append(reply, "ou", handle,
							  uri ? PORTAL_RESPONSE_OK
								  : PORTAL_RESPONSE_ERROR);
	if (r >= 0) {
		r = sd_bus_message_open_container(reply, SD_BUS_TYPE_ARRAY, "{sv}");
		if (r >= 0 && uri) {
			r = sd_bus_message_open_container(reply, SD_BUS_TYPE_DICT_ENTRY,
											  "sv");
			if (r >= 0) {
				r = sd_bus_message_append(reply, "s", "uri");
				if (r >= 0)
					r = sd_bus_message_open_container(reply, SD_BUS_TYPE_VARIANT,
													  "s");
				if (r >= 0)
					r = sd_bus_message_append(reply, "s", uri);
				if (r >= 0)
					r = sd_bus_message_close_container(reply);
				if (r >= 0)
					r = sd_bus_message_close_container(reply);
			}
			if (r >= 0)
				r = sd_bus_message_close_container(reply);
		} else if (r >= 0) {
			r = sd_bus_message_close_container(reply);
		}
	}
	if (r >= 0)
		r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	free(uri);
	return r < 0 ? r : 1;
}

static int get_version(sd_bus *bus, const char *path, const char *interface,
					   const char *property, sd_bus_message *reply,
					   void *userdata, sd_bus_error *error) {
	return sd_bus_message_append(reply, "u", 2);
}

static const sd_bus_vtable screenshot_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("Screenshot", "ossa{sv}", "oua{sv}", method_screenshot,
				  0),
	SD_BUS_PROPERTY("version", "u", get_version, 0,
					SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_VTABLE_END,
};

static int usage(void) {
	printf("acwm-portal — screenshot portal backend for acwm\n\n"
		   "  Runs a session-bus service (" PORTAL_DBUS_NAME ") implementing\n"
		   "  org.freedesktop.impl.portal.Screenshot. Intended to be started\n"
		   "  via dbus activation; no command-line options.\n\n"
		   "  Environment:\n"
		   "    WAYLAND_DISPLAY           display to capture from\n"
		   "    ACWM_PORTAL_OUTPUT        output name override\n"
		   "    ACWM_INSTANCE_SIGNATURE   acwm IPC socket path (set by acwm)\n");
	return 0;
}

int main(int argc, char **argv) {
	if (argc > 1 && (strcmp(argv[1], "-h") == 0 ||
					 strcmp(argv[1], "--help") == 0))
		return usage();

	umask(077);

	sd_bus *bus = NULL;
	int r = sd_bus_default_user(&bus);
	if (r < 0) {
		fprintf(stderr, "acwm-portal: cannot connect to the user bus: %s\n",
				strerror(-r));
		return EXIT_FAILURE;
	}

	r = sd_bus_add_object_vtable(bus, NULL, PORTAL_OBJECT_PATH,
								 SCREENSHOT_IFACE, screenshot_vtable, NULL);
	if (r < 0) {
		fprintf(stderr, "acwm-portal: vtable registration failed: %s\n",
				strerror(-r));
		return EXIT_FAILURE;
	}

	r = sd_bus_request_name(bus, PORTAL_DBUS_NAME, 0);
	if (r < 0) {
		fprintf(stderr, "acwm-portal: failed to take bus name %s: %s\n",
				PORTAL_DBUS_NAME, strerror(-r));
		return EXIT_FAILURE;
	}

	for (;;) {
		r = sd_bus_process(bus, NULL);
		if (r < 0) {
			fprintf(stderr, "acwm-portal: sd_bus_process failed: %s\n",
					strerror(-r));
			return EXIT_FAILURE;
		}
		if (r > 0)
			continue;
		r = sd_bus_wait(bus, (uint64_t)-1);
		if (r < 0) {
			fprintf(stderr, "acwm-portal: sd_bus_wait failed: %s\n",
					strerror(-r));
			return EXIT_FAILURE;
		}
	}
}
