const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const source = @import("../../ports/engine_config_source.zig");

pub const Error = error{EngineConfigReadError};

pub const Action = struct {
    locator: source.Locator,

    pub const contract: pipeline.NodeContract = .{
        .id = "locate-exact-engine-config@1",
        .kind = .action,
        .requires = &.{.invocation_working_directory},
        .produces = &.{.exact_engine_config},
        .side_effect = .filesystem_read,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator) Error!source.ExactEngineConfig {
        return self.locator.locate(allocator) catch error.EngineConfigReadError;
    }
};

test "maps locator rejection without taking on read work" {
    var fake = RejectingLocator{};
    const action: Action = .{ .locator = fake.port() };

    try std.testing.expectError(
        error.EngineConfigReadError,
        action.execute(std.testing.allocator),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

const RejectingLocator = struct {
    calls: usize = 0,

    fn port(self: *RejectingLocator) source.Locator {
        return .{
            .context = self,
            .locate_fn = locate,
        };
    }

    fn locate(context: *anyopaque, _: std.mem.Allocator) source.Error!source.ExactEngineConfig {
        const self: *RejectingLocator = @ptrCast(@alignCast(context));
        self.calls += 1;
        return error.EngineConfigReadFailure;
    }
};
