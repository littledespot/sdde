//! Packet guidance for tests: the shipped workflow resource, or marked guidance
//! whose every entry reads "MOCK <path>" so a test can prove each placement.
const std = @import("std");
const guidance = @import("../domain/packet_guidance.zig");

pub const shipped_path = "design/workflows/spec/packet-guidance.json";

/// The shipped resource compiled through its owner. Use an arena allocator.
pub fn shipped(allocator: std.mem.Allocator) !*const guidance.Compiled {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, shipped_path, allocator, .limited(guidance.max_bytes));
    return guidance.compile(allocator, bytes);
}

/// Every entry is "MOCK " followed by its dotted wire path, validated by the
/// owner at compile time.
pub const marked: guidance.Guidance = validated: {
    @setEvalBranchQuota(1_000_000);
    break :validated guidance.fromWire(mark(guidance.Wire, "")) catch unreachable;
};

/// The marked wire document, for tests that exercise the compiled resource path.
pub fn markedJson(allocator: std.mem.Allocator) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, comptime mark(guidance.Wire, ""), .{});
}

fn mark(comptime T: type, comptime path: []const u8) T {
    @setEvalBranchQuota(100_000);
    if (T == []const u8) return "MOCK " ++ path;
    return switch (@typeInfo(T)) {
        .@"enum" => |info| if (info.fields.len == 1) @enumFromInt(info.fields[0].value) else @compileError("a marked wire enum is its version"),
        .@"struct" => |info| result: {
            var result: T = undefined;
            for (info.fields) |field| @field(result, field.name) = mark(field.type, if (path.len == 0) field.name else path ++ "." ++ field.name);
            break :result result;
        },
        else => @compileError("packet guidance holds only texts"),
    };
}
