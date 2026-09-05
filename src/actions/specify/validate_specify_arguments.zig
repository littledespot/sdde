const selector = @import("../../domain/specify_invocation.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-specify-arguments@1",
        .kind = .action,
        .requires = &.{.parsed_specify_invocation},
        .produces = &.{.specify_invocation},
        .side_effect = .none,
    };

    pub fn execute(_: Action, parsed: selector.ParsedInvocation) selector.Error!selector.Invocation {
        const reference = parsed.reference orelse return error.InvalidSpecifyArguments;
        const feature = parsed.feature orelse return error.InvalidSpecifyArguments;
        for ([_][]const u8{ reference, feature }) |value| {
            if (value.len == 0 or value.len > @import("../../domain/relative_directory_path.zig").max_bytes or value[0] == '-') return error.InvalidSpecifyArguments;
        }
        return .{ .raw_reference = reference, .raw_feature = feature };
    }
};
