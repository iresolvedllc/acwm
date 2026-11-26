//! Port of the arrange hub from src/layout/arrange.c (strangler-fig Phase 4,
//! layout slice 5, slice 33).
//!
//! Covers size-weight distribution, the pre-arrange pass (visibility counts,
//! isleftstack sides, arrange hooks), tag remapping/gathering, the layout
//! table itself, the special-view edge handling and arrange().
//!
//! The resize_* drag family remains C for the next slice; its symbol
//! `set_size_per` is called from the Zig pre-arrange pass. The C twin of this
//! region is guarded with ACWM_ZIG_ARRANGE_HUB, including the layouts table.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Layout = c.Layout;
const State = c.TagScrollerState;
const WlList = c.struct_wl_list;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn set_size_per(m: *Monitor, cl: *Client, reset_proportion: bool) callconv(.c) void;
extern fn update_scroller_state(m: *Monitor) callconv(.c) void;
extern fn find_scroller_node(st: ?*State, cl: ?*Client) callconv(.c) ?*c.ScrollerStackNode;
extern fn client_check_tab_node_visible(cl: *Client) callconv(.c) void;
extern fn client_focus(cl: *Client, lift: i32) callconv(.c) void;
extern fn client_focus_top(m: *Monitor) callconv(.c) [*c]Client;
extern fn client_only_in_one_tag(cl: *Client) callconv(.c) bool;
extern fn client_update_visibility(cl: *Client) callconv(.c) void;
extern fn client_sync_layer(cl: *Client) callconv(.c) void;
extern fn reset_maximizescreen_size(cl: *Client) callconv(.c) void;
extern fn set_arrange_visible(m: *Monitor, cl: *Client, want_animation: bool) callconv(.c) void;
extern fn set_arrange_hidden(m: *Monitor, cl: *Client, want_animation: bool) callconv(.c) void;
extern fn special_update_dim(m: *Monitor) callconv(.c) void;
extern fn is_special_active(m: *const Monitor) callconv(.c) bool;
extern fn special_has_clients(m: *const Monitor) callconv(.c) bool;
extern fn toggle_special_tag_mon(m: *Monitor) callconv(.c) void;
extern fn tab_sync_monitor(m: *Monitor) callconv(.c) void;
extern fn special_sync_top_layer(special_active: bool) callconv(.c) void;
extern fn pointer_process_motion(time: u32, device: [*c]c.struct_wlr_input_device, dx: f64, dy: f64, dx_unaccel: f64, dy_unaccel: f64) callconv(.c) void;
extern fn check_idle_inhibitor(exclude: [*c]c.struct_wlr_surface) callconv(.c) void;
extern fn printstatus(kind: c.enum_ipc_watch_type) callconv(.c) void;
extern fn tag_slot_set_defaults(m: *Monitor, tag: u32) callconv(.c) void;
extern fn tag_rule_matches_monitor(tr: [*c]const c.ConfigTagRule, m: *Monitor) callconv(.c) bool;
extern fn tag_rule_apply_to_slot(m: *Monitor, tr: [*c]const c.ConfigTagRule, tag: u32) callconv(.c) void;

// Layout implementations (still in C or already Zig) and the overview backend.
extern fn tile(m: [*c]Monitor) callconv(.c) void;
extern fn tile_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn scroller(m: [*c]Monitor) callconv(.c) void;
extern fn scroller_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn grid(m: [*c]Monitor) callconv(.c) void;
extern fn grid_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn monocle(m: [*c]Monitor) callconv(.c) void;
extern fn monocle_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn deck(m: [*c]Monitor) callconv(.c) void;
extern fn deck_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn center_tile(m: [*c]Monitor) callconv(.c) void;
extern fn center_tile_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn right_tile(m: [*c]Monitor) callconv(.c) void;
extern fn right_tile_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn vertical_scroller(m: [*c]Monitor) callconv(.c) void;
extern fn vertical_scroller_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn vertical_tile(m: [*c]Monitor) callconv(.c) void;
extern fn vertical_tile_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn vertical_grid(m: [*c]Monitor) callconv(.c) void;
extern fn vertical_grid_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn vertical_deck(m: [*c]Monitor) callconv(.c) void;
extern fn vertical_deck_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn dwindle(m: [*c]Monitor) callconv(.c) void;
extern fn dwindle_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn fair(m: [*c]Monitor) callconv(.c) void;
extern fn fair_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn vertical_fair(m: [*c]Monitor) callconv(.c) void;
extern fn vertical_fair_predict(m: [*c]Monitor, cl: [*c]Client, out: [*c]c.struct_wlr_box) callconv(.c) bool;
extern fn overview(m: [*c]Monitor) callconv(.c) void;

fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn nodeOpt(p: [*c]c.ScrollerStackNode) ?*c.ScrollerStackNode {
    return if (p == null) null else @ptrCast(p);
}

fn clientOpt(p: [*c]Client) ?*Client {
    return if (p == null) null else @ptrCast(p);
}

fn ISTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and x.iskilling == 0 and
        x.ismaximizescreen == 0 and x.isfullscreen == 0 and x.isunglobal == 0;
}

fn ISFAKETILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and
        x.iskilling == 0 and x.isunglobal == 0;
}

fn ISSCROLLTILED(cl: ?*const Client) bool {
    const x = cl orelse return false;
    return x.isfloating == 0 and x.isminimized == 0 and
        x.iskilling == 0 and x.isunglobal == 0;
}

fn VISIBLEON(cl: ?*const Client, m: ?*const Monitor) bool {
    const x = cl orelse return false;
    const mon = m orelse return false;
    if (x.mon != @as([*c]Monitor, @ptrCast(@constCast(mon))))
        return false;
    if (x.isminimized != 0)
        return false;
    return (x.tags & mon.tagset[mon.seltags]) != 0 or x.isglobal != 0 or x.isunglobal != 0;
}

// ---------------------------------------------------------------------------
// size distribution
// ---------------------------------------------------------------------------

export fn check_size_per_valid(cl: *Client) callconv(.c) void {
    if (cl.ismaster) {
        std.debug.assert(cl.master_inner_per > 0.0 and cl.master_inner_per <= 1.0);
    } else {
        std.debug.assert(cl.stack_inner_per > 0.0 and cl.stack_inner_per <= 1.0);
    }
}

export fn special_keep_bg_client(m: *Monitor, cl: *Client) callconv(.c) bool {
    const prevtag = m.pertag.*.prevtag;
    const prev_bit: u32 = if (prevtag > 0) @as(u32, 1) << @intCast(prevtag - 1) else 0;
    const tag0: u32 = @bitCast(c.TAG0_MASK);
    return is_special_active(m) and cl.isminimized == 0 and
        ((prevtag > 0 and (cl.tags & prev_bit) != 0) or
            (cl.tags & (m.tagset[m.seltags ^ 1] & ~tag0)) != 0);
}

export fn reset_size_per_mon(
    m: *Monitor,
    total_left_stack_weight: f64,
    total_right_stack_weight: f64,
    total_stack_weight: f64,
    total_master_weight: f64,
    master_num: i32,
    stack_num: i32,
) callconv(.c) void {
    const tag = get_mon_curtag(m);
    const nmasters = m.pertag.*.nmasters[@intCast(tag)];
    const centered = m.pertag.*.ltidxs[@intCast(tag)].*.id == c.CENTER_TILE;

    var i: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (total_master_weight > 0.0 and i < nmasters) {
            cl.ismaster = true;
            cl.master_inner_per = cl.master_size_weight / total_master_weight;

            const stack_side = if (centered)
                total_left_stack_weight + total_right_stack_weight
            else
                total_stack_weight;
            cl.stack_inner_per = if (stack_side > 0.0)
                cl.stack_size_weight / (stack_side + cl.stack_size_weight)
            else
                1.0;
        } else {
            cl.ismaster = false;
            cl.master_inner_per = if (total_master_weight > 0.0)
                cl.master_size_weight / (total_master_weight + cl.master_size_weight)
            else if (master_num > 0)
                1.0 / @as(f64, @floatFromInt(master_num))
            else
                1.0;

            if (centered) {
                const side = if (cl.isleftstack) total_left_stack_weight else total_right_stack_weight;
                cl.stack_inner_per = if (side > 0.0) cl.stack_size_weight / side else 1.0;
            } else {
                cl.stack_inner_per = if (total_stack_weight > 0.0)
                    cl.stack_size_weight / total_stack_weight
                else if (stack_num > 0)
                    1.0 / @as(f64, @floatFromInt(stack_num))
                else
                    1.0;
            }
        }
        i += 1;

        check_size_per_valid(cl);
    }
}

// ---------------------------------------------------------------------------
// pre-arrange pass
// ---------------------------------------------------------------------------

fn specialKeepBg(m: *Monitor, cl: *Client) bool {
    return special_keep_bg_client(m, cl);
}

export fn pre_calculate_before_arrange(
    m: *Monitor,
    want_animation: bool,
    from_view: bool,
    only_calculate: bool,
) callconv(.c) void {
    var total_stack_weight: f64 = 0;
    var total_master_weight: f64 = 0;
    var total_right_stack_weight: f64 = 0;
    var total_left_stack_weight: f64 = 0;
    var i: i32 = 0;
    var master_num: i32 = 0;
    var stack_num: i32 = 0;

    m.visible_clients = 0;
    m.visible_tiling_clients = 0;
    m.visible_scroll_tiling_clients = 0;
    m.visible_fake_tiling_clients = 0;
    m.hide_clients = 0;

    const tag = get_mon_curtag(m);
    const st = if (m.pertag.*.scroller_state[@intCast(tag)] != null)
        @as(?*State, @ptrCast(m.pertag.*.scroller_state[@intCast(tag)]))
    else
        null;

    const cur_layout = m.pertag.*.ltidxs[@intCast(tag)];
    if (cur_layout.*.id == c.SCROLLER or cur_layout.*.id == c.VERTICAL_SCROLLER)
        update_scroller_state(m);

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);

        if (from_view and (cl.isglobal != 0 or cl.isunglobal != 0))
            set_size_per(m, cl, true);

        if (cl.group_bar != null and cl.group_bar.*.scene.*.node.enabled)
            client_check_tab_node_visible(cl);

        if (cl.mon == @as([*c]Monitor, @ptrCast(m)) and
            (cl.isglobal != 0 or cl.isunglobal != 0))
            cl.tags = m.tagset[m.seltags];

        if (from_view and m.sel == null and cl.isglobal != 0 and VISIBLEON(cl, m))
            client_focus(cl, 1);

        if (cl.isminimized != 0)
            m.hide_clients += 1;

        if (VISIBLEON(cl, m)) {
            if (from_view and !client_only_in_one_tag(cl))
                set_size_per(m, cl, true);

            if (cl.isunglobal == 0)
                m.visible_clients += 1;

            if (ISTILED(cl)) {
                m.visible_tiling_clients += 1;

                if (st) |state| {
                    const n = find_scroller_node(state, cl);
                    if (n != null and n.?.prev_in_stack == null)
                        m.visible_scroll_tiling_clients += 1;
                } else if (ISSCROLLTILED(cl)) {
                    m.visible_scroll_tiling_clients += 1;
                }
            }

            if (ISFAKETILED(cl))
                m.visible_fake_tiling_clients += 1;
        }
    }

    const nmasters = m.pertag.*.nmasters[@intCast(get_mon_curtag(m))];

    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (cl.iskilling != 0)
            continue;

        if (cl.mon == @as([*c]Monitor, @ptrCast(m))) {
            if (VISIBLEON(cl, m)) {
                if (ISFAKETILED(cl)) {
                    if (cl.master_size_weight <= 0.0)
                        cl.master_size_weight = 1.0;
                    if (cl.stack_size_weight <= 0.0)
                        cl.stack_size_weight = 1.0;

                    if (i < nmasters) {
                        master_num += 1;
                        total_master_weight += cl.master_size_weight;
                    } else {
                        stack_num += 1;
                        total_stack_weight += cl.stack_size_weight;
                        const stack_index = i - nmasters;
                        if ((@rem(stack_index, 2) != 0) != (@rem(m.visible_tiling_clients, 2) == 0)) {
                            cl.isleftstack = false;
                            total_right_stack_weight += cl.stack_size_weight;
                        } else {
                            cl.isleftstack = true;
                            total_left_stack_weight += cl.stack_size_weight;
                        }
                    }
                    i += 1;
                }

                if (!only_calculate)
                    set_arrange_visible(m, cl, want_animation);
            } else if (specialKeepBg(m, cl)) {
                cl.tag_visible = true;
                client_update_visibility(cl);
                cl.animation.running = false;
                cl.animation.tagining = false;
                cl.animation.tagouting = false;
            } else if (!only_calculate and cl != clientOpt(c.server.grab_client)) {
                set_arrange_hidden(m, cl, want_animation);
            }

            if (!only_calculate)
                client_sync_layer(cl);
        }

        if (!only_calculate and cl.mon == @as([*c]Monitor, @ptrCast(m)) and
            cl.ismaximizescreen != 0 and !cl.animation.tagouted and
            !cl.animation.tagouting and VISIBLEON(cl, m))
            reset_maximizescreen_size(cl);
    }

    reset_size_per_mon(m, total_left_stack_weight, total_right_stack_weight, total_stack_weight, total_master_weight, master_num, stack_num);
    special_update_dim(m);
}

// ---------------------------------------------------------------------------
// tag remapping and gathering
// ---------------------------------------------------------------------------

export fn tag_remap_mask(tags: u32, map: [*]const u32) callconv(.c) u32 {
    var out: u32 = tags & ~c.server.tagmask;
    var i: u32 = 1;
    const tag_num: u32 = @intCast(c.config.tag_num);
    while (i <= tag_num) : (i += 1) {
        if ((tags & (@as(u32, 1) << @intCast(i - 1))) != 0) {
            const mapped = map[i];
            out |= if (mapped != 0)
                (@as(u32, 1) << @intCast(mapped - 1))
            else
                (@as(u32, 1) << @intCast(i - 1));
        }
    }
    return out;
}

export fn tag_gather_reset_slot(m: *Monitor, tag: u32) callconv(.c) void {
    const idx: usize = @intCast(tag);
    tag_slot_set_defaults(m, tag);
    m.pertag.*.no_hide[idx] = 0;
    m.pertag.*.no_render_border[idx] = 0;
    m.pertag.*.open_as_floating[idx] = 0;
    m.pertag.*.dwindle_root[idx] = null;
    m.pertag.*.scroller_state[idx] = null;

    var i: i32 = 0;
    while (i < c.config.tag_rules_count) : (i += 1) {
        const tr = &c.config.tag_rules[@intCast(i)];
        if (tag_rule_matches_monitor(tr, m) and
            (tr.id_wildcard or tr.id == @as(i32, @intCast(tag))))
            tag_rule_apply_to_slot(m, tr, tag);
    }
    m.pertag.*.ltidxs[idx] = m.pertag.*.config_ltidxs[idx];
}

export fn tag_gather_move_pertag(m: *Monitor, dst: u32, src: u32) callconv(.c) void {
    const d: usize = @intCast(dst);
    const s: usize = @intCast(src);
    m.pertag.*.nmasters[d] = m.pertag.*.nmasters[s];
    m.pertag.*.mfacts[d] = m.pertag.*.mfacts[s];
    m.pertag.*.no_hide[d] = m.pertag.*.no_hide[s];
    m.pertag.*.no_render_border[d] = m.pertag.*.no_render_border[s];
    m.pertag.*.open_as_floating[d] = m.pertag.*.open_as_floating[s];
    m.pertag.*.scroller_default_proportion[d] = m.pertag.*.scroller_default_proportion[s];
    m.pertag.*.scroller_default_proportion_single[d] = m.pertag.*.scroller_default_proportion_single[s];
    m.pertag.*.scroller_ignore_proportion_single[d] = m.pertag.*.scroller_ignore_proportion_single[s];
    m.pertag.*.dwindle_root[d] = m.pertag.*.dwindle_root[s];
    m.pertag.*.config_ltidxs[d] = m.pertag.*.config_ltidxs[s];
    m.pertag.*.ltidxs[d] = m.pertag.*.ltidxs[s];
    m.pertag.*.scroller_state[d] = m.pertag.*.scroller_state[s];
    tag_gather_reset_slot(m, src);
}

export fn tag_gather_apply(m: *Monitor) callconv(.c) void {
    if (m.iscleanuping)
        return;

    const tag0: u32 = @bitCast(c.TAG0_MASK);
    var occupied: u32 = 0;
    var map: [32]u32 = std.mem.zeroes([32]u32);
    var next: u32 = 1;
    var changed = false;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (cl.mon == @as([*c]Monitor, @ptrCast(m)) and cl.iskilling == 0 and
            (cl.tags & tag0) == 0)
            occupied |= cl.tags & c.server.tagmask;
    }
    occupied |= m.tagset[m.seltags] & c.server.tagmask;

    const tag_num: u32 = @intCast(c.config.tag_num);
    var i: u32 = 1;
    while (i <= tag_num) : (i += 1) {
        if ((occupied & (@as(u32, 1) << @intCast(i - 1))) != 0) {
            map[i] = next;
            next += 1;
            if (map[i] != i)
                changed = true;
        } else {
            map[i] = 0;
        }
    }

    if (!changed)
        return;

    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (cl.mon != @as([*c]Monitor, @ptrCast(m)) or cl.iskilling != 0 or
            (cl.tags & tag0) != 0)
            continue;
        cl.tags = tag_remap_mask(cl.tags, &map);
    }

    m.tagset[m.seltags] = tag_remap_mask(m.tagset[m.seltags], &map);
    m.tagset[m.seltags ^ 1] = tag_remap_mask(m.tagset[m.seltags ^ 1], &map);
    m.ovbk_current_tagset = tag_remap_mask(m.ovbk_current_tagset, &map);
    m.ovbk_prev_tagset = tag_remap_mask(m.ovbk_prev_tagset, &map);

    const curtag = m.pertag.*.curtag;
    if (curtag <= tag_num and map[curtag] != 0)
        m.pertag.*.curtag = map[curtag];
    const prevtag = m.pertag.*.prevtag;
    if (prevtag <= tag_num and map[prevtag] != 0)
        m.pertag.*.prevtag = map[prevtag];

    i = 1;
    while (i <= tag_num) : (i += 1) {
        if (map[i] != 0 and map[i] != i)
            tag_gather_move_pertag(m, map[i], i);
    }

    const k = next - 1;
    i = k + 1;
    while (i <= tag_num) : (i += 1)
        tag_gather_reset_slot(m, i);
}

// ---------------------------------------------------------------------------
// layout table
// ---------------------------------------------------------------------------

export var overviewlayout: Layout = .{
    .symbol = "\u{f0c7}",
    .arrange = overview,
    .predict = null,
    .name = "overview",
    .id = 0,
};

export var layouts: [14]Layout = .{
    .{ .symbol = "T", .arrange = tile, .predict = tile_predict, .name = "tile", .id = @intCast(c.TILE) },
    .{ .symbol = "S", .arrange = scroller, .predict = scroller_predict, .name = "scroller", .id = @intCast(c.SCROLLER) },
    .{ .symbol = "G", .arrange = grid, .predict = grid_predict, .name = "grid", .id = @intCast(c.GRID) },
    .{ .symbol = "M", .arrange = monocle, .predict = monocle_predict, .name = "monocle", .id = @intCast(c.MONOCLE) },
    .{ .symbol = "K", .arrange = deck, .predict = deck_predict, .name = "deck", .id = @intCast(c.DECK) },
    .{ .symbol = "CT", .arrange = center_tile, .predict = center_tile_predict, .name = "center_tile", .id = @intCast(c.CENTER_TILE) },
    .{ .symbol = "RT", .arrange = right_tile, .predict = right_tile_predict, .name = "right_tile", .id = @intCast(c.RIGHT_TILE) },
    .{ .symbol = "VS", .arrange = vertical_scroller, .predict = vertical_scroller_predict, .name = "vertical_scroller", .id = @intCast(c.VERTICAL_SCROLLER) },
    .{ .symbol = "VT", .arrange = vertical_tile, .predict = vertical_tile_predict, .name = "vertical_tile", .id = @intCast(c.VERTICAL_TILE) },
    .{ .symbol = "VG", .arrange = vertical_grid, .predict = vertical_grid_predict, .name = "vertical_grid", .id = @intCast(c.VERTICAL_GRID) },
    .{ .symbol = "VK", .arrange = vertical_deck, .predict = vertical_deck_predict, .name = "vertical_deck", .id = @intCast(c.VERTICAL_DECK) },
    .{ .symbol = "DW", .arrange = dwindle, .predict = dwindle_predict, .name = "dwindle", .id = @intCast(c.DWINDLE) },
    .{ .symbol = "F", .arrange = fair, .predict = fair_predict, .name = "fair", .id = @intCast(c.FAIR) },
    .{ .symbol = "VF", .arrange = vertical_fair, .predict = vertical_fair_predict, .name = "vertical_fair", .id = @intCast(c.VERTICAL_FAIR) },
};

// ---------------------------------------------------------------------------
// special view + main entry
// ---------------------------------------------------------------------------

export fn special_handle_empty_view(m: *Monitor, from_view: bool) callconv(.c) bool {
    if (!is_special_active(m)) {
        m.special_empty_view = false;
        return false;
    }
    if (special_has_clients(m)) {
        m.special_empty_view = false;
        return false;
    }
    if (from_view) {
        m.special_empty_view = true;
        return false;
    }
    if (!m.special_empty_view) {
        toggle_special_tag_mon(m);
        return true;
    }
    return false;
}

export fn arrange(m: *Monitor, want_animation: bool, from_view: bool) callconv(.c) void {
    if (m.iscleanuping)
        return;

    if (m.wlr_output.*.enabled == false)
        return;

    if (m.sel == null)
        m.sel = client_focus_top(m);

    if (special_handle_empty_view(m, from_view))
        return;

    pre_calculate_before_arrange(m, want_animation, from_view, false);
    tab_sync_monitor(m);

    const is_tag0 = is_special_active(m);
    special_sync_top_layer(is_tag0);
    const saved_oh = m.gappoh;
    const saved_ov = m.gappov;
    const saved_ih = m.gappih;
    const saved_iv = m.gappiv;

    if (is_tag0) {
        m.gappoh = m.special_gappoh;
        m.gappov = m.special_gappov;
        m.gappih = m.special_gappih;
        m.gappiv = m.special_gappiv;
    }

    if (m.isoverview != 0) {
        overviewlayout.arrange.?(m);
    } else {
        m.pertag.*.ltidxs[@intCast(get_mon_curtag(m))].*.arrange.?(m);
    }

    if (is_tag0) {
        m.gappoh = saved_oh;
        m.gappov = saved_ov;
        m.gappih = saved_ih;
        m.gappiv = saved_iv;
    }

    if (c.config.tag_gather != 0)
        tag_gather_apply(m);

    if (!c.server.start_drag_window) {
        pointer_process_motion(0, null, 0, 0, 0, 0);
        check_idle_inhibitor(null);
    }

    printstatus(c.IPC_WATCH_ARRANGGE);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_arrange_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_curtag: c_int;
extern var stub_set_size_calls: c_int;
extern var stub_visible_calls: c_int;
extern var stub_hidden_calls: c_int;
extern var stub_sync_layer_calls: c_int;
extern var stub_focus_calls: c_int;
extern var stub_update_vis_calls: c_int;
extern var stub_resetmax_calls: c_int;
extern var stub_tab_sync_calls: c_int;
extern var stub_special_sync_calls: c_int;
extern var stub_special_sync_arg: bool;
extern var stub_pointer_calls: c_int;
extern var stub_idle_calls: c_int;
extern var stub_printstatus_calls: c_int;
extern var stub_tag_defaults_calls: c_int;
extern var stub_rule_matches_calls: c_int;
extern var stub_rule_apply_calls: c_int;
extern var stub_layout_calls: c_int;
extern var stub_layout_gappoh: c_int;
extern var stub_overview_calls: c_int;
extern var stub_focus_top_calls: c_int;
extern var stub_check_tab_visible_calls: c_int;
extern var stub_update_scroller_calls: c_int;
extern var stub_special_active: bool;
extern var stub_special_has_clients: bool;
extern var stub_only_one_tag: bool;
extern var stub_toggle_calls: c_int;
extern var stub_focus_top: ?*Client;

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn resetWorld() void {
    listInit(&c.server.clients);
    listInit(&c.server.monitors);
    c.config = std.mem.zeroes(c.Config);
    c.server.tagmask = 0;
    c.server.start_drag_window = false;
    c.server.grab_client = null;
    c.server.cursor = null;
    stub_curtag = 0;
    stub_set_size_calls = 0;
    stub_visible_calls = 0;
    stub_hidden_calls = 0;
    stub_sync_layer_calls = 0;
    stub_focus_calls = 0;
    stub_update_vis_calls = 0;
    stub_resetmax_calls = 0;
    stub_tab_sync_calls = 0;
    stub_special_sync_calls = 0;
    stub_special_sync_arg = false;
    stub_pointer_calls = 0;
    stub_idle_calls = 0;
    stub_printstatus_calls = 0;
    stub_tag_defaults_calls = 0;
    stub_rule_matches_calls = 0;
    stub_rule_apply_calls = 0;
    stub_layout_calls = 0;
    stub_layout_gappoh = 0;
    stub_overview_calls = 0;
    stub_focus_top_calls = 0;
    stub_check_tab_visible_calls = 0;
    stub_update_scroller_calls = 0;
    stub_special_active = false;
    stub_special_has_clients = false;
    stub_only_one_tag = false;
    stub_toggle_calls = 0;
    stub_focus_top = null;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.m = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 1;
    m.tagset[1] = 0;
    m.seltags = 0;
    p.nmasters[0] = 1;
    p.mfacts[0] = 0.6;
    p.ltidxs[0] = @ptrCast(&layouts[0]);
    p.config_ltidxs[0] = @ptrCast(&layouts[0]);
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

fn expectApprox(expected: f64, actual: f64) !void {
    try testing.expectApproxEqAbs(expected, actual, 0.0001);
}

test "tag_remap_mask maps occupied tags and keeps unmapped/out-of-range bits" {
    resetWorld();
    c.config.tag_num = 9;
    c.server.tagmask = 0x1ff;

    var map: [32]u32 = std.mem.zeroes([32]u32);
    map[3] = 2;
    map[9] = 3;

    const input: u32 = 0x105 | (@as(u32, 1) << 10);
    const out = tag_remap_mask(input, &map);
    try testing.expectEqual(@as(u32, 0x7 | (@as(u32, 1) << 10)), out);
}

test "tag_gather_apply compacts occupied tags and moves pertag state" {
    resetWorld();
    c.config.tag_num = 9;
    c.server.tagmask = 0x1ff;

    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.tagset[0] = 0x105;
    p.nmasters[1] = 2;
    p.nmasters[3] = 3;
    p.nmasters[9] = 9;
    p.curtag = 3;
    p.prevtag = 9;

    var a: Client = undefined;
    addClient(&a, &m, 0x105);

    tag_gather_apply(&m);

    try testing.expectEqual(@as(u32, 0x7), a.tags);
    try testing.expectEqual(@as(u32, 0x7), m.tagset[0]);
    try testing.expectEqual(@as(i32, 2), p.nmasters[1]);
    try testing.expectEqual(@as(i32, 3), p.nmasters[2]);
    try testing.expectEqual(@as(i32, 9), p.nmasters[3]);
    try testing.expectEqual(@as(u32, 2), p.curtag);
    try testing.expectEqual(@as(u32, 3), p.prevtag);
    try testing.expect(stub_tag_defaults_calls > 0);
}

test "special_handle_empty_view respects the empty-view latch" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);

    stub_special_active = false;
    try testing.expect(!special_handle_empty_view(&m, false));
    try testing.expect(!m.special_empty_view);

    stub_special_active = true;
    stub_special_has_clients = true;
    try testing.expect(!special_handle_empty_view(&m, false));
    try testing.expect(!m.special_empty_view);

    stub_special_has_clients = false;
    try testing.expect(!special_handle_empty_view(&m, true));
    try testing.expect(m.special_empty_view);

    m.special_empty_view = false;
    try testing.expect(special_handle_empty_view(&m, false));
    try testing.expectEqual(@as(c_int, 1), stub_toggle_calls);

    m.special_empty_view = true;
    try testing.expect(!special_handle_empty_view(&m, false));
    try testing.expectEqual(@as(c_int, 1), stub_toggle_calls);
}

test "reset_size_per_mon distributes weights for master and stack" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);

    var a: Client = undefined;
    var b: Client = undefined;
    var c_cl: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    addClient(&c_cl, &m, 1);
    a.master_size_weight = 1.0;
    a.stack_size_weight = 1.0;
    b.master_size_weight = 1.0;
    b.stack_size_weight = 2.0;
    c_cl.isfloating = 1;
    c_cl.stack_size_weight = 4.0;

    reset_size_per_mon(&m, 0, 0, 2, 1, 1, 1);

    // list order is newest-first: b is the first fake-tiled client and
    // therefore the master, a is the stack client.
    try testing.expect(!a.ismaster);
    try expectApprox(0.5, a.master_inner_per);
    try expectApprox(0.5, a.stack_inner_per);

    try testing.expect(b.ismaster);
    try expectApprox(1.0, b.master_inner_per);
    try expectApprox(0.5, b.stack_inner_per);

    try testing.expect(!c_cl.ismaster);
}

test "pre_calculate counts visibility and skips arrange hooks in calculate-only" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.nmasters[0] = 1;

    var a: Client = undefined;
    var b: Client = undefined;
    var other: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    addClient(&other, &m, 1);
    b.isfloating = 1;
    other.mon = @ptrFromInt(@intFromPtr(&m) + 4096);

    pre_calculate_before_arrange(&m, false, false, true);

    try testing.expectEqual(@as(u32, 2), m.visible_clients);
    try testing.expectEqual(@as(u32, 1), m.visible_tiling_clients);
    try testing.expectEqual(@as(u32, 1), m.visible_fake_tiling_clients);
    try testing.expectEqual(@as(u32, 0), m.hide_clients);
    try testing.expect(a.ismaster);
    try testing.expectEqual(@as(c_int, 0), stub_visible_calls);
    try testing.expectEqual(@as(c_int, 0), stub_sync_layer_calls);

    pre_calculate_before_arrange(&m, false, false, false);
    try testing.expectEqual(@as(c_int, 2), stub_visible_calls);
    try testing.expectEqual(@as(c_int, 2), stub_sync_layer_calls);
}

test "arrange runs the pre-pass, layout and post hooks" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.enabled = true;
    m.wlr_output = @ptrCast(&output);

    arrange(&m, false, false);

    try testing.expectEqual(@as(c_int, 1), stub_layout_calls);
    try testing.expectEqual(@as(c_int, 1), stub_tab_sync_calls);
    try testing.expectEqual(@as(c_int, 1), stub_special_sync_calls);
    try testing.expect(!stub_special_sync_arg);
    try testing.expectEqual(@as(c_int, 1), stub_pointer_calls);
    try testing.expectEqual(@as(c_int, 1), stub_idle_calls);
    try testing.expectEqual(@as(c_int, 1), stub_printstatus_calls);
    try testing.expectEqual(@as(c_int, 1), stub_focus_top_calls);

    output.enabled = false;
    stub_layout_calls = 0;
    arrange(&m, false, false);
    try testing.expectEqual(@as(c_int, 0), stub_layout_calls);
}

test "arrange swaps in special gaps around the layout call" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.enabled = true;
    m.wlr_output = @ptrCast(&output);
    m.gappoh = 1;
    m.gappov = 2;
    m.gappih = 3;
    m.gappiv = 4;
    m.special_gappoh = 7;
    m.special_gappov = 8;
    m.special_gappih = 9;
    m.special_gappiv = 10;

    stub_special_active = true;
    stub_special_has_clients = true;

    arrange(&m, false, false);

    try testing.expectEqual(@as(c_int, 7), stub_layout_gappoh);
    try testing.expectEqual(@as(i32, 1), m.gappoh);
    try testing.expectEqual(@as(i32, 2), m.gappov);
    try testing.expectEqual(@as(i32, 3), m.gappih);
    try testing.expectEqual(@as(i32, 4), m.gappiv);
    try testing.expect(stub_special_sync_arg);
}

test "arrange stops when an empty special view is closed" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.enabled = true;
    m.wlr_output = @ptrCast(&output);

    stub_special_active = true;
    stub_special_has_clients = false;
    m.special_empty_view = false;

    arrange(&m, false, false);

    try testing.expectEqual(@as(c_int, 1), stub_toggle_calls);
    try testing.expectEqual(@as(c_int, 0), stub_layout_calls);
    try testing.expectEqual(@as(c_int, 0), stub_printstatus_calls);
}

test "arrange uses the overview layout when active" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.enabled = true;
    m.wlr_output = @ptrCast(&output);
    m.isoverview = 1;

    arrange(&m, false, false);

    try testing.expectEqual(@as(c_int, 1), stub_overview_calls);
    try testing.expectEqual(@as(c_int, 0), stub_layout_calls);
}

test "arrange gathers tags after layout when configured" {
    resetWorld();
    c.config.tag_num = 9;
    c.server.tagmask = 0x1ff;
    c.config.tag_gather = 1;

    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    var output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
    output.enabled = true;
    m.wlr_output = @ptrCast(&output);
    m.tagset[0] = 0x105;

    var a: Client = undefined;
    addClient(&a, &m, 0x105);

    arrange(&m, false, false);

    try testing.expectEqual(@as(u32, 0x7), a.tags);
    try testing.expectEqual(@as(u32, 0x7), m.tagset[0]);
}
