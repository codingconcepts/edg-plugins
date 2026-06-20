const edg = @import("edg");

fn slug(input: []const u8) []const u8 {
    var pos: usize = 0;
    for (input) |c| {
        if (pos >= edg.result_buf.len) break;
        if (c >= 'A' and c <= 'Z') {
            edg.result_buf[pos] = c + 32;
            pos += 1;
        } else if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')) {
            edg.result_buf[pos] = c;
            pos += 1;
        } else if (c == ' ' or c == '_') {
            if (pos > 0 and edg.result_buf[pos - 1] != '-') {
                edg.result_buf[pos] = '-';
                pos += 1;
            }
        }
    }
    while (pos > 0 and edg.result_buf[pos - 1] == '-') pos -= 1;
    return edg.result_buf[0..pos];
}

fn rot13(input: []const u8) []const u8 {
    const len = @min(input.len, edg.result_buf.len);
    for (input[0..len], 0..) |c, i| {
        if (c >= 'a' and c <= 'z') {
            edg.result_buf[i] = 'a' + (c - 'a' + 13) % 26;
        } else if (c >= 'A' and c <= 'Z') {
            edg.result_buf[i] = 'A' + (c - 'A' + 13) % 26;
        } else {
            edg.result_buf[i] = c;
        }
    }
    return edg.result_buf[0..len];
}

const p = edg.plugin(.{
    .name = "zig_example",
    .functions = .{
        .{ .name = "slug", .handler = slug, .desc = "Convert a string to a URL-friendly slug.", .example = "slug('Hello World')" },
        .{ .name = "rot13", .handler = rot13, .desc = "Apply ROT13 cipher to a string.", .example = "rot13('Hello')" },
    },
});

export fn alloc(size: i32) i32 {
    return edg.allocImpl(size);
}
export fn describe() i64 {
    return p.describe();
}
export fn call(fn_id: i32, arg_ptr: i32, arg_len: i32) i64 {
    return p.call(fn_id, arg_ptr, arg_len);
}
export fn seed_rng(seed: i64) void {
    edg.seedRng(seed);
}
