const std = @import("std");

// ── Shared buffers ──────────────────────────────────────────────────

var alloc_buf: [65536]u8 = undefined;

/// Write function results into this buffer. It is separate from the
/// alloc buffer so serialisation cannot corrupt your return value.
pub var result_buf: [65536]u8 = undefined;

var rng_state: u64 = 0;

// ── WASM primitives ─────────────────────────────────────────────────

pub fn allocImpl(size: i32) i32 {
    _ = @as(usize, @intCast(@as(u32, @bitCast(size))));
    return @intCast(@intFromPtr(&alloc_buf));
}

pub fn seedRng(seed: i64) void {
    rng_state = @bitCast(seed);
}

/// SplitMix64 PRNG — same seed gives the same sequence.
pub fn rngU64() u64 {
    rng_state +%= 0x9e3779b97f4a7c15;
    var z = rng_state;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

/// Returns a random integer in [0, n).
pub fn rngIntn(n: u64) u64 {
    return rngU64() % n;
}

pub fn writeToMemory(data: []const u8) i64 {
    _ = allocImpl(@intCast(data.len));
    @memcpy(alloc_buf[0..data.len], data);
    const ptr: u64 = @intFromPtr(&alloc_buf);
    const len: u64 = data.len;
    return @bitCast((ptr << 32) | len);
}

pub fn writeError(msg: []const u8) i64 {
    var buf: [512]u8 = undefined;
    const prefix = "{\"error\":\"";
    const suffix = "\"}";
    const total = prefix.len + msg.len + suffix.len;
    if (total > buf.len) return writeToMemory("{\"error\":\"error too long\"}");
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len .. prefix.len + msg.len], msg);
    @memcpy(buf[prefix.len + msg.len .. total], suffix);
    return writeToMemory(buf[0..total]);
}

pub fn writeJsonString(s: []const u8) i64 {
    var buf: [65536]u8 = undefined;
    var pos: usize = 0;
    buf[pos] = '"';
    pos += 1;
    for (s) |c| {
        if (pos + 2 >= buf.len) return writeError("output too long");
        switch (c) {
            '"' => {
                buf[pos] = '\\';
                buf[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                buf[pos] = '\\';
                buf[pos + 1] = '\\';
                pos += 2;
            },
            else => {
                buf[pos] = c;
                pos += 1;
            },
        }
    }
    buf[pos] = '"';
    pos += 1;
    return writeToMemory(buf[0..pos]);
}

fn writeJsonInt(v: i64) i64 {
    var buf: [20]u8 = undefined;
    var n: u64 = undefined;
    var neg = false;
    if (v < 0) {
        neg = true;
        n = @intCast(-v);
    } else {
        n = @intCast(v);
    }
    var pos: usize = buf.len;
    if (n == 0) {
        pos -= 1;
        buf[pos] = '0';
    } else {
        while (n > 0) {
            pos -= 1;
            buf[pos] = @intCast('0' + n % 10);
            n /= 10;
        }
    }
    if (neg) {
        pos -= 1;
        buf[pos] = '-';
    }
    return writeToMemory(buf[pos..]);
}

fn writeJsonFloat(v: f64) i64 {
    var buf: [32]u8 = undefined;
    const result = std.fmt.formatFloat(buf[0..], v, .{ .mode = .decimal }) catch
        return writeError("float format error");
    return writeToMemory(result);
}

fn writeJsonBool(v: bool) i64 {
    return writeToMemory(if (v) "true" else "false");
}

// ── JSON arg extraction ─────────────────────────────────────────────

fn skipWhitespace(json: []const u8, start: usize) usize {
    var i = start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r')) : (i += 1) {}
    return i;
}

fn skipJsonValue(json: []const u8, start: usize) usize {
    const i_start = skipWhitespace(json, start);
    if (i_start >= json.len) return i_start;
    var i = i_start;
    switch (json[i]) {
        '"' => {
            i += 1;
            while (i < json.len) : (i += 1) {
                if (json[i] == '\\') {
                    i += 1;
                    continue;
                }
                if (json[i] == '"') return i + 1;
            }
            return i;
        },
        't' => return i + 4,
        'f' => return i + 5,
        'n' => return i + 4,
        else => {
            if (json[i] == '-') i += 1;
            while (i < json.len and ((json[i] >= '0' and json[i] <= '9') or json[i] == '.' or json[i] == 'e' or json[i] == 'E' or json[i] == '+' or json[i] == '-'))
                i += 1;
            return i;
        },
    }
}

const ArgRange = struct { start: usize, end: usize };

fn findNthArg(json: []const u8, n: usize) ?ArgRange {
    var i = skipWhitespace(json, 0);
    if (i >= json.len or json[i] != '[') return null;
    i = skipWhitespace(json, i + 1);

    var idx: usize = 0;
    while (i < json.len and json[i] != ']') {
        const s = skipWhitespace(json, i);
        const e = skipJsonValue(json, s);
        if (idx == n) return .{ .start = s, .end = e };
        i = skipWhitespace(json, e);
        if (i < json.len and json[i] == ',') i = skipWhitespace(json, i + 1);
        idx += 1;
    }
    return null;
}

fn extractString(json: []const u8, n: usize) ?[]const u8 {
    const range = findNthArg(json, n) orelse return null;
    if (range.start >= json.len or json[range.start] != '"') return null;
    return json[range.start + 1 .. range.end - 1];
}

fn extractInt(json: []const u8, n: usize) ?i64 {
    const range = findNthArg(json, n) orelse return null;
    const s = json[range.start..range.end];
    return std.fmt.parseInt(i64, s, 10) catch return null;
}

fn extractFloat(json: []const u8, n: usize) ?f64 {
    const range = findNthArg(json, n) orelse return null;
    const s = json[range.start..range.end];
    return std.fmt.parseFloat(f64, s) catch return null;
}

fn extractBool(json: []const u8, n: usize) ?bool {
    const range = findNthArg(json, n) orelse return null;
    const s = json[range.start..range.end];
    if (std.mem.eql(u8, s, "true")) return true;
    if (std.mem.eql(u8, s, "false")) return false;
    return null;
}

// ── Comptime type helpers ───────────────────────────────────────────

fn zigTypeToEdgName(comptime T: type) []const u8 {
    if (T == []const u8) return "string";
    if (T == i64) return "int";
    if (T == f64) return "float";
    if (T == bool) return "bool";
    @compileError("unsupported edg type: " ++ @typeName(T));
}

fn extractArg(comptime T: type, raw: []const u8, idx: usize) ?T {
    if (T == []const u8) return extractString(raw, idx);
    if (T == i64) return extractInt(raw, idx);
    if (T == f64) return extractFloat(raw, idx);
    if (T == bool) return extractBool(raw, idx);
    @compileError("unsupported edg type: " ++ @typeName(T));
}

fn serializeResult(comptime T: type, value: T) i64 {
    if (T == []const u8) return writeJsonString(value);
    if (T == i64) return writeJsonInt(value);
    if (T == f64) return writeJsonFloat(value);
    if (T == bool) return writeJsonBool(value);
    @compileError("unsupported edg return type: " ++ @typeName(T));
}

// ── Manifest builder (comptime) ─────────────────────────────────────

fn buildManifest(comptime config: anytype) []const u8 {
    comptime {
        var json: []const u8 = "{\"name\":\"" ++ config.name ++ "\",\"functions\":[";
        for (config.functions, 0..) |f, fi| {
            if (fi > 0) json = json ++ ",";
            json = json ++ "{\"name\":\"" ++ f.name ++ "\",\"description\":\"" ++ f.desc ++ "\",\"example\":\"" ++ escapeJsonComptime(f.example) ++ "\",\"params\":[";
            const fn_info = @typeInfo(@TypeOf(f.handler)).@"fn";
            for (fn_info.params, 0..) |p, pi| {
                if (pi > 0) json = json ++ ",";
                const tn = zigTypeToEdgName(p.type.?);
                json = json ++ "{\"name\":\"" ++ tn ++ "\",\"type\":\"" ++ tn ++ "\"}";
            }
            json = json ++ "],\"returns\":\"" ++ zigTypeToEdgName(fn_info.return_type.?) ++ "\"}";
        }
        json = json ++ "]}";
        return json;
    }
}

fn escapeJsonComptime(comptime s: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (s) |c| {
            if (c == '"') {
                out = out ++ "\\\"";
            } else if (c == '\\') {
                out = out ++ "\\\\";
            } else {
                out = out ++ &[_]u8{c};
            }
        }
        return out;
    }
}

// ── Plugin type generator ───────────────────────────────────────────

pub fn plugin(comptime config: anytype) type {
    const manifest = buildManifest(config);

    return struct {
        pub fn describe() i64 {
            return writeToMemory(manifest);
        }

        pub fn call(fn_id: i32, arg_ptr: i32, arg_len: i32) i64 {
            const ptr: [*]const u8 = @ptrFromInt(@as(usize, @intCast(@as(u32, @bitCast(arg_ptr)))));
            const raw = ptr[0..@as(usize, @intCast(@as(u32, @bitCast(arg_len))))];

            inline for (config.functions, 0..) |f, i| {
                if (fn_id == @as(i32, @intCast(i))) {
                    return dispatchOne(f.handler, raw);
                }
            }
            return writeError("invalid function ID");
        }
    };
}

fn dispatchOne(comptime handler: anytype, raw: []const u8) i64 {
    const fn_info = @typeInfo(@TypeOf(handler)).@"fn";
    const params = fn_info.params;

    var args: std.meta.ArgsTuple(@TypeOf(handler)) = undefined;
    inline for (params, 0..) |p, i| {
        args[i] = extractArg(p.type.?, raw, i) orelse
            return writeError("bad argument");
    }

    const result = @call(.auto, handler, args);
    return serializeResult(fn_info.return_type.?, result);
}
