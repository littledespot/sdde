const std = @import("std");
const config = @import("../../domain/config.zig");
const pipeline = @import("../../domain/pipeline.zig");
const source = @import("../../ports/engine_config_source.zig");

pub const Error = error{EngineConfigReadError};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "read-engine-config@1",
        .kind = .action,
        .requires = &.{.exact_engine_config},
        .produces = &.{.raw_engine_config},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        _: Action,
        exact_config: *source.ExactEngineConfig,
        allocator: std.mem.Allocator,
    ) Error!source.RawEngineConfig {
        return exact_config.read(allocator, config.max_engine_config_bytes) catch {
            return error.EngineConfigReadError;
        };
    }
};

test "reads only through the exact-config capability at the compiler limit" {
    const allocator = std.testing.allocator;
    var fake = FakeExactConfig{};
    const canonical_root = try allocator.dupeZ(u8, "/validated/project");
    var exact = source.ExactEngineConfig.init(
        canonical_root,
        &fake,
        &fake_exact_config_vtable,
    );
    defer exact.deinit(allocator);

    var raw = try (Action{}).execute(&exact, allocator);
    defer raw.deinit(allocator);

    try std.testing.expectEqualStrings("{}", raw.bytes);
    try std.testing.expectEqual(@as(usize, 1), fake.read_calls);
    try std.testing.expectEqual(config.max_engine_config_bytes, fake.observed_limit);
}

const FakeExactConfig = struct {
    read_calls: usize = 0,
    observed_limit: usize = 0,
};

const fake_exact_config_vtable: source.ExactEngineConfig.VTable = .{
    .read = fakeRead,
    .deinit = fakeDeinit,
};

fn fakeRead(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    max_bytes: usize,
) source.Error!source.RawEngineConfig {
    const fake: *FakeExactConfig = @ptrCast(@alignCast(context));
    fake.read_calls += 1;
    fake.observed_limit = max_bytes;
    const bytes = allocator.dupe(u8, "{}") catch return error.EngineConfigReadFailure;
    return .{ .bytes = bytes };
}

fn fakeDeinit(_: *anyopaque, _: std.mem.Allocator) void {}
