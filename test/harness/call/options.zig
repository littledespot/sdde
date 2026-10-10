const std = @import("std");

pub const Options = struct {
    run: []const u8,
    workflow: []const u8,
    call: u32,
    model: []const u8,
    reasoning_effort: ?[]const u8,
    repeats: u16 = 1,
};

pub fn parse(args: []const []const u8) !Options {
    const names = [_][]const u8{ "--run", "--workflow", "--call", "--model", "--reasoning-effort", "--repeats" };
    var values: [names.len]?[]const u8 = @splat(null);
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        if (i + 1 == args.len) return error.InvalidArguments;
        const index = for (names, 0..) |name, index| {
            if (std.mem.eql(u8, name, args[i])) break index;
        } else return error.InvalidArguments;
        if (values[index] != null or args[i + 1].len == 0) return error.InvalidArguments;
        values[index] = args[i + 1];
    }
    for (values[0..5]) |value| if (value == null) return error.InvalidArguments;
    try @import("../contracts.zig").path(values[0].?);
    if (@import("../../../src/domain/workflow.zig").WorkflowId.parse(values[1].?) == null or
        @import("../../../src/domain/llm_provider_identity.zig").ModelId.parse(values[3].?) == null) return error.InvalidArguments;
    const ordinal = try std.fmt.parseInt(u32, values[2].?, 10);
    const repeats = if (values[5]) |value| try std.fmt.parseInt(u16, value, 10) else 1;
    if (ordinal == 0 or repeats == 0) return error.InvalidArguments;
    return .{
        .run = values[0].?,
        .workflow = values[1].?,
        .call = ordinal,
        .model = values[3].?,
        .reasoning_effort = if (std.mem.eql(u8, values[4].?, "none")) null else values[4].?,
        .repeats = repeats,
    };
}
