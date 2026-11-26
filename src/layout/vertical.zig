//! Port of src/layout/vertical.c (strangler-fig Phase 4, slice 29).
//!
//! Exports the eight public symbols (vertical_tile/deck/grid/fair and their
//! *_predict variants) with the C twins guarded by ACWM_ZIG_LAYOUT_VERTICAL.
//! The cores keep the C arithmetic domains: pertag mfacts are float, client
//! master ratios are double, monitor geometry is int32. Layout math is
//! intentionally bit-for-bit conservative (truncating int conversions) so
//! the C layout and the Zig layout produce identical boxes during the
//! cutover.
//!
//! Depends on (kept in C for now): get_mon_curtag, client_tile_resize,
//! client_update_visibility, client_is_x11_popup, plus the config/server
//! globals. Tests stub those and record resize boxes.

const std = @import("std");
const c = @import("cc");

const LayoutContext = c.LayoutContext;
const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const WlList = c.struct_wl_list;
const CoreFn = *const fn (*Monitor, ?*const LayoutContext) void;

extern fn get_mon_curtag(m: *const Monitor) callconv(.c) u32;
extern fn client_tile_resize(cl: *Client, geo: Box, interact: i32, ctx: ?*const LayoutContext) callconv(.c) void;
extern fn client_update_visibility(cl: *Client) callconv(.c) void;
extern fn client_is_x11_popup(cl: *Client) callconv(.c) c_int;

extern "c" fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;



fn containerOf(comptime T: type, comptime link_field: []const u8, link: [*c]WlList) *T {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(T, link_field));
}

fn listHead(head: *WlList) [*c]WlList {
    return @ptrCast(head);
}

fn listInit(head: *WlList) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

fn curtagIndex(m: *const Monitor) usize {
    return @intCast(get_mon_curtag(m));
}

fn ISFAKETILED(cl: ?*const Client) bool {
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

fn sameMonitor(a: ?*const Client, m: *const Monitor) bool {
    const x = a orelse return false;
    return x.mon == @as([*c]Monitor, @ptrCast(@constCast(m)));
}

inline fn truncI32(x: f64) i32 {
    return @intFromFloat(x);
}

inline fn truncF32ToI32(x: f32) i32 {
    return @intFromFloat(x);
}

fn allocFloats(n: usize) ?[*]f32 {
    const raw = calloc(n, @sizeOf(f32)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn freeFloats(p: ?[*]f32) void {
    if (p) |ptr| free(@ptrCast(ptr));
}

// ---------------------------------------------------------------------------
// vertical_tile
// ---------------------------------------------------------------------------

fn verticalTileCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const ie: i32 = c.server.enable_gaps;
    const curtag = curtagIndex(m);
    const nmasters = m.pertag.*.nmasters[curtag];

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    var master_num = nmasters;
    master_num = if (n > master_num) master_num else n;
    const stack_num = n - master_num;

    if (n == 0)
        return;

    var cur_gapih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gapiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gapoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var cur_gapov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gapih = 0;
        cur_gapiv = 0;
        cur_gapoh = 0;
        cur_gapov = 0;
    }

    var fc: ?*Client = null;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISFAKETILED(cl)) {
            fc = cl;
            break;
        }
    }
    if (fc == null)
        return; // C dereferences the list head here; guard instead of UB.

    const mfact: f64 = if (fc.?.master_mfact_per > 0.0)
        fc.?.master_mfact_per
    else
        @as(f64, m.pertag.*.mfacts[curtag]);

    var mh: i32 = undefined;
    if (n > nmasters) {
        mh = if (nmasters != 0)
            truncI32(@as(f64, @floatFromInt(m.w.height + cur_gapiv * ie)) * mfact)
        else
            0;
    } else {
        mh = m.w.height - 2 * cur_gapov + cur_gapiv * ie;
    }

    var i: i32 = 0;
    var mx: i32 = cur_gapoh;
    var tx: i32 = cur_gapoh;

    var master_surplus_width: i32 =
        m.w.width - 2 * cur_gapoh - cur_gapih * ie * (master_num - 1);
    var master_surplus_ratio: f32 = 1.0;

    var slave_surplus_width: i32 =
        m.w.width - 2 * cur_gapoh - cur_gapih * ie * (stack_num - 1);
    var slave_surplus_ratio: f32 = 1.0;

    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (i < nmasters) {
            const r: i32 = @min(n, nmasters) - i;
            var w: i32 = undefined;
            if (cl.master_inner_per > 0.0) {
                w = truncI32(@as(f64, @floatFromInt(master_surplus_width)) *
                    cl.master_inner_per /
                    @as(f64, @floatCast(master_surplus_ratio)));
                master_surplus_width -= w;
                master_surplus_ratio = @floatCast(@as(f64, master_surplus_ratio) - cl.master_inner_per);
                cl.master_mfact_per = mfact;
            } else {
                const denom = m.w.width - mx - cur_gapih - cur_gapih * ie * (r - 1);
                w = @divTrunc(denom, r);
                cl.master_inner_per = @as(f64, @floatFromInt(w)) / @as(f64, @floatFromInt(denom));
                cl.master_mfact_per = mfact;
            }
            client_tile_resize(cl, .{
                .x = m.w.x + mx,
                .y = m.w.y + cur_gapov,
                .width = w,
                .height = mh - cur_gapiv * ie,
            }, 0, ctx);
            mx += w + cur_gapih * ie;
        } else {
            const r: i32 = n - i;
            var w: i32 = undefined;
            if (cl.stack_inner_per > 0.0) {
                w = truncI32(@as(f64, @floatFromInt(slave_surplus_width)) *
                    cl.stack_inner_per /
                    @as(f64, @floatCast(slave_surplus_ratio)));
                slave_surplus_width -= w;
                slave_surplus_ratio = @floatCast(@as(f64, slave_surplus_ratio) - cl.stack_inner_per);
                cl.master_mfact_per = mfact;
            } else {
                const denom = m.w.width - tx - cur_gapih - cur_gapih * ie * (r - 1);
                w = @divTrunc(denom, r);
                cl.stack_inner_per = @as(f64, @floatFromInt(w)) / @as(f64, @floatFromInt(denom));
                cl.master_mfact_per = mfact;
            }
            client_tile_resize(cl, .{
                .x = m.w.x + tx,
                .y = m.w.y + mh + cur_gapov,
                .width = w,
                .height = m.w.height - mh - 2 * cur_gapov,
            }, 0, ctx);
            tx += w + cur_gapih * ie;
        }
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// vertical_deck
// ---------------------------------------------------------------------------

fn verticalDeckCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const curtag = curtagIndex(m);
    const nmasters: i32 = m.pertag.*.nmasters[curtag];

    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gappiv = 0;
        cur_gappoh = 0;
        cur_gappov = 0;
    }

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    if (n == 0)
        return;

    var fc: ?*Client = null;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISFAKETILED(cl)) {
            fc = cl;
            break;
        }
    }
    if (fc == null)
        return; // same defensive guard as the tile core

    const mfact: f64 = if (fc.?.master_mfact_per > 0.0)
        fc.?.master_mfact_per
    else
        @as(f64, m.pertag.*.mfacts[curtag]);

    var mh: i32 = undefined;
    if (n > nmasters) {
        mh = if (nmasters != 0)
            truncI32(@round(@as(f64, @floatFromInt(m.w.height - 2 * cur_gappov)) * mfact))
        else
            0;
    } else {
        mh = m.w.height - 2 * cur_gappov;
    }

    var i: i32 = 0;
    var mx: i32 = 0;
    pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (i < nmasters) {
            cl.master_mfact_per = mfact;
            const w = @divTrunc(m.w.width - 2 * cur_gappoh - mx, @min(n, nmasters) - i);
            client_tile_resize(cl, .{
                .x = m.w.x + cur_gappoh + mx,
                .y = m.w.y + cur_gappov,
                .width = w,
                .height = mh,
            }, 0, ctx);
            mx += w;
        } else {
            cl.master_mfact_per = mfact;
            client_tile_resize(cl, .{
                .x = m.w.x + cur_gappoh,
                .y = m.w.y + mh + cur_gappov + cur_gappiv,
                .width = m.w.width - 2 * cur_gappoh,
                .height = m.w.height - mh - 2 * cur_gappov - cur_gappiv,
            }, 0, ctx);
            if (ctx == null)
                client_update_visibility(cl);
        }
        i += 1;
    }
}

// grid and fair cores follow in part 2.

// ---------------------------------------------------------------------------
// vertical_grid
// ---------------------------------------------------------------------------

fn verticalGridCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const target_gappo: i32 = if (c.server.enable_gaps != 0) @intCast(c.config.gappov) else 0;
    const target_gappi: i32 = if (c.server.enable_gaps != 0) @intCast(c.config.gappiv) else 0;
    const single_width_ratio: f32 = 0.9;
    const single_height_ratio: f32 = 0.9;
    var target_geom: Box = undefined;

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    if (n == 0)
        return;

    if (n == 1) {
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (!sameMonitor(cl, m))
                continue;
            if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
                (client_is_x11_popup(cl) == 0 or ISFAKETILED(cl)))
            {
                const ch = truncF32ToI32(@as(f32, @floatFromInt(m.w.height - 2 * target_gappo)) * single_height_ratio);
                const cw = truncF32ToI32(@as(f32, @floatFromInt(m.w.width - 2 * target_gappo)) * single_width_ratio);
                target_geom.x = m.w.x + @divTrunc(m.w.width - cw, 2);
                target_geom.y = m.w.y + @divTrunc(m.w.height - ch, 2);
                target_geom.width = cw;
                target_geom.height = ch;
                client_tile_resize(cl, target_geom, 0, ctx);
                return;
            }
        }
    }

    if (n == 2) {
        var row_pers = [2]f32{ 1.0, 1.0 };
        var i: i32 = 0;
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (!sameMonitor(cl, m))
                continue;
            if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
                (client_is_x11_popup(cl) == 0 or ISFAKETILED(cl)))
            {
                if (i < 2)
                    row_pers[@intCast(i)] = if (cl.grid_row_per > 0.0) cl.grid_row_per else 1.0;
                i += 1;
            }
        }

        const sum_row: f32 = row_pers[0] + row_pers[1];
        const avail_h: f32 = @floatFromInt(m.w.height - 2 * target_gappo - target_gappi);
        // 0.65 is a double literal in C, so the multiply happens in f64.
        const cw = truncI32(@as(f64, @floatFromInt(m.w.width - 2 * target_gappo)) * 0.65);

        i = 0;
        pos = c.server.clients.next;
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (!sameMonitor(cl, m))
                continue;
            if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
                (client_is_x11_popup(cl) == 0 or ISFAKETILED(cl)))
            {
                cl.grid_col_idx = 0;
                cl.grid_row_idx = i;
                cl.grid_col_per = 1.0;
                cl.grid_row_per = row_pers[@intCast(i)];

                const ch = truncF32ToI32(avail_h * (row_pers[@intCast(i)] / sum_row));

                target_geom.x = m.w.x + @divTrunc(m.w.width - cw, 2) + target_gappo;
                if (i == 0) {
                    target_geom.y = m.w.y + target_gappo;
                } else if (i == 1) {
                    const ch0: f32 = avail_h * (row_pers[0] / sum_row);
                    target_geom.y = truncF32ToI32(@as(f32, @floatFromInt(m.w.y + target_gappo)) + ch0 + @as(f32, @floatFromInt(target_gappi)));
                }
                target_geom.width = cw;
                target_geom.height = ch;
                client_tile_resize(cl, target_geom, 0, ctx);
                i += 1;
            }
        }
        return;
    }

    var rows: i32 = 0;
    while (rows <= @divTrunc(n, 2)) : (rows += 1) {
        if (rows * rows >= n)
            break;
    }
    const cols: i32 = if (rows != 0 and (rows - 1) * rows >= n) rows - 1 else rows;
    const overrows: i32 = @rem(n, rows);

    const col_pers = allocFloats(@intCast(cols)) orelse return;
    const row_pers = allocFloats(@intCast(rows)) orelse {
        freeFloats(col_pers);
        return;
    };
    defer freeFloats(col_pers);
    defer freeFloats(row_pers);

    var i: i32 = 0;
    while (i < cols) : (i += 1)
        col_pers[@intCast(i)] = 1.0;
    i = 0;
    while (i < rows) : (i += 1)
        row_pers[@intCast(i)] = 1.0;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    i = 0;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!sameMonitor(cl, m))
            continue;
        if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
            (client_is_x11_popup(cl) == 0 or ISFAKETILED(cl)))
        {
            const c_idx = @divTrunc(i, rows);
            const r_idx = @rem(i, rows);
            if (r_idx == 0)
                col_pers[@intCast(c_idx)] = if (cl.grid_col_per > 0.0) cl.grid_col_per else 1.0;
            if (c_idx == 0)
                row_pers[@intCast(r_idx)] = if (cl.grid_row_per > 0.0) cl.grid_row_per else 1.0;
            i += 1;
        }
    }

    var sum_col: f32 = 0.0;
    var sum_row: f32 = 0.0;
    i = 0;
    while (i < cols) : (i += 1)
        sum_col += col_pers[@intCast(i)];
    i = 0;
    while (i < rows) : (i += 1)
        sum_row += row_pers[@intCast(i)];

    const avail_w: f32 = @floatFromInt(m.w.width - 2 * target_gappo - (cols - 1) * target_gappi);
    const avail_h: f32 = @floatFromInt(m.w.height - 2 * target_gappo - (rows - 1) * target_gappi);

    pos = c.server.clients.next;
    i = 0;
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!sameMonitor(cl, m))
            continue;
        if (!(VISIBLEON(cl, m) and cl.isunglobal == 0 and
            (client_is_x11_popup(cl) == 0 or ISFAKETILED(cl))))
            continue;

        const c_idx = @divTrunc(i, rows);
        const r_idx = @rem(i, rows);

        cl.grid_col_per = col_pers[@intCast(c_idx)];
        cl.grid_row_per = row_pers[@intCast(r_idx)];
        cl.grid_col_idx = c_idx;
        cl.grid_row_idx = r_idx;

        var fl_cy: f32 = @floatFromInt(m.w.y + target_gappo);
        var fl_ch: f32 = 0.0;

        if (overrows != 0 and i >= n - overrows) {
            var over_h: f32 = 0.0;
            var j: i32 = 0;
            while (j < overrows) : (j += 1)
                over_h += avail_h * (row_pers[@intCast(j)] / sum_row);
            over_h += @floatFromInt((overrows - 1) * target_gappi);
            const dy: f32 = (@as(f32, @floatFromInt(m.w.height)) - over_h) / 2.0 -
                @as(f32, @floatFromInt(target_gappo));

            fl_cy += dy;
            j = 0;
            while (j < r_idx) : (j += 1)
                fl_cy += avail_h * (row_pers[@intCast(j)] / sum_row) + @as(f32, @floatFromInt(target_gappi));
            fl_ch = avail_h * (row_pers[@intCast(r_idx)] / sum_row);
        } else {
            var j: i32 = 0;
            while (j < r_idx) : (j += 1)
                fl_cy += avail_h * (row_pers[@intCast(j)] / sum_row) + @as(f32, @floatFromInt(target_gappi));
            fl_ch = if (r_idx == rows - 1)
                @as(f32, @floatFromInt(m.w.y + m.w.height - target_gappo)) - fl_cy
            else
                avail_h * (row_pers[@intCast(r_idx)] / sum_row);
        }

        var fl_cx: f32 = @floatFromInt(m.w.x + target_gappo);
        var j: i32 = 0;
        while (j < c_idx) : (j += 1)
            fl_cx += avail_w * (col_pers[@intCast(j)] / sum_col) + @as(f32, @floatFromInt(target_gappi));
        const fl_cw: f32 = if (c_idx == cols - 1)
            @as(f32, @floatFromInt(m.w.x + m.w.width - target_gappo)) - fl_cx
        else
            avail_w * (col_pers[@intCast(c_idx)] / sum_col);

        target_geom.x = truncF32ToI32(fl_cx);
        target_geom.y = truncF32ToI32(fl_cy);
        target_geom.width = truncF32ToI32(fl_cw);
        target_geom.height = truncF32ToI32(fl_ch);
        client_tile_resize(cl, target_geom, 0, ctx);
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// vertical_fair
// ---------------------------------------------------------------------------

fn verticalFairCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    if (n == 0)
        return;

    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;

    if (c.config.smartgaps != 0 and n == 1) {
        cur_gappiv = 0;
        cur_gappih = 0;
        cur_gappov = 0;
        cur_gappoh = 0;
    }

    var rows: i32 = 0;
    while (rows <= n) : (rows += 1) {
        if (rows * rows >= n)
            break;
    }

    const base_cols = @divTrunc(n, rows);
    const remainder = @rem(n, rows);
    const first_group_rows = rows - remainder;
    const first_group_count = first_group_rows * base_cols;
    const max_cols = base_cols + (if (remainder > 0) @as(i32, 1) else 0);

    const arr_raw = calloc(@intCast(n), @sizeOf(*Client)) orelse return;
    const arr: [*]*Client = @ptrCast(@alignCast(arr_raw));
    const row_pers = allocFloats(@intCast(rows)) orelse {
        free(arr_raw);
        return;
    };
    const col_pers = allocFloats(@intCast(max_cols)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        return;
    };
    const row_y = allocFloats(@intCast(rows)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        return;
    };
    const row_h = allocFloats(@intCast(rows)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        freeFloats(row_y);
        return;
    };
    const col_x_base = allocFloats(@intCast(base_cols)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        freeFloats(row_y);
        freeFloats(row_h);
        return;
    };
    const col_w_base = allocFloats(@intCast(base_cols)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        freeFloats(row_y);
        freeFloats(row_h);
        freeFloats(col_x_base);
        return;
    };
    const col_x_max = allocFloats(@intCast(max_cols)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        freeFloats(row_y);
        freeFloats(row_h);
        freeFloats(col_x_base);
        freeFloats(col_w_base);
        return;
    };
    const col_w_max = allocFloats(@intCast(max_cols)) orelse {
        free(arr_raw);
        freeFloats(row_pers);
        freeFloats(col_pers);
        freeFloats(row_y);
        freeFloats(row_h);
        freeFloats(col_x_base);
        freeFloats(col_w_base);
        freeFloats(col_x_max);
        return;
    };
    defer free(arr_raw);
    defer freeFloats(row_pers);
    defer freeFloats(col_pers);
    defer freeFloats(row_y);
    defer freeFloats(row_h);
    defer freeFloats(col_x_base);
    defer freeFloats(col_w_base);
    defer freeFloats(col_x_max);
    defer freeFloats(col_w_max);

    var arr_idx: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISFAKETILED(cl)) {
            arr[@intCast(arr_idx)] = cl;
            arr_idx += 1;
            if (arr_idx >= n)
                break;
        }
    }

    var i: i32 = 0;
    while (i < rows) : (i += 1)
        row_pers[@intCast(i)] = 0.0;
    i = 0;
    while (i < max_cols) : (i += 1)
        col_pers[@intCast(i)] = 0.0;

    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        const row_idx: i32 = if (i < first_group_count)
            @divTrunc(i, base_cols)
        else
            first_group_rows + @divTrunc(i - first_group_count, max_cols);
        const col_idx: i32 = if (i < first_group_count)
            @rem(i, base_cols)
        else
            @rem(i - first_group_count, max_cols);

        if (cl.grid_row_idx == row_idx and cl.grid_row_per > 0.0)
            row_pers[@intCast(row_idx)] = cl.grid_row_per;
        if (cl.grid_col_idx == col_idx and cl.grid_col_per > 0.0)
            col_pers[@intCast(col_idx)] = cl.grid_col_per;
    }
    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        const row_idx: i32 = if (i < first_group_count)
            @divTrunc(i, base_cols)
        else
            first_group_rows + @divTrunc(i - first_group_count, max_cols);
        const col_idx: i32 = if (i < first_group_count)
            @rem(i, base_cols)
        else
            @rem(i - first_group_count, max_cols);

        if (row_pers[@intCast(row_idx)] == 0.0 and cl.grid_row_per > 0.0)
            row_pers[@intCast(row_idx)] = cl.grid_row_per;
        if (col_pers[@intCast(col_idx)] == 0.0 and cl.grid_col_per > 0.0)
            col_pers[@intCast(col_idx)] = cl.grid_col_per;
    }

    var sum_row: f32 = 0.0;
    i = 0;
    while (i < rows) : (i += 1) {
        if (row_pers[@intCast(i)] == 0.0)
            row_pers[@intCast(i)] = 1.0;
        sum_row += row_pers[@intCast(i)];
    }
    i = 0;
    while (i < max_cols) : (i += 1) {
        if (col_pers[@intCast(i)] == 0.0)
            col_pers[@intCast(i)] = 1.0;
    }

    const avail_h: f32 = @floatFromInt(m.w.height - 2 * cur_gappov - (rows - 1) * cur_gappiv);
    var next_y: f32 = @floatFromInt(m.w.y + cur_gappov);
    i = 0;
    while (i < rows) : (i += 1) {
        row_y[@intCast(i)] = next_y;
        row_h[@intCast(i)] = if (i == rows - 1)
            @as(f32, @floatFromInt(m.w.y + m.w.height - cur_gappov)) - next_y
        else
            avail_h * (row_pers[@intCast(i)] / sum_row);
        next_y += row_h[@intCast(i)] + @as(f32, @floatFromInt(cur_gappiv));
    }

    var sum_col_base: f32 = 0.0;
    i = 0;
    while (i < base_cols) : (i += 1)
        sum_col_base += col_pers[@intCast(i)];
    const avail_w_base: f32 = @floatFromInt(m.w.width - 2 * cur_gappoh - (base_cols - 1) * cur_gappih);
    var next_x: f32 = @floatFromInt(m.w.x + cur_gappoh);
    i = 0;
    while (i < base_cols) : (i += 1) {
        col_x_base[@intCast(i)] = next_x;
        col_w_base[@intCast(i)] = if (i == base_cols - 1)
            @as(f32, @floatFromInt(m.w.x + m.w.width - cur_gappoh)) - next_x
        else
            avail_w_base * (col_pers[@intCast(i)] / sum_col_base);
        next_x += col_w_base[@intCast(i)] + @as(f32, @floatFromInt(cur_gappih));
    }

    if (remainder > 0) {
        var sum_col_max: f32 = 0.0;
        i = 0;
        while (i < max_cols) : (i += 1)
            sum_col_max += col_pers[@intCast(i)];
        const avail_w_max: f32 = @floatFromInt(m.w.width - 2 * cur_gappoh - (max_cols - 1) * cur_gappih);
        next_x = @floatFromInt(m.w.x + cur_gappoh);
        i = 0;
        while (i < max_cols) : (i += 1) {
            col_x_max[@intCast(i)] = next_x;
            col_w_max[@intCast(i)] = if (i == max_cols - 1)
                @as(f32, @floatFromInt(m.w.x + m.w.width - cur_gappoh)) - next_x
            else
                avail_w_max * (col_pers[@intCast(i)] / sum_col_max);
            next_x += col_w_max[@intCast(i)] + @as(f32, @floatFromInt(cur_gappih));
        }
    }

    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        var row_idx: i32 = undefined;
        var col_idx: i32 = undefined;
        var fl_cx: f32 = undefined;
        var fl_cw: f32 = undefined;

        if (i < first_group_count) {
            row_idx = @divTrunc(i, base_cols);
            col_idx = @rem(i, base_cols);
            fl_cx = col_x_base[@intCast(col_idx)];
            fl_cw = col_w_base[@intCast(col_idx)];
        } else {
            const offset = i - first_group_count;
            row_idx = first_group_rows + @divTrunc(offset, max_cols);
            col_idx = @rem(offset, max_cols);
            fl_cx = col_x_max[@intCast(col_idx)];
            fl_cw = col_w_max[@intCast(col_idx)];
        }

        cl.grid_row_per = row_pers[@intCast(row_idx)];
        cl.grid_col_per = col_pers[@intCast(col_idx)];
        cl.grid_row_idx = row_idx;
        cl.grid_col_idx = col_idx;

        const fl_cy = row_y[@intCast(row_idx)];
        const fl_ch = row_h[@intCast(row_idx)];

        client_tile_resize(cl, .{
            .x = truncF32ToI32(fl_cx),
            .y = truncF32ToI32(fl_cy),
            .width = truncF32ToI32(fl_cw),
            .height = truncF32ToI32(fl_ch),
        }, 0, ctx);
    }
}

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

fn layoutPredictBox(core: CoreFn, m: *Monitor, cl: *Client, out: *Box) bool {
    var geo = std.mem.zeroes(Box);
    var ctx = LayoutContext{ .probe = cl, .out = &geo };
    core(m, &ctx);
    out.* = geo;
    return geo.width > 0 and geo.height > 0;
}

export fn vertical_tile(m: *Monitor) callconv(.c) void {
    verticalTileCore(m, null);
}

export fn vertical_tile_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(verticalTileCore, m, cl, out);
}

export fn vertical_deck(m: *Monitor) callconv(.c) void {
    verticalDeckCore(m, null);
}

export fn vertical_deck_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(verticalDeckCore, m, cl, out);
}

export fn vertical_grid(m: *Monitor) callconv(.c) void {
    verticalGridCore(m, null);
}

export fn vertical_grid_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(verticalGridCore, m, cl, out);
}

export fn vertical_fair(m: *Monitor) callconv(.c) void {
    verticalFairCore(m, null);
}

export fn vertical_fair_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(verticalFairCore, m, cl, out);
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_vertical_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_curtag: c_int;
extern var stub_popup: c_int;
extern var stub_tile_calls: c_int;
extern var stub_tile_boxes: [128]Box;
extern var stub_tile_clients: [128]?*Client;
extern var stub_visibility_calls: c_int;

fn listInsert(head: *WlList, link: *WlList) void {
    link.next = head.next;
    link.prev = @ptrCast(head);
    head.next.*.prev = @ptrCast(link);
    head.next = @ptrCast(link);
}

fn resetWorld() void {
    listInit(&c.server.clients);
    c.server.enable_gaps = 0;
    c.config.smartgaps = 0;
    c.config.gappih = 0;
    c.config.gappiv = 0;
    c.config.gappoh = 0;
    c.config.gappov = 0;
    stub_curtag = 0;
    stub_popup = 0;
    stub_tile_calls = 0;
    stub_visibility_calls = 0;
}

fn baseMonitor(m: *Monitor, p: *c.Pertag) void {
    m.* = std.mem.zeroes(Monitor);
    p.* = std.mem.zeroes(c.Pertag);
    m.pertag = p;
    m.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    m.tagset[0] = 0xffff;
    m.seltags = 0;
    p.nmasters[0] = 1;
    p.mfacts[0] = 0.6;
}

fn addClient(cl: *Client, m: *Monitor, tags: u32) void {
    cl.* = std.mem.zeroes(Client);
    cl.mon = @ptrCast(m);
    cl.tags = tags;
    listInsert(&c.server.clients, &cl.link);
}

fn expectBox(idx: usize, x: i32, y: i32, w: i32, h: i32) !void {
    const b = stub_tile_boxes[idx];
    try testing.expectEqual(x, b.x);
    try testing.expectEqual(y, b.y);
    try testing.expectEqual(w, b.width);
    try testing.expectEqual(h, b.height);
}

fn expectCount(n: usize) !void {
    try testing.expectEqual(@as(c_int, @intCast(n)), stub_tile_calls);
}

test "vertical_tile: one master above the stack" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var clients: [2]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);

    vertical_tile(&m);

    try expectCount(2);
    try expectBox(0, 0, 0, 1000, 480);
    try expectBox(1, 0, 480, 1000, 320);
    // wl_list_insert puts the newest client first
    try testing.expect(stub_tile_clients[0] == &clients[1]);
    try testing.expect(stub_tile_clients[1] == &clients[0]);
}

test "vertical_tile: outer and inner gaps" {
    resetWorld();
    c.server.enable_gaps = 1;
    c.config.gappih = 6;
    c.config.gappiv = 4;
    c.config.gappoh = 10;
    c.config.gappov = 20;

    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.gappih = 6;
    m.gappiv = 4;
    m.gappoh = 10;
    m.gappov = 20;
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);
    addClient(&clients[2], &m, 0x1);

    vertical_tile(&m);

    try expectCount(3);
    try expectBox(0, 10, 20, 984, 478);
    try expectBox(1, 10, 502, 489, 278);
    try expectBox(2, 505, 502, 489, 278);
}

test "vertical_tile: smartgaps removes gaps for a single client" {
    resetWorld();
    c.server.enable_gaps = 1;
    c.config.smartgaps = 1;

    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.gappih = 6;
    m.gappiv = 4;
    m.gappoh = 10;
    m.gappov = 20;
    m.visible_fake_tiling_clients = 1;

    var cl: Client = undefined;
    addClient(&cl, &m, 0x1);

    vertical_tile(&m);

    try expectCount(1);
    try expectBox(0, 0, 0, 1000, 800);
}

test "vertical_tile: master_inner_per distributes surplus width" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.nmasters[0] = 3;
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);
    addClient(&clients[2], &m, 0x1);
    clients[0].master_inner_per = 0.2;
    clients[1].master_inner_per = 0.3;

    vertical_tile(&m);

    try expectCount(3);
    // list order is clients[2], clients[1], clients[0]; only the ones with a
    // stored ratio take a proportional slice, the zero-ratio one keeps an
    // even share and leaves the surplus untouched (matching C).
    try expectBox(0, 0, 0, 333, 800);
    try expectBox(1, 333, 0, 300, 800);
    try expectBox(2, 633, 0, 200, 800);
}

test "vertical_deck: masters in a row, stack below" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.nmasters[0] = 2;
    p.mfacts[0] = 0.5;
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);
    addClient(&clients[2], &m, 0x1);

    vertical_deck(&m);

    try expectCount(3);
    try expectBox(0, 0, 0, 500, 400);
    try expectBox(1, 500, 0, 500, 400);
    try expectBox(2, 0, 400, 1000, 400);
    try testing.expectEqual(@as(c_int, 1), stub_visibility_calls);
}

test "vertical_grid: single and double client layouts" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 1;

    var one: [1]Client = undefined;
    addClient(&one[0], &m, 0x1);

    vertical_grid(&m);
    try expectCount(1);
    try expectBox(0, 50, 40, 900, 720);

    resetWorld();
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var two: [2]Client = undefined;
    addClient(&two[0], &m, 0x1);
    addClient(&two[1], &m, 0x1);

    vertical_grid(&m);
    try expectCount(2);
    try expectBox(0, 175, 0, 650, 400);
    try expectBox(1, 175, 400, 650, 400);
}

test "vertical_grid: four clients form a 2x2 grid" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 4;

    var clients: [4]Client = undefined;
    for (&clients) |*cl|
        addClient(cl, &m, 0x1);

    vertical_grid(&m);

    try expectCount(4);
    try expectBox(0, 0, 0, 500, 400);
    try expectBox(1, 0, 400, 500, 400);
    try expectBox(2, 500, 0, 500, 400);
    try expectBox(3, 500, 400, 500, 400);
}

test "vertical_fair: first group gets a full row, remainder splits" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);
    addClient(&clients[2], &m, 0x1);

    vertical_fair(&m);

    try expectCount(3);
    try expectBox(0, 0, 0, 1000, 400);
    try expectBox(1, 0, 400, 500, 400);
    try expectBox(2, 500, 400, 500, 400);
}

test "predict variants answer the probe without resizing other clients" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var clients: [2]Client = undefined;
    addClient(&clients[0], &m, 0x1);
    addClient(&clients[1], &m, 0x1);

    var out: Box = std.mem.zeroes(Box);
    // clients[0] is the stack tile (the list runs newest-first)
    try testing.expect(vertical_tile_predict(&m, &clients[0], &out));
    try testing.expectEqual(@as(i32, 0), out.x);
    try testing.expectEqual(@as(i32, 480), out.y);
    try testing.expectEqual(@as(i32, 1000), out.width);
    try testing.expectEqual(@as(i32, 320), out.height);
    try expectCount(0);

    try testing.expect(vertical_grid_predict(&m, &clients[0], &out));
    try testing.expectEqual(@as(i32, 175), out.x);
    try testing.expectEqual(@as(i32, 400), out.y);
    try testing.expectEqual(@as(i32, 650), out.width);
    try testing.expectEqual(@as(i32, 400), out.height);
    try expectCount(0);
}
