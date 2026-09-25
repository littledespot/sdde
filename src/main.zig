const std = @import("std");
const sdde = @import("sdde");
pub const live_model_connections = true;

pub fn main(init: std.process.Init) !void {
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iterator.deinit();
    _ = iterator.skip();
    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(init.gpa);
    while (iterator.next()) |argument| {
        try arguments.append(init.gpa, try init.arena.allocator().dupe(u8, argument));
    }

    if (arguments.items.len > 0 and std.mem.eql(u8, arguments.items[0], "--debugger")) {
        if (arguments.items.len != 2) {
            try writeFailure(init.io, "Usage: sdde --debugger <feature-directory>");
            std.process.exit(1);
        }
        return sdde.debugRequests(init.io, init.gpa, arguments.items[1], init.environ_map) catch |err| {
            try writeFailure(init.io, @errorName(err));
            std.process.exit(1);
        };
    }
    var report = try sdde.run(init.io, init.gpa, arguments.items, init.environ_map);
    defer report.deinit();
    const outcome = report.outcome;

    switch (outcome) {
        .execution => |execution| switch (execution) {
            .ok => return,
            // Compiled graphs cannot terminate with a progress-only outcome.
            .more => unreachable,
            .needs_user => {
                try std.Io.File.stdout().writeStreamingAll(init.io, "Awaiting clarification. Answer the registered forms, then run the workflow again.\n");
                for (report.clarifications) |form| {
                    const name = form.id.filename();
                    const line = try std.fmt.allocPrint(init.arena.allocator(), "{s}: {s}\n", .{ name[0..3], form.path.project_relative });
                    try std.Io.File.stdout().writeStreamingAll(init.io, line);
                }
            },
            .invalid, .blocked, .failed, .cancelled => {
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
        .execution_rejected => |reason| {
            if (reason == .retry_limit) {
                const failure = reason.retry_limit;
                try writeFailure(init.io, try std.fmt.allocPrint(init.arena.allocator(), "RetryLimitExhausted: {s}; retry-limit={d}; completed executions={d}", .{ failure.operation().bytes, failure.limit.value, failure.completed_executions }));
            } else try writeFailure(init.io, reason.diagnostic());
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
