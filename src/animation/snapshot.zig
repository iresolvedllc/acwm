//! Port of the scene-snapshot helpers from animation/common.c
//! (Phase 5, animation cleanup slice, slice 95).

const std = @import("std");
const c = @import("cc");

extern fn handle_snapshot_meta_destroy(listener: [*c]c.struct_wl_listener, data: ?*anyopaque) callconv(.c) void;

fn nodeFromLink(link: [*c]c.struct_wl_list) [*c]c.struct_wlr_scene_node {
    return @ptrFromInt(@intFromPtr(link) - @offsetOf(c.struct_wlr_scene_node, "link"));
}

export fn scene_node_snapshot(
    node: [*c]c.struct_wlr_scene_node,
    lx_in: i32,
    ly_in: i32,
    snapshot_tree: [*c]c.struct_wlr_scene_tree,
) callconv(.c) bool {
    if (!node.*.enabled and node.*.type != c.WLR_SCENE_NODE_TREE)
        return true;

    const lx = lx_in + node.*.x;
    const ly = ly_in + node.*.y;

    var snapshot_node: [*c]c.struct_wlr_scene_node = null;
    switch (node.*.type) {
        c.WLR_SCENE_NODE_TREE => {
            const scene_tree = c.wlr_scene_tree_from_node(node);
            const head: [*c]c.struct_wl_list = @ptrCast(&scene_tree.*.children);
            var pos = scene_tree.*.children.next;
            while (pos != head) : (pos = pos.*.next) {
                _ = scene_node_snapshot(nodeFromLink(pos), lx, ly, snapshot_tree);
            }
        },
        c.WLR_SCENE_NODE_RECT => {},
        c.WLR_SCENE_NODE_BUFFER => {
            const scene_buffer = c.wlr_scene_buffer_from_node(node);

            // Creates an intermediate wrapper tree node.
            const wrapper = c.wlr_scene_tree_create(snapshot_tree);
            if (wrapper == null)
                return false;
            snapshot_node = &wrapper.*.node; // Applies the coordinate offset.

            // Collects surface state and stores it as metadata.
            const raw = c.calloc(1, @sizeOf(c.SnapshotMetadata)) orelse {
                c.wlr_scene_node_destroy(&wrapper.*.node);
                return false;
            };
            const meta: *c.SnapshotMetadata = @ptrCast(@alignCast(raw));
            meta.*.orig_width = scene_buffer.*.dst_width;
            meta.*.orig_height = scene_buffer.*.dst_height;
            meta.*.type = c.Snapshot;

            const scene_surface = c.wlr_scene_surface_try_from_buffer(scene_buffer);
            if (scene_surface != null) {
                meta.*.is_subsurface =
                    c.wlr_subsurface_try_from_wlr_surface(scene_surface.*.surface) != null;
            }

            // Bind a destruction callback to free the metadata with the wrapper.
            meta.*.destroy.notify = handle_snapshot_meta_destroy;
            c.wl_signal_add(&wrapper.*.node.events.destroy, &meta.*.destroy);
            _ = c.acwm_scene_node_set(&wrapper.*.node, @intCast(c.Snapshot), meta);

            // Attach the real buffer underneath the wrapper (relative 0,0).
            const snapshot_buffer = c.wlr_scene_buffer_create(wrapper, null);
            if (snapshot_buffer == null) {
                c.wlr_scene_node_destroy(&wrapper.*.node);
                return false;
            }

            c.wlr_scene_buffer_set_dest_size(snapshot_buffer, scene_buffer.*.dst_width, scene_buffer.*.dst_height);
            c.wlr_scene_buffer_set_opaque_region(snapshot_buffer, &scene_buffer.*.opaque_region);
            c.wlr_scene_buffer_set_source_box(snapshot_buffer, &scene_buffer.*.src_box);
            c.wlr_scene_buffer_set_transform(snapshot_buffer, scene_buffer.*.transform);
            c.wlr_scene_buffer_set_filter_mode(snapshot_buffer, scene_buffer.*.filter_mode);

            // Effects
            c.wlr_scene_buffer_set_opacity(snapshot_buffer, scene_buffer.*.opacity);
            c.wlr_scene_buffer_set_corner_radii(snapshot_buffer, scene_buffer.*.corners);

            if (scene_surface != null and scene_surface.*.surface.*.buffer != null) {
                c.wlr_scene_buffer_set_buffer(snapshot_buffer, &scene_surface.*.surface.*.buffer.*.base);
            } else {
                c.wlr_scene_buffer_set_buffer(snapshot_buffer, scene_buffer.*.buffer);
            }
        },
        c.WLR_SCENE_NODE_SHADOW => {
            const scene_shadow = c.wlr_scene_shadow_from_node(node);
            const snapshot_shadow = c.wlr_scene_shadow_create(snapshot_tree, scene_shadow.*.width, scene_shadow.*.height, scene_shadow.*.corner_radius, scene_shadow.*.blur_sigma, &scene_shadow.*.color);
            if (snapshot_shadow == null)
                return false;
            snapshot_node = &snapshot_shadow.*.node;

            c.wlr_scene_shadow_set_clipped_region(snapshot_shadow, scene_shadow.*.clipped_region);
            c.wlr_scene_node_set_enabled(&snapshot_shadow.*.node, false);
        },
        c.WLR_SCENE_NODE_BLUR => {},
        c.WLR_SCENE_NODE_OPTIMIZED_BLUR => return true,
        else => {},
    }

    if (snapshot_node != null)
        c.wlr_scene_node_set_position(snapshot_node, lx, ly);

    return true;
}

export fn wlr_scene_tree_snapshot(
    node: [*c]c.struct_wlr_scene_node,
    parent: [*c]c.struct_wlr_scene_tree,
) callconv(.c) [*c]c.struct_wlr_scene_tree {
    const snapshot = c.wlr_scene_tree_create(parent);
    if (snapshot == null)
        return null;

    // Disable and enable the snapshot tree to update the scene graph atomically.
    c.wlr_scene_node_set_enabled(&snapshot.*.node, false);

    if (!scene_node_snapshot(node, 0, 0, snapshot)) {
        c.wlr_scene_node_destroy(&snapshot.*.node);
        return null;
    }

    c.wlr_scene_node_set_enabled(&snapshot.*.node, true);
    return snapshot;
}
