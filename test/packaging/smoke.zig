const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    _ = package_directory.add(".sddtoolkit.json",
        \\{
        \\  "version": "2.0",
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

    const smoke_command = std.Build.Step.Run.create(b, "run packaged SDDE executable");
    smoke_command.addFileArg(packaged_executable);
    smoke_command.setCwd(package_directory.getDirectory());
    smoke_command.clearEnvironment();
    smoke_command.expectStdOutEqual("");
    smoke_command.expectStdErrEqual("");

    return smoke_command;
}
