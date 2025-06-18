const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target_query = std.Target.Query{
    //     .abi = .eabi,
    //     .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
    //     .cpu_arch = .thumb,
    //     .os_tag = .freestanding,
    // };
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        // .target = b.resolveTargetQuery(target_query),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "possum",
        .root_module = exe_mod,
    });

    exe.linkLibC();

    b.installArtifact(exe);
}
