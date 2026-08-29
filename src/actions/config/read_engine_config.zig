const std = @import("std");
const config = @import("../../domain/config.zig");
const pipeline = @import("../../domain/pipeline.zig");
const engine_config_source = @import("../../ports/engine_config_source.zig");

pub const Error = error{EngineConfigReadError};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "read-engine-config@1",
        .kind = .action,
        .requires = &.{.exact_engine_config_file},
        .produces = &.{.raw_engine_config},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        _: Action,
        exact_config_file: *engine_config_source.ExactEngineConfigFile,
        allocator: std.mem.Allocator,
    ) Error!engine_config_source.RawEngineConfig {
        return exact_config_file.read(allocator, config.max_engine_config_bytes) catch {
            return error.EngineConfigReadError;
        };
    }
};

test "reads only through the exact-config-file capability at the compiler limit" {
    const allocator = std.testing.allocator;
    var fake = FakeExactConfigFile{};
    const canonical_root = try allocator.dupeZ(u8, "/validated/project");
    var exact_config_file = engine_config_source.ExactEngineConfigFile.init(
        canonical_root,
        &fake,
        &fake_exact_config_file_vtable,
    );
    defer exact_config_file.deinit(allocator);

    var raw = try (Action{}).execute(&exact_config_file, allocator);
    defer raw.deinit(allocator);

    try std.testing.expectEqualStrings("{}", raw.bytes);
    try std.testing.expectEqual(@as(usize, 1), fake.read_calls);
    try std.testing.expectEqual(config.max_engine_config_bytes, fake.observed_limit);
}

const FakeExactConfigFile = struct {
    read_calls: usize = 0,
    observed_limit: usize = 0,
};

const fake_exact_config_file_vtable: engine_config_source.ExactEngineConfigFile.VTable = .{
    .read = fakeRead,
    .deinit = fakeDeinit,
};

fn fakeRead(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    max_bytes: usize,
) engine_config_source.Error!engine_config_source.RawEngineConfig {
    const fake: *FakeExactConfigFile = @ptrCast(@alignCast(context));
    fake.read_calls += 1;
    fake.observed_limit = max_bytes;
    const bytes = allocator.dupe(u8, "{}") catch return error.EngineConfigReadFailure;
    return .{ .bytes = bytes };
}

fn fakeDeinit(_: *anyopaque, _: std.mem.Allocator) void {}
