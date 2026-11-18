#ifndef __ACWM_COMMON_SCENE_NODE_H__
#define __ACWM_COMMON_SCENE_NODE_H__ 1

#include <stdbool.h>
#include <stdint.h>
#include <wayland-server-core.h>

struct wlr_scene_node;

/* Payload for wlr_scene_node.data. */
typedef struct AcwmSceneNode {
	uint32_t type; /* client kind: XDGShell / X11 / LayerShell / ... */
	void *owner;   /* Client / LayerSurface / AcwmBarDecoration / ... */
	bool ignore_hit;
	struct wl_listener destroy;
} AcwmSceneNode;

/* Allocates a payload for `node`, freed when the node is destroyed. */
AcwmSceneNode *acwm_scene_node_set(struct wlr_scene_node *node, uint32_t type,
									 void *owner);

/* Nearest payload on `node` or one of its ancestors, or NULL if there is
 * none. */
AcwmSceneNode *acwm_scene_node_find(struct wlr_scene_node *node);

/* Toggle the pointer-transparency flag of `node`'s payload. No-op when the
 * node carries no payload. */
void acwm_scene_node_set_ignore_hit(struct wlr_scene_node *node,
									 bool ignore_hit);

/* Current value of the pointer-transparency flag; false without a payload. */
bool acwm_scene_node_get_ignore_hit(struct wlr_scene_node *node);

/*
 * Read-only equivalent of wlr_scene_node_at(): returns the topmost node that
 * accepts pointer input at (lx, ly), skipping any subtree whose payload has
 * ignore_hit set. `nx` / `ny` receive node-local coordinates and may be NULL.
 */
struct wlr_scene_node *acwm_scene_node_at(struct wlr_scene_node *node,
										   double lx, double ly, double *nx,
										   double *ny);

#endif
