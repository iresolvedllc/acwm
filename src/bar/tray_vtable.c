/* sd-bus vtable glue for the Zig tray port.
 *
 * The vtable macros expand to bitfield/union initializers that translate-c
 * cannot express; the table itself stays here while all callbacks live in
 * src/bar/tray.zig. tray.c keeps its own copy when the Zig twin is disabled. */
#if defined(HAVE_TRAY) && defined(ACWM_ZIG_TRAY)
#include <systemd/sd-bus.h>
#include <stddef.h>

int aw_tray_register_item(sd_bus_message *m, void *userdata, sd_bus_error *e);
int aw_tray_register_host(sd_bus_message *m, void *userdata, sd_bus_error *e);
int aw_tray_get_items(sd_bus *bus, const char *path, const char *iface,
					  const char *prop, sd_bus_message *reply,
					  void *userdata, sd_bus_error *e);
int aw_tray_get_bool(sd_bus *bus, const char *path, const char *iface,
					 const char *prop, sd_bus_message *reply, void *userdata,
					 sd_bus_error *e);
int aw_tray_get_version(sd_bus *bus, const char *path, const char *iface,
						const char *prop, sd_bus_message *reply,
						void *userdata, sd_bus_error *e);

const sd_bus_vtable aw_tray_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("RegisterStatusNotifierItem", "s", "", aw_tray_register_item,
				  0),
	SD_BUS_METHOD("RegisterStatusNotifierHost", "s", "",
				  aw_tray_register_host, 0),
	SD_BUS_PROPERTY("RegisteredStatusNotifierItems", "as", aw_tray_get_items, 0,
					0),
	SD_BUS_PROPERTY("IsStatusNotifierHostRegistered", "b", aw_tray_get_bool, 0,
					0),
	SD_BUS_PROPERTY("ProtocolVersion", "i", aw_tray_get_version, 0, 0),
	SD_BUS_VTABLE_END,
};
#endif

#if defined(HAVE_TRAY) && defined(ACWM_ZIG_TRAY)
const sd_bus_vtable *aw_tray_vtable_get(void) { return aw_tray_vtable; }
#endif