const std = @import("std");

pub fn build(b: *std.Build) void {
    const edg_dep = b.dependency("edg_plugin", .{});

    const exe = b.addExecutable(.{
        .name = "zig_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
            }),
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "edg", .module = edg_dep.module("edg") },
            },
        }),
    });
    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);
}
