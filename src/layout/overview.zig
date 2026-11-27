//! Port of layout/overview.c (Phase 5, layout slice, slice 86).

const std = @import("std");
const c = @import("cc");

const Client = c.Client;
const Monitor = c.Monitor;

extern fn overview_update_jump_label(cl: [*c]Client) callconv(.c) void;

fn allocArray(comptime T: type, n: usize) ?[*]T {
    if (n == 0) return null;
    const raw = c.calloc(n, @sizeOf(T)) orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn clientFromLink(link: [*c]c.struct_wl_list) *Client {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(Client, "link"));
}

fn visibleOn(cl: *Client, m: *Monitor) bool {
    return cl.mon == m and cl.isminimized == 0 and
        ((cl.tags & m.tagset[@intCast(m.seltags)]) != 0 or
            cl.isglobal != 0 or cl.isunglobal != 0);
}

fn isSelectable(cl: *Client) bool {
    return cl.isunglobal == 0 and c.client_is_x11_popup(cl) == 0;
}

export fn compare_layout_items(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
    const area_a = @as(*const c.OvLayoutItem, @ptrCast(@alignCast(a))).area;
    const area_b = @as(*const c.OvLayoutItem, @ptrCast(@alignCast(b))).area;
    if (area_a < area_b) return 1;
    if (area_a > area_b) return -1;
    return 0;
}

export fn begin_jump_mode(m: [*c]Monitor) callconv(.c) void {
    m.*.is_jump_mode = 1;
}

export fn try_place(
    placed: [*c]c.OvPlacedRect,
    placed_cnt: c_int,
    w: f32,
    h: f32,
    gap: f32,
    avail_w: f32,
    avail_h: f32,
    out: [*c]c.OvPlacedRect,
    cands: [*c]c.OvPoint,
    feas: [*c]c.OvPoint,
) callconv(.c) bool {
    var cand_cnt: c_int = 0;
    cands[@intCast(cand_cnt)] = .{ .x = 0.0, .y = 0.0 };
    cand_cnt += 1;

    var i: c_int = 0;
    while (i < placed_cnt) : (i += 1) {
        const p = placed[@intCast(i)];
        cands[@intCast(cand_cnt)] = .{ .x = p.x + p.w + gap, .y = p.y };
        cand_cnt += 1;
        cands[@intCast(cand_cnt)] = .{ .x = p.x, .y = p.y + p.h + gap };
        cand_cnt += 1;
        cands[@intCast(cand_cnt)] = .{ .x = p.x + p.w + gap, .y = p.y + p.h + gap };
        cand_cnt += 1;
    }

    var unique_cnt: c_int = 0;
    i = 0;
    while (i < cand_cnt) : (i += 1) {
        var dup = false;
        var j: c_int = 0;
        while (j < unique_cnt) : (j += 1) {
            if (@abs(cands[@intCast(i)].x - cands[@intCast(j)].x) < 0.5 and
                @abs(cands[@intCast(i)].y - cands[@intCast(j)].y) < 0.5)
            {
                dup = true;
                break;
            }
        }
        if (!dup) {
            cands[@intCast(unique_cnt)] = cands[@intCast(i)];
            unique_cnt += 1;
        }
    }
    cand_cnt = unique_cnt;

    var feas_cnt: c_int = 0;
    i = 0;
    while (i < cand_cnt) : (i += 1) {
        const cx = cands[@intCast(i)].x;
        const cy = cands[@intCast(i)].y;
        if (cx < 0 or cy < 0 or cx + w > avail_w or cy + h > avail_h)
            continue;

        var overlap = false;
        var j: c_int = 0;
        while (j < placed_cnt) : (j += 1) {
            const p = placed[@intCast(j)];
            if (!(cx + w + gap <= p.x or cx >= p.x + p.w + gap or
                cy + h + gap <= p.y or cy >= p.y + p.h + gap))
            {
                overlap = true;
                break;
            }
        }
        if (!overlap) {
            feas[@intCast(feas_cnt)] = .{ .x = cx, .y = cy };
            feas_cnt += 1;
        }
    }

    if (feas_cnt == 0)
        return false;

    var best: c_int = 0;
    i = 1;
    while (i < feas_cnt) : (i += 1) {
        if (feas[@intCast(i)].y < feas[@intCast(best)].y or
            (@abs(feas[@intCast(i)].y - feas[@intCast(best)].y) < 0.5 and
                feas[@intCast(i)].x < feas[@intCast(best)].x))
        {
            best = i;
        }
    }

    out.*.x = feas[@intCast(best)].x;
    out.*.y = feas[@intCast(best)].y;
    out.*.w = w;
    out.*.h = h;
    return true;
}

// Centers each packed row on the widest row's axis without creating overlaps.
fn centerPlacedRows(placed: [*c]c.OvPlacedRect, n: c_int, gap: f32) void {
    if (n <= 1)
        return;

    const usize_n: usize = @intCast(n);
    const row_of = allocArray(c_int, usize_n) orelse return;
    defer c.free(row_of);
    const row_y = allocArray(f32, usize_n) orelse return;
    defer c.free(row_y);
    const row_order = allocArray(c_int, usize_n) orelse return;
    defer c.free(row_order);

    var row_cnt: c_int = 0;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        var r: c_int = -1;
        var j: c_int = 0;
        while (j < row_cnt) : (j += 1) {
            if (@abs(placed[@intCast(i)].y - row_y[@intCast(j)]) < 0.5) {
                r = j;
                break;
            }
        }
        if (r < 0) {
            r = row_cnt;
            row_cnt += 1;
            row_y[@intCast(r)] = placed[@intCast(i)].y;
        }
        row_of[@intCast(i)] = r;
    }

    i = 0;
    while (i < row_cnt) : (i += 1) row_order[@intCast(i)] = i;
    i = 1;
    while (i < row_cnt) : (i += 1) {
        const key = row_order[@intCast(i)];
        var j = i - 1;
        while (j >= 0 and row_y[@intCast(row_order[@intCast(j)])] > row_y[@intCast(key)]) : (j -= 1) {
            row_order[@intCast(j + 1)] = row_order[@intCast(j)];
        }
        row_order[@intCast(j + 1)] = key;
    }

    var grid_w: f32 = 0.0;
    var r: c_int = 0;
    while (r < row_cnt) : (r += 1) {
        var left: f32 = 1e30;
        var right: f32 = -1e30;
        i = 0;
        while (i < n) : (i += 1) {
            if (row_of[@intCast(i)] != r)
                continue;
            if (placed[@intCast(i)].x < left)
                left = placed[@intCast(i)].x;
            const e = placed[@intCast(i)].x + placed[@intCast(i)].w;
            if (e > right)
                right = e;
        }
        const span = right - left;
        if (span > grid_w)
            grid_w = span;
    }

    var oi: c_int = 0;
    while (oi < row_cnt) : (oi += 1) {
        r = row_order[@intCast(oi)];
        var left: f32 = 1e30;
        var right: f32 = -1e30;
        i = 0;
        while (i < n) : (i += 1) {
            if (row_of[@intCast(i)] != r)
                continue;
            if (placed[@intCast(i)].x < left)
                left = placed[@intCast(i)].x;
            const e = placed[@intCast(i)].x + placed[@intCast(i)].w;
            if (e > right)
                right = e;
        }
        const span = right - left;
        var delta = grid_w * 0.5 - (left + span * 0.5);
        var lo: f32 = -1e30;
        var hi: f32 = 1e30;

        // Rows sharing a vertical band keep the gap and never swap sides.
        i = 0;
        while (i < n) : (i += 1) {
            if (row_of[@intCast(i)] != r)
                continue;
            const a = &placed[@intCast(i)];
            var j: c_int = 0;
            while (j < n) : (j += 1) {
                const b = &placed[@intCast(j)];
                if (row_of[@intCast(j)] == r)
                    continue;
                if (!(a.y + a.h + gap <= b.y or a.y >= b.y + b.h + gap)) {
                    if (b.x < a.x) {
                        const min_delta = b.x + b.w + gap - a.x;
                        if (min_delta > lo)
                            lo = min_delta;
                    } else {
                        const max_delta = b.x - gap - a.x - a.w;
                        if (max_delta < hi)
                            hi = max_delta;
                    }
                }
            }
        }

        if (-left > lo)
            lo = -left;
        if (grid_w - right < hi)
            hi = grid_w - right;

        if (lo <= hi) {
            if (delta < lo)
                delta = lo;
            if (delta > hi)
                delta = hi;
            if (@abs(delta) > 0.5) {
                i = 0;
                while (i < n) : (i += 1) {
                    if (row_of[@intCast(i)] == r)
                        placed[@intCast(i)].x += delta;
                }
            }
        }
    }
}

fn areaLessThan(_: void, a: c.OvLayoutItem, b: c.OvLayoutItem) bool {
    return a.area > b.area;
}

export fn overview_scale(m: [*c]Monitor) callconv(.c) void {
    const target_gappo: i32 = c.config.overviewgappo;
    const target_gappi: i32 = c.config.overviewgappi;

    const orig_n: i32 = @intCast(m.*.visible_clients);
    if (orig_n == 0)
        return;

    const items = allocArray(c.OvLayoutItem, @intCast(orig_n)) orelse return;
    defer c.free(@ptrCast(items));

    var n: c_int = 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.mon != m)
            continue;
        if (visibleOn(cl, m) and isSelectable(cl)) {
            const idx: usize = @intCast(n);
            items[idx].c = cl;
            var w = cl.overview_backup_geom.width;
            var h = cl.overview_backup_geom.height;
            if (w <= 0 or h <= 0) {
                w = 100;
                h = 100;
            }
            items[idx].orig_w = @floatFromInt(w);
            items[idx].orig_h = @floatFromInt(h);
            items[idx].area = items[idx].orig_w * items[idx].orig_h;
            n += 1;
        }
    }

    if (n == 0)
        return;

    std.mem.sort(c.OvLayoutItem, items[0..@intCast(n)], {}, areaLessThan);

    const gapo_f: f32 = @floatFromInt(target_gappo);
    const max_avail_w = @max(1.0, @as(f32, @floatFromInt(m.*.w.width)) - 2 * gapo_f);
    const max_avail_h = @max(1.0, @as(f32, @floatFromInt(m.*.w.height)) - 2 * gapo_f);

    const max_points: usize = @intCast(1 + 3 * n);
    const placed = allocArray(c.OvPlacedRect, @intCast(n)) orelse return;
    defer c.free(placed);
    const cands = allocArray(c.OvPoint, max_points) orelse return;
    defer c.free(cands);
    const feas = allocArray(c.OvPoint, max_points) orelse return;
    defer c.free(feas);

    const gappi_f: f32 = @floatFromInt(target_gappi);
    var low: f32 = 0.0;
    var high: f32 = 1.0;
    var best_s: f32 = 0.0;
    var iter: c_int = 0;
    while (iter < 50) : (iter += 1) {
        const mid = (low + high) / 2.0;
        var ok = true;
        var placed_cnt: c_int = 0;
        var k: c_int = 0;
        while (k < n) : (k += 1) {
            const w = items[@intCast(k)].orig_w * mid;
            const h = items[@intCast(k)].orig_h * mid;
            var out: c.OvPlacedRect = undefined;
            if (!try_place(placed, placed_cnt, w, h, gappi_f, max_avail_w, max_avail_h, &out, cands, feas)) {
                ok = false;
                break;
            }
            placed[@intCast(placed_cnt)] = out;
            placed_cnt += 1;
        }
        if (ok) {
            best_s = mid;
            low = mid;
        } else {
            high = mid;
        }
    }

    if (best_s > 0.0) {
        var placed_cnt: c_int = 0;
        var k: c_int = 0;
        while (k < n) : (k += 1) {
            const w = items[@intCast(k)].orig_w * best_s;
            const h = items[@intCast(k)].orig_h * best_s;
            var out: c.OvPlacedRect = undefined;
            _ = try_place(placed, placed_cnt, w, h, gappi_f, max_avail_w, max_avail_h, &out, cands, feas);
            placed[@intCast(placed_cnt)] = out;
            placed_cnt += 1;
        }

        centerPlacedRows(placed, n, gappi_f);

        var box_w: f32 = 0;
        var box_h: f32 = 0;
        k = 0;
        while (k < n) : (k += 1) {
            const r = placed[@intCast(k)].x + placed[@intCast(k)].w;
            const b = placed[@intCast(k)].y + placed[@intCast(k)].h;
            if (r > box_w) box_w = r;
            if (b > box_h) box_h = b;
        }

        const dx = (max_avail_w - box_w) / 2.0;
        const dy = (max_avail_h - box_h) / 2.0;
        const base_x = @as(f32, @floatFromInt(m.*.w.x)) + gapo_f + dx;
        const base_y = @as(f32, @floatFromInt(m.*.w.y)) + gapo_f + dy;

        // Collects the target geometry of all clients and calls
        // client_tile_resize once at the end.
        const overview_boxes = allocArray(c.struct_wlr_box, @intCast(n)) orelse return;
        defer c.free(overview_boxes);
        k = 0;
        while (k < n) : (k += 1) {
            const w = items[@intCast(k)].orig_w * best_s;
            const h = items[@intCast(k)].orig_h * best_s;
            const ix: i32 = @intFromFloat(base_x + placed[@intCast(k)].x + 0.5);
            const iy: i32 = @intFromFloat(base_y + placed[@intCast(k)].y + 0.5);
            const iw: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(ix)) + w + 0.5)) - ix;
            const ih: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(iy)) + h + 0.5)) - iy;
            overview_boxes[@intCast(k)] = .{ .x = ix, .y = iy, .width = iw, .height = ih };
        }

        k = 0;
        while (k < n) : (k += 1) {
            c.client_tile_resize(items[@intCast(k)].c, overview_boxes[@intCast(k)], 0, null);
        }
    }
}

// Overview layout: focused window centered (about half screen width), remaining
// windows split on both sides.
export fn overview_layout_column(
    m: [*c]Monitor,
    items: [*c][*c]Client,
    cnt: c_int,
    x: f32,
    top: f32,
    col_w: f32,
    col_h: f32,
    gap: f32,
) callconv(.c) void {
    _ = m;
    if (cnt <= 0)
        return;

    const usize_cnt: usize = @intCast(cnt);
    const ws = allocArray(f32, usize_cnt) orelse return;
    defer c.free(ws);
    const hs = allocArray(f32, usize_cnt) orelse return;
    defer c.free(hs);

    // Width fills the column width; height is proportional.
    var total_h: f32 = 0.0;
    var i: c_int = 0;
    while (i < cnt) : (i += 1) {
        var ow = items[@intCast(i)].*.overview_backup_geom.width;
        var oh = items[@intCast(i)].*.overview_backup_geom.height;
        if (ow <= 0 or oh <= 0) {
            ow = 100;
            oh = 100;
        }
        ws[@intCast(i)] = col_w;
        hs[@intCast(i)] = col_w * (@as(f32, @floatFromInt(oh)) / @as(f32, @floatFromInt(ow)));
        total_h += hs[@intCast(i)];
    }

    // Scales the whole item down when it is too tall.
    const gap_total = gap * @as(f32, @floatFromInt(cnt - 1));
    if (total_h + gap_total > col_h) {
        var s = (col_h - gap_total) / total_h;
        if (s < 0.0)
            s = 0.01;
        i = 0;
        while (i < cnt) : (i += 1) {
            ws[@intCast(i)] *= s;
            hs[@intCast(i)] *= s;
        }
        total_h *= s;
    }

    // Vertically centers when there is extra room.
    var y = top;
    if (total_h + gap_total < col_h)
        y = top + (col_h - (total_h + gap_total)) / 2.0;

    i = 0;
    while (i < cnt) : (i += 1) {
        const ix: i32 = @intFromFloat(x + (col_w - ws[@intCast(i)]) / 2.0 + 0.5);
        const iy: i32 = @intFromFloat(y + 0.5);
        c.client_tile_resize(items[@intCast(i)], .{
            .x = ix,
            .y = iy,
            .width = @intFromFloat(ws[@intCast(i)]),
            .height = @intFromFloat(hs[@intCast(i)]),
        }, 0, null);
        y += hs[@intCast(i)] + gap;
    }
}

export fn overview_scale_tab(m: [*c]Monitor) callconv(.c) void {
    const target_gappo: i32 = c.config.overviewgappo;
    const target_gappi: i32 = c.config.overviewgappi;

    if (m.*.visible_clients <= 0)
        return;

    const items = allocArray([*c]Client, @intCast(m.*.visible_clients)) orelse return;
    defer c.free(@ptrCast(items));

    var n: c_int = 0;
    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.mon != m)
            continue;
        if (visibleOn(cl, m) and isSelectable(cl)) {
            items[@intCast(n)] = cl;
            n += 1;
        }
    }

    if (n == 0)
        return;

    // Index of the focused window (or the first one if none).
    var focus_idx: c_int = 0;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        if (items[@intCast(i)] == m.*.sel) {
            focus_idx = i;
            break;
        }
    }

    // Uses the larger gap between columns and the smaller gap at the edges.
    var gap_mid: f32 = @floatFromInt(target_gappo);
    var gap_edge: f32 = @floatFromInt(target_gappi);
    if (gap_mid < gap_edge) {
        const tmp = gap_mid;
        gap_mid = gap_edge;
        gap_edge = tmp;
    }
    gap_mid *= 0.5; // Halves the gap between columns.

    const avail_w = @max(1.0, @as(f32, @floatFromInt(m.*.w.width)) - 2 * gap_edge);
    const avail_h = @max(1.0, @as(f32, @floatFromInt(m.*.w.height)) - 2 * gap_edge);

    // Center column ratio is configurable; both sides split the remaining space
    // evenly.
    const center_w = avail_w * c.config.overcircle_center_ratio;
    var side_w = (avail_w - center_w - 2.0 * gap_mid) * 0.5;
    if (side_w < 1.0)
        side_w = 1.0;

    const base_x = @as(f32, @floatFromInt(m.*.w.x)) + gap_edge;
    const base_y = @as(f32, @floatFromInt(m.*.w.y)) + gap_edge;

    const left_x = base_x;
    const center_x = base_x + side_w + gap_mid;
    const right_x = center_x + center_w + gap_mid;

    // The focused window is centered.
    const focus = items[@intCast(focus_idx)];
    {
        var ow = focus.*.overview_backup_geom.width;
        var oh = focus.*.overview_backup_geom.height;
        if (ow <= 0 or oh <= 0) {
            ow = 100;
            oh = 100;
        }
        var w = center_w;
        var h = w * (@as(f32, @floatFromInt(oh)) / @as(f32, @floatFromInt(ow)));
        if (h > avail_h) {
            const s = avail_h / h;
            w *= s;
            h *= s;
        }
        const ix: i32 = @intFromFloat(center_x + (center_w - w) / 2.0 + 0.5);
        const iy: i32 = @intFromFloat(base_y + (avail_h - h) / 2.0 + 0.5);
        c.client_tile_resize(focus, .{
            .x = ix,
            .y = iy,
            .width = @intFromFloat(w),
            .height = @intFromFloat(h),
        }, 0, null);
    }

    // The rest split into the left/right columns; on focus change they
    // circulate (rotate).
    const left = allocArray([*c]Client, @intCast(n)) orelse return;
    defer c.free(@ptrCast(left));
    const right = allocArray([*c]Client, @intCast(n)) orelse return;
    defer c.free(@ptrCast(right));
    const rest = n - 1;
    const right_cnt = @divTrunc(rest + 1, 2);
    const left_cnt = rest - right_cnt;

    var nr: c_int = 0;
    var k: c_int = 0;
    while (k < right_cnt) : (k += 1) {
        const idx: c_int = @mod(focus_idx + 1 + k, n);
        right[@intCast(nr)] = items[@intCast(idx)];
        nr += 1;
    }
    var nl: c_int = 0;
    k = 0;
    while (k < left_cnt) : (k += 1) {
        const idx: c_int = @mod(focus_idx - 1 - k + n, n);
        left[@intCast(nl)] = items[@intCast(idx)];
        nl += 1;
    }

    overview_layout_column(m, left, nl, left_x, base_y, side_w, avail_h, gap_edge);
    overview_layout_column(m, right, nr, right_x, base_y, side_w, avail_h, gap_edge);
}

export fn create_jump_hints(m: [*c]Monitor) callconv(.c) void {
    // Uses the static default sequence when jump_labels is not configured.
    const labels: [*c]const u8 = if (c.config.jump_labels != null) c.config.jump_labels else c.default_jump_labels;
    if (labels == null or labels[0] == 0)
        return;
    const labels_z: [*:0]const u8 = @ptrCast(labels);
    const jump_labels_len = std.mem.len(labels_z);
    var label_idx: usize = 0;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (visibleOn(cl, m) and isSelectable(cl)) {
            if (label_idx >= jump_labels_len)
                break;
            const ch = labels[label_idx];
            cl.jump_char = @intCast(ch);
            _ = c.find_keycodes_for_char(ch, &cl.jump_keycodes);

            const label_text = [2]u8{ ch, 0 };
            c.acwm_jump_label_node_update(cl.jump_label_node, &label_text, m.*.wlr_output.*.scale);
            overview_update_jump_label(cl);
            label_idx += 1;
        }
    }
}

export fn finish_jump_mode(m: [*c]Monitor) callconv(.c) void {
    if (m.*.is_jump_mode == 0)
        return;

    const head: [*c]c.struct_wl_list = @ptrCast(&c.server.clients);
    var pos = c.server.clients.next;
    while (pos != head) : (pos = pos.*.next) {
        const cl = clientFromLink(pos);
        if (cl.mon != m)
            continue;

        cl.jump_char = 0;
        cl.jump_keycodes = std.mem.zeroes(c.MultiKeycode);

        if (cl.jump_label_node != null and cl.jump_label_node.*.scene.*.node.enabled) {
            c.wlr_scene_node_set_enabled(&cl.jump_label_node.*.scene.*.node, false);
        }
    }
    m.*.is_jump_mode = 0;
}

export fn overview(m: [*c]Monitor) callconv(.c) void {
    if (m.*.ov_tab_layout != 0 and m.*.is_jump_mode == 0 and m.*.ov_normal_mode == 0) {
        overview_scale_tab(m);
    } else {
        overview_scale(m);
    }

    if (m.*.is_jump_mode != 0) {
        create_jump_hints(m);
    }
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/layout_overview_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_resize_calls: c_int;
extern var stub_resize_client: [16][*c]Client;
extern var stub_resize_box: [16]c.struct_wlr_box;
extern var stub_keycode_calls: c_int;
extern var stub_keycode_char: [16]u8;
extern var stub_label_update_calls: c_int;
extern var stub_label_text: [16][4]u8;
extern var stub_label_scale: [16]f32;
extern var stub_overview_label_calls: c_int;
extern var stub_overview_label_client: [16][*c]Client;

var test_mon: Monitor = std.mem.zeroes(Monitor);
var test_output: c.struct_wlr_output = std.mem.zeroes(c.struct_wlr_output);
var test_clients: [4]Client = std.mem.zeroes([4]Client);
var test_label_node: c.AcwmJumpLabel = std.mem.zeroes(c.AcwmJumpLabel);
var test_label_scene: c.struct_wlr_scene_tree = std.mem.zeroes(c.struct_wlr_scene_tree);

fn wlListInit(list: *c.struct_wl_list) void {
    list.prev = @ptrCast(list);
    list.next = @ptrCast(list);
}

fn resetWorld() void {
    c.config = std.mem.zeroes(c.Config);
    c.server = std.mem.zeroes(c.AcwmServer);
    wlListInit(&c.server.clients);
    test_mon = std.mem.zeroes(Monitor);
    test_output = std.mem.zeroes(c.struct_wlr_output);
    test_mon.wlr_output = &test_output;
    test_mon.tagset[0] = 1;
    test_mon.seltags = 0;
    test_mon.w = .{ .x = 0, .y = 0, .width = 1000, .height = 800 };
    test_clients = std.mem.zeroes([4]Client);
    test_label_node = std.mem.zeroes(c.AcwmJumpLabel);
    test_label_scene = std.mem.zeroes(c.struct_wlr_scene_tree);
    stub_resize_calls = 0;
    stub_resize_client = std.mem.zeroes([16][*c]Client);
    stub_resize_box = std.mem.zeroes([16]c.struct_wlr_box);
    stub_keycode_calls = 0;
    stub_keycode_char = std.mem.zeroes([16]u8);
    stub_label_update_calls = 0;
    stub_label_text = std.mem.zeroes([16][4]u8);
    stub_label_scale = std.mem.zeroes([16]f32);
    stub_overview_label_calls = 0;
    stub_overview_label_client = std.mem.zeroes([16][*c]Client);
}

fn addClient(idx: usize) *Client {
    const cl = &test_clients[idx];
    cl.mon = &test_mon;
    cl.tags = 1;
    c.wl_list_insert(&c.server.clients, &cl.link);
    return cl;
}

fn setBackup(cl: *Client, w: i32, h: i32) void {
    cl.overview_backup_geom = .{ .x = 0, .y = 0, .width = w, .height = h };
}

fn rectsOverlap(a: c.struct_wlr_box, b: c.struct_wlr_box) bool {
    return !(a.x + a.width <= b.x or a.x >= b.x + b.width or
        a.y + a.height <= b.y or a.y >= b.y + b.height);
}

test "compare_layout_items sorts larger areas first" {
    var small = c.OvLayoutItem{ .c = null, .orig_w = 1, .orig_h = 1, .area = 10 };
    var large = c.OvLayoutItem{ .c = null, .orig_w = 1, .orig_h = 1, .area = 20 };
    try testing.expectEqual(@as(c_int, 1), compare_layout_items(&small, &large));
    try testing.expectEqual(@as(c_int, -1), compare_layout_items(&large, &small));
    try testing.expectEqual(@as(c_int, 0), compare_layout_items(&large, &large));
}

test "begin_jump_mode flags the monitor" {
    resetWorld();
    begin_jump_mode(&test_mon);
    try testing.expectEqual(@as(i32, 1), test_mon.is_jump_mode);
}

test "try_place fills from the origin and packs beside occupied space" {
    var placed = std.mem.zeroes([4]c.OvPlacedRect);
    var cands = std.mem.zeroes([13]c.OvPoint);
    var feas = std.mem.zeroes([13]c.OvPoint);
    var out: c.OvPlacedRect = undefined;

    try testing.expect(try_place(&placed, 0, 10, 10, 2, 100, 100, &out, &cands, &feas));
    try testing.expectEqual(@as(f32, 0), out.x);
    try testing.expectEqual(@as(f32, 0), out.y);
    placed[0] = out;

    try testing.expect(try_place(&placed, 1, 10, 10, 2, 100, 100, &out, &cands, &feas));
    try testing.expectEqual(@as(f32, 12), out.x);
    try testing.expectEqual(@as(f32, 0), out.y);
    try testing.expect(!rectsOverlap(
        .{ .x = @intFromFloat(out.x), .y = @intFromFloat(out.y), .width = 10, .height = 10 },
        .{ .x = 0, .y = 0, .width = 10, .height = 10 },
    ));
}

test "try_place picks the topmost free row" {
    var placed = std.mem.zeroes([4]c.OvPlacedRect);
    var cands = std.mem.zeroes([13]c.OvPoint);
    var feas = std.mem.zeroes([13]c.OvPoint);
    var out: c.OvPlacedRect = undefined;
    placed[0] = .{ .x = 0, .y = 0, .w = 10, .h = 10 };
    placed[1] = .{ .x = 12, .y = 0, .w = 10, .h = 10 };
    try testing.expect(try_place(&placed, 2, 10, 10, 2, 100, 100, &out, &cands, &feas));
    try testing.expectEqual(@as(f32, 24), out.x);
    try testing.expectEqual(@as(f32, 0), out.y);
}

test "try_place rejects items larger than the area" {
    var placed = std.mem.zeroes([1]c.OvPlacedRect);
    var cands = std.mem.zeroes([4]c.OvPoint);
    var feas = std.mem.zeroes([4]c.OvPoint);
    var out: c.OvPlacedRect = undefined;
    try testing.expect(!try_place(&placed, 0, 200, 10, 2, 100, 100, &out, &cands, &feas));
}

test "layout column stacks proportionally and centers vertically" {
    resetWorld();
    var a: Client = std.mem.zeroes(Client);
    var b: Client = std.mem.zeroes(Client);
    setBackup(&a, 100, 100);
    setBackup(&b, 100, 100);
    var items = [_][*c]Client{ &a, &b };
    overview_layout_column(&test_mon, &items, 2, 0, 0, 200, 500, 10);
    try testing.expectEqual(@as(c_int, 2), stub_resize_calls);
    try testing.expectEqual(@as(i32, 0), stub_resize_box[0].x);
    try testing.expectEqual(@as(i32, 45), stub_resize_box[0].y);
    try testing.expectEqual(@as(i32, 200), stub_resize_box[0].width);
    try testing.expectEqual(@as(i32, 200), stub_resize_box[0].height);
    try testing.expectEqual(@as(i32, 255), stub_resize_box[1].y);
}

test "layout column scales down when the stack is too tall" {
    resetWorld();
    var a: Client = std.mem.zeroes(Client);
    setBackup(&a, 100, 100);
    var items = [_][*c]Client{&a};
    overview_layout_column(&test_mon, &items, 1, 0, 0, 200, 100, 10);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(i32, 100), stub_resize_box[0].height);
    try testing.expectEqual(@as(i32, 100), stub_resize_box[0].width);
}

test "overview_scale tiles all visible clients inside the monitor" {
    resetWorld();
    c.config.overviewgappo = 20;
    c.config.overviewgappi = 10;
    test_mon.visible_clients = 2;
    const a = addClient(0);
    const b = addClient(1);
    setBackup(a, 200, 100);
    setBackup(b, 400, 200);
    overview_scale(&test_mon);
    try testing.expectEqual(@as(c_int, 2), stub_resize_calls);
    for (stub_resize_box[0..2]) |box| {
        try testing.expect(box.x >= 0 and box.y >= 0);
        try testing.expect(box.x + box.width <= 1000);
        try testing.expect(box.y + box.height <= 800);
        try testing.expect(box.width > 0 and box.height > 0);
    }
    try testing.expect(!rectsOverlap(stub_resize_box[0], stub_resize_box[1]));
    try testing.expect(stub_resize_box[0].width * stub_resize_box[0].height >
        stub_resize_box[1].width * stub_resize_box[1].height);
}

test "overview_scale_tab centers the focused client" {
    resetWorld();
    c.config.overviewgappo = 20;
    c.config.overviewgappi = 10;
    c.config.overcircle_center_ratio = 0.5;
    test_mon.visible_clients = 3;
    const a = addClient(0);
    const b = addClient(1);
    const c0 = addClient(2);
    setBackup(a, 100, 100);
    setBackup(b, 100, 100);
    setBackup(c0, 100, 100);
    test_mon.sel = b;
    overview_scale_tab(&test_mon);
    try testing.expectEqual(@as(c_int, 3), stub_resize_calls);
    try testing.expectEqual(@as(i32, 490), stub_resize_box[0].width);
    try testing.expectEqual(@as(i32, 490), stub_resize_box[0].height);
    try testing.expect(stub_resize_box[1].x < stub_resize_box[0].x);
    try testing.expect(stub_resize_box[2].x > stub_resize_box[0].x);
}

test "create_jump_hints labels visible clients in list order" {
    resetWorld();
    test_output.scale = 2;
    test_mon.visible_clients = 2;
    test_label_node.scene = &test_label_scene;
    const a = addClient(0);
    const b = addClient(1);
    a.jump_label_node = &test_label_node;
    b.jump_label_node = &test_label_node;
    create_jump_hints(&test_mon);
    // wl_list_insert pushes to the head, so the list visits b first.
    try testing.expectEqual(@as(u8, 'J'), a.jump_char);
    try testing.expectEqual(@as(u8, 'H'), b.jump_char);
    try testing.expectEqual(@as(c_int, 2), stub_keycode_calls);
    try testing.expectEqual(@as(u8, 'H'), stub_keycode_char[0]);
    try testing.expectEqual(@as(c_int, 2), stub_label_update_calls);
    try testing.expectEqual(@as(u8, 'H'), stub_label_text[0][0]);
    try testing.expectEqual(@as(u8, 'J'), stub_label_text[1][0]);
    try testing.expectEqual(@as(f32, 2), stub_label_scale[0]);
    try testing.expectEqual(@as(c_int, 2), stub_overview_label_calls);
}

test "finish_jump_mode clears labels and hides enabled hints" {
    resetWorld();
    test_label_node.scene = &test_label_scene;
    test_label_scene.node.enabled = true;
    const a = addClient(0);
    a.jump_label_node = &test_label_node;
    a.jump_char = 'H';
    a.jump_keycodes.keycode1 = 9;
    test_mon.is_jump_mode = 1;
    const other = addClient(1);
    other.jump_char = 'J';
    other.mon = null;
    finish_jump_mode(&test_mon);
    try testing.expectEqual(@as(i32, 0), test_mon.is_jump_mode);
    try testing.expectEqual(@as(u8, 0), a.jump_char);
    try testing.expectEqual(@as(u32, 0), a.jump_keycodes.keycode1);
    try testing.expect(!test_label_scene.node.enabled);
    try testing.expectEqual(@as(u8, 'J'), other.jump_char);
}

test "overview dispatch enters jump hints in jump mode" {
    resetWorld();
    test_mon.visible_clients = 1;
    test_mon.is_jump_mode = 1;
    test_label_node.scene = &test_label_scene;
    const a = addClient(0);
    setBackup(a, 100, 100);
    a.jump_label_node = &test_label_node;
    overview(&test_mon);
    try testing.expectEqual(@as(c_int, 1), stub_resize_calls);
    try testing.expectEqual(@as(u8, 'H'), a.jump_char);
    try testing.expectEqual(@as(c_int, 1), stub_overview_label_calls);
}
