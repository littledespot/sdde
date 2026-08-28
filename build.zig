const std = @import("std");
const builtin = @import("builtin");
const zig_version = @import("build/zig_version.zig");
const packaging_smoke = @import("test/packaging/smoke.zig");

comptime {
    if (!zig_version.isSupported(builtin.zig_version)) {
        @compileError("SDDE requires Zig 0.16.0 exactly");
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const yaml_dependency = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    const yaml_module = yaml_dependency.module("yaml");
    const toolchain_yaml_syntax_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/parsers/yaml_syntax.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yaml", .module = yaml_module },
        },
    });

    const sdde_module = b.addModule("sdde", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "toolchain_yaml_syntax", .module = toolchain_yaml_syntax_module },
        },
    });

    const executable = b.addExecutable(.{
        .name = "sdde",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdde", .module = sdde_module },
            },
        }),
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run SDDE");
    run_step.dependOn(&run_command.step);

    const module_tests = b.addTest(.{
        .root_module = sdde_module,
    });
    const run_module_tests = b.addRunArtifact(module_tests);

    const executable_tests = b.addTest(.{
        .root_module = executable.root_module,
    });
    const run_executable_tests = b.addRunArtifact(executable_tests);

    const config_reader_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/adapters/filesystem/engine_config_reader.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_config_reader_tests = b.addRunArtifact(config_reader_tests);

    const yaml_safety_tests = b.addTest(.{
        .root_module = toolchain_yaml_syntax_module,
    });
    const run_yaml_safety_tests = b.addRunArtifact(yaml_safety_tests);

    const version_policy_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/zig_version.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_version_policy_tests = b.addRunArtifact(version_policy_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_module_tests.step);
    test_step.dependOn(&run_executable_tests.step);
    test_step.dependOn(&run_config_reader_tests.step);
    test_step.dependOn(&run_yaml_safety_tests.step);
    test_step.dependOn(&run_version_policy_tests.step);

    const smoke_command = packaging_smoke.add(b, executable);
    const smoke_step = b.step("smoke", "Test the packaged executable in a clean directory");
    smoke_step.dependOn(&smoke_command.step);

    const lint_command = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "fmt",
        "--check",
        "--ast-check",
    });
    lint_command.setName("lint Zig source");
    lint_command.addFileArg(b.path("build.zig"));
    lint_command.addFileArg(b.path("build.zig.zon"));
    lint_command.addDirectoryArg(b.path("build"));
    lint_command.addDirectoryArg(b.path("src"));
    lint_command.addDirectoryArg(b.path("test"));

    const lint_step = b.step("lint", "Check Zig formatting and AST validity");
    lint_step.dependOn(&lint_command.step);

    const verify_step = b.step("verify", "Run all repository verification");
    verify_step.dependOn(lint_step);
    verify_step.dependOn(test_step);
    verify_step.dependOn(smoke_step);
}
