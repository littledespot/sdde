const selector = @import("../../domain/reference_selector.zig");
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
        if (parsed.count != 1) return error.InvalidSpecifyArguments;
        const reference = parsed.reference orelse return error.InvalidSpecifyArguments;
        if (reference.len == 0 or reference.len > selector.max_bytes or reference[0] == '-') return error.InvalidSpecifyArguments;
        return .{ .raw_reference = reference };
    }
};
