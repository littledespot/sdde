const std = @import("std");
const selector = @import("../../domain/reference_selector.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "parse-specify-invocation@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{.parsed_specify_invocation},
        .side_effect = .none,
    };

    pub fn execute(_: Action, arguments: []const []const u8) selector.Error!selector.ParsedInvocation {
        var result: selector.ParsedInvocation = .{ .reference = null, .count = 0 };
        var index: usize = 0;
        while (index < arguments.len) : (index += 2) {
            if (!std.mem.eql(u8, arguments[index], "--reference") or index + 1 == arguments.len) return error.InvalidSpecifyArguments;
            result.reference = arguments[index + 1];
            result.count += 1;
        }
        return result;
    }
};
