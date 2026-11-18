/* acwm-launch — minimal app-only Wayland launcher for acwm.
 *
 * House-style standalone client next to acwm-nag: layer-shell overlay with an
 * exclusive keyboard grab, pangocairo rendering over wl_shm buffers, no GTK.
 *
 * Searches applications only — no file/run modes. Sources:
 *   1. .desktop files from the XDG data dirs (natively installed apps).
 *      Nix profile paths and the Flatpak export dirs are appended so the
 *      launcher works even when the session env is not XDG-complete.
 *   2. Flatpak apps (their .desktop files live under the flatpak export dirs).
 *   3. AppImages found under $HOME/Applications (override with
 *      ACWM_LAUNCH_APPIMAGE_DIRS=dir1:dir2): direct exec when the executable bit
 *      is set, appimage-run fallback otherwise.
 *   4. Running windows that match no app (focused via foreign-toplevel
 *      activation); apps with live windows carry the running dot.
 *
 * Environment knobs:
 *   ACWM_LAUNCH_FONT           pango font description (default "sans 10")
 *   ACWM_LAUNCH_WIDTH          logical px width (default 440)
 *   ACWM_LAUNCH_MAX_ROWS       visible rows (default 8)
 *   ACWM_LAUNCH_ICON_THEME     icon theme name (default hicolor)
 *   ACWM_LAUNCH_APPIMAGE_DIRS  colon-separated AppImage dirs
 *   ACWM_LAUNCH_OUTPUT         wl_output name to show on (optional)
 *
 * Keys: type to filter, Up/Down (Tab) to move, Enter to launch, Escape to
 * exit, Ctrl+W/U edits. Mouse: hover select, click launch, wheel scroll.
 */

#if defined(__linux__)
#define _GNU_SOURCE
#elif !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include <cairo/cairo.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <math.h>
#include <pango/pangocairo.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <ctype.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon.h>
#include <wayland-client.h>
#include <wayland-util.h>

#include "acwm/common/input-event-codes.h"
#include "acwm-launch-foreign-toplevel-client-protocol.h"
#include "acwm-launch-layer-shell-client-protocol.h"
#include "acwm-launch-xdg-shell-client-protocol.h"

#define ACWM_LAUNCH_NAMESPACE "acwm-launch"

enum {
	ACWM_LAUNCH_PAD = 10,
	ACWM_LAUNCH_INPUT_H = 44,
	ACWM_LAUNCH_ROW_H = 40,
	ACWM_LAUNCH_ICON = 26,
	ACWM_LAUNCH_MAX_INPUT = 256,
};

/* Colors (ARGB; the accent mirrors the fork's focus_color). */
static const uint32_t acwm_launch_bg = 0x14141AE0;
static const uint32_t acwm_launch_row_sel = 0x2A2F3AE6;
static const uint32_t acwm_launch_text = 0xE8E8EAFF;
static const uint32_t acwm_launch_dim = 0x8E93A0FF;
static const uint32_t acwm_launch_accent = 0x00FFCCFF;
static const uint32_t acwm_launch_hairline = 0x3A3A44FF;
static const uint32_t acwm_launch_icon_box = 0x45454f88;

struct acwm_launch_buffer {
	struct wl_buffer *wl_buffer;
	void *data;
	size_t size;
	int width, height;
	struct wl_buffer_listener release;
};

struct acwm_launch_output {
	struct wl_output *wl_output;
	uint32_t global_name;
	char *name;
	int32_t scale;
	struct wl_list link;
};

struct acwm_launch_toplevel {
	struct zwlr_foreign_toplevel_handle_v1 *handle;
	char *app_id;
	char *title;
	bool closed;
};

struct acwm_launch_entry {
	char *name;		/* display name */
	char *desc;		/* description line */
	char *icon;		/* .desktop Icon= value (NULL for AppImages/windows) */
	char *exec;		/* Exec= string (desktop) or AppImage path */
	char *exec_path; /* .desktop file path (for %k in Exec) */
	char **ids;		/* candidate app ids for window matching */
	size_t ids_len;
	bool terminal;
	bool is_appimage;
	bool is_window; /* running window with no matching app */
	struct zwlr_foreign_toplevel_handle_v1 *toplevel;
	bool running; /* has live windows */
	cairo_surface_t *icon_surface; /* lazy-loaded premultiplied ARGB32 */
};

static struct acwm_launch_state {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct zwlr_layer_shell_v1 *layer_shell;
	struct wl_seat *seat;
	struct wl_pointer *pointer;
	struct wl_keyboard *keyboard;
	struct zwlr_foreign_toplevel_manager_v1 *foreign_manager;

	struct wl_list outputs;
	struct wl_output *output;
	int32_t scale;

	struct wl_surface *surface;
	struct zwlr_layer_surface_v1 *layer_surface;

	uint32_t width, height; /* logical size */
	uint32_t target_width;
	bool configured;

	struct xkb_context *xkb_ctx;
	struct xkb_keymap *xkb_keymap;
	struct xkb_state *xkb_state;

	char input[ACWM_LAUNCH_MAX_INPUT];
	size_t input_len;

	struct acwm_launch_entry **entries;
	size_t entries_len;

	size_t *filtered;
	size_t filtered_len;
	size_t selected;

	struct acwm_launch_toplevel **toplevels;
	size_t toplevels_len;

	char *font;
	char *desc_font;
	int max_rows;

	bool running;

	double pointer_x, pointer_y;
	char *output_name;
} m;

static void acwm_launch_signal(int signal_number) {
	(void)signal_number;
	m.running = false;
}

static void rgba_to_cairo(uint32_t color, double *r, double *g, double *b,
						  double *a) {
	*r = ((color >> 24) & 0xFF) / 255.0;
	*g = ((color >> 16) & 0xFF) / 255.0;
	*b = ((color >> 8) & 0xFF) / 255.0;
	*a = (color & 0xFF) / 255.0;
}

static bool acwm_launch_str_eq(const char *a, const char *b) {
	if (!a || !b)
		return false;
	return strcmp(a, b) == 0;
}

static bool acwm_launch_str_ieq(const char *a, const char *b) {
	if (!a || !b)
		return false;
	while (*a && *b) {
		int ca = tolower((unsigned char)*a);
		int cb = tolower((unsigned char)*b);
		if (ca != cb)
			return false;
		a++;
		b++;
	}
	return *a == '\0' && *b == '\0';
}

/* App id slug for window matching: lowercased, separators unified. */
static char *acwm_launch_slug(const char *text) {
	if (!text)
		return NULL;
	size_t len = strlen(text);
	char *out = malloc(len + 1);
	if (!out)
		return NULL;
	size_t o = 0;
	for (size_t i = 0; i < len; i++) {
		unsigned char c = (unsigned char)text[i];
		if (c == '_' || c == ' ' || c == '.')
			c = '-';
		else
			c = (unsigned char)tolower(c);
		out[o++] = (char)c;
	}
	out[o] = '\0';
	return out;
}

static bool acwm_launch_slug_eq(const char *a, const char *b) {
	if (!a || !b)
		return false;
	char *sa = acwm_launch_slug(a);
	char *sb = acwm_launch_slug(b);
	bool eq = sa && sb && strcmp(sa, sb) == 0;
	free(sa);
	free(sb);
	return eq;
}

/* const-correct strrchr shorthand used throughout */
static const char *strrchr_n(const char *s, int c) {
	return strrchr(s, c);
}

static void acwm_launch_push_unique(char ***dirs, size_t *count, const char *path) {
	if (!path || !path[0])
		return;
	for (size_t i = 0; i < *count; i++)
		if (acwm_launch_str_eq((*dirs)[i], path))
			return;
	char **next = realloc(*dirs, (*count + 1) * sizeof(**dirs));
	if (!next)
		return;
	*dirs = next;
	char *copy = strdup(path);
	if (!copy)
		return;
	(*dirs)[(*count)++] = copy;
}

static bool acwm_launch_path_is_file(const char *path) {
	struct stat st;
	if (!path || !path[0])
		return false;
	return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* ------------------------------------------------------------------ */
/* App entries                                                         */
/* ------------------------------------------------------------------ */

static bool acwm_launch_has_id(const struct acwm_launch_entry *e, const char *id) {
	if (!e || !id || id[0] == '\0')
		return false;
	for (size_t i = 0; i < e->ids_len; i++) {
		if (acwm_launch_str_ieq(e->ids[i], id))
			return true;
		if (acwm_launch_slug_eq(e->ids[i], id))
			return true;
	}
	return false;
}

static void acwm_launch_add_id(struct acwm_launch_entry *e, const char *id) {
	if (!e || !id || id[0] == '\0')
		return;
	if (acwm_launch_has_id(e, id))
		return;
	char **next = realloc(e->ids, (e->ids_len + 1) * sizeof(*e->ids));
	if (!next)
		return;
	e->ids = next;
	char *copy = strdup(id);
	if (!copy)
		return;
	e->ids[e->ids_len++] = copy;
}

static bool acwm_launch_entry_dup(struct acwm_launch_entry **entries, size_t to,
							  const char *exec, const char *name) {
	for (size_t i = 0; i < to; i++) {
		if (entries[i]->is_window)
			continue;
		if (exec && exec[0] && acwm_launch_str_eq(entries[i]->exec, exec))
			return true;
		if (name && name[0] && acwm_launch_str_ieq(entries[i]->name, name))
			return true;
	}
	return false;
}

static struct acwm_launch_entry *acwm_launch_entry_new(void) {
	struct acwm_launch_entry *e = calloc(1, sizeof(*e));
	if (!e)
		return NULL;
	struct acwm_launch_entry **next =
		realloc(m.entries, (m.entries_len + 1) * sizeof(*m.entries));
	if (!next) {
		free(e);
		return NULL;
	}
	m.entries = next;
	m.entries[m.entries_len++] = e;
	return e;
}

/* OnlyShowIn/NotShowIn handling with XDG_CURRENT_DESKTOP (acwm exports it). */
static bool acwm_launch_desktop_group_filter(const char *value) {
	const char *current = getenv("XDG_CURRENT_DESKTOP");
	if (!current || !current[0])
		current = "acwm";

	char *values = strdup(value);
	if (!values)
		return false;
	bool hit = false;
	char *save = NULL;
	for (char *tok = strtok_r(values, ";", &save); tok;
		 tok = strtok_r(NULL, ";", &save)) {
		if (acwm_launch_str_ieq(tok, "acwm") || acwm_launch_str_ieq(tok, current)) {
			hit = true;
			break;
		}
	}
	free(values);
	return hit;
}

static void acwm_launch_load_desktop_file(const char *path) {
	FILE *file = fopen(path, "r");
	if (!file)
		return;

	char *line = NULL;
	size_t line_size = 0;

	bool in_entry = false;

	char *t_type = NULL, *t_name = NULL, *t_comment = NULL, *t_generic = NULL;
	char *t_icon = NULL, *t_exec = NULL, *t_tryexec = NULL, *t_wmclass = NULL;
	bool t_terminal = false, t_skip = false;
	bool t_onlyshow = false, t_onlyshow_ok = false, t_notshow = false,
		 t_notshow_hit = false;

	while (getline(&line, &line_size, file) != -1) {
		size_t n = strlen(line);
		while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
			line[--n] = '\0';
		char *text = line;
		if (text[0] == '[') {
			if (in_entry)
				break; /* next section: done with [Desktop Entry] */
			if (strncmp(text, "[Desktop Entry]", 15) == 0)
				in_entry = true;
			continue;
		}
		if (!in_entry || text[0] == '#' || text[0] == '\0')
			continue;

		char *eq = strchr(text, '=');
		char *sep = strchr(text, ':');
		char *val = NULL;
		int key_len = 0;
		if (eq && (!sep || eq < sep)) {
			val = eq + 1;
			key_len = (int)(eq - text);
		} else if (sep) {
			val = sep + 1;
			if (*val == ':')
				val++;
			key_len = (int)(sep - text);
		} else {
			continue;
		}
		if (!val)
			continue;
		char *key = strndup(text, (size_t)key_len);
		if (!key)
			continue;

#define IS_KEY(k) (strcmp(key, (k)) == 0)
		if (IS_KEY("Type")) {
			free(t_type);
			t_type = strdup(val);
			if (!acwm_launch_str_ieq(val, "application"))
				t_skip = true;
		} else if (IS_KEY("Hidden") || IS_KEY("NoDisplay")) {
			if (acwm_launch_str_ieq(val, "true"))
				t_skip = true;
		} else if (IS_KEY("Name")) {
			free(t_name);
			t_name = strdup(val);
		} else if (IS_KEY("Comment")) {
			free(t_comment);
			t_comment = strdup(val);
		} else if (IS_KEY("GenericName")) {
			free(t_generic);
			t_generic = strdup(val);
		} else if (IS_KEY("Icon")) {
			free(t_icon);
			t_icon = strdup(val);
		} else if (IS_KEY("Exec")) {
			free(t_exec);
			t_exec = strdup(val);
		} else if (IS_KEY("TryExec")) {
			free(t_tryexec);
			t_tryexec = strdup(val);
		} else if (IS_KEY("StartupWMClass")) {
			free(t_wmclass);
			t_wmclass = strdup(val);
		} else if (IS_KEY("Terminal")) {
			t_terminal = acwm_launch_str_ieq(val, "true");
		} else if (IS_KEY("OnlyShowIn")) {
			t_onlyshow = true;
			t_onlyshow_ok = acwm_launch_desktop_group_filter(val);
		} else if (IS_KEY("NotShowIn")) {
			t_notshow = true;
			t_notshow_hit = acwm_launch_desktop_group_filter(val);
		}
#undef IS_KEY
		free(key);
	}

	free(line);
	fclose(file);

	if (t_skip || !t_name || !t_name[0] || !t_exec || t_exec[0] == '\0' ||
		(t_onlyshow && !t_onlyshow_ok) || (t_notshow && t_notshow_hit))
		goto cleanup;

	if (t_tryexec && t_tryexec[0]) {
		if (strchr(t_tryexec, '/')) {
			if (!acwm_launch_path_is_file(t_tryexec))
				goto cleanup;
		} else if (access(t_tryexec, X_OK) != 0) {
			goto cleanup;
		}
	}

	if (acwm_launch_entry_dup(m.entries, m.entries_len, t_exec, t_name))
		goto cleanup;

	struct acwm_launch_entry *e = acwm_launch_entry_new();
	if (!e)
		goto cleanup;

	e->name = t_name;
	t_name = NULL;
	e->exec = t_exec;
	t_exec = NULL;
	e->exec_path = strdup(path);
	e->icon = t_icon;
	t_icon = NULL;
	const char *desc_src =
		(t_comment && t_comment[0]) ? t_comment
									: (t_generic && t_generic[0]) ? t_generic : "";
	e->desc = strdup(desc_src);
	e->terminal = t_terminal;

	acwm_launch_add_id(e, t_wmclass);
	acwm_launch_add_id(e, e->name);

	/* The first Exec token's basename as a matching id; unpack flatpak
	 * wrappers (Exec=flatpak run --opts… APPID). */
	{
		char *first = strdup(e->exec);
		char *end = first;
		while (*end && *end != ' ' && *end != '\t')
			end++;
		size_t word_len = (size_t)(end - first);
		const char *src = first;
		char *slash = (char *)strrchr_n(first, '/');
		if (slash) {
			src = slash + 1;
		}
		word_len = strlen(src);
		char *token = malloc(word_len + 1);
		if (token) {
			memcpy(token, src, word_len);
			token[word_len] = '\0';

			if (acwm_launch_str_eq(token, "flatpak") ||
				acwm_launch_str_eq(token, "sh")) {
				char *rest = strdup(end);
				char *save = NULL;
				char *tok = strtok_r(rest, " \t", &save);
				bool after_run =
					acwm_launch_str_eq(token, "flatpak") ? false : true;
				while (tok) {
					if (acwm_launch_str_eq(tok, "run"))
						after_run = true;
					else if (after_run && tok[0] != '-')
						break;
					tok = strtok_r(NULL, " \t", &save);
				}
				free(token);
				token = (tok && after_run) ? strdup(tok) : NULL;
				free(rest);
			}
			acwm_launch_add_id(e, token);
			free(token);
		}
		free(first);
	}

	/* Desktop file basename as an id too */
	{
		const char *base = strrchr_n(path, '/');
		base = base ? base + 1 : path;
		const char *dot = strrchr_n(base, '.');
		size_t len = dot ? (size_t)(dot - base) : strlen(base);
		char *file_name = strndup(base, len);
		acwm_launch_add_id(e, file_name);
		free(file_name);
	}

cleanup:
	free(t_type);
	free(t_name);
	free(t_comment);
	free(t_generic);
	free(t_icon);
	free(t_exec);
	free(t_tryexec);
	free(t_wmclass);
}

/* XDG data roots, augmented with Nix profile paths and Flatpak export dirs
 * so that the launcher works even when the session env is XDG-incomplete. */
static char **acwm_launch_data_roots(size_t *count_out) {
	char **dirs = NULL;
	size_t count = 0;

	const char *home = getenv("HOME");
	const char *xdg_data_home = getenv("XDG_DATA_HOME");
	const char *xdg_data_dirs = getenv("XDG_DATA_DIRS");

	char buffer[4096];

	if (xdg_data_home && xdg_data_home[0])
		acwm_launch_push_unique(&dirs, &count, xdg_data_home);
	else if (home) {
		snprintf(buffer, sizeof(buffer), "%s/.local/share", home);
		acwm_launch_push_unique(&dirs, &count, buffer);
	}

	if (xdg_data_dirs && xdg_data_dirs[0]) {
		char *copy = strdup(xdg_data_dirs);
		if (copy) {
			char *save = NULL;
			for (char *tok = strtok_r(copy, ":", &save); tok;
				 tok = strtok_r(NULL, ":", &save))
				acwm_launch_push_unique(&dirs, &count, tok);
			free(copy);
		}
	} else {
		acwm_launch_push_unique(&dirs, &count, "/usr/local/share");
		acwm_launch_push_unique(&dirs, &count, "/usr/share");
	}

	if (home) {
		snprintf(buffer, sizeof(buffer), "%s/.nix-profile/share", home);
		acwm_launch_push_unique(&dirs, &count, buffer);

		const char *user = getenv("USER");
		if (user && user[0]) {
			snprintf(buffer, sizeof(buffer), "/etc/profiles/per-user/%s/share",
					 user);
			acwm_launch_push_unique(&dirs, &count, buffer);
		}

		snprintf(buffer, sizeof(buffer),
				 "%s/.local/share/flatpak/exports/share", home);
		acwm_launch_push_unique(&dirs, &count, buffer);
	}

	acwm_launch_push_unique(&dirs, &count, "/run/current-system/sw/share");
	acwm_launch_push_unique(&dirs, &count, "/nix/var/nix/profiles/default/share");
	acwm_launch_push_unique(&dirs, &count, "/var/lib/flatpak/exports/share");

	*count_out = count;
	return dirs;
}

/* NixOS multi-profile layout: match ↓ w/o NAME first-perl. */
static void acwm_launch_idle(void) {}

static void acwm_launch_load_desktops(void) {
	size_t roots_count = 0;
	char **roots = acwm_launch_data_roots(&roots_count);

	for (size_t i = 0; i < roots_count; i++) {
		size_t len = strlen(roots[i]) + strlen("/applications") + 1;
		char *full = malloc(len);
		if (!full)
			continue;
		snprintf(full, len, "%s/applications", roots[i]);

		DIR *dir = opendir(full);
		if (dir) {
			struct dirent *de;
			while ((de = readdir(dir))) {
				size_t n = strlen(de->d_name);
				if (n <= 8 || strcmp(de->d_name + n - 8, ".desktop") != 0)
					continue;
				size_t path_len = strlen(full) + n + 2;
				char *path = malloc(path_len);
				snprintf(path, path_len, "%s/%s", full, de->d_name);
				acwm_launch_load_desktop_file(path);
				free(path);
			}
			closedir(dir);
		}
		free(full);
	}

	for (size_t i = 0; i < roots_count; i++)
		free(roots[i]);
	free(roots);
}

static void acwm_launch_load_appimages(void) {
	const char *home = getenv("HOME");
	const char *spec = getenv("ACWM_LAUNCH_APPIMAGE_DIRS");

	char dirs_buffer[4096];
	if (spec && spec[0]) {
		snprintf(dirs_buffer, sizeof(dirs_buffer), "%s", spec);
	} else if (home) {
		snprintf(dirs_buffer, sizeof(dirs_buffer), "%s/Applications", home);
	} else {
		return;
	}

	char *copy = strdup(dirs_buffer);
	if (!copy)
		return;

	char *save = NULL;
	for (char *tok = strtok_r(copy, ":", &save); tok;
		 tok = strtok_r(NULL, ":", &save)) {
		DIR *dir = opendir(tok);
		if (!dir)
			continue;
		struct dirent *de;
		while ((de = readdir(dir))) {
			size_t n = strlen(de->d_name);
			bool is_image = false;
			if (n > 9 && strcmp(de->d_name + n - 9, ".AppImage") == 0)
				is_image = true;
			else if (n > 9 && strcmp(de->d_name + n - 9, ".appimage") == 0)
				is_image = true;
			if (!is_image)
				continue;

			size_t path_len = strlen(tok) + n + 2;
			char *path = malloc(path_len);
			if (!path)
				continue;
			snprintf(path, path_len, "%s/%s", tok, de->d_name);

			char *name = strdup(de->d_name);
			char *dot = strrchr(name, '.');
			if (dot)
				*dot = '\0';

			if (acwm_launch_entry_dup(m.entries, m.entries_len, path, name)) {
				free(path);
				free(name);
				continue;
			}

			struct acwm_launch_entry *e = acwm_launch_entry_new();
			if (!e) {
				free(path);
				free(name);
				continue;
			}
			e->name = name; /* ownership moved */
			e->desc = strdup("AppImage");
			e->exec = path; /* ownership moved */
			e->is_appimage = true;
			acwm_launch_add_id(e, name);
			acwm_launch_add_id(e, de->d_name);
		}
		closedir(dir);
	}
	free(copy);
}

static int acwm_launch_entry_cmp(const void *a, const void *b) {
	const struct acwm_launch_entry *ea = *(const struct acwm_launch_entry *const *)a;
	const struct acwm_launch_entry *eb = *(const struct acwm_launch_entry *const *)b;
	if (ea->running != eb->running)
		return ea->running ? -1 : 1;
	if (!ea->name || !eb->name)
		return 0;
	for (const char *x = ea->name, *y = eb->name;; x++, y++) {
		int cx = tolower((unsigned char)*x);
		int cy = tolower((unsigned char)*y);
		if (cx != cy)
			return cx - cy;
		if (cx == '\0')
			break;
	}
	return 0;
}

/* ------------------------------------------------------------------ */
/* Icon lookup (XDG icon theme, lazy loaded)                           */
/* ------------------------------------------------------------------ */

static void acwm_launch_icon_dirs_ready(char ***dirs, size_t *count) {
	size_t roots_count = 0;
	char **roots = acwm_launch_data_roots(&roots_count);
	char buffer[4096];

	for (size_t i = 0; i < roots_count; i++) {
		snprintf(buffer, sizeof(buffer), "%s/icons", roots[i]);
		acwm_launch_push_unique(dirs, count, buffer);
		free(roots[i]);
	}
	free(roots);

	acwm_launch_push_unique(dirs, count, "/usr/share/pixmaps");
	acwm_launch_push_unique(dirs, count, "/usr/local/share/pixmaps");
}

static char *acwm_launch_icon_path(const char *icon) {
	if (!icon || icon[0] == '\0')
		return NULL;

	/* Absolute or directly readable path. */
	if (icon[0] == '/' && acwm_launch_path_is_file(icon))
		return strdup(icon);

	static char **dirs = NULL;
	static size_t dirs_count = 0;
	static bool ready = false;
	if (!ready) {
		acwm_launch_icon_dirs_ready(&dirs, &dirs_count);
		ready = true;
	}

	const char *theme = getenv("ACWM_LAUNCH_ICON_THEME");
	if (!theme || !theme[0])
		theme = "hicolor";

	static const char *sizes[] = {"scalable", "512x512", "256x256",
								  "128x128", "96x96",   "64x64",
								  "48x48"};
	static const char *cats[] = {"apps", ""};
	static const char *exts[] = {"", ".png", ".svg", ".xpm", ".jpg", ".jpeg"};

	const char *themes[2] = {theme, "hicolor"};
	char path[4096];

	for (size_t t = 0; t < 2; t++) {
		if (t == 1 && strcmp(themes[0], themes[1]) == 0)
			continue;
		for (size_t d = 0; d < dirs_count; d++) {
			for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
				for (size_t c = 0; c < sizeof(cats) / sizeof(cats[0]); c++) {
					for (size_t x = 0; x < sizeof(exts) / sizeof(exts[0]); x++) {
						int n = snprintf(path, sizeof(path),
										 "%s/%s/%s/%s%s%s%s", dirs[d],
										 themes[t], sizes[s],
										 cats[c][0] ? cats[c] : "",
										 cats[c][0] ? "/" : "", icon, exts[x]);
						(void)n;
						if (acwm_launch_path_is_file(path))
							return strdup(path);
					}
				}
			}
			/* legacy pixmaps layout: <dir>/<icon>.<ext> */
			for (size_t x = 0; x < sizeof(exts) / sizeof(exts[0]); x++) {
				snprintf(path, sizeof(path), "%s/%s%s", dirs[d], icon, exts[x]);
				if (acwm_launch_path_is_file(path))
					return strdup(path);
			}
		}
	}
	return NULL;
}

static cairo_surface_t *acwm_launch_icon_surface(struct acwm_launch_entry *e, int px) {
	if (e->icon_surface)
		return e->icon_surface;

	char *path = acwm_launch_icon_path(e->icon);
	if (!path && e->exec && !e->is_window) {
		/* AppImages and Windows rows without an Icon=: try the exec basename */
		const char *base = strrchr_n(e->exec, '/');
		base = base ? base + 1 : e->exec;
		const char *dot = strrchr_n(base, '.');
		size_t len = dot ? (size_t)(dot - base) : strlen(base);
		char *stem = strndup(base, len);
		if (stem) {
			path = acwm_launch_icon_path(stem);
			free(stem);
		}
	}
	if (!path) {
		e->icon_surface = NULL;
		return NULL;
	}

	GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file_at_size(path, px, px, NULL);
	if (!pixbuf) {
		free(path);
		e->icon_surface = NULL;
		return NULL;
	}

	int width = gdk_pixbuf_get_width(pixbuf);
	int height = gdk_pixbuf_get_height(pixbuf);
	int channels = gdk_pixbuf_get_n_channels(pixbuf);
	int rowstride = gdk_pixbuf_get_rowstride(pixbuf);
	const guchar *pixels = gdk_pixbuf_get_pixels(pixbuf);

	cairo_surface_t *surface =
		cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
	if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
		g_object_unref(pixbuf);
		free(path);
		return NULL;
	}
	if (width <= 0 || height <= 0) {
		g_object_unref(pixbuf);
		free(path);
		cairo_surface_destroy(surface);
		e->icon_surface = NULL;
		return NULL;
	}

	unsigned char *target = cairo_image_surface_get_data(surface);
	int target_stride = cairo_image_surface_get_stride(surface);
	for (int y = 0; y < height; y++) {
		const guchar *src = pixels + y * rowstride;
		uint32_t *dst = (uint32_t *)(target + y * target_stride);
		for (int x = 0; x < width; x++) {
			const guchar *p = src + x * channels;
			guchar blue = p[0], green = p[1], red = p[2];
			guchar alpha = (channels == 4) ? p[3] : 255;
			uint32_t rmul = (uint32_t)red * alpha / 255;
			uint32_t gmul = (uint32_t)green * alpha / 255;
			uint32_t bmul = (uint32_t)blue * alpha / 255;
			dst[x] = ((uint32_t)alpha << 24) | (rmul << 16) | (gmul << 8) |
					 bmul;
		}
	}
	cairo_surface_mark_dirty(surface);

	g_object_unref(pixbuf);
	free(path);
	e->icon_surface = surface;
	return surface;
}

/* ------------------------------------------------------------------ */
/* Fuzzy filter                                                        */
/* ------------------------------------------------------------------ */

/* First token of the exec string, basename only; caller frees. NULL if none. */
static char *acwm_launch_exec_first_token(const struct acwm_launch_entry *e) {
	if (!e->exec || !e->exec[0])
		return NULL;
	const char *start = e->exec;
	const char *end = start;
	while (*end && *end != ' ' && *end != '\t')
		end++;
	size_t len = (size_t)(end - start);
	if (len == 0)
		return NULL;
	char *first = strndup(start, len);
	if (!first)
		return NULL;
	const char *slash = strrchr_n(first, '/');
	if (slash) {
		char *base = strdup(slash + 1);
		free(first);
		first = base;
	}
	return first;
}

/* Subsequence fuzzy match: returns score when the query is a subsequence of
 * hay, -1 otherwise. Hand-rolled scoring, no extra deps. */
static int32_t acwm_launch_score(const char *query, const char *hay) {
	if (!query || query[0] == '\0')
		return 0;
	if (!hay || hay[0] == '\0')
		return -1;

	size_t qlen = strlen(query);
	size_t hlen = strlen(hay);

	int32_t score = 0;
	uint32_t matched = 0;
	size_t hi = 0;
	size_t last = 0; /* index of previous matched char */

	for (size_t qi = 0; qi < qlen; qi++) {
		while (qi < qlen && (unsigned char)query[qi] == ' ')
			qi++;
		if (qi >= qlen)
			continue;
		int qc = tolower((unsigned char)query[qi]);
		bool found = false;
		for (; hi < hlen; hi++) {
			int hc = tolower((unsigned char)hay[hi]);
			if (hc != qc)
				continue;
			if (matched > 0 && hi == last + 1)
				score += 10; /* consecutive */
			if (hi == 0 || hay[hi - 1] == '-' || hay[hi - 1] == '_' ||
				hay[hi - 1] == ' ')
				score += 12; /* word start */
			if (matched == 0 && hi == 0)
				score += 8; /* starts with */
			if (matched > 0 && hi > last)
				score -= (int32_t)(hi - last) - 1; /* gap penalty */
			last = hi;
			hi++;
			matched++;
			found = true;
			break;
		}
		if (!found)
			return -1;
	}
	if (matched == 0)
		return -1;
	return score + (int32_t)matched;
}

static void acwm_launch_refilter(void) {
	size_t *next = NULL;
	size_t len = 0;

	if (m.input_len == 0) {
		next = malloc((m.entries_len ? m.entries_len : 1) * sizeof(*next));
		if (next) {
			for (size_t i = 0; i < m.entries_len; i++)
				next[len++] = i;
		}
	} else {
		struct scored_entry {
			size_t index;
			int32_t score;
		} *scored = malloc((m.entries_len ? m.entries_len : 1) *
						   sizeof(*scored));
		size_t n = 0;
		if (scored) {
			for (size_t i = 0; i < m.entries_len; i++) {
				const struct acwm_launch_entry *e = m.entries[i];
				int32_t best = acwm_launch_score(m.input, e->name);
				if (best < 0 && e->desc && e->desc[0]) {
					int32_t s = acwm_launch_score(m.input, e->desc);
					if (s >= 0)
						best = s / 2 - 4; /* description matches rank lower */
				}
				if (best < 0) {
					char *first = acwm_launch_exec_first_token(e);
					if (first) {
						int32_t s = acwm_launch_score(m.input, first);
						if (s >= 0)
							best = s / 2 - 4;
						free(first);
					}
				}
				if (best >= 0) {
					scored[n].index = i;
					scored[n].score = best;
					n++;
				}
			}
			/* simple insertion sort by score desc, index asc */
			for (size_t i = 1; i < n; i++) {
				struct scored_entry tmp = scored[i];
				size_t j = i;
				while (j > 0 && (scored[j - 1].score < tmp.score)) {
					scored[j] = scored[j - 1];
					j--;
				}
				scored[j] = tmp;
			}
			next = malloc((n ? n : 1) * sizeof(*next));
			if (next) {
				for (size_t i = 0; i < n; i++)
					next[len++] = scored[i].index;
			}
			free(scored);
		}
	}

	free(m.filtered);
	m.filtered = next;
	m.filtered_len = len;
	if (m.filtered_len > 0) {
		if (m.selected >= m.filtered_len)
			m.selected = m.filtered_len - 1;
	} else
		m.selected = 0;
}

static void acwm_launch_sort_entries(void) {
	qsort(m.entries, m.entries_len, sizeof(*m.entries), acwm_launch_entry_cmp);
}

/* ------------------------------------------------------------------ */
/* Foreign toplevels (running state + window rows)                     */
/* ------------------------------------------------------------------ */

static void acwm_launch_toplevels_apply(void) {
	/* flag entries with live windows */
	for (size_t i = 0; i < m.entries_len; i++) {
		struct acwm_launch_entry *e = m.entries[i];
		for (size_t j = 0; j < m.toplevels_len; j++) {
			struct acwm_launch_toplevel *t = m.toplevels[j];			if (t->closed || !t->app_id || t->app_id[0] == '\0')
				continue;
			if (acwm_launch_has_id(e, t->app_id))
				e->running = true;
		}
	}

	/* window rows for toplevels that match no app */
	for (size_t j = 0; j < m.toplevels_len; j++) {
		struct acwm_launch_toplevel *t = m.toplevels[j];		if (t->closed || !t->app_id)
			continue;
		bool matched = false;
		for (size_t i = 0; i < m.entries_len; i++) {
			if (acwm_launch_has_id(m.entries[i], t->app_id)) {
				matched = true;
				break;
			}
		}
		if (matched)
			continue;

		struct acwm_launch_entry *e = acwm_launch_entry_new();
		if (!e)
			continue;
		e->is_window = true;
		e->name = strdup(t->title && t->title[0] ? t->title
												 : (t->app_id[0] ? t->app_id : "window"));
		e->desc = strdup("running window");
		e->toplevel = t->handle;
		e->running = true;
		acwm_launch_add_id(e, t->app_id);
	}
}

static void acwm_launch_toplevel_handle_title(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {
	struct acwm_launch_toplevel *t = data;
	(void)handle;
	free(t->title);
	t->title = strdup(title ? title : "");
}

static void acwm_launch_toplevel_handle_app_id(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id) {
	struct acwm_launch_toplevel *t = data;
	(void)handle;
	free(t->app_id);
	t->app_id = strdup(app_id ? app_id : "");
}

static void acwm_launch_toplevel_handle_state(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
	struct wl_array *state) {
	(void)data;
	(void)handle;
	(void)state;
}

static void acwm_launch_toplevel_handle_done(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
	(void)data;
	(void)handle;
}

static void acwm_launch_toplevel_handle_closed(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
	struct acwm_launch_toplevel *t = data;
	(void)handle;
	t->closed = true;
}

static void acwm_launch_toplevel_handle_output_enter(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
	struct wl_output *output) {
	(void)data;
	(void)handle;
	(void)output;
}

static void acwm_launch_toplevel_handle_output_leave(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
	struct wl_output *output) {
	(void)data;
	(void)handle;
	(void)output;
}

static void acwm_launch_toplevel_handle_parent(
	void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
	struct zwlr_foreign_toplevel_handle_v1 *parent) {
	(void)data;
	(void)handle;
	(void)parent;
}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
	.title = acwm_launch_toplevel_handle_title,
	.app_id = acwm_launch_toplevel_handle_app_id,
	.state = acwm_launch_toplevel_handle_state,
	.done = acwm_launch_toplevel_handle_done,
	.closed = acwm_launch_toplevel_handle_closed,
	.output_enter = acwm_launch_toplevel_handle_output_enter,
	.output_leave = acwm_launch_toplevel_handle_output_leave,
	.parent = acwm_launch_toplevel_handle_parent,
};

static void acwm_launch_manager_toplevel(
	void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
	struct zwlr_foreign_toplevel_handle_v1 *toplevel) {
	(void)data;
	(void)manager;
	struct acwm_launch_toplevel *t = calloc(1, sizeof(*t));
	if (!t) {
		zwlr_foreign_toplevel_handle_v1_destroy(toplevel);
		return;
	}
	t->handle = toplevel;
	struct acwm_launch_toplevel **next =
		realloc(m.toplevels,
				(m.toplevels_len + 1) * sizeof(*m.toplevels));
	if (!next) {
		free(t);
		zwlr_foreign_toplevel_handle_v1_destroy(toplevel);
		return;
	}
	m.toplevels = next;
	m.toplevels[m.toplevels_len++] = t;
	zwlr_foreign_toplevel_handle_v1_add_listener(toplevel,
												 &toplevel_listener, t);
}

static void acwm_launch_manager_finished(
	void *data, struct zwlr_foreign_toplevel_manager_v1 *manager) {
	(void)data;
	(void)manager;
	m.foreign_manager = NULL;
}

static const struct
	zwlr_foreign_toplevel_manager_v1_listener toplevel_manager_listener = {
		.toplevel = acwm_launch_manager_toplevel,
		.finished = acwm_launch_manager_finished,
	};

/* ------------------------------------------------------------------ */
/* Launch                                                              */
/* ------------------------------------------------------------------ */

/* Split an Exec= string into an argv array, honoring quoting, backslash
 * escapes and Exec field codes. %f %F %u %U %d %D %n %N %i %v %m expand to
 * nothing (no file args available); %c to the app name; %k to the .desktop
 * path; %% to a literal '%'. NULL-terminated; caller frees. */
static char **acwm_launch_exec_parse(const char *exec, const char *name,
								 const char *desktop_path) {
	char **argv = NULL;
	size_t argc = 0;

	if (!exec || !exec[0])
		return NULL;

	const char *p = exec;
	while (*p) {
		while (*p == ' ' || *p == '\t')
			p++;
		if (*p == '\0')
			break;

		size_t cap = 32;
		size_t len = 0;
		char *token = malloc(cap);
		if (!token)
			break;

		bool keep_token = true;

		while (*p && *p != ' ' && *p != '\t') {
			if (*p == '"') {
				p++;
				while (*p && *p != '"') {
					if (*p == '\\' && (p[1] == '"' || p[1] == '\\'))
						p++;
					if (len + 2 > cap) {
						cap *= 2;
						char *grown = realloc(token, cap);
						if (!grown)
							goto token_fail;
						token = grown;
					}
					token[len++] = *p++;
				}
				if (*p == '"')
					p++;
				continue;
			}
			if (*p == '\\' && p[1]) {
				p++;
				if (len + 2 > cap) {
					cap *= 2;
					char *grown = realloc(token, cap);
					if (!grown)
						goto token_fail;
					token = grown;
				}
				token[len++] = *p++;
				continue;
			}
			if (*p == '%' && p[1] != '\0') {
				char code = p[1];
				if (code == '%' ) {
					p += 2;
					if (len + 2 > cap) {
						cap *= 2;
						char *grown = realloc(token, cap);
						if (!grown)
							goto token_fail;
						token = grown;
					}
					token[len++] = '%';
					continue;
				}
				bool drop = (code == 'f' || code == 'F' || code == 'u' ||
							 code == 'U' || code == 'd' || code == 'D' ||
							 code == 'n' || code == 'N' || code == 'i' ||
							 code == 'v' || code == 'm');
				if (drop) {
					p += 2;
					continue;
				}
				const char *sub = NULL;
				if (code == 'c')
					sub = name;
				else if (code == 'k')
					sub = desktop_path;
				if (sub && sub[0]) {
					size_t need = strlen(sub);
					while (len + need + 1 > cap) {
						cap *= 2;
						char *grown = realloc(token, cap);
						if (!grown)
							goto token_fail;
						token = grown;
					}
					memcpy(token + len, sub, need);
					len += need;
				}
				p += 2;
				continue;
			}
			if (len + 2 > cap) {
				cap *= 2;
				char *grown = realloc(token, cap);
				if (!grown)
					goto token_fail;
				token = grown;
			}
			token[len++] = *p++;
			continue;

		token_fail:
			free(token);
			token = NULL;
			keep_token = false;
			break;
		}

		if (!token)
			break;
		if (len == 0) {
			/* the token was fully consumed field code / empty quotes */
			free(token);
			continue;
		}
		token[len] = '\0';

		char **grown = realloc(argv, (argc + 2) * sizeof(*argv));
		if (!grown) {
			free(token);
			break;
		}
		argv = grown;
		argv[argc++] = token;
		argv[argc] = NULL;
		(void)keep_token;
		if (!*p)
			break;
	}

	if (argc == 0) {
		free(argv);
		return NULL;
	}
	return argv;
}

static void acwm_launch_free_argv(char **argv) {
	if (!argv)
		return;
	for (size_t i = 0; argv[i]; i++)
		free(argv[i]);
	free(argv);
}

static void acwm_launch_exec_image(const char *path) {
	struct stat st = {0};
	if (stat(path, &st) == 0 && (st.st_mode & S_IXUSR))
		execl(path, path, (char *)NULL);
	/* Not executable (or the exec image needs an FHS env): appimage-run. */
	execlp("appimage-run", "appimage-run", path, (char *)NULL);
	execl(path, path, (char *)NULL);
	_exit(127);
}

static void acwm_launch_exec_terminal(char **argv, const char *desktop_path) {
	(void)desktop_path;
	const char *term_env = getenv("TERMINAL");
	const char *candidates[7] = {term_env ? term_env : NULL,
								 "foot",    "alacritty", "kitty",
								 "wezterm", "st",       "xterm"};

	for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
		const char *term = candidates[i];
		if (!term || !term[0])
			continue;

		size_t argc = 0;
		while (argv[argc])
			argc++;
		char **args = malloc((argc + 3) * sizeof(*args));
		if (!args)
			continue;
		args[0] = strdup(term);
		args[1] = strdup("-e");
		for (size_t k = 0; k < argc; k++) {
			args[2 + k] = strdup(argv[k]);
			if (!args[2 + k]) {
				args[2 + k] = NULL;
				break;
			}
		}
		args[argc + 2] = NULL;
		execvp(term, args);
		/* ENOENT: try the next candidate */
	}

	/* No terminal client around: run without the wrapper rather than fail. */
	execvp(argv[0], argv);
	_exit(127);
}

static void acwm_launch_entry_spawn(struct acwm_launch_entry *e) {
	char **argv = acwm_launch_exec_parse(e->exec, e->name, e->exec_path);
	if (!argv)
		return;

	pid_t pid = fork();
	if (pid < 0) {
		acwm_launch_free_argv(argv);
		return;
	}
	if (pid == 0) {
		pid_t pid2 = fork();
		if (pid2 < 0)
			_exit(EXIT_FAILURE);
		if (pid2 == 0) {
			setsid();
			if (e->is_appimage)
				acwm_launch_exec_image(argv[0]);
			else if (e->terminal)
				acwm_launch_exec_terminal(argv, e->exec_path);
			else
				execvp(argv[0], argv);
			_exit(127);
		}
		_exit(EXIT_SUCCESS);
	}

	int status;
	waitpid(pid, &status, 0);
	acwm_launch_free_argv(argv);
}

static void acwm_launch_launch(struct acwm_launch_entry *e) {
	if (!e)
		return;

	if (e->is_window) {
		if (e->toplevel && m.seat) {
			zwlr_foreign_toplevel_handle_v1_activate(e->toplevel, m.seat);
			wl_display_flush(m.display);
		}
		m.running = false;
		return;
	}

	acwm_launch_entry_spawn(e);
	m.running = false;
}

/* ------------------------------------------------------------------ */
/* Rendering                                                           */
/* ------------------------------------------------------------------ */

static void handle_buffer_release(void *data, struct wl_buffer *wl_buffer) {
	struct acwm_launch_buffer *buffer = data;
	wl_buffer_destroy(buffer->wl_buffer);
	munmap(buffer->data, buffer->size);
	free(buffer);
}

static struct acwm_launch_buffer *acwm_launch_buffer_create(int width, int height) {
	int stride = width * 4;
	int size = stride * height;

	int fd = memfd_create(ACWM_LAUNCH_NAMESPACE, MFD_CLOEXEC);
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

	struct acwm_launch_buffer *buffer = calloc(1, sizeof(*buffer));
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

static PangoLayout *acwm_launch_layout(cairo_t *cr, const char *text,
								   const char *font_desc) {
	PangoLayout *layout = pango_cairo_create_layout(cr);
	PangoFontDescription *desc = pango_font_description_from_string(font_desc);
	pango_layout_set_font_description(layout, desc);
	pango_font_description_free(desc);
	pango_layout_set_text(layout, text ? text : "", -1);
	pango_layout_set_single_paragraph_mode(layout, true);
	return layout;
}

/* one-line ellipsized layout clipped to avail px */
static PangoLayout *acwm_launch_layout_ellipsized(cairo_t *cr, const char *text,
											  const char *font_desc,
											  int avail) {
	PangoLayout *layout = acwm_launch_layout(cr, text, font_desc);
	pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
	pango_layout_set_width(layout, avail > 0 ? avail * PANGO_SCALE : -1);
	return layout;
}

static size_t acwm_launch_rows_visible(void) {
	size_t rows = m.filtered_len > 0 ? m.filtered_len : 1;
	if (rows > (size_t)m.max_rows)
		rows = (size_t)m.max_rows;
	return rows;
}

static uint32_t acwm_launch_target_height(void) {
	return (uint32_t)(ACWM_LAUNCH_PAD + ACWM_LAUNCH_INPUT_H + 2 +
					  (int)(acwm_launch_rows_visible() * ACWM_LAUNCH_ROW_H) +
					  ACWM_LAUNCH_PAD);
}

static void acwm_launch_draw_generic_icon(cairo_t *cr, double x, double y,
									  const char *name, bool selected) {
	double r, g, b, a;
	(void)selected;

	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
	rgba_to_cairo(acwm_launch_icon_box, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_rectangle(cr, x, y, ACWM_LAUNCH_ICON, ACWM_LAUNCH_ICON);
	cairo_fill(cr);

	if (name && name[0]) {
		/* first UTF-8 codepoint only */
		size_t bytes = 1;
		unsigned char lead = (unsigned char)name[0];
		if ((lead & 0xE0) == 0xC0)
			bytes = 2;
		else if ((lead & 0xF0) == 0xE0)
			bytes = 3;
		else if ((lead & 0xF8) == 0xF0)
			bytes = 4;
		char letter[5] = {0};
		for (size_t i = 0; i < bytes && name[i]; i++)
			letter[i] = name[i];

		PangoLayout *layout = acwm_launch_layout(cr, letter, m.font);
		int w = 0, h = 0;
		pango_layout_get_pixel_size(layout, &w, &h);
		rgba_to_cairo(acwm_launch_dim, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r, g, b, a);
		cairo_move_to(cr, x + (ACWM_LAUNCH_ICON - w) / 2.0,
					  y + (ACWM_LAUNCH_ICON - h) / 2.0);
		pango_cairo_show_layout(cr, layout);
		g_object_unref(layout);
	}
}

static void acwm_launch_render(void) {
	if (!m.surface || !m.configured || m.width == 0 || m.height == 0)
		return;

	int scale = m.scale > 0 ? m.scale : 1;
	struct acwm_launch_buffer *buffer =
		acwm_launch_buffer_create(m.width * scale, m.height * scale);
	if (!buffer)
		return;

	cairo_surface_t *surface = cairo_image_surface_create_for_data(
		buffer->data, CAIRO_FORMAT_ARGB32, m.width * scale, m.height * scale,
		m.width * scale * 4);
	cairo_t *cr = cairo_create(surface);
	cairo_scale(cr, scale, scale);
	cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);

	double r, g, b, a;

	/* background */
	cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
	rgba_to_cairo(acwm_launch_bg, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	cairo_paint(cr);

	/* prompt marker */
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
	rgba_to_cairo(acwm_launch_accent, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	{
		PangoLayout *marker = acwm_launch_layout(cr, "❯", m.font);
		int mw = 0, mh = 0;
		pango_layout_get_pixel_size(marker, &mw, &mh);
		cairo_move_to(cr, ACWM_LAUNCH_PAD,
					  ACWM_LAUNCH_PAD + (ACWM_LAUNCH_INPUT_H - mh) / 2.0);
		pango_cairo_show_layout(cr, marker);
		g_object_unref(marker);
	}

	/* input line */
	{
		const char *text = m.input_len ? m.input : "type to search...";
		PangoLayout *layout = acwm_launch_layout(cr, text, m.font);
		int tw = 0, th = 0;
		pango_layout_get_pixel_size(layout, &tw, &th);
		rgba_to_cairo(m.input_len ? acwm_launch_text : acwm_launch_dim, &r, &g, &b,
					  &a);
		cairo_set_source_rgba(cr, r, g, b, a);
		cairo_move_to(cr, ACWM_LAUNCH_PAD + 30,
					  ACWM_LAUNCH_PAD + (ACWM_LAUNCH_INPUT_H - th) / 2.0);
		pango_cairo_show_layout(cr, layout);
		g_object_unref(layout);

		/* caret */
		rgba_to_cairo(acwm_launch_dim, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r, g, b, a);
		cairo_rectangle(cr, ACWM_LAUNCH_PAD + 30 + tw + 3.0,
						ACWM_LAUNCH_PAD + (ACWM_LAUNCH_INPUT_H - ACWM_LAUNCH_ICON) / 2.0,
						2.0, ACWM_LAUNCH_ICON);
		cairo_fill(cr);
	}

	/* separator */
	rgba_to_cairo(acwm_launch_hairline, &r, &g, &b, &a);
	cairo_set_source_rgba(cr, r, g, b, a);
	double sep_y = ACWM_LAUNCH_PAD + ACWM_LAUNCH_INPUT_H;
	cairo_rectangle(cr, 0, sep_y, m.width, 1.0);
	cairo_fill(cr);

	if (m.filtered_len == 0) {
		cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
		rgba_to_cairo(acwm_launch_dim, &r, &g, &b, &a);
		cairo_set_source_rgba(cr, r, g, b, a);
		PangoLayout *layout = acwm_launch_layout(cr, "no matching apps", m.font);
		int th = 0;
		pango_layout_get_pixel_size(layout, NULL, &th);
		cairo_move_to(cr, ACWM_LAUNCH_PAD + ACWM_LAUNCH_ICON + 20,
					  sep_y + (ACWM_LAUNCH_ROW_H - th) / 2.0 + 2.0);
		pango_cairo_show_layout(cr, layout);
		g_object_unref(layout);
	} else {
		size_t rows = acwm_launch_rows_visible();
		for (size_t i = 0; i < rows; i++) {
			size_t index = m.filtered[i];
			struct acwm_launch_entry *e = m.entries[index];
			double row_y = sep_y + 2.0 + (double)i * ACWM_LAUNCH_ROW_H;
			bool sel = (i == m.selected);

			if (sel) {
				cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
				rgba_to_cairo(acwm_launch_row_sel, &r, &g, &b, &a);
				cairo_set_source_rgba(cr, r, g, b, a);
				cairo_rectangle(cr, 6.0, row_y, m.width - 12.0,
								ACWM_LAUNCH_ROW_H - 2.0);
				cairo_fill(cr);
			}

			cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

			int icon_x = ACWM_LAUNCH_PAD + 6;
			double icon_y =
				row_y + (ACWM_LAUNCH_ROW_H - ACWM_LAUNCH_ICON) / 2.0 + 1.0;
			cairo_surface_t *icon = acwm_launch_icon_surface(e, ACWM_LAUNCH_ICON);
			if (icon) {
				int iw = cairo_image_surface_get_width(icon);
				int ih = cairo_image_surface_get_height(icon);
				cairo_set_source_surface(
					cr, icon, icon_x + (ACWM_LAUNCH_ICON - iw) / 2.0,
					icon_y + (ACWM_LAUNCH_ICON - ih) / 2.0);
				cairo_paint_with_alpha(cr, sel ? 1.0 : 0.85);
			} else {
				acwm_launch_draw_generic_icon(cr, icon_x, icon_y, e->name, sel);
			}

			int text_x = icon_x + ACWM_LAUNCH_ICON + 12;
			int text_avail =
				(int)m.width - text_x - 30;

			/* name */
			PangoLayout *name_l =
				acwm_launch_layout_ellipsized(cr, e->name, m.font, text_avail);
			rgba_to_cairo(acwm_launch_text, &r, &g, &b, &a);
			cairo_set_source_rgba(cr, r, g, b, a);
			cairo_move_to(cr, text_x, row_y + 6.0);
			pango_cairo_show_layout(cr, name_l);
			g_object_unref(name_l);

			/* description */
			if (e->desc && e->desc[0]) {
				PangoLayout *desc_l = acwm_launch_layout_ellipsized(
					cr, e->desc, m.desc_font, text_avail);
				rgba_to_cairo(acwm_launch_dim, &r, &g, &b, &a);
				cairo_set_source_rgba(cr, r, g, b, a);
				cairo_move_to(cr, text_x, row_y + 23.0);
				pango_cairo_show_layout(cr, desc_l);
				g_object_unref(desc_l);
			}

			/* running dot */
			if (e->running) {
				rgba_to_cairo(acwm_launch_accent, &r, &g, &b, &a);
				cairo_set_source_rgba(cr, r, g, b, a);
				cairo_arc(cr, (double)m.width - 20.0,
						  row_y + ACWM_LAUNCH_ROW_H / 2.0, 4.0, 0, 2 * M_PI);
				cairo_fill(cr);
			}
		}
	}

	cairo_destroy(cr);
	cairo_surface_flush(surface);

	wl_surface_set_buffer_scale(m.surface, scale);
	wl_surface_attach(m.surface, buffer->wl_buffer, 0, 0);
	wl_surface_damage_buffer(m.surface, 0, 0, m.width * scale,
							 m.height * scale);
	wl_surface_commit(m.surface);

	cairo_surface_destroy(surface);
}

static void acwm_launch_refresh(void) {
	uint32_t height = acwm_launch_target_height();
	uint32_t width = m.target_width;

	if (!m.configured)
		return;
	if (height != m.height || width != m.width) {
		zwlr_layer_surface_v1_set_size(m.layer_surface, width, height);
		wl_surface_commit(m.surface);
		m.width = width;
		m.height = height;
	} else {
		acwm_launch_render();
	}
}

/* ------------------------------------------------------------------ */
/* Layer surface events                                                */
/* ------------------------------------------------------------------ */

static void acwm_launch_layer_configure(
	void *data, struct zwlr_layer_surface_v1 *layer_surface, uint32_t serial,
	uint32_t width, uint32_t height) {
	(void)data;
	zwlr_layer_surface_v1_ack_configure(layer_surface, serial);
	if (width > 0)
		m.width = width;
	if (height > 0)
		m.height = height;
	if (!m.configured || width != m.target_width) {
		zwlr_layer_surface_v1_set_size(layer_surface, m.target_width,
									   acwm_launch_target_height());
		wl_surface_commit(m.surface);
	}
	m.configured = true;
	acwm_launch_render();
}

static void acwm_launch_layer_closed(
	void *data, struct zwlr_layer_surface_v1 *layer_surface) {
	(void)data;
	(void)layer_surface;
	m.running = false;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = acwm_launch_layer_configure,
	.closed = acwm_launch_layer_closed,
};

/* ------------------------------------------------------------------ */
/* Pointer + keyboard                                                  */
/* ------------------------------------------------------------------ */

static void acwm_launch_hover_at(double sx, double sy) {
	double rows_start = ACWM_LAUNCH_PAD + ACWM_LAUNCH_INPUT_H + 2;
	if (m.filtered_len == 0)
		return;
	if (sx < 0 || sy < rows_start)
		return;
	size_t row = (size_t)((sy - rows_start) / ACWM_LAUNCH_ROW_H);
	if (row >= acwm_launch_rows_visible())
		return;
	if (m.selected != row) {
		m.selected = row;
		acwm_launch_render();
	}
}

static void acwm_launch_pointer_enter(void *data, struct wl_pointer *pointer,
								  uint32_t serial, struct wl_surface *surface,
								  wl_fixed_t sx, wl_fixed_t sy) {
	(void)data;
	(void)pointer;
	(void)serial;
	(void)surface;
	m.pointer_x = wl_fixed_to_double(sx);
	m.pointer_y = wl_fixed_to_double(sy);
	acwm_launch_hover_at(m.pointer_x, m.pointer_y);
}

static void acwm_launch_pointer_leave(void *data, struct wl_pointer *pointer,
								  uint32_t serial, struct wl_surface *surface) {
	(void)data;
	(void)pointer;
	(void)serial;
	(void)surface;
}

static void acwm_launch_pointer_motion(void *data, struct wl_pointer *pointer,
								   uint32_t time, wl_fixed_t sx,
								   wl_fixed_t sy) {
	(void)data;
	(void)pointer;
	(void)time;
	m.pointer_x = wl_fixed_to_double(sx);
	m.pointer_y = wl_fixed_to_double(sy);
	acwm_launch_hover_at(m.pointer_x, m.pointer_y);
}

static void acwm_launch_pointer_button(void *data, struct wl_pointer *pointer,
								   uint32_t serial, uint32_t time,
								   uint32_t button, uint32_t state) {
	(void)data;
	(void)pointer;
	(void)serial;
	(void)time;
	if (button != BTN_LEFT)
		return;
	if (state == WL_POINTER_BUTTON_STATE_RELEASED)
		return;

	double rows_start = ACWM_LAUNCH_PAD + ACWM_LAUNCH_INPUT_H + 2;
	if (m.filtered_len == 0)
		return;
	if (m.pointer_y < rows_start)
		return;
	size_t row = (size_t)((m.pointer_y - rows_start) / ACWM_LAUNCH_ROW_H);
	if (row >= acwm_launch_rows_visible())
		return;
	if (row < m.filtered_len)
		acwm_launch_launch(m.entries[m.filtered[row]]);
}

static void acwm_launch_pointer_axis(void *data, struct wl_pointer *pointer,
								 uint32_t time, uint32_t axis,
								 wl_fixed_t value) {
	(void)data;
	(void)pointer;
	(void)time;
	if (axis != WL_POINTER_AXIS_VERTICAL_SCROLL)
		return;
	double v = wl_fixed_to_double(value);
	if (fabs(v) < 5.0)
		return;
	if (m.filtered_len == 0)
		return;
	size_t new_sel = m.selected;
	if (v > 0) {
		if (new_sel + 1 < m.filtered_len)
			new_sel++;
	} else {
		if (new_sel > 0)
			new_sel--;
	}
	if (new_sel != m.selected) {
		m.selected = new_sel;
		acwm_launch_render();
	}
}

static void acwm_launch_pointer_frame(void *data, struct wl_pointer *pointer) {
	(void)data;
	(void)pointer;
}

static void acwm_launch_pointer_axis_source(void *data, struct wl_pointer *pointer,
										uint32_t source) {
	(void)data;
	(void)pointer;
	(void)source;
}

static void acwm_launch_pointer_axis_stop(void *data, struct wl_pointer *pointer,
									  uint32_t time, uint32_t axis) {
	(void)data;
	(void)pointer;
	(void)time;
	(void)axis;
}

static void acwm_launch_pointer_axis_discrete(void *data,
										  struct wl_pointer *pointer,
										  uint32_t axis, int32_t discrete) {
	(void)data;
	(void)pointer;
	(void)axis;
	(void)discrete;
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = acwm_launch_pointer_enter,
	.leave = acwm_launch_pointer_leave,
	.motion = acwm_launch_pointer_motion,
	.button = acwm_launch_pointer_button,
	.axis = acwm_launch_pointer_axis,
	.frame = acwm_launch_pointer_frame,
	.axis_source = acwm_launch_pointer_axis_source,
	.axis_stop = acwm_launch_pointer_axis_stop,
	.axis_discrete = acwm_launch_pointer_axis_discrete,
};

static void acwm_launch_edit_backspace(void) {
	if (m.input_len == 0)
		return;
	size_t n = m.input_len;
	while (n > 0 && ((uint8_t)m.input[n - 1] & 0xC0) == 0x80)
		n--;
	if (n > 0)
		n--;
	m.input_len = n;
	m.input[n] = '\0';
}

static void acwm_launch_edit_kill_word(void) {
	size_t n = m.input_len;
	while (n > 0 && (m.input[n - 1] == ' ' || m.input[n - 1] == '\t'))
		n--;
	while (n > 0 && m.input[n - 1] != ' ' && m.input[n - 1] != '\t')
		n--;
	m.input_len = n;
	m.input[n] = '\0';
}

static void acwm_launch_input_append(const char *text, size_t len) {
	if (m.input_len + len >= ACWM_LAUNCH_MAX_INPUT)
		return;
	memcpy(m.input + m.input_len, text, len);
	m.input_len += len;
	m.input[m.input_len] = '\0';
}

static bool acwm_launch_mod_active(const char *name) {
	if (!m.xkb_state)
		return false;
	return xkb_state_mod_name_is_active(m.xkb_state, name,
										XKB_STATE_MODS_EFFECTIVE) > 0;
}

static void acwm_launch_handle_keysym(xkb_keysym_t sym) {
	if (sym == XKB_KEY_Escape) {
		m.running = false;
		return;
	}

	if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
		if (m.filtered_len == 0)
			return;
		acwm_launch_launch(m.entries[m.filtered[m.selected % m.filtered_len]]);
		return;
	}

	bool move = acwm_launch_mod_active(XKB_MOD_NAME_SHIFT);
	if (sym == XKB_KEY_Up || sym == XKB_KEY_ISO_Left_Tab ||
		(sym == XKB_KEY_Tab && move)) {
		if (m.selected > 0) {
			m.selected--;
			acwm_launch_render();
		}
		return;
	}
	if (sym == XKB_KEY_Down ||
		(sym == XKB_KEY_Tab && !move) || sym == XKB_KEY_KP_Tab) {
		if (m.selected + 1 < m.filtered_len) {
			m.selected++;
			acwm_launch_render();
		}
		return;
	}

	if (sym == XKB_KEY_BackSpace) {
		acwm_launch_edit_backspace();
		acwm_launch_refilter();
		acwm_launch_refresh();
		return;
	}
	if (sym == XKB_KEY_Delete) {
		acwm_launch_refilter();
		acwm_launch_refresh();
		return;
	}

	/* Control editing */
	if (acwm_launch_mod_active(XKB_MOD_NAME_CTRL)) {
		if (sym == XKB_KEY_u) {
			m.input_len = 0;
			m.input[0] = '\0';
			acwm_launch_refilter();
			acwm_launch_refresh();
			return;
		}
		if (sym == XKB_KEY_w) {
			acwm_launch_edit_kill_word();
			acwm_launch_refilter();
			acwm_launch_refresh();
			return;
		}
		return; /* other control chords: ignored */
	}

	/* printable input */
	char buffer[8] = {0};
	int n = xkb_keysym_to_utf8(sym, buffer, sizeof(buffer));
	if (n > 0) {
		/* n includes the terminating NUL */
		acwm_launch_input_append(buffer, (size_t)n - 1);
		acwm_launch_refilter();
		acwm_launch_refresh();
	}
}

static void acwm_launch_keyboard_keymap(void *data, struct wl_keyboard *keyboard,
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

static void acwm_launch_keyboard_enter(void *data, struct wl_keyboard *keyboard,
								   uint32_t serial, struct wl_surface *surface,
								   struct wl_array *keys) {
	(void)data;
	(void)keyboard;
	(void)serial;
	(void)surface;
	(void)keys;
}

static void acwm_launch_keyboard_leave(void *data, struct wl_keyboard *keyboard,
								   uint32_t serial,
								   struct wl_surface *surface) {
	(void)data;
	(void)keyboard;
	(void)serial;
	(void)surface;
}

static void acwm_launch_keyboard_key(void *data, struct wl_keyboard *keyboard,
								 uint32_t serial, uint32_t time, uint32_t key,
								 uint32_t state) {
	(void)data;
	(void)keyboard;
	(void)serial;
	(void)time;
	if (state != WL_KEYBOARD_KEY_STATE_PRESSED)
		return;
	if (!m.xkb_state)
		return;

	const xkb_keysym_t *syms;
	int count = xkb_state_key_get_syms(m.xkb_state, key + 8, &syms);
	for (int i = 0; i < count; i++) {
		acwm_launch_handle_keysym(syms[i]);
		if (!m.running)
			break;
	}
}

static void acwm_launch_keyboard_modifiers(void *data,
									   struct wl_keyboard *keyboard,
									   uint32_t serial,
									   uint32_t mods_depressed,
									   uint32_t mods_latched,
									   uint32_t mods_locked, uint32_t group) {
	(void)data;
	(void)keyboard;
	(void)serial;
	if (m.xkb_state)
		xkb_state_update_mask(m.xkb_state, mods_depressed, mods_latched,
							  mods_locked, 0, 0, group);
}

static void acwm_launch_keyboard_repeat_info(void *data,
										 struct wl_keyboard *keyboard,
										 int32_t rate, int32_t delay) {
	(void)data;
	(void)keyboard;
	(void)rate;
	(void)delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
	.keymap = acwm_launch_keyboard_keymap,
	.enter = acwm_launch_keyboard_enter,
	.leave = acwm_launch_keyboard_leave,
	.key = acwm_launch_keyboard_key,
	.modifiers = acwm_launch_keyboard_modifiers,
	.repeat_info = acwm_launch_keyboard_repeat_info,
};

static void acwm_launch_seat_capabilities(void *data, struct wl_seat *seat,
									  uint32_t capabilities) {
	(void)data;
	if ((capabilities & WL_SEAT_CAPABILITY_POINTER) && !m.pointer) {
		m.pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(m.pointer, &pointer_listener, NULL);
	}
	if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && !m.keyboard) {
		m.keyboard = wl_seat_get_keyboard(seat);
		wl_keyboard_add_listener(m.keyboard, &keyboard_listener, NULL);
	}
}

static void acwm_launch_seat_name(void *data, struct wl_seat *seat,
							  const char *name) {
	(void)data;
	(void)seat;
	(void)name;
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = acwm_launch_seat_capabilities,
	.name = acwm_launch_seat_name,
};

/* ------------------------------------------------------------------ */
/* Outputs                                                             */
/* ------------------------------------------------------------------ */

static void acwm_launch_output_name(void *data, struct wl_output *wl_output,
								const char *name) {
	struct acwm_launch_output *output = data;
	(void)wl_output;
	free(output->name);
	output->name = strdup(name);
}

static void acwm_launch_output_geometry(
	void *data, struct wl_output *wl_output, int32_t x, int32_t y,
	int32_t physical_width, int32_t physical_height, int32_t subpixel,
	const char *make, const char *model, int32_t transform) {
	(void)data;
	(void)wl_output;
	(void)x;
	(void)y;
	(void)physical_width;
	(void)physical_height;
	(void)subpixel;
	(void)make;
	(void)model;
	(void)transform;
}

static void acwm_launch_output_mode(void *data, struct wl_output *wl_output,
								uint32_t flags, int32_t width, int32_t height,
								int32_t refresh) {
	(void)data;
	(void)wl_output;
	(void)flags;
	(void)width;
	(void)height;
	(void)refresh;
}

static void acwm_launch_output_done(void *data, struct wl_output *wl_output) {
	(void)data;
	(void)wl_output;
}

static void acwm_launch_output_scale(void *data, struct wl_output *wl_output,
								 int32_t factor) {
	struct acwm_launch_output *output = data;
	(void)wl_output;
	output->scale = factor > 0 ? factor : 1;
}

static void acwm_launch_output_description(void *data, struct wl_output *wl_output,
									   const char *description) {
	(void)data;
	(void)wl_output;
	(void)description;
}

static const struct wl_output_listener output_listener = {
	.geometry = acwm_launch_output_geometry,
	.mode = acwm_launch_output_mode,
	.done = acwm_launch_output_done,
	.scale = acwm_launch_output_scale,
	.name = acwm_launch_output_name,
	.description = acwm_launch_output_description,
};

/* ------------------------------------------------------------------ */
/* Registry + setup                                                    */
/* ------------------------------------------------------------------ */

static void acwm_launch_registry_global(void *data, struct wl_registry *registry,
									uint32_t name, const char *interface,
									uint32_t version) {
	(void)data;
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		m.compositor = wl_registry_bind(
			registry, name, &wl_compositor_interface, version > 4 ? 4 : version);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		m.shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		m.seat = wl_registry_bind(registry, name, &wl_seat_interface,
								  version > 5 ? 5 : version);
		wl_seat_add_listener(m.seat, &seat_listener, NULL);
	} else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
		m.layer_shell = wl_registry_bind(
			registry, name, &zwlr_layer_shell_v1_interface,
			version > 4 ? 4 : version);
	} else if (strcmp(interface,
					  zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
		m.foreign_manager = wl_registry_bind(
			registry, name, &zwlr_foreign_toplevel_manager_v1_interface,
			version > 3 ? 3 : version);
		zwlr_foreign_toplevel_manager_v1_add_listener(
			m.foreign_manager, &toplevel_manager_listener, NULL);
	} else if (strcmp(interface, wl_output_interface.name) == 0) {
		struct acwm_launch_output *output = calloc(1, sizeof(*output));
		if (!output)
			return;
		output->global_name = name;
		output->wl_output = wl_registry_bind(
			registry, name, &wl_output_interface, version > 4 ? 4 : version);
		wl_output_add_listener(output->wl_output, &output_listener, output);
		wl_list_insert(m.outputs.prev, &output->link);
	}
}

static void acwm_launch_registry_global_remove(void *data,
										   struct wl_registry *registry,
										   uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = acwm_launch_registry_global,
	.global_remove = acwm_launch_registry_global_remove,
};

static void acwm_launch_setup_surface(void) {
	m.surface = wl_compositor_create_surface(m.compositor);
	m.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
		m.layer_shell, m.surface, m.output,
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, ACWM_LAUNCH_NAMESPACE);
	zwlr_layer_surface_v1_add_listener(m.layer_surface, &layer_surface_listener,
									   NULL);
	zwlr_layer_surface_v1_set_exclusive_zone(m.layer_surface, -1);
	zwlr_layer_surface_v1_set_keyboard_interactivity(
		m.layer_surface,
		ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);

	m.width = m.target_width;
	m.height = acwm_launch_target_height();
	zwlr_layer_surface_v1_set_size(m.layer_surface, m.width, m.height);
	wl_surface_commit(m.surface);
}

static char *acwm_launch_small_font(const char *font) {
	if (!font || !font[0])
		return strdup("sans 9");
	char *copy = strdup(font);
	if (!copy)
		return NULL;
	char *last_space = strrchr(copy, ' ');
	if (last_space && last_space[1] >= '1' && last_space[1] <= '9') {
		bool all_digits = true;
		for (const char *p = last_space + 1; *p; p++) {
			if (*p < '0' || *p > '9') {
				all_digits = false;
				break;
			}
		}
		if (all_digits) {
			int size = atoi(last_space + 1);
			if (size > 4) {
				snprintf(last_space + 1, strlen(last_space + 1) + 1, "%d",
						 size - 2);
				return copy;
			}
		}
	}
	free(copy);
	return strdup("sans 9");
}

static void acwm_launch_usage(void) {
	fprintf(stderr,
			"Usage: acwm-launch [options]\n"
			"  -f, --font <pango font>     font description (default sans 10)\n"
			"  -w, --width <px>            logical window width\n"
			"  -r, --rows <n>              max visible rows\n"
			"  -o, --output <name>         output to show on\n"
			"  -h, --help                  show this help\n");
}

static void acwm_launch_destroy(void) {
	for (size_t i = 0; i < m.entries_len; i++) {
		struct acwm_launch_entry *e = m.entries[i];
		free(e->name);
		free(e->desc);
		free(e->icon);
		free(e->exec);
		free(e->exec_path);
		for (size_t j = 0; j < e->ids_len; j++)
			free(e->ids[j]);
		free(e->ids);
		if (e->icon_surface)
			cairo_surface_destroy(e->icon_surface);
		free(e);
	}
	free(m.entries);

	for (size_t i = 0; i < m.toplevels_len; i++) {
		free(m.toplevels[i]->app_id);
		free(m.toplevels[i]->title);
		free(m.toplevels[i]);
	}
	free(m.toplevels);

	free(m.filtered);
	free(m.font);
	free(m.desc_font);
	free(m.output_name);

	if (m.layer_surface) {
		zwlr_layer_surface_v1_destroy(m.layer_surface);
		m.layer_surface = NULL;
	}
	if (m.surface) {
		wl_surface_destroy(m.surface);
		m.surface = NULL;
	}
	if (m.display)
		wl_display_flush(m.display);

	if (m.pointer)
		wl_pointer_destroy(m.pointer);
	if (m.keyboard)
		wl_keyboard_destroy(m.keyboard);
	if (m.seat)
		wl_seat_destroy(m.seat);
	if (m.layer_shell)
		zwlr_layer_shell_v1_destroy(m.layer_shell);
	if (m.foreign_manager)
		zwlr_foreign_toplevel_manager_v1_destroy(m.foreign_manager);
	if (m.compositor)
		wl_compositor_destroy(m.compositor);
	if (m.shm)
		wl_shm_destroy(m.shm);
	if (m.registry)
		wl_registry_destroy(m.registry);

	struct acwm_launch_output *output, *tmp;
	wl_list_for_each_safe(output, tmp, &m.outputs, link) {
		wl_list_remove(&output->link);
		if (output->wl_output)
			wl_output_destroy(output->wl_output);
		free(output->name);
		free(output);
	}

	if (m.xkb_state)
		xkb_state_unref(m.xkb_state);
	if (m.xkb_keymap)
		xkb_keymap_unref(m.xkb_keymap);
	if (m.xkb_ctx)
		xkb_context_unref(m.xkb_ctx);

	if (m.display)
		wl_display_disconnect(m.display);
}

int main(int argc, char *argv[]) {
	memset(&m, 0, sizeof(m));

	m.font = strdup("sans 10");
	m.desc_font = acwm_launch_small_font(m.font);
	m.max_rows = 8;
	m.running = true;
	wl_list_init(&m.outputs);

	{
		const char *env;
		if ((env = getenv("ACWM_LAUNCH_FONT")) && env[0]) {
			free(m.font);
			m.font = strdup(env);
		}
		if ((env = getenv("ACWM_LAUNCH_WIDTH")) && env[0])
			m.target_width = (uint32_t)atoi(env);
		if ((env = getenv("ACWM_LAUNCH_MAX_ROWS")) && env[0])
			m.max_rows = atoi(env);
	}
	if (m.target_width < 200)
		m.target_width = 440;
	if (m.max_rows < 1)
		m.max_rows = 1;
	if (m.max_rows > 20)
		m.max_rows = 20;

	int opt;
	while ((opt = getopt(argc, argv, "f:w:r:o:h")) != -1) {
		switch (opt) {
		case 'f':
			free(m.font);
			m.font = strdup(optarg);
			free(m.desc_font);
			m.desc_font = acwm_launch_small_font(m.font);
			break;
		case 'w':
			m.target_width = (uint32_t)atoi(optarg);
			break;
		case 'r':
			m.max_rows = atoi(optarg);
			break;
		case 'o':
			free(m.output_name);
			m.output_name = strdup(optarg);
			break;
		case 'h':
			acwm_launch_usage();
			return EXIT_SUCCESS;
		default:
			acwm_launch_usage();
			return EXIT_FAILURE;
		}
	}
	if (m.target_width < 200)
		m.target_width = 440;
	if (m.max_rows < 1)
		m.max_rows = 1;
	if (m.max_rows > 20)
		m.max_rows = 20;

	struct sigaction sa = {.sa_handler = acwm_launch_signal, .sa_flags = 0};
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	m.xkb_ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	m.display = wl_display_connect(NULL);
	if (!m.display) {
		fprintf(stderr, "acwm-launch: failed to connect to the compositor\n");
		acwm_launch_destroy();
		return EXIT_FAILURE;
	}
	m.registry = wl_display_get_registry(m.display);
	wl_registry_add_listener(m.registry, &registry_listener, NULL);
	/* two passes: globals bound, output/seat events dispatched */
	wl_display_roundtrip(m.display);
	wl_display_roundtrip(m.display);

	if (!m.compositor || !m.shm || !m.layer_shell) {
		fprintf(stderr, "acwm-launch: missing required compositor globals\n");
		acwm_launch_destroy();
		return EXIT_FAILURE;
	}

	acwm_launch_load_desktops();
	acwm_launch_load_appimages();

	/* foreign toplevels: ask for the initial set and give the compositor a
	 * couple of passes to deliver app_id/title events */
	if (m.foreign_manager) {
		wl_display_roundtrip(m.display);
		wl_display_roundtrip(m.display);
		wl_display_roundtrip(m.display);
		acwm_launch_toplevels_apply();
	}

	acwm_launch_sort_entries();
	acwm_launch_refilter();

	/* pick output: requested, else first advertised */
	{
		struct acwm_launch_output *output;
		wl_list_for_each(output, &m.outputs, link) {
			if (m.output_name && output->name &&
				strcmp(output->name, m.output_name) == 0) {
				m.output = output->wl_output;
				if (output->scale > 0)
					m.scale = output->scale;
				break;
			}
		}
		if (!m.output) {
			wl_list_for_each(output, &m.outputs, link) {
				m.output = output->wl_output;
				break;
			}
			wl_list_for_each(output, &m.outputs, link) {
				if (output->scale > m.scale)
					m.scale = output->scale;
			}
		}
	}

	acwm_launch_setup_surface();

	while (m.running) {
		if (wl_display_dispatch_pending(m.display) < 0)
			break;
		if (wl_display_flush(m.display) < 0 && errno != EAGAIN)
			break;

		struct pollfd pfd = {
			.fd = wl_display_get_fd(m.display),
			.events = POLLIN,
		};
		int ret = poll(&pfd, 1, 30000);
		if (ret == 0) {
			/* idle for 30 s with no events — nothing more to wait for */
		} else if (ret < 0) {
			if (errno == EINTR)
				continue;
			break;
		}

		if (pfd.revents & POLLIN) {
			if (wl_display_dispatch(m.display) < 0)
				break;
		}
	}

	acwm_launch_destroy();
	return EXIT_SUCCESS;
}
