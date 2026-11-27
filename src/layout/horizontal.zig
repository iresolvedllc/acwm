//! Port of src/layout/horizontal.c (strangler-fig Phase 4, layout slice 3,
//! slice 31).
//!
//! Seven horizontal layouts with predict variants: tile, right_tile,
//! center_tile, deck, monocle, grid and fair. The C twin is guarded with
//! ACWM_ZIG_LAYOUT_HORIZONTAL.
//!
//! Arithmetic domains mirror the C: pertag mfacts float promoted to double
//! for the master width, client master/stack ratios double, grid/fair
//! weights float, the grid 0.65 height double. The tile cores store
//! `w / available` with C integer division (as the original does), which is
//! intentionally reproduced.

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;
const Box = c.struct_wlr_box;
const LayoutContext = c.LayoutContext;
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

fn sameMonitor(cl: ?*const Client, m: *const Monitor) bool {
    const x = cl orelse return false;
    return x.mon == @as([*c]Monitor, @ptrCast(@constCast(m)));
}

inline fn truncD(x: f64) i32 {
    return @intFromFloat(x);
}

inline fn truncF(x: f32) i32 {
    return @intFromFloat(x);
}

fn allocFloats(n: usize) ?[*]f32 {
    const raw = calloc(n, @sizeOf(f32)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn freeFloats(p: ?[*]f32) void {
    if (p) |ptr| free(@ptrCast(ptr));
}

fn firstVisibleFakeTiled(m: *Monitor) ?*Client {
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (VISIBLEON(cl, m) and ISFAKETILED(cl))
            return cl;
    }
    return null;
}

// ---------------------------------------------------------------------------
// tile / right_tile
// ---------------------------------------------------------------------------

fn tileCore(m: *Monitor, ctx: ?*const LayoutContext, right: bool) void {
    const ie: i32 = c.server.enable_gaps;
    const curtag = curtagIndex(m);
    const nmasters = m.pertag.*.nmasters[curtag];

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    var master_num = nmasters;
    master_num = if (n > master_num) master_num else n;
    const stack_num = n - master_num;

    if (n == 0)
        return;

    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gappiv = 0;
        cur_gappih = 0;
        cur_gappov = 0;
        cur_gappoh = 0;
    }

    const fc = firstVisibleFakeTiled(m) orelse return; // C derefs the list head
    const mfact: f64 = if (fc.master_mfact_per > 0.0)
        fc.master_mfact_per
    else
        @as(f64, m.pertag.*.mfacts[curtag]);

    var mw: i32 = undefined;
    if (n > nmasters) {
        mw = if (nmasters != 0)
            truncD(@as(f64, @floatFromInt(m.w.width + cur_gappih * ie)) * mfact)
        else
            0;
    } else {
        mw = m.w.width - 2 * cur_gappoh + cur_gappih * ie;
    }

    var i: i32 = 0;
    var my: i32 = cur_gappov;
    var ty: i32 = cur_gappov;

    var master_surplus_height: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (master_num - 1);
    var master_surplus_ratio: f32 = 1.0;

    var slave_surplus_height: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (stack_num - 1);
    var slave_surplus_ratio: f32 = 1.0;

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (i < nmasters) {
            const r: i32 = @min(n, nmasters) - i;
            var h: i32 = undefined;
            if (cl.master_inner_per > 0.0) {
                h = truncD(@as(f64, @floatFromInt(master_surplus_height)) *
                    cl.master_inner_per /
                    @as(f64, @floatCast(master_surplus_ratio)));
                master_surplus_height -= h;
                master_surplus_ratio = @floatCast(@as(f64, master_surplus_ratio) - cl.master_inner_per);
                cl.master_mfact_per = mfact;
            } else {
                const denom = m.w.height - my - cur_gappov - cur_gappiv * ie * (r - 1);
                h = @divTrunc(denom, r);
                // C divides ints here before assigning to the double field.
                cl.master_inner_per = @floatFromInt(@divTrunc(h, denom));
                cl.master_mfact_per = mfact;
            }
            client_tile_resize(cl, .{
                .x = if (right) m.w.x + m.w.width - mw - cur_gappoh + cur_gappih * ie else m.w.x + cur_gappoh,
                .y = m.w.y + my,
                .width = mw - cur_gappih * ie,
                .height = h,
            }, 0, ctx);
            my += h + cur_gappiv * ie;
        } else {
            const r: i32 = n - i;
            var h: i32 = undefined;
            if (cl.stack_inner_per > 0.0) {
                h = truncD(@as(f64, @floatFromInt(slave_surplus_height)) *
                    cl.stack_inner_per /
                    @as(f64, @floatCast(slave_surplus_ratio)));
                slave_surplus_height -= h;
                slave_surplus_ratio = @floatCast(@as(f64, slave_surplus_ratio) - cl.stack_inner_per);
                cl.master_mfact_per = mfact;
            } else {
                const denom = m.w.height - ty - cur_gappov - cur_gappiv * ie * (r - 1);
                h = @divTrunc(denom, r);
                cl.stack_inner_per = @floatFromInt(@divTrunc(h, denom));
                cl.master_mfact_per = mfact;
            }
            client_tile_resize(cl, .{
                .x = if (right) m.w.x + cur_gappoh else m.w.x + mw + cur_gappoh,
                .y = m.w.y + ty,
                .width = m.w.width - mw - 2 * cur_gappoh,
                .height = h,
            }, 0, ctx);
            ty += h + cur_gappiv * ie;
        }
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// deck
// ---------------------------------------------------------------------------

fn deckCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const curtag = curtagIndex(m);
    const nmasters: i32 = m.pertag.*.nmasters[curtag];

    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gappih = 0;
        cur_gappoh = 0;
        cur_gappov = 0;
    }

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    if (n == 0)
        return;

    const fc = firstVisibleFakeTiled(m) orelse return;
    const mfact: f64 = if (fc.master_mfact_per > 0.0)
        fc.master_mfact_per
    else
        @as(f64, m.pertag.*.mfacts[curtag]);

    var mw: i32 = undefined;
    if (n > nmasters) {
        mw = if (nmasters != 0)
            truncD(@round(@as(f64, @floatFromInt(m.w.width - 2 * cur_gappoh)) * mfact))
        else
            0;
    } else {
        mw = m.w.width - 2 * cur_gappoh;
    }

    var i: i32 = 0;
    var my: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (i < nmasters) {
            cl.master_mfact_per = mfact;
            const h = @divTrunc(m.w.height - 2 * cur_gappov - my, @min(n, nmasters) - i);
            client_tile_resize(cl, .{
                .x = m.w.x + cur_gappoh,
                .y = m.w.y + cur_gappov + my,
                .width = mw,
                .height = h,
            }, 0, ctx);
            my += h;
        } else {
            cl.master_mfact_per = mfact;
            client_tile_resize(cl, .{
                .x = m.w.x + mw + cur_gappoh + cur_gappih,
                .y = m.w.y + cur_gappov,
                .width = m.w.width - mw - 2 * cur_gappoh - cur_gappih,
                .height = m.w.height - 2 * cur_gappov,
            }, 0, ctx);
            if (ctx == null)
                client_update_visibility(cl);
        }
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// monocle
// ---------------------------------------------------------------------------

fn monocleCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;

    if (c.config.monocle_no_gap != 0) {
        cur_gappoh = 0;
        cur_gappov = 0;
    }

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gappoh = 0;
        cur_gappov = 0;
    }

    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;
        client_tile_resize(cl, .{
            .x = m.w.x + cur_gappoh,
            .y = m.w.y + cur_gappov,
            .width = m.w.width - 2 * cur_gappoh,
            .height = m.w.height - 2 * cur_gappov,
        }, 0, ctx);
        if (ctx == null)
            client_update_visibility(cl);
    }
}

// center/grid/fair follow in part 2.

// ---------------------------------------------------------------------------
// center tile
// ---------------------------------------------------------------------------

fn centerTileCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const ie: i32 = c.server.enable_gaps;
    const curtag = curtagIndex(m);
    const nmasters = m.pertag.*.nmasters[curtag];

    const n: i32 = @intCast(m.visible_fake_tiling_clients);
    var master_num = nmasters;
    master_num = if (n > master_num) master_num else n;
    const stack_num = n - master_num;

    if (n == 0)
        return;

    const fc = firstVisibleFakeTiled(m) orelse return;
    const mfact: f64 = if (fc.master_mfact_per > 0.0)
        fc.master_mfact_per
    else
        @as(f64, m.pertag.*.mfacts[curtag]);

    var cur_gappiv: i32 = if (c.server.enable_gaps != 0) m.gappiv else 0;
    var cur_gappih: i32 = if (c.server.enable_gaps != 0) m.gappih else 0;
    var cur_gappov: i32 = if (c.server.enable_gaps != 0) m.gappov else 0;
    var cur_gappoh: i32 = if (c.server.enable_gaps != 0) m.gappoh else 0;

    if (c.config.smartgaps != 0 and m.visible_fake_tiling_clients == 1) {
        cur_gappiv = 0;
        cur_gappih = 0;
        cur_gappov = 0;
        cur_gappoh = 0;
    }

    var mw: i32 = m.w.width;
    var mx: i32 = cur_gappoh;
    var my: i32 = cur_gappov;
    var tw: i32 = mw;

    const should_overspread = c.config.center_master_overspread != 0 and n <= nmasters;

    var left_num: i32 = 0;
    var right_num: i32 = 0;
    var j: i32 = 0;
    while (j < stack_num) : (j += 1) {
        if ((@rem(j, 2) != 0) != (@rem(n, 2) == 0))
            right_num += 1
        else
            left_num += 1;
    }

    var master_surplus_height: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (if (master_num > 0) master_num - 1 else 0);
    var master_surplus_ratio: f32 = 1.0;
    const init_master_surplus = master_surplus_height;

    var slave_left_surplus_height: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (if (left_num > 0) left_num - 1 else 0);
    var slave_left_surplus_ratio: f32 = 1.0;
    const init_slave_left_surplus = slave_left_surplus_height;

    var slave_right_surplus_height: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (if (right_num > 0) right_num - 1 else 0);
    var slave_right_surplus_ratio: f32 = 1.0;
    const init_slave_right_surplus = slave_right_surplus_height;

    const init_single_stack_surplus: i32 =
        m.w.height - 2 * cur_gappov - cur_gappiv * ie * (if (stack_num > 0) stack_num - 1 else 0);

    if (n > nmasters or !should_overspread) {
        mw = if (nmasters != 0)
            truncD(@as(f64, @floatFromInt(m.w.width - 2 * cur_gappoh - cur_gappih * ie)) * mfact)
        else
            0;

        if (n - nmasters > 1) {
            tw = @divTrunc(m.w.width - mw, 2) - cur_gappoh - cur_gappih * ie;
            mx = cur_gappoh + tw + cur_gappih * ie;
        } else if (n - nmasters == 1) {
            if (c.config.center_when_single_stack != 0) {
                tw = @divTrunc(m.w.width - mw, 2) - cur_gappoh - cur_gappih * ie;
                mx = cur_gappoh + tw + cur_gappih * ie;
            } else {
                tw = m.w.width - mw - 2 * cur_gappoh - cur_gappih * ie;
                mx = cur_gappoh;
            }
        } else {
            tw = @divTrunc(m.w.width - mw, 2) - cur_gappoh - cur_gappih * ie;
            mx = cur_gappoh + tw + cur_gappih * ie;
        }
    } else {
        mw = m.w.width - 2 * cur_gappoh;
        mx = cur_gappoh;
        tw = 0;
    }

    var oty: i32 = cur_gappov;
    var ety: i32 = cur_gappov;

    var i: i32 = 0;
    var pos = c.server.clients.next;
    const head = listHead(&c.server.clients);
    while (pos != head) : (pos = pos.*.next) {
        const cl = containerOf(Client, "link", pos);
        if (!VISIBLEON(cl, m) or !ISFAKETILED(cl))
            continue;

        if (i < nmasters) {
            const r: i32 = @min(n, nmasters) - i;
            var h: i32 = undefined;
            if (cl.master_inner_per > 0.0) {
                h = truncD(@as(f64, @floatFromInt(master_surplus_height)) *
                    cl.master_inner_per /
                    @as(f64, @floatCast(master_surplus_ratio)));
                if (r == 1)
                    h = m.w.height - my - cur_gappov;
                master_surplus_height -= h;
                master_surplus_ratio = @floatCast(@as(f64, master_surplus_ratio) - cl.master_inner_per);
                cl.master_mfact_per = mfact;
            } else {
                h = @divTrunc(m.w.height - my - cur_gappov - cur_gappiv * ie * (r - 1), r);
                if (r == 1)
                    h = m.w.height - my - cur_gappov;
                cl.master_inner_per = if (init_master_surplus > 0)
                    @as(f64, @floatCast(@as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(init_master_surplus))))
                else
                    0;
                cl.master_mfact_per = mfact;
            }

            client_tile_resize(cl, .{
                .x = m.w.x + mx,
                .y = m.w.y + my,
                .width = mw,
                .height = h,
            }, 0, ctx);
            my += h + cur_gappiv * ie;
        } else {
            const stack_index = i - nmasters;

            if (n - nmasters == 1) {
                const r: i32 = n - i;
                var h: i32 = undefined;
                if (cl.stack_inner_per > 0.0) {
                    h = truncD(@as(f64, @floatFromInt(init_single_stack_surplus)) * cl.stack_inner_per);
                    if (r == 1)
                        h = m.w.height - ety - cur_gappov;
                    cl.master_mfact_per = mfact;
                } else {
                    h = @divTrunc(m.w.height - ety - cur_gappov - cur_gappiv * ie * (r - 1), r);
                    if (r == 1)
                        h = m.w.height - ety - cur_gappov;
                    cl.stack_inner_per = if (init_single_stack_surplus > 0)
                        @as(f64, @floatCast(@as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(init_single_stack_surplus))))
                    else
                        0;
                    cl.master_mfact_per = mfact;
                }

                const stack_x = m.w.x + mx + mw + cur_gappih * ie;
                client_tile_resize(cl, .{
                    .x = stack_x,
                    .y = m.w.y + ety,
                    .width = tw,
                    .height = h,
                }, 0, ctx);
                ety += h + cur_gappiv * ie;
            } else {
                const r: i32 = @divTrunc(n - i + 1, 2);

                if ((@rem(stack_index, 2) != 0) != (@rem(n, 2) == 0)) {
                    // right stack
                    var h: i32 = undefined;
                    if (cl.stack_inner_per > 0.0) {
                        h = truncD(@as(f64, @floatFromInt(slave_right_surplus_height)) *
                            cl.stack_inner_per /
                            @as(f64, @floatCast(slave_right_surplus_ratio)));
                        if (r == 1)
                            h = m.w.height - ety - cur_gappov;
                        slave_right_surplus_height -= h;
                        slave_right_surplus_ratio = @floatCast(@as(f64, slave_right_surplus_ratio) - cl.stack_inner_per);
                        cl.master_mfact_per = mfact;
                    } else {
                        h = @divTrunc(m.w.height - ety - cur_gappov - cur_gappiv * ie * (r - 1), r);
                        if (r == 1)
                            h = m.w.height - ety - cur_gappov;
                        cl.stack_inner_per = if (init_slave_right_surplus > 0)
                            @as(f64, @floatCast(@as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(init_slave_right_surplus))))
                        else
                            0;
                        cl.master_mfact_per = mfact;
                    }

                    const stack_x = m.w.x + mx + mw + cur_gappih * ie;
                    client_tile_resize(cl, .{
                        .x = stack_x,
                        .y = m.w.y + ety,
                        .width = tw,
                        .height = h,
                    }, 0, ctx);
                    ety += h + cur_gappiv * ie;
                } else {
                    // left stack
                    var h: i32 = undefined;
                    if (cl.stack_inner_per > 0.0) {
                        h = truncD(@as(f64, @floatFromInt(slave_left_surplus_height)) *
                            cl.stack_inner_per /
                            @as(f64, @floatCast(slave_left_surplus_ratio)));
                        if (r == 1)
                            h = m.w.height - oty - cur_gappov;
                        slave_left_surplus_height -= h;
                        slave_left_surplus_ratio = @floatCast(@as(f64, slave_left_surplus_ratio) - cl.stack_inner_per);
                        cl.master_mfact_per = mfact;
                    } else {
                        h = @divTrunc(m.w.height - oty - cur_gappov - cur_gappiv * ie * (r - 1), r);
                        if (r == 1)
                            h = m.w.height - oty - cur_gappov;
                        cl.stack_inner_per = if (init_slave_left_surplus > 0)
                            @as(f64, @floatCast(@as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(init_slave_left_surplus))))
                        else
                            0;
                        cl.master_mfact_per = mfact;
                    }

                    const stack_x = m.w.x + cur_gappoh;
                    client_tile_resize(cl, .{
                        .x = stack_x,
                        .y = m.w.y + oty,
                        .width = tw,
                        .height = h,
                    }, 0, ctx);
                    oty += h + cur_gappiv * ie;
                }
            }
        }
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// grid
// ---------------------------------------------------------------------------

fn gridCore(m: *Monitor, ctx: ?*const LayoutContext) void {
    const target_gappo: i32 = if (c.server.enable_gaps != 0) @intCast(c.config.gappoh) else 0;
    const target_gappi: i32 = if (c.server.enable_gaps != 0) @intCast(c.config.gappih) else 0;
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
                ((m.isoverview != 0 and client_is_x11_popup(cl) == 0) or ISFAKETILED(cl)))
            {
                const cw = truncF(@as(f32, @floatFromInt(m.w.width - 2 * target_gappo)) * single_width_ratio);
                const ch = truncF(@as(f32, @floatFromInt(m.w.height - 2 * target_gappo)) * single_height_ratio);
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
        var col_pers = [2]f32{ 1.0, 1.0 };
        var i: i32 = 0;
        var pos = c.server.clients.next;
        const head = listHead(&c.server.clients);
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (!sameMonitor(cl, m))
                continue;
            if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
                ((m.isoverview != 0 and client_is_x11_popup(cl) == 0) or ISFAKETILED(cl)))
            {
                if (i < 2)
                    col_pers[@intCast(i)] = if (cl.grid_col_per > 0.0) cl.grid_col_per else 1.0;
                i += 1;
            }
        }

        const sum_col: f32 = col_pers[0] + col_pers[1];
        const avail_w: f32 = @floatFromInt(m.w.width - 2 * target_gappo - target_gappi);
        // 0.65 is a double literal in C.
        const ch = truncD(@as(f64, @floatFromInt(m.w.height - 2 * target_gappo)) * 0.65);

        i = 0;
        pos = c.server.clients.next;
        while (pos != head) : (pos = pos.*.next) {
            const cl = containerOf(Client, "link", pos);
            if (!sameMonitor(cl, m))
                continue;
            if (VISIBLEON(cl, m) and cl.isunglobal == 0 and
                ((m.isoverview != 0 and client_is_x11_popup(cl) == 0) or ISFAKETILED(cl)))
            {
                cl.grid_col_idx = i;
                cl.grid_row_idx = 0;
                cl.grid_col_per = col_pers[@intCast(i)];
                cl.grid_row_per = 1.0;

                const cw = truncF(avail_w * (col_pers[@intCast(i)] / sum_col));

                if (i == 0) {
                    target_geom.x = m.w.x + target_gappo;
                } else if (i == 1) {
                    const cw0: f32 = avail_w * (col_pers[0] / sum_col);
                    target_geom.x = truncF(@as(f32, @floatFromInt(m.w.x + target_gappo)) + cw0 + @as(f32, @floatFromInt(target_gappi)));
                }
                target_geom.y = m.w.y + @divTrunc(m.w.height - ch, 2) + target_gappo;
                target_geom.width = cw;
                target_geom.height = ch;
                client_tile_resize(cl, target_geom, 0, ctx);
                i += 1;
            }
        }
        return;
    }

    var cols: i32 = 0;
    while (cols <= @divTrunc(n, 2)) : (cols += 1) {
        if (cols * cols >= n)
            break;
    }
    const rows: i32 = if (cols != 0 and (cols - 1) * cols >= n) cols - 1 else cols;
    const overcols: i32 = @rem(n, cols);

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
            ((m.isoverview != 0 and client_is_x11_popup(cl) == 0) or ISFAKETILED(cl)))
        {
            const c_idx = @rem(i, cols);
            const r_idx = @divTrunc(i, cols);
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
            ((m.isoverview != 0 and client_is_x11_popup(cl) == 0) or ISFAKETILED(cl))))
            continue;

        const c_idx = @rem(i, cols);
        const r_idx = @divTrunc(i, cols);

        cl.grid_col_per = col_pers[@intCast(c_idx)];
        cl.grid_row_per = row_pers[@intCast(r_idx)];
        cl.grid_col_idx = c_idx;
        cl.grid_row_idx = r_idx;

        var fl_cx: f32 = @floatFromInt(m.w.x + target_gappo);
        var fl_cw: f32 = 0.0;

        if (overcols != 0 and i >= n - overcols) {
            var over_w: f32 = 0.0;
            var k: i32 = 0;
            while (k < overcols) : (k += 1)
                over_w += avail_w * (col_pers[@intCast(k)] / sum_col);
            over_w += @floatFromInt((overcols - 1) * target_gappi);
            const dx: f32 = (@as(f32, @floatFromInt(m.w.width)) - over_w) / 2.0 -
                @as(f32, @floatFromInt(target_gappo));

            fl_cx += dx;
            k = 0;
            while (k < c_idx) : (k += 1)
                fl_cx += avail_w * (col_pers[@intCast(k)] / sum_col) + @as(f32, @floatFromInt(target_gappi));
            fl_cw = avail_w * (col_pers[@intCast(c_idx)] / sum_col);
        } else {
            var k: i32 = 0;
            while (k < c_idx) : (k += 1)
                fl_cx += avail_w * (col_pers[@intCast(k)] / sum_col) + @as(f32, @floatFromInt(target_gappi));
            fl_cw = if (c_idx == cols - 1)
                @as(f32, @floatFromInt(m.w.x + m.w.width - target_gappo)) - fl_cx
            else
                avail_w * (col_pers[@intCast(c_idx)] / sum_col);
        }

        var fl_cy: f32 = @floatFromInt(m.w.y + target_gappo);
        var k: i32 = 0;
        while (k < r_idx) : (k += 1)
            fl_cy += avail_h * (row_pers[@intCast(k)] / sum_row) + @as(f32, @floatFromInt(target_gappi));
        const fl_ch: f32 = if (r_idx == rows - 1)
            @as(f32, @floatFromInt(m.w.y + m.w.height - target_gappo)) - fl_cy
        else
            avail_h * (row_pers[@intCast(r_idx)] / sum_row);

        target_geom.x = truncF(fl_cx);
        target_geom.y = truncF(fl_cy);
        target_geom.width = truncF(fl_cw);
        target_geom.height = truncF(fl_ch);
        client_tile_resize(cl, target_geom, 0, ctx);
        i += 1;
    }
}

// ---------------------------------------------------------------------------
// fair
// ---------------------------------------------------------------------------

fn fairCore(m: *Monitor, ctx: ?*const LayoutContext) void {
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

    var cols: i32 = 0;
    while (cols <= n) : (cols += 1) {
        if (cols * cols >= n)
            break;
    }

    const base_rows = @divTrunc(n, cols);
    const remainder = @rem(n, cols);
    const first_group_cols = cols - remainder;
    const first_group_count = first_group_cols * base_rows;
    const max_rows = base_rows + (if (remainder > 0) @as(i32, 1) else 0);

    const arr_raw = calloc(@intCast(n), @sizeOf(*Client)) orelse return;
    const arr: [*]*Client = @ptrCast(@alignCast(arr_raw));
    const col_pers = allocFloats(@intCast(cols)) orelse {
        free(arr_raw);
        return;
    };
    const row_pers = allocFloats(@intCast(max_rows)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        return;
    };
    const col_x = allocFloats(@intCast(cols)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        return;
    };
    const col_w = allocFloats(@intCast(cols)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        freeFloats(col_x);
        return;
    };
    const row_y_base = allocFloats(@intCast(base_rows)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        freeFloats(col_x);
        freeFloats(col_w);
        return;
    };
    const row_h_base = allocFloats(@intCast(base_rows)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        freeFloats(col_x);
        freeFloats(col_w);
        freeFloats(row_y_base);
        return;
    };
    const row_y_max = allocFloats(@intCast(max_rows)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        freeFloats(col_x);
        freeFloats(col_w);
        freeFloats(row_y_base);
        freeFloats(row_h_base);
        return;
    };
    const row_h_max = allocFloats(@intCast(max_rows)) orelse {
        free(arr_raw);
        freeFloats(col_pers);
        freeFloats(row_pers);
        freeFloats(col_x);
        freeFloats(col_w);
        freeFloats(row_y_base);
        freeFloats(row_h_base);
        freeFloats(row_y_max);
        return;
    };
    defer free(arr_raw);
    defer freeFloats(col_pers);
    defer freeFloats(row_pers);
    defer freeFloats(col_x);
    defer freeFloats(col_w);
    defer freeFloats(row_y_base);
    defer freeFloats(row_h_base);
    defer freeFloats(row_y_max);
    defer freeFloats(row_h_max);

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
    while (i < cols) : (i += 1)
        col_pers[@intCast(i)] = 0.0;
    i = 0;
    while (i < max_rows) : (i += 1)
        row_pers[@intCast(i)] = 0.0;

    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        const col_idx: i32 = if (i < first_group_count)
            @divTrunc(i, base_rows)
        else
            first_group_cols + @divTrunc(i - first_group_count, max_rows);
        const row_idx: i32 = if (i < first_group_count)
            @rem(i, base_rows)
        else
            @rem(i - first_group_count, max_rows);

        if (cl.grid_col_idx == col_idx and cl.grid_col_per > 0.0)
            col_pers[@intCast(col_idx)] = cl.grid_col_per;
        if (cl.grid_row_idx == row_idx and cl.grid_row_per > 0.0)
            row_pers[@intCast(row_idx)] = cl.grid_row_per;
    }
    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        const col_idx: i32 = if (i < first_group_count)
            @divTrunc(i, base_rows)
        else
            first_group_cols + @divTrunc(i - first_group_count, max_rows);
        const row_idx: i32 = if (i < first_group_count)
            @rem(i, base_rows)
        else
            @rem(i - first_group_count, max_rows);

        if (col_pers[@intCast(col_idx)] == 0.0 and cl.grid_col_per > 0.0)
            col_pers[@intCast(col_idx)] = cl.grid_col_per;
        if (row_pers[@intCast(row_idx)] == 0.0 and cl.grid_row_per > 0.0)
            row_pers[@intCast(row_idx)] = cl.grid_row_per;
    }

    var sum_col: f32 = 0.0;
    i = 0;
    while (i < cols) : (i += 1) {
        if (col_pers[@intCast(i)] == 0.0)
            col_pers[@intCast(i)] = 1.0;
        sum_col += col_pers[@intCast(i)];
    }
    i = 0;
    while (i < max_rows) : (i += 1) {
        if (row_pers[@intCast(i)] == 0.0)
            row_pers[@intCast(i)] = 1.0;
    }

    const avail_w: f32 = @floatFromInt(m.w.width - 2 * cur_gappoh - (cols - 1) * cur_gappih);
    var next_x: f32 = @floatFromInt(m.w.x + cur_gappoh);
    i = 0;
    while (i < cols) : (i += 1) {
        col_x[@intCast(i)] = next_x;
        col_w[@intCast(i)] = if (i == cols - 1)
            @as(f32, @floatFromInt(m.w.x + m.w.width - cur_gappoh)) - next_x
        else
            avail_w * (col_pers[@intCast(i)] / sum_col);
        next_x += col_w[@intCast(i)] + @as(f32, @floatFromInt(cur_gappih));
    }

    var sum_row_base: f32 = 0.0;
    i = 0;
    while (i < base_rows) : (i += 1)
        sum_row_base += row_pers[@intCast(i)];
    const avail_h_base: f32 = @floatFromInt(m.w.height - 2 * cur_gappov - (base_rows - 1) * cur_gappiv);
    var next_y: f32 = @floatFromInt(m.w.y + cur_gappov);
    i = 0;
    while (i < base_rows) : (i += 1) {
        row_y_base[@intCast(i)] = next_y;
        row_h_base[@intCast(i)] = if (i == base_rows - 1)
            @as(f32, @floatFromInt(m.w.y + m.w.height - cur_gappov)) - next_y
        else
            avail_h_base * (row_pers[@intCast(i)] / sum_row_base);
        next_y += row_h_base[@intCast(i)] + @as(f32, @floatFromInt(cur_gappiv));
    }

    if (remainder > 0) {
        var sum_row_max: f32 = 0.0;
        i = 0;
        while (i < max_rows) : (i += 1)
            sum_row_max += row_pers[@intCast(i)];
        const avail_h_max: f32 = @floatFromInt(m.w.height - 2 * cur_gappov - (max_rows - 1) * cur_gappiv);
        next_y = @floatFromInt(m.w.y + cur_gappov);
        i = 0;
        while (i < max_rows) : (i += 1) {
            row_y_max[@intCast(i)] = next_y;
            row_h_max[@intCast(i)] = if (i == max_rows - 1)
                @as(f32, @floatFromInt(m.w.y + m.w.height - cur_gappov)) - next_y
            else
                avail_h_max * (row_pers[@intCast(i)] / sum_row_max);
            next_y += row_h_max[@intCast(i)] + @as(f32, @floatFromInt(cur_gappiv));
        }
    }

    i = 0;
    while (i < n) : (i += 1) {
        const cl = arr[@intCast(i)];
        var col_idx: i32 = undefined;
        var row_idx: i32 = undefined;
        var fl_cy: f32 = undefined;
        var fl_ch: f32 = undefined;

        if (i < first_group_count) {
            col_idx = @divTrunc(i, base_rows);
            row_idx = @rem(i, base_rows);
            fl_cy = row_y_base[@intCast(row_idx)];
            fl_ch = row_h_base[@intCast(row_idx)];
        } else {
            const offset = i - first_group_count;
            col_idx = first_group_cols + @divTrunc(offset, max_rows);
            row_idx = @rem(offset, max_rows);
            fl_cy = row_y_max[@intCast(row_idx)];
            fl_ch = row_h_max[@intCast(row_idx)];
        }

        cl.grid_col_per = col_pers[@intCast(col_idx)];
        cl.grid_row_per = row_pers[@intCast(row_idx)];
        cl.grid_col_idx = col_idx;
        cl.grid_row_idx = row_idx;

        const fl_cx = col_x[@intCast(col_idx)];
        const fl_cw = col_w[@intCast(col_idx)];

        client_tile_resize(cl, .{
            .x = truncF(fl_cx),
            .y = truncF(fl_cy),
            .width = truncF(fl_cw),
            .height = truncF(fl_ch),
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

fn tileCorePublic(m: *Monitor, ctx: ?*const LayoutContext) void {
    tileCore(m, ctx, false);
}

fn rightTileCorePublic(m: *Monitor, ctx: ?*const LayoutContext) void {
    tileCore(m, ctx, true);
}

export fn tile(m: *Monitor) callconv(.c) void {
    tileCore(m, null, false);
}

export fn tile_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(tileCorePublic, m, cl, out);
}

export fn right_tile(m: *Monitor) callconv(.c) void {
    tileCore(m, null, true);
}

export fn right_tile_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(rightTileCorePublic, m, cl, out);
}

export fn center_tile(m: *Monitor) callconv(.c) void {
    centerTileCore(m, null);
}

export fn center_tile_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(centerTileCore, m, cl, out);
}

export fn deck(m: *Monitor) callconv(.c) void {
    deckCore(m, null);
}

export fn deck_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(deckCore, m, cl, out);
}

export fn monocle(m: *Monitor) callconv(.c) void {
    monocleCore(m, null);
}

export fn monocle_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(monocleCore, m, cl, out);
}

export fn grid(m: *Monitor) callconv(.c) void {
    gridCore(m, null);
}

export fn grid_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(gridCore, m, cl, out);
}

export fn fair(m: *Monitor) callconv(.c) void {
    fairCore(m, null);
}

export fn fair_predict(m: *Monitor, cl: *Client, out: *Box) callconv(.c) bool {
    return layoutPredictBox(fairCore, m, cl, out);
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
    c.server.enable_gaps = 0;
    c.config = std.mem.zeroes(c.Config);
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

test "tile: masters in a left column, stack on the right" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    tile(&m);

    try expectCount(2);
    // newest client first: b is the master
    try expectBox(0, 0, 0, 600, 800);
    try expectBox(1, 600, 0, 400, 800);
    try testing.expect(stub_tile_clients[1] == &a);
}

test "tile: inner and outer gaps" {
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
    addClient(&clients[0], &m, 1);
    addClient(&clients[1], &m, 1);
    addClient(&clients[2], &m, 1);

    tile(&m);

    try expectCount(3);
    try expectBox(0, 10, 20, 597, 760);
    try expectBox(1, 613, 20, 377, 378);
    try expectBox(2, 613, 402, 377, 378);
}

test "tile: inner ratios use C integer division" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.mfacts[0] = 0.5;
    m.visible_fake_tiling_clients = 3;

    var a: Client = undefined;
    var b: Client = undefined;
    var cl_c: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    addClient(&cl_c, &m, 1);

    tile(&m);

    // list runs c (master), b (first stack), a (second stack)
    try testing.expectEqual(@as(f64, 0.0), b.stack_inner_per);
    try testing.expectEqual(@as(f64, 1.0), a.stack_inner_per);
    try testing.expectEqual(@as(f64, 1.0), cl_c.master_inner_per);
}

test "right_tile: masters on the right, stack on the left" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    right_tile(&m);

    try expectCount(2);
    try expectBox(0, 400, 0, 600, 800);
    try expectBox(1, 0, 0, 400, 800);
}

test "deck: master rows on the left, stack column on the right" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.nmasters[0] = 2;
    p.mfacts[0] = 0.5;
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 1);
    addClient(&clients[1], &m, 1);
    addClient(&clients[2], &m, 1);

    deck(&m);

    try expectCount(3);
    try expectBox(0, 0, 0, 500, 400);
    try expectBox(1, 0, 400, 500, 400);
    try expectBox(2, 500, 0, 500, 800);
    try testing.expectEqual(@as(c_int, 1), stub_visibility_calls);
}

test "monocle: gaps, no-gap and smartgaps" {
    resetWorld();
    c.server.enable_gaps = 1;
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.gappoh = 10;
    m.gappov = 20;
    m.visible_fake_tiling_clients = 2;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    monocle(&m);
    try expectCount(2);
    try expectBox(0, 10, 20, 980, 760);
    try expectBox(1, 10, 20, 980, 760);
    try testing.expectEqual(@as(c_int, 2), stub_visibility_calls);

    stub_tile_calls = 0;
    c.config.monocle_no_gap = 1;
    monocle(&m);
    try expectBox(0, 0, 0, 1000, 800);

    stub_tile_calls = 0;
    c.config.monocle_no_gap = 0;
    c.config.smartgaps = 1;
    m.visible_fake_tiling_clients = 1;
    monocle(&m);
    try expectBox(0, 0, 0, 1000, 800);
}

test "center_tile: master centered with alternating side stacks" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.mfacts[0] = 0.5;
    m.visible_fake_tiling_clients = 3;

    var a: Client = undefined;
    var b: Client = undefined;
    var cl_c: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    addClient(&cl_c, &m, 1);

    center_tile(&m);

    try expectCount(3);
    // c is the master, b the left stack, a the right stack
    try expectBox(0, 250, 0, 500, 800);
    try expectBox(1, 0, 0, 250, 800);
    try expectBox(2, 750, 0, 250, 800);
}

test "center_tile: single stack placement and overspread master" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    p.mfacts[0] = 0.5;
    m.visible_fake_tiling_clients = 2;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    center_tile(&m);
    try expectCount(2);
    try expectBox(0, 0, 0, 500, 800);
    try expectBox(1, 500, 0, 500, 800);

    stub_tile_calls = 0;
    c.config.center_when_single_stack = 1;
    center_tile(&m);
    try expectBox(0, 250, 0, 500, 800);
    try expectBox(1, 750, 0, 250, 800);

    // overspread: a lone client with two configured masters fills the width
    resetWorld();
    baseMonitor(&m, &p);
    p.nmasters[0] = 2;
    m.visible_fake_tiling_clients = 1;
    addClient(&a, &m, 1);
    c.config.center_master_overspread = 1;
    center_tile(&m);
    try expectBox(0, 0, 0, 1000, 800);
}

test "grid: single, double and 2x2 layouts" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 1;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    grid(&m);
    try expectCount(1);
    try expectBox(0, 50, 40, 900, 720);

    resetWorld();
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);
    grid(&m);
    try expectCount(2);
    try expectBox(0, 0, 140, 500, 520);
    try expectBox(1, 500, 140, 500, 520);

    resetWorld();
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 4;
    var clients: [4]Client = undefined;
    for (&clients) |*cl|
        addClient(cl, &m, 1);
    grid(&m);
    try expectCount(4);
    try expectBox(0, 0, 0, 500, 400);
    try expectBox(1, 500, 0, 500, 400);
    try expectBox(2, 0, 400, 500, 400);
    try expectBox(3, 500, 400, 500, 400);
}

test "grid: overflow column is centered" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    for (&clients) |*cl|
        addClient(cl, &m, 1);

    grid(&m);

    try expectCount(3);
    try expectBox(0, 0, 0, 500, 400);
    try expectBox(1, 500, 0, 500, 400);
    try expectBox(2, 250, 400, 500, 400);
}

test "fair: short first column then full-height remainder columns" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 3;

    var clients: [3]Client = undefined;
    addClient(&clients[0], &m, 1);
    addClient(&clients[1], &m, 1);
    addClient(&clients[2], &m, 1);

    fair(&m);

    try expectCount(3);
    try expectBox(0, 0, 0, 500, 800);
    try expectBox(1, 500, 0, 500, 400);
    try expectBox(2, 500, 400, 500, 400);
}

test "predict variants answer the probe and do not resize others" {
    resetWorld();
    var p: c.Pertag = undefined;
    var m: Monitor = undefined;
    baseMonitor(&m, &p);
    m.visible_fake_tiling_clients = 2;

    var a: Client = undefined;
    var b: Client = undefined;
    addClient(&a, &m, 1);
    addClient(&b, &m, 1);

    var out: Box = std.mem.zeroes(Box);
    // a is the stack client
    try testing.expect(tile_predict(&m, &a, &out));
    try testing.expectEqual(@as(i32, 600), out.x);
    try testing.expectEqual(@as(i32, 400), out.width);

    try testing.expect(right_tile_predict(&m, &a, &out));
    try testing.expectEqual(@as(i32, 0), out.x);
    try testing.expectEqual(@as(i32, 400), out.width);

    try testing.expect(grid_predict(&m, &a, &out));
    try testing.expectEqual(@as(i32, 500), out.x);
    try testing.expectEqual(@as(i32, 140), out.y);
    try expectCount(0);
}
