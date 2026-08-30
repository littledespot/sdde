const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    _ = package_directory.add(".sddtoolkit.json",
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "specs", "references": "references",
        \\    "specsArchive": "specs/_archive", "workflows": ".sddtoolkit/workflows",
        \\    "toolchainPreset": ".sddtoolkit/toolchainPreset",
        \\    "principles": ".sddtoolkit/principles", "templates": ".sddtoolkit/templates"
        \\  }
        \\}
    );
    _ = package_directory.add(".sddtoolkit/workflows/features/.keep", "");
    _ = package_directory.add(".sddtoolkit/workflows/hello.workflow.yaml",
        \\schemaVersion: "1.0"
        \\workflowId: hello
        \\workflowVersion: 1
        \\workflowShortcode: HELO
        \\invocationContractNodeId: core.empty-invocation@1
        \\workflowPolicyProfileId: core.capability-free@1
        \\entryWorkflowNodeId: run
        \\nodes:
        \\  - workflowNodeId: run
        \\    pipelineNodeContractId: core.noop@1
        \\    parameters: []
        \\transitions:
        \\  - fromWorkflowNodeId: run
        \\    outcomeTag: ok
        \\    target:
        \\      kind: terminal
        \\      outcomeTag: ok
    );
    _ = package_directory.add(".sddtoolkit/toolchainPreset/core.toolchain-preset.yaml",
        \\schema: toolchain-preset/v1
        \\package: core@1.0.0
        \\layer: environment
        \\extends: []
        \\policies: []
    );
    _ = package_directory.add(".sddtoolkit/principles/toolchain.yaml",
        \\schema: project-toolchain/v1
        \\presets: []
        \\policies: []
    );

    const valid_command = std.Build.Step.Run.create(b, "run packaged SDDE executable");
    valid_command.addFileArg(packaged_executable);
    valid_command.addArg("hello");
    valid_command.setCwd(package_directory.getDirectory());
    valid_command.clearEnvironment();
    valid_command.expectStdOutEqual("");
    valid_command.expectStdErrEqual("");

    const missing_config_directory = b.addTempFiles();
    const executable_without_config = missing_config_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const missing_config_command = std.Build.Step.Run.create(
        b,
        "reject packaged SDDE invocation without target config",
    );
    missing_config_command.step.dependOn(&valid_command.step);
    missing_config_command.addFileArg(executable_without_config);
    missing_config_command.addArg("hello");
    missing_config_command.setCwd(missing_config_directory.getDirectory());
    missing_config_command.clearEnvironment();
    missing_config_command.expectExitCode(1);
    missing_config_command.expectStdOutEqual("");
    missing_config_command.expectStdErrEqual("ENGINE_CONFIG_READ_ERROR\n");

    return missing_config_command;
}
