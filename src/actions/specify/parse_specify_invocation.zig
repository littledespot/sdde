const std = @import("std");
const selector = @import("../../domain/specify_invocation.zig");
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
        var result: selector.ParsedInvocation = .{};
        var index: usize = 0;
        while (index < arguments.len) : (index += 2) {
            if (index + 1 == arguments.len) return error.InvalidSpecifyArguments;
            const slot = if (std.mem.eql(u8, arguments[index], "--reference"))
                &result.reference
            else if (std.mem.eql(u8, arguments[index], "--feature"))
                &result.feature
            else
                return error.InvalidSpecifyArguments;
            if (slot.* != null) return error.InvalidSpecifyArguments;
            slot.* = arguments[index + 1];
        }
        return result;
    }
};
