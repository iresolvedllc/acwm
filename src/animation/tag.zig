//! Port of src/animation/tag.c (Phase 5, animation slice 2, slice 47).
//! Tag-in/tag-out/arrange visibility animation state for clients.

const std = @import("std");
const c = @import("cc");

const Arg = c.Arg;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;

extern fn client_animations_enabled(cl: ?*Client) callconv(.c) bool;
extern fn client_update_visibility(cl: ?*Client) callconv(.c) void;
extern fn resize(cl: *Client, geo: Box, opts: c.ResizeOpts) callconv(.c) void;
extern fn is_scroller_layout(m: ?*Monitor) callconv(.c) bool;
extern fn wlr_box_equal(a: *const Box, b: *const Box) callconv(.c) bool;

fn ISTILED(cl: *const Client) bool {
    return cl.isfloating == 0 and cl.isminimized == 0 and cl.iskilling == 0 and
        cl.ismaximizescreen == 0 and cl.isfullscreen == 0 and cl.isunglobal == 0;
}

fn SCRATCHPAD_SHOWN(cl: *const Client) bool {
    return cl.is_in_scratchpad != 0 and cl.isminimized == 0;
}

fn tagBit(num: u32) u32 {
    if (num == 0 or num > 32)
        return 0;
    return @as(u32, 1) << @intCast(num - 1);
}

fn goingForward(m: *Monitor) bool {
    if (m.carousel_anim_dir != 0)
        return m.carousel_anim_dir > 0;
    return m.pertag.*.curtag > m.pertag.*.prevtag;
}

fn vertical() bool {
    return c.config.tag_animation_direction == c.VERTICAL;
}

fn resizeAnimated(cl: *Client) void {
    resize(cl, cl.geom, .{ .skip_ov_enter_anim = true });
}

export fn set_tagin_animation(m: *Monitor, cl: *Client) callconv(.c) void {
    if (cl.animation.running) {
        cl.animainit_geom.x = cl.animation.current.x;
        cl.animainit_geom.y = cl.animation.current.y;
        return;
    }

    if ((cl.isglobal != 0 or cl.isunglobal != 0) or
        ((cl.tags & tagBit(m.pertag.*.prevtag)) != 0 and
            (cl.tags & tagBit(m.pertag.*.curtag)) != 0))
    {
        cl.animation.tagouting = false;
        cl.animation.tagouted = false;
        cl.animation.tagining = false;
        cl.animation.action = c.MOVE;
        return;
    }

    if (goingForward(m)) {
        cl.animainit_geom.x = if (vertical())
            cl.animation.current.x
        else
            @max(cl.mon.*.m.x + cl.mon.*.m.width, cl.geom.x + cl.mon.*.m.width);
        cl.animainit_geom.y = if (vertical())
            @max(cl.mon.*.m.y + cl.mon.*.m.height, cl.geom.y + cl.mon.*.m.height)
        else
            cl.animation.current.y;
    } else {
        cl.animainit_geom.x = if (vertical())
            cl.animation.current.x
        else
            @min(cl.mon.*.m.x - cl.geom.width, cl.geom.x - cl.mon.*.m.width);
        cl.animainit_geom.y = if (vertical())
            @min(cl.mon.*.m.y - cl.geom.height, cl.geom.y - cl.mon.*.m.height)
        else
            cl.animation.current.y;
    }
}

export fn set_arrange_visible(m: *Monitor, cl: *Client, want_animation: bool) callconv(.c) void {
    cl.tag_visible = true;

    const was_enabled = cl.scene.*.node.enabled;
    const in_place = was_enabled and !cl.animation.running and
        wlr_box_equal(&cl.animation.current, &cl.geom);
    const tag_switch = !in_place and !cl.animation.tag_from_rule and
        want_animation and m.pertag.*.prevtag != 0 and
        m.pertag.*.curtag != 0 and client_animations_enabled(cl);

    if (!ISTILED(cl) or !cl.is_clip_to_hide or !is_scroller_layout(cl.mon)) {
        cl.is_clip_to_hide = false;
        client_update_visibility(cl);
    }

    if (SCRATCHPAD_SHOWN(cl) and cl.scratchpad_tagin) {
        cl.scratchpad_tagin = false;
        cl.animation.tag_from_rule = false;
        cl.animation.tagouted = false;
        const reversing = cl.animation.tagouting and cl.animation.running and
            !wlr_box_equal(&cl.animation.current, &cl.animation.initial);
        cl.animation.tagouting = false;
        if (client_animations_enabled(cl)) {
            cl.animation.tagining = true;
            cl.animainit_geom = cl.geom;
            if (reversing) {
                cl.animainit_geom.x = cl.animation.current.x;
                cl.animainit_geom.y = cl.animation.current.y;
            } else {
                cl.animainit_geom.y = cl.mon.*.m.y - cl.geom.height;
            }
        } else {
            cl.animation.tagining = false;
            cl.animainit_geom.x = cl.animation.current.x;
            cl.animainit_geom.y = cl.animation.current.y;
        }
        resizeAnimated(cl);
        return;
    }

    if ((cl.tags & @as(u32, @bitCast(c.TAG0_MASK))) != 0) {
        cl.animation.tag_from_rule = false;
        cl.animation.tagouting = false;
        cl.animation.tagouted = false;
        if (want_animation and client_animations_enabled(cl)) {
            cl.animation.tagining = true;
            cl.animainit_geom = cl.geom;
            cl.animainit_geom.y = cl.mon.*.m.y - cl.geom.height;
        } else {
            cl.animainit_geom.x = cl.animation.current.x;
            cl.animainit_geom.y = cl.animation.current.y;
        }
        resizeAnimated(cl);
        return;
    }

    if (tag_switch) {
        cl.animation.tagining = true;
        set_tagin_animation(m, cl);
    } else {
        cl.animainit_geom.x = cl.animation.current.x;
        cl.animainit_geom.y = cl.animation.current.y;
    }

    cl.animation.tag_from_rule = false;
    cl.animation.tagouting = false;
    cl.animation.tagouted = false;
    resizeAnimated(cl);
}

export fn set_tagout_animation(m: *Monitor, cl: *Client) callconv(.c) void {
    if ((cl.isglobal != 0 or cl.isunglobal != 0) or
        ((cl.tags & tagBit(m.pertag.*.prevtag)) != 0 and
            (cl.tags & tagBit(m.pertag.*.curtag)) != 0))
    {
        cl.animation.tagouting = false;
        cl.animation.tagouted = false;
        cl.animation.tagining = false;
        cl.animation.action = c.MOVE;
        return;
    }

    if (goingForward(m)) {
        cl.pending = cl.geom;
        cl.pending.x = if (vertical())
            cl.animation.current.x
        else
            @min(cl.mon.*.m.x - cl.geom.width, cl.geom.x - cl.mon.*.m.width);
        cl.pending.y = if (vertical())
            @min(cl.mon.*.m.y - cl.geom.height, cl.geom.y - cl.mon.*.m.height)
        else
            cl.animation.current.y;
        resize(cl, cl.geom, .{ .interact = false });
    } else {
        cl.pending = cl.geom;
        cl.pending.x = if (vertical())
            cl.animation.current.x
        else
            @max(cl.mon.*.m.x + cl.mon.*.m.width, cl.geom.x + cl.mon.*.m.width);
        cl.pending.y = if (vertical())
            @max(cl.mon.*.m.y + cl.mon.*.m.height, cl.geom.y + cl.mon.*.m.height)
        else
            cl.animation.current.y;
        resize(cl, cl.geom, .{ .interact = false });
    }
}

export fn set_arrange_hidden(m: *Monitor, cl: *Client, want_animation: bool) callconv(.c) void {
    cl.tag_visible = false;

    if (cl.ov_card_tree != null) {
        cl.is_clip_to_hide = false;
        client_update_visibility(cl);
        cl.animation.running = false;
        cl.animation.tagining = false;
        cl.animation.tagouting = false;
        return;
    }

    if ((cl.tags & @as(u32, @bitCast(c.TAG0_MASK))) == 0 and
        cl.is_in_scratchpad != 0 and cl.isminimized != 0)
    {
        if (client_animations_enabled(cl) and !cl.animation.tagouted) {
            cl.animation.tagouting = true;
            cl.animation.tagining = false;
            cl.pending = cl.geom;
            cl.pending.y = cl.mon.*.m.y - cl.geom.height;
            resize(cl, cl.geom, .{ .interact = false });
        } else {
            cl.animation.running = false;
            cl.animation.tagouting = false;
            cl.animation.tagining = false;
            client_update_visibility(cl);
            cl.animainit_geom = cl.geom;
            cl.current = cl.geom;
            cl.pending = cl.geom;
            cl.animation.current = cl.geom;
        }
        return;
    }

    if ((cl.tags & @as(u32, @bitCast(c.TAG0_MASK))) != 0) {
        if (want_animation and m.isoverview == 0 and client_animations_enabled(cl) and
            !cl.animation.tagouted)
        {
            cl.animation.tagouting = true;
            cl.animation.tagining = false;
            cl.pending = cl.geom;
            cl.pending.y = cl.mon.*.m.y - cl.geom.height;
            resize(cl, cl.geom, .{ .interact = false });
        } else {
            cl.animation.running = false;
            cl.animation.tagouting = false;
            cl.animation.tagining = false;
            client_update_visibility(cl);
            cl.animainit_geom = cl.geom;
            cl.current = cl.geom;
            cl.pending = cl.geom;
            cl.animation.current = cl.geom;
        }
        return;
    }

    if (!cl.is_tab_hidden and !cl.animation.tagouted and
        (cl.tags & tagBit(m.pertag.*.prevtag)) != 0 and
        m.pertag.*.prevtag != 0 and m.pertag.*.curtag != 0 and
        client_animations_enabled(cl))
    {
        cl.animation.tagouting = true;
        cl.animation.tagining = false;
        set_tagout_animation(m, cl);
    } else {
        cl.animation.running = false;
        cl.animation.tagining = false;
        cl.animation.tagouting = false;
        cl.animation.tagouted = true;
        client_update_visibility(cl);
        cl.animainit_geom = cl.geom;
        cl.current = cl.geom;
        cl.pending = cl.geom;
        cl.animation.current = cl.geom;
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/animation_tag_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_animations_enabled: bool;
extern var stub_update_vis_calls: c_int;
extern var stub_resize_calls: c_int;
extern var stub_resize_geom: Box;
extern var stub_resize_skip_ov: bool;
extern var stub_is_scroller: bool;

fn resetTagStub() void {
    c.config = std.mem.zeroes(c.Config);
    c.config.tag_animation_direction = c.HORIZONTAL;
    c.server = std.mem.zeroes(c.AcwmServer);
    stub_animations_enabled = true;
    stub_update_vis_calls = 0;
    stub_resize_calls = 0;
    stub_resize_geom = std.mem.zeroes(Box);
    stub_resize_skip_ov = false;
    stub_is_scroller = false;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.w = m.m;
    p.prevtag = 1;
    p.curtag = 2;
}

fn baseClient(cl: *Client, m: *Monitor, scene: *c.struct_wlr_scene_tree) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.scene = @ptrCast(scene);
    scene.node.enabled = true;
    cl.geom = .{ .x = 100, .y = 100, .width = 200, .height = 100 };
    cl.animation.current = .{ .x = 50, .y = 50, .width = 200, .height = 100 };
}

test "tagin animation handles running, global and directional states" {
    resetTagStub();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var cl: Client = undefined;
    baseClient(&cl, &m, &scene);

    cl.animation.running = true;
    set_tagin_animation(&m, &cl);
    try testing.expectEqual(@as(i32, 50), cl.animainit_geom.x);

    cl.animation.running = false;
    cl.isglobal = 1;
    set_tagin_animation(&m, &cl);
    try testing.expectEqual(@as(i32, c.MOVE), cl.animation.action);
    try testing.expect(!cl.animation.tagining);

    cl.isglobal = 0;
    cl.tags = 3; // previous + current bits
    cl.animation.action = c.NONE;
    set_tagin_animation(&m, &cl);
    try testing.expectEqual(@as(i32, c.MOVE), cl.animation.action);

    cl.tags = 2;
    set_tagin_animation(&m, &cl);
    try testing.expectEqual(@as(i32, 1100), cl.animainit_geom.x);
    try testing.expectEqual(@as(i32, 50), cl.animainit_geom.y);

    c.config.tag_animation_direction = c.VERTICAL;
    set_tagin_animation(&m, &cl);
    try testing.expectEqual(@as(i32, 50), cl.animainit_geom.x);
    try testing.expectEqual(@as(i32, 900), cl.animainit_geom.y);
}

test "arrange visible animates tag switches, scratchpads and tag0" {
    resetTagStub();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var cl: Client = undefined;
    baseClient(&cl, &m, &scene);
    cl.tags = 2;

    // in-place: no tag switch, resize with the skip flag
    cl.animation.current = cl.geom;
    set_arrange_visible(&m, &cl, true);
    try testing.expect(cl.tag_visible);
    try testing.expect(!cl.animation.tagining);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expect(stub_resize_skip_ov);
    try testing.expectEqual(@as(c_int, 1), stub_update_vis_calls);

    // tag switch
    cl.animation.current = .{ .x = 50, .y = 50, .width = 200, .height = 100 };
    set_arrange_visible(&m, &cl, true);
    try testing.expect(cl.animation.tagining);
    try testing.expectEqual(@as(i32, 1100), cl.animainit_geom.x);

    // scratchpad slide-in
    cl.animation.tagining = false;
    cl.is_in_scratchpad = 1;
    cl.isminimized = 0;
    cl.scratchpad_tagin = true;
    set_arrange_visible(&m, &cl, true);
    try testing.expect(cl.animation.tagining);
    try testing.expectEqual(@as(i32, -100), cl.animainit_geom.y);
    try testing.expect(cl.animainit_geom.x == cl.geom.x);

    // tag0 slide-in
    cl.is_in_scratchpad = 0;
    cl.tags = @bitCast(c.TAG0_MASK);
    set_arrange_visible(&m, &cl, true);
    try testing.expectEqual(@as(i32, -100), cl.animainit_geom.y);
}

test "tagout animation sets pending geometry by direction" {
    resetTagStub();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var cl: Client = undefined;
    baseClient(&cl, &m, &scene);
    cl.tags = 2;

    set_tagout_animation(&m, &cl);
    try testing.expectEqual(@as(i32, -900), cl.pending.x);
    try testing.expectEqual(@as(i32, 50), cl.pending.y);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);

    p.prevtag = 2;
    p.curtag = 1;
    set_tagout_animation(&m, &cl);
    try testing.expectEqual(@as(i32, 1100), cl.pending.x);

    c.config.tag_animation_direction = c.VERTICAL;
    set_tagout_animation(&m, &cl);
    try testing.expectEqual(@as(i32, 900), cl.pending.y);
}

test "arrange hidden resets or animates out depending on state" {
    resetTagStub();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);
    var cl: Client = undefined;
    baseClient(&cl, &m, &scene);
    cl.tags = 1;

    // normal previous-tag slide-out
    set_arrange_hidden(&m, &cl, true);
    try testing.expect(!cl.tag_visible);
    try testing.expect(cl.animation.tagouting);
    try testing.expectEqual(@as(i32, -900), cl.pending.x);

    // scratchpad minimized hide
    resetTagStub();
    baseMonitor(&m, &p);
    baseClient(&cl, &m, &scene);
    cl.tags = 1;
    cl.is_in_scratchpad = 1;
    cl.isminimized = 1;
    set_arrange_hidden(&m, &cl, true);
    try testing.expect(cl.animation.tagouting);
    try testing.expectEqual(@as(i32, -100), cl.pending.y);

    // no animation: tagouted + visibility update + geometry reset
    stub_animations_enabled = false;
    cl.animation.tagouting = false;
    cl.is_in_scratchpad = 0;
    cl.isminimized = 0;
    set_arrange_hidden(&m, &cl, true);
    try testing.expect(cl.animation.tagouted);
    try testing.expectEqual(@as(i32, 100), cl.animation.current.x);
    try testing.expectEqual(@as(c_int, 1), stub_update_vis_calls);

    // tag0 hide
    stub_animations_enabled = true;
    cl.tags = @bitCast(c.TAG0_MASK);
    cl.is_in_scratchpad = 0;
    cl.isminimized = 0;
    cl.animation.tagouted = false;
    set_arrange_hidden(&m, &cl, true);
    try testing.expect(cl.animation.tagouting);
    try testing.expectEqual(@as(i32, -100), cl.pending.y);
}
