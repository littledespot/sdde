const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );

    const smoke_command = std.Build.Step.Run.create(b, "run packaged SDDE executable");
    smoke_command.addFileArg(packaged_executable);
    smoke_command.setCwd(package_directory.getDirectory());
    smoke_command.clearEnvironment();
    smoke_command.expectStdOutEqual("Hello, world!\n");
    smoke_command.expectStdErrEqual("");

    return smoke_command;
}
