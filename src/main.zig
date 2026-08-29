const std = @import("std");
const sdde = @import("sdde");

pub fn main(init: std.process.Init) !void {
    var outcome = sdde.run(init.io, init.gpa);
    defer outcome.deinit();

    switch (outcome) {
        .ready => return,
        .failed => |failure| {
            var stderr_buffer: [256]u8 = undefined;
            var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
            const stderr = &stderr_file_writer.interface;
            try stderr.writeAll(failure.text());
            try stderr.writeByte('\n');
            try stderr.flush();
            std.process.exit(1);
        },
    }
}
