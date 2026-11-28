//! Port of config/preset.c constants (Phase 5, config data slice, slice 92).

const c = @import("cc");

export var tags: [c.tag_num_MAX][*c]const u8 = .{
    "1",  "2",  "3",  "4",  "5",  "6",  "7",  "8",  "9",  "10", "11",
    "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22",
    "23", "24", "25", "26", "27", "28", "29", "30", "31",
};

export const xkb_fallback_rules: c.struct_xkb_rule_names = .{
    .layout = "us",
    .variant = null,
    .model = null,
    .rules = null,
    .options = null,
};
