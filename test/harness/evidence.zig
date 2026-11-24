//! Durable diagnostic artifacts for explicitly invoked live test runs.
const std = @import("std");
const output = @import("output.zig");

pub const Phase = enum { generation, evaluation };
pub const Artifact = enum { request, response, context, model_output, outcome };

/// The layout of a run's call evidence: `evidence/<phase>/call-<ordinal>/<artifact file>`. `Store.path` and
/// the offline readers share these names, so a moved path fails to compile rather than reading as no calls.
pub const root_directory = "evidence";
pub const call_prefix = "call-";

/// The directory that holds one phase's calls.
pub fn phaseDirectory(comptime phase: Phase) []const u8 {
    return root_directory ++ "/" ++ @tagName(phase);
}

pub fn artifactFile(artifact: Artifact) []const u8 {
    return switch (artifact) {
        .request => "request.json",
        .response => "response.json",
        .context => "context.json",
        .model_output => "model_output.txt",
        .outcome => "outcome.json",
    };
}

pub const Store = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    run: std.Io.Dir,
    secrets: []const []const u8,

    pub fn path(a: std.mem.Allocator, phase: Phase, ordinal: usize, artifact: Artifact) ![]const u8 {
        return std.fmt.allocPrint(a, "{s}/{s}/{s}{d:0>6}/{s}", .{ root_directory, @tagName(phase), call_prefix, ordinal, artifactFile(artifact) });
    }

    pub fn write(self: Store, phase: Phase, ordinal: usize, artifact: Artifact, bytes: []const u8) !void {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const target = try path(a, phase, ordinal, artifact);
        try self.run.createDirPath(self.io, std.fs.path.dirname(target).?);
        // Bodies are exact except for explicitly known credentials. HTTP headers,
        // authorization leases and environment maps are never captured.
        try output.write(self.io, self.run, target, try self.redact(a, bytes));
    }

    /// Owned redacted bytes for both evidence files and retained report metadata.
    pub fn redact(self: Store, a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
        var safe = try a.dupe(u8, bytes);
        errdefer a.free(safe);
        for (self.secrets) |secret| if (secret.len != 0) {
            const plain = try std.mem.replaceOwned(u8, a, safe, secret, "[REDACTED_CREDENTIAL]");
            a.free(safe);
            safe = plain;
            const encoded = try std.json.Stringify.valueAlloc(a, secret, .{});
            defer a.free(encoded);
            const quoted = try std.mem.replaceOwned(u8, a, safe, encoded[1 .. encoded.len - 1], "[REDACTED_CREDENTIAL]");
            a.free(safe);
            safe = quoted;
        };
        return safe;
    }
};
