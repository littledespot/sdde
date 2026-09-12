//! Durable diagnostic artifacts for explicitly invoked live test runs.
const std = @import("std");
const output = @import("output.zig");

pub const Phase = enum { generation, evaluation };
pub const Artifact = enum { request, response, context, model_output, outcome };
pub const Store = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    run: std.Io.Dir,
    secrets: []const []const u8,

    pub fn path(a: std.mem.Allocator, phase: Phase, ordinal: usize, artifact: Artifact) ![]const u8 {
        return std.fmt.allocPrint(a, "evidence/{s}/call-{d:0>6}/{s}.{s}", .{
            @tagName(phase), ordinal, @tagName(artifact), if (artifact == .model_output) "txt" else "json",
        });
    }

    pub fn write(self: Store, phase: Phase, ordinal: usize, artifact: Artifact, bytes: []const u8) !void {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const target = try path(a, phase, ordinal, artifact);
        try self.run.createDirPath(self.io, std.fs.path.dirname(target).?);
        // Bodies are exact except for explicitly known credentials. HTTP headers,
        // authorization leases and environment maps are never captured.
        var safe = bytes;
        for (self.secrets) |secret| if (secret.len != 0) {
            safe = try std.mem.replaceOwned(u8, a, safe, secret, "[REDACTED_CREDENTIAL]");
            const encoded = try std.json.Stringify.valueAlloc(a, secret, .{});
            safe = try std.mem.replaceOwned(u8, a, safe, encoded[1 .. encoded.len - 1], "[REDACTED_CREDENTIAL]");
        };
        try output.write(self.io, self.run, target, safe);
    }
};
