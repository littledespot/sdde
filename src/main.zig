const std = @import("std");
const sdde = @import("sdde");

pub fn main(init: std.process.Init) !void {
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iterator.deinit();
    _ = iterator.skip();
    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(init.gpa);
    while (iterator.next()) |argument| {
        try arguments.append(init.gpa, try init.arena.allocator().dupe(u8, argument));
    }

    const outcome = sdde.run(init.io, init.gpa, arguments.items);

    switch (outcome) {
        .execution => |execution| switch (execution) {
            .ok => return,
            .needs_user, .invalid, .blocked, .failed, .cancelled => {
                try writeFailure(init.io, @tagName(execution));
                std.process.exit(1);
            },
        },
        .bootstrap_failed => |failure| {
            var stderr_buffer: [256]u8 = undefined;
            var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
            const stderr = &stderr_file_writer.interface;
            try stderr.writeAll(failure.text());
            try stderr.writeByte('\n');
            try stderr.flush();
            std.process.exit(1);
        },
        .invocation_invalid => {
            try writeFailure(init.io, "invalid");
            std.process.exit(1);
        },
    }
}

fn writeFailure(io: std.Io, text: []const u8) !void {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;
    try stderr.writeAll(text);
    try stderr.writeByte('\n');
    try stderr.flush();
}
