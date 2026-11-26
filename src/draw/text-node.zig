//! Port of src/draw/text-node.c (strangler-fig Phase 4, draw slice,
//! slice 36).
//!
//! Cairo/Pango text surfaces wrapped as wlr_buffers, scene rect/buffer
//! decorators for jump labels and bar decorations. Cairo, Pango, wlroots and
//! scenefx stay linked; the C twin is guarded with ACWM_ZIG_TEXT_NODE.
//!
//! The font cache mirrors the C GHashTable with a small libc-linked list.
//! Corner radii are compiled in when scenefx exposes them.

const std = @import("std");
const c = @import("cc");

const TextBuffer = extern struct {
    base: c.struct_wlr_buffer,
    surface: ?*c.cairo_surface_t,
};

const DRM_FORMAT_ARGB8888: u32 = 0x34325241; // fourcc 'AR24'

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(str: [*:0]const u8) ?[*:0]u8;
extern "c" fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn memcmp(a: ?*const anyopaque, b: ?*const anyopaque, n: usize) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;

extern fn g_free(ptr: ?*anyopaque) callconv(.c) void;
extern fn g_object_unref(obj: ?*anyopaque) callconv(.c) void;
extern fn pango_font_description_from_string(str: [*:0]const u8) ?*c.PangoFontDescription;
extern fn pango_font_description_free(desc: ?*c.PangoFontDescription) void;
extern fn pango_cairo_font_map_set_default(font_map: ?*anyopaque) void;
extern fn acwm_scene_node_set(node: [*c]c.struct_wlr_scene_node, node_type: u32, data: ?*anyopaque) ?*anyopaque;

const FontEntry = struct {
    next: ?*FontEntry,
    key: [*:0]u8,
    desc: *c.PangoFontDescription,
};

var font_cache: ?*FontEntry = null;

fn dupStr(s: [*:0]const u8) [*:0]u8 {
    return strdup(s) orelse @panic("out of memory");
}

fn dupOptional(s: [*c]const u8, fallback: [*:0]const u8) [*:0]u8 {
    if (s == null)
        return dupStr(fallback);
    return dupStr(@ptrCast(s));
}

fn containerOf(comptime T: type, comptime field: []const u8, ptr: *c.struct_wlr_buffer) *T {
    return @ptrFromInt(@intFromPtr(ptr) - @offsetOf(T, field));
}

fn getCachedFontDesc(font_desc: [*:0]const u8) *c.PangoFontDescription {
    var it = font_cache;
    while (it) |entry| : (it = entry.next) {
        if (strcmp(entry.key, font_desc) == 0)
            return entry.desc;
    }
    const desc = pango_font_description_from_string(font_desc) orelse @panic("bad font description");
    const entry: *FontEntry = @ptrCast(@alignCast(calloc(1, @sizeOf(FontEntry)) orelse @panic("oom")));
    entry.next = font_cache;
    entry.key = dupStr(font_desc);
    entry.desc = desc;
    font_cache = entry;
    return desc;
}

export fn acwm_text_global_finish() callconv(.c) void {
    var it = font_cache;
    while (it) |entry| {
        const next = entry.next;
        pango_font_description_free(entry.desc);
        free(@ptrCast(entry.key));
        free(@ptrCast(entry));
        it = next;
    }
    font_cache = null;
    pango_cairo_font_map_set_default(null);
}

// ---------------------------------------------------------------------------
// wlr_buffer implementation
// ---------------------------------------------------------------------------

export fn text_buffer_destroy(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    const buf = containerOf(TextBuffer, "base", buffer);
    if (buf.surface != null)
        c.cairo_surface_destroy(buf.surface);
    free(@ptrCast(buf));
}

export fn text_buffer_begin_data_ptr_access(
    buffer: [*c]c.struct_wlr_buffer,
    flags: u32,
    data: [*c]?*anyopaque,
    format: [*c]u32,
    stride: [*c]usize,
) callconv(.c) bool {
    if ((flags & c.WLR_BUFFER_DATA_PTR_ACCESS_WRITE) != 0)
        return false;
    const buf = containerOf(TextBuffer, "base", buffer);
    if (buf.surface == null)
        return false;
    data[0] = @ptrCast(c.cairo_image_surface_get_data(buf.surface));
    format[0] = DRM_FORMAT_ARGB8888;
    stride[0] = @intCast(c.cairo_image_surface_get_stride(buf.surface));
    return true;
}

export fn text_buffer_end_data_ptr_access(buffer: [*c]c.struct_wlr_buffer) callconv(.c) void {
    _ = buffer;
}

var text_buffer_impl: c.struct_wlr_buffer_impl = .{
    .destroy = text_buffer_destroy,
    .begin_data_ptr_access = text_buffer_begin_data_ptr_access,
    .end_data_ptr_access = text_buffer_end_data_ptr_access,
};

const has_corner_radius = @hasDecl(c, "wlr_scene_rect_set_corner_radii");

// ---------------------------------------------------------------------------
// scene rectangles
// ---------------------------------------------------------------------------

fn rectApply(rect: [*c]c.struct_wlr_scene_rect, color: *const [4]f32, radius_in: i32, x: i32, y: i32, width_in: i32, height_in: i32) void {
    var premultiplied = [4]f32{
        color[0] * color[3],
        color[1] * color[3],
        color[2] * color[3],
        color[3],
    };
    c.wlr_scene_rect_set_color(rect, &premultiplied);

    var width = width_in;
    var height = height_in;
    if (width < 0)
        width = 0;
    if (height < 0)
        height = 0;

    if (comptime has_corner_radius) {
        var radius = radius_in;
        const limit = @divTrunc(@min(width, height), 2);
        if (radius < 0)
            radius = limit
        else if (radius > limit)
            radius = limit;
        c.wlr_scene_rect_set_corner_radii(rect, c.corner_radii_all(radius));
    }

    c.wlr_scene_node_set_position(&rect.*.node, x, y);
    c.wlr_scene_rect_set_size(rect, width, height);
}

fn rectApplyBorder(
    rect: [*c]c.struct_wlr_scene_rect,
    color: *const [4]f32,
    outer_radius: i32,
    inner_radius: i32,
    border: i32,
    width: i32,
    height: i32,
) void {
    rectApply(rect, color, outer_radius, 0, 0, width, height);

    if (comptime has_corner_radius) {
        const inner_w = width - 2 * border;
        const inner_h = height - 2 * border;
        if (border > 0 and inner_w > 0 and inner_h > 0) {
            var clipped = c.clipped_region_get_default();
            clipped.area = .{ .x = border, .y = border, .width = inner_w, .height = inner_h };
            clipped.corners = c.corner_radii_all(inner_radius);
            c.wlr_scene_rect_set_clipped_region(rect, clipped);
        } else {
            c.wlr_scene_rect_set_clipped_region(rect, c.clipped_region_get_default());
        }
    }
}

// ---------------------------------------------------------------------------
// text measurement / rendering
// ---------------------------------------------------------------------------

fn layoutConfigure(layout: *c.PangoLayout, font_desc: [*:0]const u8, text: [*:0]const u8) void {
    c.pango_layout_set_font_description(layout, getCachedFontDesc(font_desc));
    c.pango_layout_set_text(layout, text, -1);
}

fn measureInit(measure: *c.struct_acwm_text_measure) void {
    measure.surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
    measure.cr = c.cairo_create(measure.surface);
    measure.context = c.pango_cairo_create_context(measure.cr);
    measure.layout = c.pango_layout_new(measure.context);
    measure.scale = 1.0;
}

fn measureFinish(measure: *c.struct_acwm_text_measure) void {
    if (measure.layout != null) {
        g_object_unref(@ptrCast(measure.layout));
        measure.layout = null;
    }
    if (measure.context != null) {
        g_object_unref(@ptrCast(measure.context));
        measure.context = null;
    }
    if (measure.cr != null) {
        c.cairo_destroy(measure.cr);
        measure.cr = null;
    }
    if (measure.surface != null) {
        c.cairo_surface_destroy(measure.surface);
        measure.surface = null;
    }
}

fn measureText(measure: *c.struct_acwm_text_measure, font_desc: [*:0]const u8, text: [*:0]const u8, scale_in: f32, out_pixel_w: *c_int, out_pixel_h: *c_int) void {
    var scale = scale_in;
    if (scale <= 0.0)
        scale = 1.0;
    if (measure.scale != scale) {
        c.pango_cairo_context_set_resolution(measure.context, 96.0 * @as(f64, scale));
        measure.scale = scale;
    }

    layoutConfigure(measure.layout.?, font_desc, text);
    c.pango_layout_get_pixel_size(measure.layout, out_pixel_w, out_pixel_h);
}

fn utf8Next(p: [*]const u8) [*]const u8 {
    const ch = p[0];
    const n: usize = if (ch < 0x80) 1 else if ((ch & 0xe0) == 0xc0) 2 else if ((ch & 0xf0) == 0xe0) 3 else if ((ch & 0xf8) == 0xf0) 4 else 1;
    return p + n;
}

fn dupPrefixEllipsis(text: [*:0]const u8, prefix_len: usize) [*:0]u8 {
    var buf: [8192]u8 = undefined;
    const n = @min(prefix_len, buf.len - 4);
    @memcpy(buf[0..n], text[0..n]);
    buf[n] = 0xe2;
    buf[n + 1] = 0x80;
    buf[n + 2] = 0xa6;
    buf[n + 3] = 0;
    return dupStr(@ptrCast(&buf));
}

fn textEllipsize(measure: *c.struct_acwm_text_measure, font_desc: [*:0]const u8, text: [*:0]const u8, scale: f32, max_pixel_w: i32) [*:0]u8 {
    var pixel_w: c_int = 0;
    var pixel_h: c_int = 0;
    var best: c_int = 0;
    const len = strlen(text);

    measureText(measure, font_desc, "\xe2\x80\xa6", scale, &pixel_w, &pixel_h);
    if (pixel_w > max_pixel_w)
        return dupStr("\xe2\x80\xa6");

    const base: [*]const u8 = @ptrCast(text);
    var pos = utf8Next(base);
    while (@intFromPtr(pos) <= @intFromPtr(base) + len) : (pos = utf8Next(pos)) {
        const length: usize = @intFromPtr(pos) - @intFromPtr(base);
        const candidate = dupPrefixEllipsis(text, length);
        defer g_free(@ptrCast(candidate));
        measureText(measure, font_desc, candidate, scale, &pixel_w, &pixel_h);
        if (pixel_w > max_pixel_w)
            break;
        best = @intCast(length);
    }

    return dupPrefixEllipsis(text, @intCast(best));
}

fn textSurfaceCreate(
    measure: *c.struct_acwm_text_measure,
    font_desc: [*:0]const u8,
    text: [*:0]const u8,
    scale_in: f32,
    color: *const [4]f32,
    out_pixel_w: *c_int,
    out_pixel_h: *c_int,
) ?*c.cairo_surface_t {
    var scale = scale_in;
    if (scale <= 0.0)
        scale = 1.0;

    var width: c_int = 0;
    var height: c_int = 0;
    measureText(measure, font_desc, text, scale, &width, &height);
    out_pixel_w.* = 0;
    out_pixel_h.* = 0;
    if (width <= 0 or height <= 0)
        return null;

    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, height);
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surface);
        return null;
    }

    const cr = c.cairo_create(surface);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const context = c.pango_cairo_create_context(cr);
    c.pango_cairo_context_set_resolution(context, 96.0 * @as(f64, scale));
    const layout = c.pango_layout_new(context);
    layoutConfigure(layout.?, font_desc, text);
    c.cairo_move_to(cr, 0.0, 0.0);
    c.cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
    c.pango_cairo_show_layout(cr, layout);
    c.cairo_surface_flush(surface);

    g_object_unref(@ptrCast(layout));
    g_object_unref(@ptrCast(context));
    c.cairo_destroy(cr);

    out_pixel_w.* = width;
    out_pixel_h.* = height;
    return surface;
}

// ---------------------------------------------------------------------------
// scene buffer installation
// ---------------------------------------------------------------------------

fn textNodeInstall(
    scene_buffer: [*c]c.struct_wlr_scene_buffer,
    slot: *[*c]c.struct_acwm_text_buffer,
    surface: ?*c.cairo_surface_t,
    pixel_w: i32,
    pixel_h: i32,
) void {
    if (slot.* != null) {
        c.wlr_buffer_drop(&slot.*.*.base);
        slot.* = null;
    }

    if (surface == null) {
        c.wlr_scene_buffer_set_buffer(scene_buffer, null);
        c.wlr_scene_buffer_set_dest_size(scene_buffer, 0, 0);
        return;
    }

    const buf: *TextBuffer = @ptrCast(@alignCast(calloc(1, @sizeOf(TextBuffer)) orelse {
        c.cairo_surface_destroy(surface);
        return;
    }));
    c.wlr_buffer_init(&buf.base, &text_buffer_impl, pixel_w, pixel_h);
    buf.surface = surface;
    slot.* = @ptrCast(buf);

    c.wlr_scene_buffer_set_buffer(scene_buffer, &buf.base);
}

fn textNodeApplySize(
    scene_buffer: [*c]c.struct_wlr_scene_buffer,
    pixel_w: i32,
    pixel_h: i32,
    scale_in: f32,
    max_logical_w: i32,
    max_logical_h: i32,
    out_logical_w: *c_int,
    out_logical_h: *c_int,
) void {
    var scale = scale_in;
    if (scale <= 0.0)
        scale = 1.0;

    var clip_pixel_w = pixel_w;
    var clip_pixel_h = pixel_h;

    if (max_logical_w > 0) {
        const max_pixel_w: i32 = @intFromFloat(@as(f32, @floatFromInt(max_logical_w)) * scale + 0.5);
        if (max_pixel_w < clip_pixel_w)
            clip_pixel_w = max_pixel_w;
    }
    if (max_logical_h > 0) {
        const max_pixel_h: i32 = @intFromFloat(@as(f32, @floatFromInt(max_logical_h)) * scale + 0.5);
        if (max_pixel_h < clip_pixel_h)
            clip_pixel_h = max_pixel_h;
    }
    if (clip_pixel_w < 0)
        clip_pixel_w = 0;
    if (clip_pixel_h < 0)
        clip_pixel_h = 0;

    if (pixel_w > 0 and (clip_pixel_w < pixel_w or clip_pixel_h < pixel_h)) {
        const box = c.struct_wlr_fbox{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(clip_pixel_w),
            .height = @floatFromInt(clip_pixel_h),
        };
        c.wlr_scene_buffer_set_source_box(scene_buffer, &box);
    } else {
        c.wlr_scene_buffer_set_source_box(scene_buffer, null);
    }

    const logical_w: i32 = @intFromFloat(@as(f32, @floatFromInt(clip_pixel_w)) / scale + 0.5);
    const logical_h: i32 = @intFromFloat(@as(f32, @floatFromInt(clip_pixel_h)) / scale + 0.5);
    c.wlr_scene_buffer_set_dest_size(scene_buffer, logical_w, logical_h);

    out_logical_w.* = logical_w;
    out_logical_h.* = logical_h;
}

fn textNodeClear(
    scene_buffer: [*c]c.struct_wlr_scene_buffer,
    slot: *[*c]c.struct_acwm_text_buffer,
    border: [*c]c.struct_wlr_scene_rect,
    bg: [*c]c.struct_wlr_scene_rect,
) void {
    textNodeInstall(scene_buffer, slot, null, 0, 0);
    c.wlr_scene_buffer_set_source_box(scene_buffer, null);
    c.wlr_scene_rect_set_size(border, 0, 0);
    c.wlr_scene_rect_set_size(bg, 0, 0);
    if (comptime has_corner_radius)
        c.wlr_scene_rect_set_clipped_region(border, c.clipped_region_get_default());
}

// ---------------------------------------------------------------------------
// jump labels
// ---------------------------------------------------------------------------

export fn acwm_jump_label_node_create(parent: [*c]c.struct_wlr_scene_tree, data: c.DecorateDrawData) callconv(.c) ?*c.AcwmJumpLabel {
    const node: *c.AcwmJumpLabel = @ptrCast(@alignCast(calloc(1, @sizeOf(c.AcwmJumpLabel)) orelse return null));

    node.scene = c.wlr_scene_tree_create(parent);
    if (node.scene == null) {
        free(@ptrCast(node));
        return null;
    }

    const zero = [4]f32{ 0, 0, 0, 0 };
    node.border = c.wlr_scene_rect_create(node.scene, 0, 0, &zero);
    node.bg = c.wlr_scene_rect_create(node.scene, 0, 0, &zero);
    node.scene_buffer = c.wlr_scene_buffer_create(node.scene, null);
    if (node.border == null or node.bg == null or node.scene_buffer == null) {
        c.wlr_scene_node_destroy(&node.scene.*.node);
        free(@ptrCast(node));
        return null;
    }

    node.fg_color = data.fg_color;
    node.bg_color = data.bg_color;
    node.focus_fg_color = data.focus_fg_color;
    node.focus_bg_color = data.focus_bg_color;
    node.border_color = data.border_color;
    node.border_width = data.border_width;
    node.corner_radius = data.corner_radius;
    node.padding_x = data.padding_x;
    node.padding_y = data.padding_y;
    node.font_desc = dupOptional(data.font_desc, "monospace Bold 16");

    node.cached_scale = -1.0;
    node.scene_buffer.*.node.data = null;
    measureInit(&node.measure);

    return node;
}

export fn acwm_jump_label_node_destroy(node_in: ?*c.AcwmJumpLabel) callconv(.c) void {
    const node = node_in orelse return;

    if (node.buffer != null) {
        c.wlr_buffer_drop(&node.buffer.*.base);
        node.buffer = null;
    }
    if (node.scene != null) {
        c.wlr_scene_node_destroy(&node.scene.*.node);
        node.scene = null;
    }

    measureFinish(&node.measure);

    if (node.font_desc != null)
        g_free(@ptrCast(node.font_desc));
    if (node.cached_text != null)
        g_free(@ptrCast(node.cached_text));
    if (node.cached_font_desc != null)
        g_free(@ptrCast(node.cached_font_desc));

    free(@ptrCast(node));
}

fn jumpLabelApplyGeometry(node: *c.AcwmJumpLabel) void {
    const scale: f32 = if (node.cached_scale > 0.0) node.cached_scale else 1.0;

    textNodeApplySize(node.scene_buffer, node.surface_pixel_w, node.surface_pixel_h, scale, 0, 0, &node.text_logical_w, &node.text_logical_h);

    if (node.text_logical_w <= 0 or node.text_logical_h <= 0) {
        c.wlr_scene_rect_set_size(node.border, 0, 0);
        c.wlr_scene_rect_set_size(node.bg, 0, 0);
        node.logical_width = 0;
        node.logical_height = 0;
        return;
    }

    const border: i32 = if (node.border_width > 0) node.border_width else 0;
    const width = node.text_logical_w + 2 * node.padding_x + 2 * border;
    const height = node.text_logical_h + 2 * node.padding_y + 2 * border;

    node.logical_width = width;
    node.logical_height = height;

    rectApplyBorder(node.border, &node.border_color, node.corner_radius, node.corner_radius, border, width, height);
    const bg_color: *const [4]f32 = if (node.focused) &node.focus_bg_color else &node.bg_color;
    rectApply(node.bg, bg_color, node.corner_radius, border, border, width - 2 * border, height - 2 * border);

    c.wlr_scene_node_set_position(&node.scene_buffer.*.node, border + node.padding_x, border + node.padding_y);
}

export fn acwm_jump_label_node_update(node_in: ?*c.AcwmJumpLabel, text: [*c]const u8, scale_in: f32) callconv(.c) void {
    const node = node_in orelse return;
    if (text == null)
        return;
    var scale = scale_in;
    if (scale <= 0.0)
        scale = 1.0;

    const fg_color: *const [4]f32 = if (node.focused) &node.focus_fg_color else &node.fg_color;

    const dirty = node.cached_scale != scale or node.cached_text == null or
        strcmp(node.cached_text, @ptrCast(text)) != 0 or node.cached_font_desc == null or
        strcmp(node.cached_font_desc, node.font_desc) != 0 or
        memcmp(&node.cached_fg_color, fg_color, @sizeOf([4]f32)) != 0 or
        node.cached_focused != node.focused;

    if (dirty) {
        if (node.cached_text != null)
            g_free(@ptrCast(node.cached_text));
        node.cached_text = dupStr(@ptrCast(text));
        if (node.cached_font_desc != null)
            g_free(@ptrCast(node.cached_font_desc));
        node.cached_font_desc = dupStr(node.font_desc);
        node.cached_scale = scale;
        node.cached_fg_color = fg_color.*;
        node.cached_focused = node.focused;

        const surface = textSurfaceCreate(&node.measure, node.font_desc, @ptrCast(text), scale, fg_color, &node.surface_pixel_w, &node.surface_pixel_h);
        textNodeInstall(node.scene_buffer, &node.buffer, surface, node.surface_pixel_w, node.surface_pixel_h);
    }

    jumpLabelApplyGeometry(node);
}

export fn acwm_jump_label_node_set_focus(node_in: ?*c.AcwmJumpLabel, focused: bool) callconv(.c) void {
    const node = node_in orelse return;
    if (node.focused == focused)
        return;
    node.focused = focused;
    if (node.cached_text != null)
        acwm_jump_label_node_update(node, node.cached_text, if (node.cached_scale > 0.0) node.cached_scale else 1.0);
}

export fn acwm_jump_label_node_set_background(node_in: ?*c.AcwmJumpLabel, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    const node = node_in orelse return;
    node.bg_color = .{ r, g, b, a };
    if (node.cached_text != null)
        acwm_jump_label_node_update(node, node.cached_text, if (node.cached_scale > 0.0) node.cached_scale else 1.0);
}

export fn acwm_jump_label_node_set_border(node_in: ?*c.AcwmJumpLabel, r: f32, g: f32, b: f32, a: f32, width: i32, radius: i32) callconv(.c) void {
    const node = node_in orelse return;
    node.border_color = .{ r, g, b, a };
    node.border_width = if (width > 0) width else 0;
    node.corner_radius = radius;
    if (node.cached_text != null)
        acwm_jump_label_node_update(node, node.cached_text, if (node.cached_scale > 0.0) node.cached_scale else 1.0);
}

export fn acwm_jump_label_node_set_padding(node_in: ?*c.AcwmJumpLabel, pad_x: i32, pad_y: i32) callconv(.c) void {
    const node = node_in orelse return;
    node.padding_x = if (pad_x >= 0) pad_x else 0;
    node.padding_y = if (pad_y >= 0) pad_y else 0;
    if (node.cached_text != null)
        acwm_jump_label_node_update(node, node.cached_text, if (node.cached_scale > 0.0) node.cached_scale else 1.0);
}

// ---------------------------------------------------------------------------
// bar decorations
// ---------------------------------------------------------------------------

export fn acwm_bar_decoration_create(
    cdata: ?*anyopaque,
    node_type: u32,
    is_tab: bool,
    parent: [*c]c.struct_wlr_scene_tree,
    data: c.DecorateDrawData,
    width: i32,
    height: i32,
) callconv(.c) ?*c.AcwmBarDecoration {
    const deco: *c.AcwmBarDecoration = @ptrCast(@alignCast(calloc(1, @sizeOf(c.AcwmBarDecoration)) orelse return null));

    deco.scene = c.wlr_scene_tree_create(parent);
    if (deco.scene == null) {
        free(@ptrCast(deco));
        return null;
    }

    const zero = [4]f32{ 0, 0, 0, 0 };
    deco.border = c.wlr_scene_rect_create(deco.scene, 0, 0, &zero);
    deco.bg = c.wlr_scene_rect_create(deco.scene, 0, 0, &zero);
    deco.scene_buffer = c.wlr_scene_buffer_create(deco.scene, null);
    deco.close_buffer = c.wlr_scene_buffer_create(deco.scene, null);
    if (deco.border == null or deco.bg == null or deco.scene_buffer == null or deco.close_buffer == null) {
        c.wlr_scene_node_destroy(&deco.scene.*.node);
        free(@ptrCast(deco));
        return null;
    }
    c.wlr_scene_node_set_enabled(&deco.close_buffer.*.node, false);

    deco.fg_color = data.fg_color;
    deco.bg_color = data.bg_color;
    deco.focus_fg_color = data.focus_fg_color;
    deco.focus_bg_color = data.focus_bg_color;
    deco.border_color = data.border_color;
    deco.border_width = data.border_width;
    deco.corner_radius = data.corner_radius;
    deco.padding_x = data.padding_x;
    deco.padding_y = data.padding_y;
    deco.font_desc = dupOptional(data.font_desc, "monospace Bold 13");

    deco.target_width = width;
    deco.target_height = height;
    deco.type = node_type;
    deco.is_tab = is_tab;
    deco.node_data = cdata;

    deco.cached_scale = -1.0;

    deco.close_color = .{ 0.68, 0.25, 0.12, 1.0 };
    deco.close_hover_color = .{ 0.81, 0.55, 0.47, 1.0 };
    deco.close_x_color = .{ 1.0, 1.0, 1.0, 1.0 };

    _ = acwm_scene_node_set(&deco.scene.*.node, deco.type, deco);
    measureInit(&deco.measure);

    return deco;
}

export fn acwm_bar_decoration_destroy(node_in: ?*c.AcwmBarDecoration) callconv(.c) void {
    const node = node_in orelse return;

    if (node.buffer != null) {
        c.wlr_buffer_drop(&node.buffer.*.base);
        node.buffer = null;
    }
    if (node.close_texture != null) {
        c.wlr_buffer_drop(&node.close_texture.*.base);
        node.close_texture = null;
    }
    if (node.scene != null) {
        c.wlr_scene_node_destroy(&node.scene.*.node);
        node.scene = null;
    }

    measureFinish(&node.measure);

    if (node.font_desc != null)
        g_free(@ptrCast(node.font_desc));
    if (node.cached_text != null)
        g_free(@ptrCast(node.cached_text));
    if (node.cached_font_desc != null)
        g_free(@ptrCast(node.cached_font_desc));
    if (node.last_text != null)
        g_free(@ptrCast(node.last_text));
    free(@ptrCast(node));
}

fn barDecorationAvailWidth(node: *c.AcwmBarDecoration) i32 {
    const border: i32 = if (node.border_width > 0) node.border_width else 0;
    const avail = node.target_width - 2 * border - 2 * node.padding_x;
    return if (avail > 0) avail else 0;
}

fn barDecorationApplyGeometry(node: *c.AcwmBarDecoration) void {
    const border: i32 = if (node.border_width > 0) node.border_width else 0;
    const width: i32 = if (node.target_width > 0) node.target_width else 0;
    const height: i32 = if (node.target_height > 0) node.target_height else 0;
    const inner_w = width - 2 * border;
    const inner_h = height - 2 * border;
    const avail_w = barDecorationAvailWidth(node);
    const avail_h = inner_h - 2 * node.padding_y;

    if (avail_w <= 0 or avail_h <= 0) {
        textNodeClear(node.scene_buffer, &node.buffer, node.border, node.bg);
        node.cached_scale = -1.0;
        node.cached_clip_pixel_w = -1;
        node.text_logical_w = 0;
        node.text_logical_h = 0;
        node.logical_width = 0;
        node.logical_height = 0;
        return;
    }

    rectApplyBorder(node.border, &node.border_color, node.corner_radius, node.corner_radius, border, width, height);
    const bg_color: *const [4]f32 = if (node.focused) &node.focus_bg_color else &node.bg_color;
    rectApply(node.bg, bg_color, node.corner_radius, border, border, inner_w, inner_h);

    node.logical_width = width;
    node.logical_height = height;

    const scale: f32 = if (node.cached_scale > 0.0) node.cached_scale else 1.0;
    textNodeApplySize(node.scene_buffer, node.surface_pixel_w, node.surface_pixel_h, scale, 0, avail_h, &node.text_logical_w, &node.text_logical_h);

    var offset_x = @divTrunc(avail_w - node.text_logical_w, 2);
    var offset_y = @divTrunc(avail_h - node.text_logical_h, 2);
    if (offset_x < 0)
        offset_x = 0;
    if (offset_y < 0)
        offset_y = 0;

    c.wlr_scene_node_set_position(&node.scene_buffer.*.node, border + node.padding_x + offset_x, border + node.padding_y + offset_y);
}

export fn acwm_bar_decoration_set_size(node_in: ?*c.AcwmBarDecoration, width_in: i32, height_in: i32) callconv(.c) void {
    const node = node_in orelse return;

    var width = width_in;
    var height = height_in;
    if (width < 0)
        width = 0;
    if (height < 0)
        height = 0;

    if (node.target_width == width and node.target_height == height)
        return;

    node.target_width = width;
    node.target_height = height;

    const redraw_text: [*:0]const u8 = if (node.last_text != null) @ptrCast(node.last_text) else "";
    const redraw_scale: f32 = if (node.last_scale > 0.0) node.last_scale else 1.0;

    acwm_bar_decoration_update(node, redraw_text, redraw_scale);
}

fn closeButtonBox(node: *const c.AcwmBarDecoration, out_x: *i32, out_y: *i32, out_size: *i32) bool {
    if (!node.close_enabled or node.close_size <= 0 or node.target_width <= 0 or node.target_height <= 0)
        return false;

    var size = node.close_size;
    if (size > node.target_height)
        size = node.target_height;
    if (size > node.target_width)
        size = node.target_width;
    var margin = node.close_margin;
    if (margin > node.target_width - size)
        margin = node.target_width - size;

    out_size.* = size;
    out_x.* = node.target_width - size - margin;
    out_y.* = @divTrunc(node.target_height - size, 2);
    return true;
}

fn closeButtonRender(node: *c.AcwmBarDecoration, size: i32, pixel: i32, scale: f32, hover: bool) void {
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, pixel, pixel);
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(surface);
        textNodeInstall(node.close_buffer, &node.close_texture, null, 0, 0);
        return;
    }

    const cr = c.cairo_create(surface);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
    c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
    c.cairo_paint(cr);
    c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

    const center: f64 = @as(f64, @floatFromInt(pixel)) / 2.0;
    const circle: *const [4]f32 = if (hover) &node.close_hover_color else &node.close_color;
    c.cairo_set_source_rgba(cr, circle[0], circle[1], circle[2], circle[3]);
    c.cairo_arc(cr, center, center, center, 0, 2 * 3.14159265358979323846);
    c.cairo_fill(cr);

    const inset: f64 = @as(f64, @floatFromInt(pixel)) * 0.30;
    var line_width: f64 = @as(f64, @floatFromInt(pixel)) * 0.12;
    if (line_width < 1.0)
        line_width = 1.0;
    c.cairo_set_line_width(cr, line_width);
    c.cairo_set_line_cap(cr, c.CAIRO_LINE_CAP_ROUND);
    c.cairo_set_source_rgba(cr, node.close_x_color[0], node.close_x_color[1], node.close_x_color[2], node.close_x_color[3]);
    c.cairo_move_to(cr, inset, inset);
    c.cairo_line_to(cr, @as(f64, @floatFromInt(pixel)) - inset, @as(f64, @floatFromInt(pixel)) - inset);
    c.cairo_move_to(cr, @as(f64, @floatFromInt(pixel)) - inset, inset);
    c.cairo_line_to(cr, inset, @as(f64, @floatFromInt(pixel)) - inset);
    c.cairo_stroke(cr);

    c.cairo_surface_flush(surface);
    c.cairo_destroy(cr);

    textNodeInstall(node.close_buffer, &node.close_texture, surface, pixel, pixel);

    node.close_cached_size = size;
    node.close_cached_scale = scale;
    node.close_cached_hover = hover;
    node.close_cached_valid = true;
}

fn closeButtonSync(node_in: ?*c.AcwmBarDecoration) void {
    const node = node_in orelse return;
    if (node.close_buffer == null)
        return;

    var x: i32 = 0;
    var y: i32 = 0;
    var size: i32 = 0;
    if (!closeButtonBox(node, &x, &y, &size)) {
        textNodeInstall(node.close_buffer, &node.close_texture, null, 0, 0);
        node.close_cached_valid = false;
        c.wlr_scene_node_set_enabled(&node.close_buffer.*.node, false);
        return;
    }

    const scale: f32 = if (node.last_scale > 0.0) node.last_scale else 1.0;
    var pixel: i32 = @intFromFloat(@as(f32, @floatFromInt(size)) * scale + 0.5);
    if (pixel < 1)
        pixel = 1;

    if (!node.close_cached_valid or node.close_cached_size != size or
        node.close_cached_scale != scale or node.close_cached_hover != node.close_hover)
    {
        closeButtonRender(node, size, pixel, scale, node.close_hover);
    }

    c.wlr_scene_buffer_set_dest_size(node.close_buffer, size, size);
    c.wlr_scene_node_set_position(&node.close_buffer.*.node, x, y);
    c.wlr_scene_node_place_above(&node.close_buffer.*.node, &node.scene_buffer.*.node);
    c.wlr_scene_node_set_enabled(&node.close_buffer.*.node, true);
}

export fn acwm_bar_decoration_update(node_in: ?*c.AcwmBarDecoration, text: [*c]const u8, scale_in: f32) callconv(.c) void {
    const node = node_in orelse return;
    if (text == null)
        return;
    var scale = scale_in;
    if (scale <= 0.0)
        scale = 1.0;

    if (node.last_text == null or strcmp(node.last_text, @ptrCast(text)) != 0) {
        if (node.last_text != null)
            g_free(@ptrCast(node.last_text));
        node.last_text = dupStr(@ptrCast(text));
    }
    node.last_scale = scale;

    const fg_color: *const [4]f32 = if (node.focused) &node.focus_fg_color else &node.fg_color;

    const avail_w = barDecorationAvailWidth(node);
    const avail_pixel_w: i32 = @intFromFloat(@as(f32, @floatFromInt(avail_w)) * scale + 0.5);

    var natural_pixel_w: c_int = 0;
    var natural_pixel_h: c_int = 0;
    measureText(&node.measure, node.font_desc, @ptrCast(text), scale, &natural_pixel_w, &natural_pixel_h);

    const overlong = avail_pixel_w > 0 and natural_pixel_w > avail_pixel_w;
    const clip_pixel_w: i32 = if (overlong) avail_pixel_w else 0;

    const dirty = node.cached_scale != scale or node.cached_text == null or
        strcmp(node.cached_text, @ptrCast(text)) != 0 or node.cached_font_desc == null or
        strcmp(node.cached_font_desc, node.font_desc) != 0 or
        memcmp(&node.cached_fg_color, fg_color, @sizeOf([4]f32)) != 0 or
        node.cached_focused != node.focused or node.cached_clip_pixel_w != clip_pixel_w;

    if (dirty) {
        var ellipsized: [*:0]u8 = undefined;
        var display: [*:0]const u8 = @ptrCast(text);
        if (overlong) {
            ellipsized = textEllipsize(&node.measure, node.font_desc, @ptrCast(text), scale, avail_pixel_w);
            display = ellipsized;
        }

        if (node.cached_text != null)
            g_free(@ptrCast(node.cached_text));
        node.cached_text = dupStr(@ptrCast(text));
        if (node.cached_font_desc != null)
            g_free(@ptrCast(node.cached_font_desc));
        node.cached_font_desc = dupStr(node.font_desc);
        node.cached_scale = scale;
        node.cached_fg_color = fg_color.*;
        node.cached_focused = node.focused;
        node.cached_clip_pixel_w = clip_pixel_w;

        const surface = textSurfaceCreate(&node.measure, node.font_desc, display, scale, fg_color, &node.surface_pixel_w, &node.surface_pixel_h);
        textNodeInstall(node.scene_buffer, &node.buffer, surface, node.surface_pixel_w, node.surface_pixel_h);
        if (overlong)
            g_free(@ptrCast(ellipsized));
    }

    barDecorationApplyGeometry(node);
    closeButtonSync(node);
}

export fn acwm_bar_decoration_set_focus(node_in: ?*c.AcwmBarDecoration, focused: bool) callconv(.c) void {
    const node = node_in orelse return;
    if (node.focused == focused)
        return;
    node.focused = focused;
    if (node.last_text != null) {
        const scale: f32 = if (node.last_scale > 0.0) node.last_scale else 1.0;
        acwm_bar_decoration_update(node, node.last_text, scale);
    }
}

export fn acwm_bar_decoration_set_colors(node_in: ?*c.AcwmBarDecoration, fg: *const [4]f32, bg: *const [4]f32) callconv(.c) void {
    const node = node_in orelse return;
    node.fg_color = fg.*;
    node.bg_color = bg.*;
    if (node.last_text != null) {
        const scale: f32 = if (node.last_scale > 0.0) node.last_scale else 1.0;
        acwm_bar_decoration_update(node, node.last_text, scale);
    }
}

export fn acwm_bar_decoration_set_close(node_in: ?*c.AcwmBarDecoration, enabled: bool, size: i32, margin: i32) callconv(.c) void {
    const node = node_in orelse return;
    if (node.close_enabled == enabled and node.close_size == size and node.close_margin == margin)
        return;
    node.close_enabled = enabled;
    node.close_size = size;
    node.close_margin = margin;
    closeButtonSync(node);
}

export fn acwm_bar_decoration_set_close_color(node_in: ?*c.AcwmBarDecoration, circle: *const [4]f32) callconv(.c) void {
    const node = node_in orelse return;
    node.close_color = circle.*;
    var i: usize = 0;
    while (i < 3) : (i += 1)
        node.close_hover_color[i] = circle[i] + (1.0 - circle[i]) * 0.4;
    node.close_hover_color[3] = circle[3];

    node.close_cached_valid = false;
    closeButtonSync(node);
}

export fn acwm_bar_decoration_set_close_hover(node_in: ?*c.AcwmBarDecoration, hover: bool) callconv(.c) void {
    const node = node_in orelse return;
    if (node.close_hover == hover)
        return;
    node.close_hover = hover;
    closeButtonSync(node);
}

export fn acwm_bar_decoration_close_contains(node_in: ?*c.AcwmBarDecoration, lx: f64, ly: f64) callconv(.c) bool {
    const node = node_in orelse return false;

    var x: i32 = 0;
    var y: i32 = 0;
    var size: i32 = 0;
    if (!closeButtonBox(node, &x, &y, &size))
        return false;

    return lx >= @as(f64, @floatFromInt(x)) and lx < @as(f64, @floatFromInt(x + size)) and
        ly >= @as(f64, @floatFromInt(y)) and ly < @as(f64, @floatFromInt(y + size));
}

export fn acwm_jump_label_node_apply_config(node_in: ?*c.AcwmJumpLabel, data: ?*const c.DecorateDrawData) callconv(.c) void {
    const node = node_in orelse return;
    const d = data orelse return;

    node.fg_color = d.fg_color;
    node.bg_color = d.bg_color;
    node.focus_fg_color = d.focus_fg_color;
    node.focus_bg_color = d.focus_bg_color;
    node.border_color = d.border_color;
    node.border_width = d.border_width;
    node.corner_radius = d.corner_radius;
    node.padding_x = d.padding_x;
    node.padding_y = d.padding_y;

    if (node.font_desc != null)
        g_free(@ptrCast(node.font_desc));
    node.font_desc = dupOptional(d.font_desc, "monospace Bold 16");

    if (node.cached_text != null)
        acwm_jump_label_node_update(node, node.cached_text, if (node.cached_scale > 0.0) node.cached_scale else 1.0);
}

export fn acwm_bar_decoration_apply_config(node_in: ?*c.AcwmBarDecoration, data: ?*const c.DecorateDrawData) callconv(.c) void {
    const node = node_in orelse return;
    const d = data orelse return;

    node.fg_color = d.fg_color;
    node.bg_color = d.bg_color;
    node.focus_fg_color = d.focus_fg_color;
    node.focus_bg_color = d.focus_bg_color;
    node.border_color = d.border_color;
    node.border_width = d.border_width;
    node.corner_radius = d.corner_radius;
    node.padding_x = d.padding_x;
    node.padding_y = d.padding_y;

    if (node.font_desc != null)
        g_free(@ptrCast(node.font_desc));
    node.font_desc = dupOptional(d.font_desc, "monospace Bold 13");

    if (node.last_text != null) {
        const scale: f32 = if (node.last_scale > 0.0) node.last_scale else 1.0;
        acwm_bar_decoration_update(node, node.last_text, scale);
    }
}

// ---------------------------------------------------------------------------
// tests (real cairo/pango/wlroots scene; tests/text_node_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_scene_node_set_calls: c_int;

fn makeData(font: [*:0]const u8) c.DecorateDrawData {
    var data = std.mem.zeroes(c.DecorateDrawData);
    data.fg_color = .{ 1.0, 1.0, 1.0, 1.0 };
    data.bg_color = .{ 0.1, 0.1, 0.1, 1.0 };
    data.focus_fg_color = .{ 1.0, 0.2, 0.2, 1.0 };
    data.focus_bg_color = .{ 0.2, 0.4, 0.2, 1.0 };
    data.border_color = .{ 0.5, 0.5, 0.5, 1.0 };
    data.border_width = 2;
    data.corner_radius = 4;
    data.padding_x = 3;
    data.padding_y = 2;
    data.font_desc = font;
    return data;
}

test "jump label renders text and positions its decorations" {
    const node = acwm_jump_label_node_create(null, makeData("monospace 10")).?;
    defer acwm_jump_label_node_destroy(node);

    acwm_jump_label_node_update(node, "Hi", 1.0);

    try testing.expect(node.surface_pixel_w > 0);
    try testing.expect(node.surface_pixel_h > 0);
    try testing.expect(node.logical_width > 0);
    try testing.expect(node.logical_height > 0);
    try testing.expect(node.buffer != null);

    // border 2 + padding 3/2
    try testing.expectEqual(@as(c_int, 5), node.scene_buffer.*.node.x);
    try testing.expectEqual(@as(c_int, 4), node.scene_buffer.*.node.y);
    try testing.expectEqual(node.logical_width, node.border.*.width);
    try testing.expectEqual(node.logical_height, node.border.*.height);
    try testing.expectEqual(@as(c_int, 2), node.bg.*.node.x);

    acwm_jump_label_node_set_focus(node, true);
    try testing.expect(node.focused);
    try testing.expect(node.cached_focused);
    try testing.expect(node.logical_width > 0);
}

test "text buffer exposes cairo image data through wlr_buffer" {
    const node = acwm_jump_label_node_create(null, makeData("monospace 10")).?;
    defer acwm_jump_label_node_destroy(node);
    acwm_jump_label_node_update(node, "buffer", 1.0);

    try testing.expect(node.buffer != null);
    const buf: *TextBuffer = @ptrCast(@alignCast(node.buffer));

    var data: ?*anyopaque = null;
    var format: u32 = 0;
    var stride: usize = 0;
    try testing.expect(text_buffer_begin_data_ptr_access(&buf.base, 0, &data, &format, &stride));
    try testing.expect(data != null);
    try testing.expectEqual(DRM_FORMAT_ARGB8888, format);
    try testing.expect(stride > 0);

    var wd: ?*anyopaque = null;
    var wf: u32 = 0;
    var ws: usize = 0;
    try testing.expect(!text_buffer_begin_data_ptr_access(&buf.base, c.WLR_BUFFER_DATA_PTR_ACCESS_WRITE, &wd, &wf, &ws));
}

test "bar decoration ellipsizes and lays out the close button" {
    const node = acwm_bar_decoration_create(null, 7, false, null, makeData("monospace 10"), 120, 30).?;
    defer acwm_bar_decoration_destroy(node);

    acwm_bar_decoration_update(node, "A very long title that will certainly be ellipsized", 1.0);

    try testing.expectEqual(@as(c_int, 120), node.logical_width);
    try testing.expectEqual(@as(c_int, 30), node.logical_height);
    try testing.expect(node.text_logical_w > 0);
    try testing.expect(node.text_logical_w <= 110); // 120 - 2*border - 2*padding
    try testing.expectEqual(@as(c_int, 110), node.cached_clip_pixel_w);
    try testing.expectEqual(@as(c_int, 1), stub_scene_node_set_calls);

    acwm_bar_decoration_set_close(node, true, 12, 4);
    try testing.expect(node.close_cached_valid);
    try testing.expect(node.close_buffer.*.node.enabled);
    try testing.expectEqual(@as(c_int, 104), node.close_buffer.*.node.x);
    try testing.expectEqual(@as(c_int, 9), node.close_buffer.*.node.y);
    try testing.expect(acwm_bar_decoration_close_contains(node, 105, 10));
    try testing.expect(!acwm_bar_decoration_close_contains(node, 0, 0));

    acwm_bar_decoration_set_close_hover(node, true);
    try testing.expect(node.close_cached_hover);

    acwm_bar_decoration_set_size(node, 200, 40);
    try testing.expectEqual(@as(c_int, 200), node.logical_width);
    try testing.expectEqual(@as(c_int, 40), node.logical_height);
    try testing.expectEqual(@as(c_int, 184), node.close_buffer.*.node.x);
    try testing.expectEqual(@as(c_int, 14), node.close_buffer.*.node.y);
}

test "bar decoration config updates fonts and padding" {
    const node = acwm_bar_decoration_create(null, 1, true, null, makeData("monospace 10"), 150, 28).?;
    defer acwm_bar_decoration_destroy(node);

    acwm_bar_decoration_update(node, "tab", 1.0);

    var data = makeData("monospace 8");
    data.padding_x = 0;
    data.padding_y = 0;
    data.border_width = 0;
    acwm_bar_decoration_apply_config(node, &data);

    try testing.expectEqualStrings("monospace 8", std.mem.span(node.font_desc));
    try testing.expectEqual(@as(i32, 0), node.padding_x);
    try testing.expectEqual(@as(i32, 0), node.border_width);
    try testing.expect(node.logical_width > 0);

    acwm_jump_label_node_destroy(null);
    acwm_bar_decoration_destroy(null);
    acwm_bar_decoration_set_close(null, true, 1, 1);
}
