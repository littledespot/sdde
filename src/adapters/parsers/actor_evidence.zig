const std = @import("std");
const evidence = @import("../../domain/actor_evidence.zig");
const port = @import("../../ports/actor_evidence_parser.zig");
const strict_json = @import("../../domain/strict_json.zig");

pub fn parser() port.Parser {
    return .{ .parse_fn = parse };
}

fn parse(allocator: std.mem.Allocator, bytes: []const u8) evidence.Error!evidence.Registry {
    return strict_json.decode(evidence.Registry, allocator, bytes, .{
        .maximum_bytes = evidence.max_bytes,
        .maximum_depth = evidence.max_depth,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidActorEvidence,
    };
}

test "the parser admits only the registry's closed document" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const empty = try evidence.encode(a, evidence.empty(@import("../../domain/feature_identity.zig").FeatureId.parse("Chosen/Café").?));
    const decoded = try parser().parse(a, empty);
    try std.testing.expectEqual(@as(u64, 0), decoded.revision);
    for ([_][]const u8{ "", "[]", "{}", "{\"schema\":\"actor-evidence-registry/v1\"}", "not json" }) |bad| {
        try std.testing.expectError(error.InvalidActorEvidence, parser().parse(a, bad));
    }
}
