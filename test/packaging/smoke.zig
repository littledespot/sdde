const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const configuration =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "requirements/current", "references": "references",
        \\    "specsArchive": "requirements/current/_archive", "workflows": ".sddtoolkit/workflows",
        \\    "toolchainPreset": ".sddtoolkit/toolchainPreset",
        \\    "principles": ".sddtoolkit/principles", "templates": ".sddtoolkit/templates",
        \\    "providers": ".sddproviders.json"
        \\  }
        \\}
    ;
    _ = package_directory.add(".sddtoolkit.json", configuration);
    _ = package_directory.add(".sddtoolkit/workflows/features/.keep", "");
    const hello_workflow =
        \\schema: workflow/v1
        \\id: hello
        \\version: 1
        \\shortcode: HELO
        \\invoke: core.empty-invocation@1
        \\policy: core.capability-free@1
        \\start: run
        \\steps:
        \\  run:
        \\    use: core.noop@1
        \\    on: { ok: end.ok }
    ;
    _ = package_directory.add(".sddtoolkit/workflows/transactions/hello.workflow.yaml", hello_workflow);
    _ = package_directory.add(".sddtoolkit/workflows/toolchain.workflow.yaml", @embedFile("../../src/test_fixtures/toolchain.workflow.yaml"));
    _ = package_directory.add(".sddtoolkit/workflows/preflight.workflow.yaml", @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"));
    _ = package_directory.add(".sddtoolkit/workflows/feature-input.workflow.yaml", @embedFile("../../src/test_fixtures/feature-input-preflight.workflow.yaml"));
    const clarification = @import("../../src/test_fixtures/clarification_inputs.zig").closed(b.allocator, "P01", true) catch @panic("allocate packaging clarification fixture");
    _ = package_directory.add(".sddtoolkit/workflows/features/Chosen/Café/state/clarifications.json", clarification.state.?);
    _ = package_directory.add("requirements/current/Chosen/Café/clarify/P01.md", clarification.forms[0].bytes);
    _ = package_directory.add("requirements/current/Orphan/clarify/P01.md", clarification.forms[0].bytes);
    _ = package_directory.add("references/Café/日本語/stories.md", "Hello, World!\n");
    // A hard-coded specs root would select this non-directory and fail.
    _ = package_directory.add("specs/Selected/日本語", "not a directory\n");
    _ = package_directory.add(".sddtoolkit/toolchainPreset/core.toolchain-preset.yaml", "invalid unselected preset");
    _ = package_directory.add(".sddtoolkit/principles/toolchain.yaml", "invalid unselected project layer");

    const valid_command = std.Build.Step.Run.create(b, "run packaged SDDE executable");
    valid_command.addFileArg(packaged_executable);
    valid_command.addArg("hello");
    valid_command.setCwd(package_directory.getDirectory());
    valid_command.clearEnvironment();
    valid_command.expectStdOutEqual("");
    valid_command.expectStdErrEqual("");

    const unregistered_directory = b.addTempFiles();
    const unregistered_executable = unregistered_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = unregistered_directory.add(".sddtoolkit.json", configuration);
    _ = unregistered_directory.add(".sddtoolkit/workflows/hello.workflow.yaml", hello_workflow);
    _ = unregistered_directory.add(".sddtoolkit/workflows/transactions/unregistered.json", "{}");
    const denied_unregistered = std.Build.Step.Run.create(b, "reject unregistered files beneath an ordinary packaged workflow directory");
    denied_unregistered.addFileArg(unregistered_executable);
    denied_unregistered.addArg("hello");
    denied_unregistered.setCwd(unregistered_directory.getDirectory());
    denied_unregistered.clearEnvironment();
    denied_unregistered.expectExitCode(1);
    denied_unregistered.expectStdOutEqual("");
    denied_unregistered.expectStdErrEqual("WORKFLOW_AUTHORITY_INVENTORY_INVALID\n");

    const denied_toolchain = std.Build.Step.Run.create(b, "reject invalid toolchain only when selected");
    denied_toolchain.addFileArg(packaged_executable);
    denied_toolchain.addArg("toolchain-check");
    denied_toolchain.setCwd(package_directory.getDirectory());
    denied_toolchain.clearEnvironment();
    denied_toolchain.expectExitCode(1);
    denied_toolchain.expectStdOutEqual("");
    denied_toolchain.expectStdErrEqual("failed\n");

    const toolchain_directory = b.addTempFiles();
    const toolchain_executable = toolchain_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = toolchain_directory.add(".sddtoolkit.json", configuration);
    _ = toolchain_directory.add(".sddtoolkit/workflows/toolchain.workflow.yaml", @embedFile("../../src/test_fixtures/toolchain.workflow.yaml"));
    _ = toolchain_directory.add(".sddtoolkit/principles/toolchain.yaml", "schema: project-toolchain/v1\npresets: [core@1.0.0]\npolicies: []\n");
    _ = toolchain_directory.add(".sddtoolkit/toolchainPreset/core.toolchain-preset.yaml", "schema: toolchain-preset/v1\npackage: core@1.0.0\nlayer: environment\nextends: []\npolicies: []\n");
    const toolchain_command = std.Build.Step.Run.create(b, "run packaged YAML-selected toolchain operations");
    toolchain_command.addFileArg(toolchain_executable);
    toolchain_command.addArg("toolchain-check");
    toolchain_command.setCwd(toolchain_directory.getDirectory());
    toolchain_command.clearEnvironment();
    toolchain_command.expectStdOutEqual("");
    toolchain_command.expectStdErrEqual("");

    const missing_config_directory = b.addTempFiles();
    const reference_command = std.Build.Step.Run.create(b, "run packaged config-root-relative feature and Unicode reference preflight");
    reference_command.addFileArg(packaged_executable);
    reference_command.addArgs(&.{ "reference-preflight", "--feature", "Selected/日本語", "--reference", "./Cafe\u{301}/日本語" });
    reference_command.setCwd(package_directory.getDirectory());
    reference_command.clearEnvironment();
    reference_command.expectStdOutEqual("");
    reference_command.expectStdErrEqual("");

    const denied_reference = std.Build.Step.Run.create(b, "reject packaged reference traversal");
    denied_reference.addFileArg(packaged_executable);
    denied_reference.addArgs(&.{ "reference-preflight", "--feature", "Selected/日本語", "--reference", "../references" });
    denied_reference.setCwd(package_directory.getDirectory());
    denied_reference.clearEnvironment();
    denied_reference.expectExitCode(1);
    denied_reference.expectStdOutEqual("");
    denied_reference.expectStdErrEqual("failed\n");
    const executable_without_config = missing_config_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const missing_config_command = std.Build.Step.Run.create(
        b,
        "reject packaged SDDE invocation without target config",
    );
    missing_config_command.step.dependOn(&valid_command.step);
    missing_config_command.step.dependOn(&denied_unregistered.step);
    missing_config_command.step.dependOn(&denied_toolchain.step);
    missing_config_command.step.dependOn(&toolchain_command.step);
    missing_config_command.step.dependOn(&reference_command.step);
    missing_config_command.step.dependOn(&denied_reference.step);
    for ([_]struct { feature: []const u8, rejected: bool }{
        .{ .feature = "Selected/日本語", .rejected = false },
        .{ .feature = "Chosen/Café", .rejected = false },
        .{ .feature = "Orphan", .rejected = true },
    }) |case| {
        const check = std.Build.Step.Run.create(b, "run packaged read-only clarification preflight");
        check.addFileArg(packaged_executable);
        check.addArgs(&.{ "feature-input-preflight", "--feature", case.feature, "--reference", "Café/日本語" });
        check.setCwd(package_directory.getDirectory());
        check.clearEnvironment();
        check.expectExitCode(if (case.rejected) 1 else 0);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(if (case.rejected) "failed\n" else "");
        missing_config_command.step.dependOn(&check.step);
    }
    for ([_][]const []const u8{
        &.{ "reference-preflight", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "../escape", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "_archive/child", "--reference", "Café/日本語" },
    }) |arguments| {
        const rejected = std.Build.Step.Run.create(b, "reject packaged invalid feature selection");
        rejected.addFileArg(packaged_executable);
        rejected.addArgs(arguments);
        rejected.setCwd(package_directory.getDirectory());
        rejected.clearEnvironment();
        rejected.expectExitCode(1);
        rejected.expectStdOutEqual("");
        rejected.expectStdErrEqual("failed\n");
        missing_config_command.step.dependOn(&rejected.step);
    }
    missing_config_command.addFileArg(executable_without_config);
    missing_config_command.addArg("hello");
    missing_config_command.setCwd(missing_config_directory.getDirectory());
    missing_config_command.clearEnvironment();
    missing_config_command.expectExitCode(1);
    missing_config_command.expectStdOutEqual("");
    missing_config_command.expectStdErrEqual("ENGINE_CONFIG_READ_ERROR\n");

    return missing_config_command;
}
