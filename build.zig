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
    const unicode_dependency = b.dependency("utf8proc", .{});
    const unicode_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/text/unicode_nfc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    unicode_module.addIncludePath(unicode_dependency.path(""));
    unicode_module.addCMacro("UTF8PROC_STATIC", "1");
    unicode_module.addCSourceFile(.{ .file = unicode_dependency.path("utf8proc.c"), .flags = &.{"-DUTF8PROC_STATIC"} });
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(unicode_dependency.path("LICENSE.md"), .prefix, "share/licenses/utf8proc/LICENSE.md").step);
    const yaml_dependency = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    const yaml_module = yaml_dependency.module("yaml");
    const bounded_yaml_syntax_module = b.createModule(.{
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
            .{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module },
            .{ .name = "unicode_nfc", .module = unicode_module },
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

    const yaml_safety_tests = b.addTest(.{
        .root_module = bounded_yaml_syntax_module,
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

    const architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/architecture_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_architecture_tests = b.addRunArtifact(architecture_tests);
    run_architecture_tests.setCwd(b.path("."));

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_module_tests.step);
    test_step.dependOn(&run_executable_tests.step);
    test_step.dependOn(&run_yaml_safety_tests.step);
    test_step.dependOn(&run_version_policy_tests.step);
    test_step.dependOn(&run_architecture_tests.step);
    const unicode_tests = b.addTest(.{ .root_module = unicode_module });
    const run_unicode_tests = b.addRunArtifact(unicode_tests);
    test_step.dependOn(&run_unicode_tests.step);

    const result_schema_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/model_result_schema_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const result_schema_step = b.step("test-model-result-schema", "Test the closed model result-schema boundary");
    result_schema_step.dependOn(&b.addRunArtifact(result_schema_tests).step);

    const reference_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_preflight_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_nfc", .module = unicode_module }},
    }) });
    const reference_step = b.step("test-reference-preflight", "Test Specify arguments and reference selector contracts");
    reference_step.dependOn(&b.addRunArtifact(reference_tests).step);
    reference_step.dependOn(&run_unicode_tests.step);

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
