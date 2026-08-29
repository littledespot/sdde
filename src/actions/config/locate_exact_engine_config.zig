const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const engine_config_source = @import("../../ports/engine_config_source.zig");

pub const Error = error{EngineConfigReadError};

pub const Action = struct {
    locator: engine_config_source.Locator,

    pub const contract: pipeline.NodeContract = .{
        .id = "locate-exact-engine-config@1",
        .kind = .action,
        .requires = &.{.invocation_working_directory},
        .produces = &.{.exact_engine_config_file},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
    ) Error!engine_config_source.ExactEngineConfigFile {
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

    fn port(self: *RejectingLocator) engine_config_source.Locator {
        return .{
            .context = self,
            .locate_fn = locate,
        };
    }

    fn locate(
        context: *anyopaque,
        _: std.mem.Allocator,
    ) engine_config_source.Error!engine_config_source.ExactEngineConfigFile {
        const self: *RejectingLocator = @ptrCast(@alignCast(context));
        self.calls += 1;
        return error.EngineConfigReadFailure;
    }
};
