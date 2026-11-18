#ifndef jump_label_node_H
#define jump_label_node_H

#include <cairo.h>
#include <pango/pango.h>
#include <pango/pangocairo.h>
#include <stdbool.h>
#include <stdint.h>

#if defined(__has_include) && __has_include(<scenefx/types/wlr_scene.h>)
#include <scenefx/types/wlr_scene.h>
#else
#include <wlr/types/wlr_scene.h>
#endif

typedef struct {
	float fg_color[4];
	float bg_color[4];
	float focus_fg_color[4];
	float focus_bg_color[4];
	float border_color[4];
	int32_t border_width;
	int32_t corner_radius;
	int32_t padding_x;
	int32_t padding_y;
	const char *font_desc;
} DecorateDrawData;

struct acwm_text_buffer {
	struct wlr_buffer base;
	cairo_surface_t *surface;
};

struct acwm_text_measure {
	cairo_surface_t *surface;
	cairo_t *cr;
	PangoContext *context;
	PangoLayout *layout;
	float scale;
};

typedef struct AcwmJumpLabel {
	struct wlr_scene_tree *scene;
	struct wlr_scene_rect *border;
	struct wlr_scene_rect *bg;
	struct wlr_scene_buffer *scene_buffer;
	struct acwm_text_buffer *buffer;
	struct acwm_text_measure measure;

	float fg_color[4];
	float bg_color[4];
	float focus_fg_color[4];
	float focus_bg_color[4];
	float border_color[4];
	int32_t border_width;
	int32_t corner_radius;
	int32_t padding_x;
	int32_t padding_y;
	char *font_desc;

	char *cached_text;
	char *cached_font_desc;
	float cached_scale;
	float cached_fg_color[4];
	bool cached_focused;
	int32_t surface_pixel_w;
	int32_t surface_pixel_h;

	bool focused;

	int32_t text_logical_w;
	int32_t text_logical_h;
	int32_t logical_width;
	int32_t logical_height;
} AcwmJumpLabel;

typedef struct AcwmBarDecoration {
	uint32_t type;
	bool is_tab;
	struct wlr_scene_tree *scene;
	struct wlr_scene_rect *border;
	struct wlr_scene_rect *bg;
	struct wlr_scene_buffer *scene_buffer;
	struct acwm_text_buffer *buffer;
	void *node_data;
	struct acwm_text_measure measure;

	float fg_color[4];
	float bg_color[4];
	float focus_fg_color[4];
	float focus_bg_color[4];
	float border_color[4];
	int32_t border_width;
	int32_t corner_radius;
	int32_t padding_x;
	int32_t padding_y;
	char *font_desc;

	int32_t target_width;
	int32_t target_height;

	char *cached_text;
	char *cached_font_desc;
	float cached_scale;
	float cached_fg_color[4];
	bool cached_focused;
	int32_t cached_clip_pixel_w;
	int32_t surface_pixel_w;
	int32_t surface_pixel_h;

	bool focused;

	char *last_text;
	float last_scale;

	int32_t text_logical_w;
	int32_t text_logical_h;
	int32_t logical_width;
	int32_t logical_height;

	struct wlr_scene_buffer *close_buffer;
	struct acwm_text_buffer *close_texture;
	bool close_enabled;
	bool close_hover;
	int32_t close_size;
	int32_t close_margin;
	float close_color[4];
	float close_hover_color[4];
	float close_x_color[4];
	int32_t close_cached_size;
	float close_cached_scale;
	bool close_cached_hover;
	bool close_cached_valid;
} AcwmBarDecoration;

void acwm_text_global_finish(void);
AcwmJumpLabel *acwm_jump_label_node_create(struct wlr_scene_tree *parent,
											 DecorateDrawData data);
void acwm_jump_label_node_destroy(AcwmJumpLabel *node);
void acwm_jump_label_node_set_background(AcwmJumpLabel *node, float r,
										  float g, float b, float a);
void acwm_jump_label_node_set_border(AcwmJumpLabel *node, float r, float g,
									  float b, float a, int32_t width,
									  int32_t radius);
void acwm_jump_label_node_set_padding(AcwmJumpLabel *node, int32_t pad_x,
									   int32_t pad_y);
void acwm_jump_label_node_update(AcwmJumpLabel *node, const char *text,
								  float scale);

AcwmBarDecoration *acwm_bar_decoration_create(void *cdata, uint32_t type,
												bool is_tab,
												struct wlr_scene_tree *parent,
												DecorateDrawData data,
												int32_t width, int32_t height);
void acwm_bar_decoration_destroy(AcwmBarDecoration *node);
void acwm_bar_decoration_set_size(AcwmBarDecoration *node, int32_t width,
								   int32_t height);
void acwm_bar_decoration_update(AcwmBarDecoration *node, const char *text,
								 float scale);

void acwm_jump_label_node_set_focus(AcwmJumpLabel *node, bool focused);
void acwm_bar_decoration_set_focus(AcwmBarDecoration *node, bool focused);

void acwm_bar_decoration_set_colors(AcwmBarDecoration *node,
									 const float fg[4], const float bg[4]);

void acwm_bar_decoration_set_close(AcwmBarDecoration *node, bool enabled,
									int32_t size, int32_t margin);
void acwm_bar_decoration_set_close_color(AcwmBarDecoration *node,
										  const float circle[4]);
void acwm_bar_decoration_set_close_hover(AcwmBarDecoration *node, bool hover);
bool acwm_bar_decoration_close_contains(AcwmBarDecoration *node, double lx,
										 double ly);

void acwm_jump_label_node_apply_config(AcwmJumpLabel *node,
										const DecorateDrawData *data);
void acwm_bar_decoration_apply_config(AcwmBarDecoration *node,
									   const DecorateDrawData *data);
#endif // jump_label_node_H
