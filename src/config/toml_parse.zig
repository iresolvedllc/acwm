//! Port of src/config/toml_parse.c (strangler-fig Phase 4, config slice,
//! slice 35).
//!
//! Decision: hand-port the TOML subset parser rather than adding a Zig TOML
//! dependency. The accepted syntax is project-specific (bind sections with
//! keymode/flag suffixes, rule sections, comma-joined arrays) and the exact
//! diagnostics/truncation behaviour matters for config compatibility.
//!
//! Only `parse_toml_stream` is public. Still in C: apply_option_expanded,
//! parse_option, expand_config_variables and the error reporter; tests stub
//! them.

const std = @import("std");
const c = @import("cc");

const Config = c.Config;

extern fn apply_option_expanded(config: *Config, key: [*:0]u8, value: [*:0]u8, line_number: c_int) callconv(.c) bool;
extern fn parse_option(config: *Config, key: [*:0]u8, value: [*:0]u8, line_number: c_int) callconv(.c) bool;
extern fn expand_config_variables(value: [*:0]const u8) callconv(.c) [*c]u8;
extern fn report_config_line_error(full_path: [*:0]const u8, line_number: c_int, line: [*:0]const u8) callconv(.c) void;
extern fn acwm_error_impl(log: bool, verbosity: c_uint, file: [*:0]const u8, line: c_int, fmt: [*:0]const u8, ...) callconv(.c) void;

extern "c" fn fgets(buf: [*]u8, size: c_int, stream: *c.FILE) ?[*:0]u8;
extern "c" fn free(ptr: ?*anyopaque) void;

const WLR_ERROR: c_uint = @intCast(c.WLR_ERROR);

const TOML_SECTION_NONE = 0;
const TOML_SECTION_GLOBAL = 1;
const TOML_SECTION_ENV = 2;
const TOML_SECTION_VAR = 3;
const TOML_SECTION_BIND = 4;
const TOML_SECTION_RULE = 5;

const TomlSection = struct {
    name: [256]u8 = std.mem.zeroes([256]u8),
    keymode: [28]u8 = std.mem.zeroes([28]u8),
    saved_keymode: [28]u8 = std.mem.zeroes([28]u8),
    bindtype: [16]u8 = std.mem.zeroes([16]u8),
    keyword: [24]u8 = std.mem.zeroes([24]u8),
    pairs: [8192]u8 = std.mem.zeroes([8192]u8),
    pairs_len: usize = 0,
    line_number: c_int = 0,
    kind: c_int = TOML_SECTION_NONE,
    active: bool = false,
    skip: bool = false,
};

fn z(buf: []u8) [*:0]u8 {
    return @ptrCast(buf.ptr);
}

fn zc(buf: []u8) [*:0]const u8 {
    return @ptrCast(buf.ptr);
}

fn span(p: [*:0]const u8) []const u8 {
    return std.mem.span(p);
}

fn setTrunc(dst: []u8, src: []const u8, max: usize) void {
    if (dst.len == 0)
        return;
    const n = @min(@min(src.len, max), dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

fn trimWhitespace(buf: []u8) void {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) : (len += 1) {}
    if (len == 0)
        return;
    var start: usize = 0;
    while (start < len and std.ascii.isWhitespace(buf[start])) : (start += 1) {}
    var end = len;
    while (end > start and std.ascii.isWhitespace(buf[end - 1])) : (end -= 1) {}
    if (start > 0) {
        const n = end - start;
        std.mem.copyForwards(u8, buf[0..n], buf[start..end]);
        len = n;
    } else {
        len = end;
    }
    buf[len] = 0;
}

fn removeTomlComment(str: [*]u8) void {
    var quote: u8 = 0;
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        const ch = str[i];
        if (quote == '"') {
            if (ch == '\\' and str[i + 1] != 0) {
                i += 1;
                continue;
            }
            if (ch == '"')
                quote = 0;
        } else if (quote == '\'') {
            if (ch == '\'')
                quote = 0;
        } else if (ch == '"' or ch == '\'') {
            quote = ch;
        } else if (ch == '#') {
            str[i] = 0;
            return;
        }
    }
}

fn tomlScalar(raw: [*:0]const u8, out: []u8, map_bool: bool) void {
    var n: usize = 0;
    out[0] = 0;
    var src = span(raw);

    var start: usize = 0;
    while (start < src.len and std.ascii.isWhitespace(src[start])) : (start += 1) {}
    var len = src.len;
    while (len > start and std.ascii.isWhitespace(src[len - 1])) : (len -= 1) {}
    src = src[start..len];

    if (src.len >= 2 and src[0] == '"' and src[src.len - 1] == '"') {
        var i: usize = 1;
        while (i + 1 < src.len and n + 1 < out.len) : (i += 1) {
            var ch = src[i];
            if (ch == '\\' and i + 2 < src.len) {
                i += 1;
                const esc = src[i];
                switch (esc) {
                    'n' => ch = '\n',
                    't' => ch = '\t',
                    'r' => ch = '\r',
                    '"', '\\' => ch = esc,
                    else => {
                        if (n + 2 < out.len) {
                            out[n] = '\\';
                            n += 1;
                            out[n] = esc;
                            n += 1;
                        }
                        continue;
                    },
                }
            }
            out[n] = ch;
            n += 1;
        }
        out[n] = 0;
        return;
    }

    if (src.len >= 2 and src[0] == '\'' and src[src.len - 1] == '\'') {
        var i: usize = 1;
        while (i + 1 < src.len and n + 1 < out.len) : (i += 1) {
            out[n] = src[i];
            n += 1;
        }
        out[n] = 0;
        return;
    }

    if (map_bool) {
        if (std.mem.eql(u8, src, "true")) {
            setTrunc(out, "1", 1);
            return;
        }
        if (std.mem.eql(u8, src, "false")) {
            setTrunc(out, "0", 1);
            return;
        }
    }

    var i: usize = 0;
    while (i < src.len and n + 1 < out.len) : (i += 1) {
        out[n] = src[i];
        n += 1;
    }
    out[n] = 0;
}

fn tomlValueToString(raw: [*:0]const u8, out: []u8) void {
    tomlScalar(raw, out, true);
}

fn tomlValueAsString(raw: [*:0]const u8, out: []u8) void {
    tomlScalar(raw, out, false);
}

const ElemFn = *const fn (*anyopaque, [*:0]const u8) bool;

fn tomlForeachArrayElement(p_in: [*:0]const u8, func: ElemFn, ctx: *anyopaque) bool {
    var elem: [2048]u8 = undefined;
    var el: usize = 0;
    var depth: i32 = 0;
    var quote: u8 = 0;

    var p = p_in;
    while (p[0] != 0) : (p += 1) {
        const ch = p[0];
        if (quote != 0) {
            if (quote == '"' and ch == '\\' and p[1] != 0) {
                if (el + 1 < elem.len) {
                    elem[el] = ch;
                    el += 1;
                }
                p += 1;
            }
            if (el + 1 < elem.len) {
                elem[el] = p[0];
                el += 1;
            }
            if (p[0] == quote)
                quote = 0;
            continue;
        }

        if (ch == '"' or ch == '\'') {
            quote = ch;
            if (el + 1 < elem.len) {
                elem[el] = ch;
                el += 1;
            }
        } else if (ch == '[') {
            depth += 1;
            if (el + 1 < elem.len) {
                elem[el] = ch;
                el += 1;
            }
        } else if (ch == ']') {
            if (depth == 0) {
                elem[el] = 0;
                return func(ctx, zc(&elem));
            }
            depth -= 1;
            if (el + 1 < elem.len) {
                elem[el] = ch;
                el += 1;
            }
        } else if (ch == ',' and depth == 0) {
            elem[el] = 0;
            if (!func(ctx, zc(&elem)))
                return false;
            el = 0;
        } else if (el + 1 < elem.len) {
            elem[el] = ch;
            el += 1;
        }
    }

    elem[el] = 0;
    if (el > 0)
        return func(ctx, zc(&elem));
    return true;
}

const TomlApplyCtx = struct {
    config: *Config,
    key: [256]u8 = std.mem.zeroes([256]u8),
    line_number: c_int = 0,
    joined: [4096]u8 = std.mem.zeroes([4096]u8),
    joined_len: usize = 0,
};

fn tomlApplyElement(ctx: *anyopaque, elem: [*:0]const u8) bool {
    const apply: *TomlApplyCtx = @ptrCast(@alignCast(ctx));
    var value: [2048]u8 = undefined;
    tomlValueToString(elem, &value);
    if (value[0] == 0)
        return true;
    return apply_option_expanded(apply.config, z(&apply.key), z(&value), apply.line_number);
}

fn tomlJoinElement(ctx: *anyopaque, elem: [*:0]const u8) bool {
    const apply: *TomlApplyCtx = @ptrCast(@alignCast(ctx));
    var value: [2048]u8 = undefined;
    tomlValueToString(elem, &value);
    if (value[0] == 0)
        return true;

    const len = std.mem.len(zc(&value));
    if (apply.joined_len + len + 2 >= apply.joined.len)
        return false;
    if (apply.joined_len > 0) {
        apply.joined[apply.joined_len] = ',';
        apply.joined_len += 1;
    }
    @memcpy(apply.joined[apply.joined_len .. apply.joined_len + len], value[0..len]);
    apply.joined_len += len;
    apply.joined[apply.joined_len] = 0;
    return true;
}

fn tomlKeyJoinsArray(key: []const u8) bool {
    return std.mem.startsWith(u8, key, "animation_curve_") or
        std.mem.eql(u8, key, "scroller_proportion_preset") or
        std.mem.eql(u8, key, "circle_layout");
}

fn tomlApplyValue(config: *Config, key: []const u8, raw: [*:0]const u8, line_number: c_int) bool {
    var p = span(raw);
    while (p.len > 0 and std.ascii.isWhitespace(p[0])) p = p[1..];

    var ctx = TomlApplyCtx{ .config = config, .line_number = line_number };
    setTrunc(&ctx.key, key, 255);

    if (p.len > 0 and p[0] == '[') {
        if (tomlKeyJoinsArray(key)) {
            ctx.joined[0] = 0;
            ctx.joined_len = 0;
            if (!tomlForeachArrayElement(@ptrCast(p[1..].ptr), tomlJoinElement, @ptrCast(&ctx)))
                return false;
            return apply_option_expanded(config, z(&ctx.key), z(&ctx.joined), line_number);
        }
        return tomlForeachArrayElement(@ptrCast(p[1..].ptr), tomlApplyElement, @ptrCast(&ctx));
    }

    var value: [4096]u8 = undefined;
    tomlValueToString(raw, &value);
    if (value[0] == 0)
        return true;
    return apply_option_expanded(config, z(&ctx.key), z(&value), line_number);
}

fn tomlIsRuleType(name: []const u8) bool {
    return std.mem.eql(u8, name, "monitor_rule") or
        std.mem.eql(u8, name, "tag_rule") or
        std.mem.eql(u8, name, "layer_rule") or
        std.mem.eql(u8, name, "window_rule") or
        std.mem.eql(u8, name, "window_rule_once") or
        std.mem.eql(u8, name, "device_rule");
}

fn tomlSectionAdd(section: *TomlSection, subkey: []const u8, raw_value: [*:0]const u8) bool {
    var value: [2048]u8 = undefined;
    tomlValueToString(raw_value, &value);
    if (value[0] == 0)
        return true;

    const expanded = expand_config_variables(zc(&value));
    const v: []const u8 = if (expanded != null) span(@ptrCast(expanded)) else span(zc(&value));

    if (section.pairs_len + subkey.len + v.len + 2 >= section.pairs.len) {
        if (expanded != null)
            free(@ptrCast(expanded));
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Toml section is too long: \x1b[1m\x1b[31m%s\x1b[0m\n", zc(&section.name));
        return false;
    }

    if (section.pairs_len > 0) {
        section.pairs[section.pairs_len] = ',';
        section.pairs_len += 1;
    }
    @memcpy(section.pairs[section.pairs_len .. section.pairs_len + subkey.len], subkey);
    section.pairs_len += subkey.len;
    section.pairs[section.pairs_len] = ':';
    section.pairs_len += 1;
    @memcpy(section.pairs[section.pairs_len .. section.pairs_len + v.len], v);
    section.pairs_len += v.len;
    section.pairs[section.pairs_len] = 0;

    if (expanded != null)
        free(@ptrCast(expanded));
    return true;
}

fn tomlBindFlagChar(word: []const u8) u8 {
    if (std.mem.eql(u8, word, "sym")) return 's';
    if (std.mem.eql(u8, word, "lock")) return 'l';
    if (std.mem.eql(u8, word, "release")) return 'r';
    if (std.mem.eql(u8, word, "pass")) return 'p';
    if (std.mem.eql(u8, word, "conflict")) return 'c';
    return 0;
}

// ---------------------------------------------------------------------------
// sections
// ---------------------------------------------------------------------------

fn startsWithWord(name: []const u8, word: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, name, word))
        return null;
    if (name.len == word.len)
        return name[name.len..];
    if (name[word.len] == '.')
        return name[word.len + 1 ..];
    return null;
}

fn tomlSectionBegin(
    config: *Config,
    section: *TomlSection,
    name_in: [*:0]const u8,
    line_number: c_int,
    full_path: [*:0]const u8,
    stmt: [*:0]const u8,
) bool {
    section.* = .{ .line_number = line_number, .active = true };
    const name = span(name_in);

    if (std.mem.eql(u8, name, "global") or std.mem.eql(u8, name, "rule")) {
        section.kind = TOML_SECTION_GLOBAL;
        return true;
    }
    if (std.mem.eql(u8, name, "env")) {
        section.kind = TOML_SECTION_ENV;
        return true;
    }
    if (std.mem.eql(u8, name, "var")) {
        section.kind = TOML_SECTION_VAR;
        return true;
    }

    var base: ?[]const u8 = null;
    var suffix: []const u8 = "";
    if (startsWithWord(name, "keybind")) |s| {
        base = "bind";
        suffix = s;
    } else if (startsWithWord(name, "bind")) |s| {
        base = "bind";
        suffix = s;
    } else if (startsWithWord(name, "mousebind")) |s| {
        base = "mousebind";
        suffix = s;
    } else if (startsWithWord(name, "axisbind")) |s| {
        base = "axisbind";
        suffix = s;
    } else if (startsWithWord(name, "gesturebind")) |s| {
        base = "gesturebind";
        suffix = s;
    } else if (startsWithWord(name, "switchbind")) |s| {
        base = "switchbind";
        suffix = s;
    } else if (std.mem.startsWith(u8, name, "rule.")) {
        const rule_type = name[5..];
        if (!tomlIsRuleType(rule_type)) {
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown toml rule type: \x1b[1m\x1b[31m%s\x1b[0m\n", name_in + 5);
            report_config_line_error(full_path, line_number, stmt);
            section.skip = true;
            return false;
        }
        section.kind = TOML_SECTION_RULE;
        setTrunc(&section.name, rule_type, 255);
    } else if (tomlIsRuleType(name)) {
        section.kind = TOML_SECTION_RULE;
        setTrunc(&section.name, name, 255);
    } else {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown toml section: \x1b[1m\x1b[31m%s\x1b[0m\n", name_in);
        report_config_line_error(full_path, line_number, stmt);
        section.skip = true;
        return false;
    }

    const b = base orelse return true;
    section.kind = TOML_SECTION_BIND;
    setTrunc(&section.bindtype, b, 15);
    setTrunc(&section.keymode, "default", 27);

    var letters = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    var letter_len: usize = 0;

    var suffix_buf: [128]u8 = undefined;
    setTrunc(&suffix_buf, suffix, 127);
    var depth: i32 = 0;

    var it = std.mem.splitScalar(u8, std.mem.span(zc(&suffix_buf)), '.');
    while (it.next()) |raw_tok| {
        var tok = raw_tok;
        while (tok.len > 0 and std.ascii.isWhitespace(tok[0])) tok = tok[1..];
        while (tok.len > 0 and std.ascii.isWhitespace(tok[tok.len - 1])) tok = tok[0 .. tok.len - 1];
        if (tok.len == 0)
            continue;

        if (depth == 0) {
            setTrunc(&section.keymode, tok, 27);
        } else {
            const flag = tomlBindFlagChar(tok);
            if (flag == 0) {
                acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Unknown bind flag: \x1b[1m\x1b[31m%s\x1b[0m\n", zc(@constCast(tok.ptr[0..tok.len])));
                report_config_line_error(full_path, line_number, stmt);
                section.skip = true;
                return false;
            }
            if (letter_len + 1 < letters.len) {
                letters[letter_len] = flag;
                letter_len += 1;
            }
            letters[letter_len] = 0;
        }
        depth += 1;
    }

    if (depth == 0) {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Bind keymode is required, e.g. \x1b[1m\x1b[31m[%s.default]\x1b[0m\n", zc(@constCast(b.ptr[0..b.len])));
        report_config_line_error(full_path, line_number, stmt);
        section.skip = true;
        return false;
    }

    var keyword_len: usize = 0;
    const bn = @min(b.len, 15);
    @memcpy(section.keyword[0..bn], b[0..bn]);
    keyword_len = bn;
    const ln = @min(letter_len, 7);
    @memcpy(section.keyword[keyword_len .. keyword_len + ln], letters[0..ln]);
    keyword_len += ln;
    section.keyword[keyword_len] = 0;

    setTrunc(&section.saved_keymode, span(zc(@constCast(&config.keymode))), 27);
    setTrunc(&config.keymode, span(zc(&section.keymode)), 27);
    return true;
}

const TomlBindCtx = struct {
    config: *Config,
    keyword: [24]u8 = std.mem.zeroes([24]u8),
    prefix: [1024]u8 = std.mem.zeroes([1024]u8),
    line_number: c_int = 0,
};

fn tomlBindElement(ctx: *anyopaque, elem: [*:0]const u8) bool {
    const bind: *TomlBindCtx = @ptrCast(@alignCast(ctx));
    var action: [2048]u8 = undefined;
    tomlValueToString(elem, &action);
    if (action[0] == 0)
        return true;
    var buf: [3200]u8 = undefined;
    // "%.950s%.2047s"
    const plen = std.mem.len(zc(&bind.prefix));
    const alen = std.mem.len(zc(&action));
    const pn = @min(plen, 950);
    const an = @min(alen, 2047);
    @memcpy(buf[0..pn], bind.prefix[0..pn]);
    @memcpy(buf[pn .. pn + an], action[0..an]);
    buf[pn + an] = 0;
    return apply_option_expanded(bind.config, z(&bind.keyword), z(&buf), bind.line_number);
}

fn tomlBindPrefix(base: []const u8, combo_in: []const u8, prefix: []u8) bool {
    var tmp: [256]u8 = undefined;
    setTrunc(&tmp, combo_in, 255);
    const combo = std.mem.span(zc(&tmp));

    var segs: [16][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, combo, '+');
    while (it.next()) |raw| {
        var tok = raw;
        while (tok.len > 0 and std.ascii.isWhitespace(tok[0])) tok = tok[1..];
        while (tok.len > 0 and std.ascii.isWhitespace(tok[tok.len - 1])) tok = tok[0 .. tok.len - 1];
        if (tok.len != 0 and n < 16) {
            segs[n] = tok;
            n += 1;
        }
    }
    if (n == 0)
        return false;

    if (std.mem.eql(u8, base, "switchbind")) {
        const s0 = @min(segs[0].len, 255);
        @memcpy(prefix[0..s0], segs[0][0..s0]);
        prefix[s0] = ',';
        prefix[s0 + 1] = 0;
        return true;
    }

    if (std.mem.eql(u8, base, "gesturebind")) {
        if (n < 3)
            return false;
        var pos: usize = 0;
        var idx: usize = 0;
        while (idx < 3) : (idx += 1) {
            const sn = @min(segs[idx].len, 255);
            @memcpy(prefix[pos .. pos + sn], segs[idx][0..sn]);
            pos += sn;
            prefix[pos] = ',';
            pos += 1;
        }
        prefix[pos] = 0;
        return true;
    }

    var mod: [256]u8 = undefined;
    if (n >= 2) {
        var mod_len: usize = 0;
        var idx: usize = 0;
        while (idx + 1 < n) : (idx += 1) {
            if (idx != 0 and mod_len + 1 < mod.len) {
                mod[mod_len] = '+';
                mod_len += 1;
            }
            const sn = @min(segs[idx].len, mod.len - mod_len - 1);
            @memcpy(mod[mod_len .. mod_len + sn], segs[idx][0..sn]);
            mod_len += sn;
        }
        mod[mod_len] = 0;
    } else {
        setTrunc(&mod, "none", 255);
    }

    const mn = @min(std.mem.len(zc(&mod)), 255);
    var pos: usize = 0;
    @memcpy(prefix[pos .. pos + mn], mod[0..mn]);
    pos += mn;
    prefix[pos] = ',';
    pos += 1;
    const ln = @min(segs[n - 1].len, 255);
    @memcpy(prefix[pos .. pos + ln], segs[n - 1][0..ln]);
    pos += ln;
    prefix[pos] = ',';
    pos += 1;
    prefix[pos] = 0;
    return true;
}

fn tomlSectionLeaf(
    config: *Config,
    section: *TomlSection,
    key_in: [*:0]const u8,
    raw_value: [*:0]const u8,
    line_number: c_int,
) bool {
    const key = span(key_in);

    if (section.kind == TOML_SECTION_ENV) {
        var value: [2048]u8 = undefined;
        tomlValueAsString(raw_value, &value);
        if (value[0] == 0)
            return true;
        var buf: [2304]u8 = undefined;
        const kn = @min(key.len, 255);
        const vn = @min(std.mem.len(zc(&value)), 2047);
        @memcpy(buf[0..kn], key[0..kn]);
        buf[kn] = ',';
        @memcpy(buf[kn + 1 .. kn + 1 + vn], value[0..vn]);
        buf[kn + 1 + vn] = 0;
        return apply_option_expanded(config, @ptrCast(@constCast("env")), z(&buf), line_number);
    }
    if (section.kind == TOML_SECTION_VAR) {
        var value: [2048]u8 = undefined;
        tomlValueAsString(raw_value, &value);
        var buf: [2304]u8 = undefined;
        const kn = @min(key.len, 255);
        const vn = @min(std.mem.len(zc(&value)), 2047);
        @memcpy(buf[0..kn], key[0..kn]);
        buf[kn] = ',';
        @memcpy(buf[kn + 1 .. kn + 1 + vn], value[0..vn]);
        buf[kn + 1 + vn] = 0;
        return apply_option_expanded(config, @ptrCast(@constCast("var")), z(&buf), line_number);
    }
    if (section.kind == TOML_SECTION_RULE)
        return tomlSectionAdd(section, key, raw_value);

    if (section.kind == TOML_SECTION_BIND) {
        var bind = TomlBindCtx{ .config = config, .line_number = line_number };
        setTrunc(&bind.keyword, span(zc(&section.keyword)), 23);

        const expanded = expand_config_variables(key_in);
        const combo: []const u8 = if (expanded != null) span(@ptrCast(expanded)) else key;
        const prefix_ok = tomlBindPrefix(span(zc(&section.bindtype)), combo, &bind.prefix);
        if (expanded != null)
            free(@ptrCast(expanded));
        if (!prefix_ok)
            return false;

        var p = span(raw_value);
        while (p.len > 0 and std.ascii.isWhitespace(p[0])) p = p[1..];
        if (p.len > 0 and p[0] == '[')
            return tomlForeachArrayElement(@ptrCast(p[1..].ptr), tomlBindElement, @ptrCast(&bind));

        var action: [2048]u8 = undefined;
        tomlValueToString(raw_value, &action);
        if (action[0] == 0)
            return true;
        var buf: [3200]u8 = undefined;
        const pn = @min(std.mem.len(zc(&bind.prefix)), 950);
        const an = @min(std.mem.len(zc(&action)), 2047);
        @memcpy(buf[0..pn], bind.prefix[0..pn]);
        @memcpy(buf[pn .. pn + an], action[0..an]);
        buf[pn + an] = 0;
        return apply_option_expanded(config, z(&bind.keyword), z(&buf), line_number);
    }

    return tomlApplyValue(config, key, raw_value, line_number);
}

fn tomlSectionFlush(config: *Config, section: *TomlSection, full_path: [*:0]const u8) bool {
    if (!section.active)
        return true;

    var ok = true;
    if (section.kind == TOML_SECTION_RULE and section.pairs_len > 0) {
        if (!parse_option(config, z(&section.name), z(&section.pairs), section.line_number)) {
            ok = false;
            report_config_line_error(full_path, section.line_number, zc(&section.name));
        }
    }

    if (section.kind == TOML_SECTION_BIND)
        setTrunc(&config.keymode, span(zc(&section.saved_keymode)), 27);

    section.active = false;
    section.pairs_len = 0;
    section.pairs[0] = 0;
    return ok;
}

// ---------------------------------------------------------------------------
// statements
// ---------------------------------------------------------------------------

fn tomlStatementComplete(stmt: [*:0]const u8) bool {
    const s = span(stmt);
    if (s.len > 0 and s[0] == '[') {
        var n = s.len;
        while (n > 0 and std.ascii.isWhitespace(s[n - 1])) n -= 1;
        return n > 0 and s[n - 1] == ']';
    }

    const eq = std.mem.indexOfScalar(u8, s, '=') orelse return true;

    var depth: i32 = 0;
    var quote: u8 = 0;
    var i = eq + 1;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (quote != 0) {
            if (quote == '"' and ch == '\\' and i + 1 < s.len) {
                i += 1;
                continue;
            }
            if (ch == quote)
                quote = 0;
            continue;
        }
        if (ch == '"' or ch == '\'')
            quote = ch
        else if (ch == '[')
            depth += 1
        else if (ch == ']' and depth > 0)
            depth -= 1;
    }
    return depth == 0 and quote == 0;
}

fn tomlProcessStatement(
    config: *Config,
    stmt: [*:0]const u8,
    line_number: c_int,
    full_path: [*:0]const u8,
    section: *TomlSection,
) bool {
    const s = span(stmt);

    if (s.len > 0 and s[0] == '[') {
        const ok = tomlSectionFlush(config, section, full_path);

        var begin: usize = 0;
        while (begin < s.len and s[begin] == '[') begin += 1;
        var len = s.len - begin;
        while (len > 0 and s[begin + len - 1] == ']') len -= 1;

        var name: [256]u8 = undefined;
        const n = @min(len, name.len - 1);
        @memcpy(name[0..n], s[begin .. begin + n]);
        name[n] = 0;
        trimWhitespace(&name);

        const begun = tomlSectionBegin(config, section, zc(&name), line_number, full_path, stmt);
        return ok and begun;
    }

    if (section.skip)
        return true;

    const eq = std.mem.indexOfScalar(u8, s, '=') orelse {
        acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Invalid toml line format: \x1b[1m\x1b[31m%s\x1b[0m\n", stmt);
        report_config_line_error(full_path, line_number, stmt);
        return false;
    };

    var key: [256]u8 = undefined;
    const key_len = @min(eq, key.len - 1);
    @memcpy(key[0..key_len], s[0..key_len]);
    key[key_len] = 0;
    trimWhitespace(&key);

    var key_quoted = std.mem.len(zc(&key));
    if (key_quoted >= 2 and
        ((key[0] == '"' and key[key_quoted - 1] == '"') or
            (key[0] == '\'' and key[key_quoted - 1] == '\'')))
    {
        const inner = key_quoted - 2;
        std.mem.copyForwards(u8, key[0..inner], key[1 .. 1 + inner]);
        key[inner] = 0;
        key_quoted = inner;
    }

    var value_start = eq + 1;
    while (value_start < s.len and std.ascii.isWhitespace(s[value_start])) value_start += 1;
    const value: [*:0]const u8 = @ptrCast(s[value_start..].ptr);

    if (section.active) {
        const ok = tomlSectionLeaf(config, section, zc(&key), value, line_number);
        if (!ok and section.kind != TOML_SECTION_RULE)
            report_config_line_error(full_path, line_number, stmt);
        return ok;
    }

    if (!tomlApplyValue(config, key[0..key_quoted], value, line_number)) {
        report_config_line_error(full_path, line_number, stmt);
        return false;
    }
    return true;
}

export fn parse_toml_stream(config: *Config, file: *c.FILE, full_path: [*:0]const u8) callconv(.c) bool {
    var raw: [4096]u8 = undefined;
    var stmt: [8192]u8 = undefined;
    var stmt_len: usize = 0;
    var line_count: c_int = 0;
    var stmt_line: c_int = 0;
    var parse_correct = true;
    var section = TomlSection{};

    stmt[0] = 0;

    while (fgets(&raw, @intCast(raw.len), file) != null) {
        line_count += 1;
        removeTomlComment(&raw);
        trimWhitespace(&raw);
        if (raw[0] == 0)
            continue;

        if (stmt_len == 0)
            stmt_line = line_count;

        const raw_len = std.mem.len(@as([*:0]const u8, @ptrCast(&raw)));
        if (stmt_len + raw_len + 2 >= stmt.len) {
            acwm_error_impl(false, WLR_ERROR, @src().file, @src().line, "Config line too long in \x1b[1m\x1b[31m%s\x1b[0m\n", full_path);
            return false;
        }
        if (stmt_len > 0) {
            stmt[stmt_len] = ' ';
            stmt_len += 1;
        }
        @memcpy(stmt[stmt_len .. stmt_len + raw_len], raw[0..raw_len]);
        stmt[stmt_len + raw_len] = 0;
        stmt_len += raw_len;

        if (!tomlStatementComplete(zc(&stmt)))
            continue;

        if (!tomlProcessStatement(config, zc(&stmt), stmt_line, full_path, &section))
            parse_correct = false;
        stmt_len = 0;
        stmt[0] = 0;
    }

    if (stmt_len > 0 and
        !tomlProcessStatement(config, zc(&stmt), stmt_line, full_path, &section))
        parse_correct = false;

    if (!tomlSectionFlush(config, &section, full_path))
        parse_correct = false;

    return parse_correct;
}

// ---------------------------------------------------------------------------
// tests (stub-backed: tests/toml_parse_stub.c)
// ---------------------------------------------------------------------------

const testing = std.testing;

extern var stub_apply_calls: c_int;
extern var stub_apply_keys: [64][256]u8;
extern var stub_apply_values: [64][4096]u8;
extern var stub_apply_lines: [64]c_int;
extern var stub_parse_calls: c_int;
extern var stub_parse_names: [16][256]u8;
extern var stub_parse_pairs: [16][8192]u8;
extern var stub_parse_lines: [16]c_int;
extern var stub_report_calls: c_int;
extern var stub_error_calls: c_int;
extern var stub_expand_calls: c_int;
extern var stub_expand_value: [256]u8;
extern var stub_fail_key: [256]u8;
extern var stub_fail_rule: c_int;

extern "c" fn tmpfile() ?*c.FILE;
extern "c" fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: *c.FILE) usize;
extern "c" fn rewind(stream: *c.FILE) void;
extern "c" fn fclose(stream: *c.FILE) c_int;

fn resetStub() void {
    stub_apply_calls = 0;
    stub_parse_calls = 0;
    stub_report_calls = 0;
    stub_error_calls = 0;
    stub_expand_calls = 0;
    stub_expand_value[0] = 0;
    stub_fail_key[0] = 0;
    stub_fail_rule = 0;
}

fn parseText(config: *Config, text: []const u8) bool {
    const file = tmpfile() orelse @panic("tmpfile failed");
    defer _ = fclose(file);
    _ = fwrite(text.ptr, 1, text.len, file);
    rewind(file);
    return parse_toml_stream(config, file, "/tmp/test.toml");
}

fn applyKey(i: usize) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(&stub_apply_keys[i])));
}

fn applyValue(i: usize) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(&stub_apply_values[i])));
}

fn parseName(i: usize) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(&stub_parse_names[i])));
}

fn parsePairs(i: usize) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(&stub_parse_pairs[i])));
}

test "toml: scalars, comments, escapes and quoted strings" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\# top comment
        \\border_width = 2
        \\smartgaps = true
        \\foo = "a\nb"
        \\bar = 'raw # not comment'
        \\quoted = "escaped \"quote\""
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 5), stub_apply_calls);

    try testing.expectEqualStrings("border_width", applyKey(0));
    try testing.expectEqualStrings("2", applyValue(0));
    try testing.expectEqual(@as(c_int, 2), stub_apply_lines[0]);

    try testing.expectEqualStrings("smartgaps", applyKey(1));
    try testing.expectEqualStrings("1", applyValue(1));

    try testing.expectEqualStrings("foo", applyKey(2));
    try testing.expectEqualStrings("a\nb", applyValue(2));

    try testing.expectEqualStrings("bar", applyKey(3));
    try testing.expectEqualStrings("raw # not comment", applyValue(3));

    try testing.expectEqualStrings("quoted", applyKey(4));
    try testing.expectEqualStrings("escaped \"quote\"", applyValue(4));
}

test "toml: arrays apply per element and configured keys join" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\animation_curve_foo = [1, 2, 3]
        \\tags = ["a", "b"]
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 3), stub_apply_calls);

    try testing.expectEqualStrings("animation_curve_foo", applyKey(0));
    try testing.expectEqualStrings("1,2,3", applyValue(0));

    try testing.expectEqualStrings("tags", applyKey(1));
    try testing.expectEqualStrings("a", applyValue(1));
    try testing.expectEqualStrings("tags", applyKey(2));
    try testing.expectEqualStrings("b", applyValue(2));
}

test "toml: env and var sections keep their value formatting" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\[env]
        \\FOO = "bar baz"
        \\[var]
        \\X = 'one'
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 2), stub_apply_calls);
    try testing.expectEqualStrings("env", applyKey(0));
    try testing.expectEqualStrings("FOO,bar baz", applyValue(0));
    try testing.expectEqualStrings("var", applyKey(1));
    try testing.expectEqualStrings("X,one", applyValue(1));
}

test "toml: keybind sections build prefixes, flags and restore keymode" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);
    setTrunc(&config.keymode, "default", 27);

    const text =
        \\[bind.default]
        \\SUPER+Q = "spawn kitty"
        \\[bind.resize.sym.pass]
        \\SUPER+H = ["resize left", "resize right"]
        \\[keybind.default]
        \\A = "killclient"
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 4), stub_apply_calls);
    try testing.expectEqualStrings("bind", applyKey(0));
    try testing.expectEqualStrings("SUPER,Q,spawn kitty", applyValue(0));
    try testing.expectEqualStrings("bindsp", applyKey(1));
    try testing.expectEqualStrings("SUPER,H,resize left", applyValue(1));
    try testing.expectEqualStrings("bindsp", applyKey(2));
    try testing.expectEqualStrings("SUPER,H,resize right", applyValue(2));
    try testing.expectEqualStrings("bind", applyKey(3));
    try testing.expectEqualStrings("none,A,killclient", applyValue(3));
    try testing.expectEqualStrings("default", std.mem.sliceTo(&config.keymode, 0));
}

test "toml: mouse, switch and gesture bind prefixes" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\[mousebind.default]
        \\SUPER+BTN_LEFT = "movewindow"
        \\[switchbind.default]
        \\lid = "toggle"
        \\[gesturebind.default]
        \\SUPER+3+up = "workspace 1"
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 3), stub_apply_calls);
    try testing.expectEqualStrings("mousebind", applyKey(0));
    try testing.expectEqualStrings("SUPER,BTN_LEFT,movewindow", applyValue(0));
    try testing.expectEqualStrings("switchbind", applyKey(1));
    try testing.expectEqualStrings("lid,toggle", applyValue(1));
    try testing.expectEqualStrings("gesturebind", applyKey(2));
    try testing.expectEqualStrings("SUPER,3,up,workspace 1", applyValue(2));
}

test "toml: rule sections accumulate pairs and flush to parse_option" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\[window_rule]
        \\class = "foo"
        \\tags = 2
        \\[device_rule]
        \\name = "mouse"
        \\[global]
        \\border_width = 1
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 2), stub_parse_calls);
    try testing.expectEqualStrings("window_rule", parseName(0));
    try testing.expectEqualStrings("class:foo,tags:2", parsePairs(0));
    try testing.expectEqualStrings("device_rule", parseName(1));
    try testing.expectEqualStrings("name:mouse", parsePairs(1));
    // [global] writes plain options, not rule pairs
    try testing.expectEqual(@as(c_int, 1), stub_apply_calls);
    try testing.expectEqualStrings("border_width", applyKey(0));
    try testing.expectEqualStrings("1", applyValue(0));
}

test "toml: multi-line arrays are joined before applying" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\[bind.default]
        \\SUPER+Q = [
        \\  "spawn a",
        \\  "spawn b"
        \\]
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 2), stub_apply_calls);
    try testing.expectEqualStrings("bind", applyKey(0));
    try testing.expectEqualStrings("SUPER,Q,spawn a", applyValue(0));
    try testing.expectEqualStrings("bind", applyKey(1));
    try testing.expectEqualStrings("SUPER,Q,spawn b", applyValue(1));
    try testing.expectEqual(@as(c_int, 2), stub_apply_lines[0]);
}

test "toml: quoted keys are stripped" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);

    const text =
        \\"foo bar" = 1
        \\'baz' = true
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 2), stub_apply_calls);
    try testing.expectEqualStrings("foo bar", applyKey(0));
    try testing.expectEqualStrings("1", applyValue(0));
    try testing.expectEqualStrings("baz", applyKey(1));
    try testing.expectEqualStrings("1", applyValue(1));
}

test "toml: expand_config_variables applies to rule values" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);
    setTrunc(&stub_expand_value, "/home/user", 255);

    const text =
        \\[window_rule]
        \\class = "$HOME"
    ;

    try testing.expect(parseText(&config, text));
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqualStrings("class:/home/user", parsePairs(0));
    try testing.expect(stub_expand_calls > 0);
}

test "toml: errors are reported and parsing continues" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);
    setTrunc(&stub_fail_key, "bad", 255);

    const text =
        \\bad = 1
        \\good = 2
    ;

    try testing.expect(!parseText(&config, text));
    try testing.expectEqual(@as(c_int, 2), stub_apply_calls);
    try testing.expectEqual(@as(c_int, 1), stub_report_calls);
    try testing.expectEqualStrings("good", applyKey(1));

    resetStub();
    try testing.expect(!parseText(&config, "[nope]\nfoo = 1\n"));
    try testing.expect(stub_report_calls > 0);
    try testing.expect(stub_error_calls > 0);

    resetStub();
    try testing.expect(!parseText(&config, "[bind.default.bad]\nA = \"x\"\n"));
    try testing.expect(stub_report_calls > 0);

    resetStub();
    try testing.expect(!parseText(&config, "[bind]\nA = \"x\"\n"));
    try testing.expect(stub_error_calls > 0);

    resetStub();
    try testing.expect(!parseText(&config, "justtext\n"));
    try testing.expect(stub_report_calls > 0);
}

test "toml: failing rule flush marks the parse incorrect" {
    resetStub();
    var config: Config = std.mem.zeroes(Config);
    stub_fail_rule = 1;

    const text =
        \\[window_rule]
        \\class = "foo"
    ;

    try testing.expect(!parseText(&config, text));
    try testing.expectEqual(@as(c_int, 1), stub_parse_calls);
    try testing.expectEqual(@as(c_int, 1), stub_report_calls);
}
