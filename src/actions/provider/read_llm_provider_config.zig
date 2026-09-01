const std = @import("std");
const llm_provider_config = @import("../../domain/llm_provider_config.zig");
const pipeline = @import("../../domain/pipeline.zig");
const source_port = @import("../../ports/llm_provider_config_source.zig");

pub const Error = error{ LLMProviderConfigReadError, Cancelled, DeadlineExhausted };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "read-llm-provider-config@1",
        .kind = .action,
        .requires = &.{.exact_llm_provider_config_file},
        .produces = &.{.raw_llm_provider_config},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        _: Action,
        exact_file: *source_port.ExactFile,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) Error!llm_provider_config.Raw {
        return exact_file.read(
            allocator,
            llm_provider_config.max_bytes,
            runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => error.Cancelled,
            error.DeadlineExhausted => error.DeadlineExhausted,
            error.LLMProviderConfigReadFailure => error.LLMProviderConfigReadError,
        };
    }
};

test "captures through the exact-file capability at the compiler limit" {
    var fake: FakeFile = .{};
    var exact: source_port.ExactFile = .{
        .identity = .{ .filesystem_id = 1, .file_id = 2 },
        .context = &fake,
        .vtable = &fake_vtable,
    };
    defer exact.deinit(std.testing.allocator);
    var raw = try (Action{}).execute(&exact, std.testing.allocator, .{});
    defer raw.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("{}", raw.bytes);
    try std.testing.expectEqual(llm_provider_config.max_bytes, fake.limit);
}

const FakeFile = struct { limit: usize = 0 };

const fake_vtable: source_port.ExactFile.VTable = .{
    .read = fakeRead,
    .deinit = fakeDeinit,
};

fn fakeRead(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    limit: usize,
    _: pipeline.NodeRuntime,
) source_port.Error!llm_provider_config.Raw {
    const fake: *FakeFile = @ptrCast(@alignCast(context));
    fake.limit = limit;
    return .{ .bytes = allocator.dupe(u8, "{}") catch {
        return error.LLMProviderConfigReadFailure;
    } };
}

fn fakeDeinit(_: *anyopaque, _: std.mem.Allocator) void {}
