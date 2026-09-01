const std = @import("std");
const bootstrap_root_registry = @import("../../domain/bootstrap_root_registry.zig");
const pipeline = @import("../../domain/pipeline.zig");
const source_port = @import("../../ports/llm_provider_config_source.zig");

pub const Error = error{ LLMProviderConfigReadError, Cancelled, DeadlineExhausted };

pub const Action = struct {
    locator: source_port.Locator,

    pub const contract: pipeline.NodeContract = .{
        .id = "locate-llm-provider-config@1",
        .kind = .action,
        .requires = &.{.bootstrap_root_registry_evidence},
        .produces = &.{.exact_llm_provider_config_file},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) Error!source_port.ExactFile {
        return self.locator.locate(
            capability,
            allocator,
            runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => error.Cancelled,
            error.DeadlineExhausted => error.DeadlineExhausted,
            error.LLMProviderConfigReadFailure => error.LLMProviderConfigReadError,
        };
    }
};

test "uses only the registry-owned provider capability" {
    const owner = try testRegistry(std.testing.allocator);
    defer bootstrap_root_registry.deinitOwner(owner);
    var fake: FakeLocator = .{};
    var exact = try (Action{ .locator = fake.port() }).execute(
        bootstrap_root_registry.registry(owner).llmProviderConfig(),
        std.testing.allocator,
        .{},
    );
    defer exact.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

const FakeLocator = struct {
    calls: usize = 0,

    fn port(self: *FakeLocator) source_port.Locator {
        return .{ .context = self, .locate_fn = locate };
    }

    fn locate(
        context: *anyopaque,
        _: *const bootstrap_root_registry.LLMProviderConfigCapability,
        _: std.mem.Allocator,
        _: pipeline.NodeRuntime,
    ) source_port.Error!source_port.ExactFile {
        const self: *FakeLocator = @ptrCast(@alignCast(context));
        self.calls += 1;
        return .{
            .identity = .{ .filesystem_id = 1, .file_id = 2 },
            .context = self,
            .vtable = &fake_vtable,
        };
    }
};

const fake_vtable: source_port.ExactFile.VTable = .{
    .read = fakeRead,
    .deinit = fakeDeinit,
};

fn fakeRead(
    _: *anyopaque,
    _: std.mem.Allocator,
    _: usize,
    _: pipeline.NodeRuntime,
) source_port.Error!@import("../../domain/llm_provider_config.zig").Raw {
    return error.LLMProviderConfigReadFailure;
}

fn fakeDeinit(_: *anyopaque, _: std.mem.Allocator) void {}

fn testRegistry(allocator: std.mem.Allocator) !*bootstrap_root_registry.Owner {
    const roots = @import("../../domain/bootstrap_roots.zig");
    var configured: [roots.PathKey.count]roots.ValidatedConfiguredRoot = undefined;
    const paths = [_][]const u8{
        "specs",
        "references",
        "specs/archive",
        ".sdd/workflows",
        ".sdd/presets",
        ".sdd/principles",
        ".sdd/templates",
    };
    for (&configured, 0..) |*value, index| {
        const key: roots.PathKey = @enumFromInt(index);
        value.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = paths[index],
            .canonical_path = switch (key) {
                .specs => "/project/specs",
                .references => "/project/references",
                .specs_archive => "/project/specs/archive",
                .workflows => "/project/.sdd/workflows",
                .toolchain_preset => "/project/.sdd/presets",
                .principles => "/project/.sdd/principles",
                .templates => "/project/.sdd/templates",
            },
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = if (key == .workflows)
                .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }
            else
                .absent,
        };
    }
    return bootstrap_root_registry.createValidated(allocator, .{
        .id = .{
            .canonical_project_root = "/project",
            .contract_version = roots.bootstrap_root_contract_version,
        },
        .config_location = .{
            .canonical_project_root = "/project",
            .canonical_config_path = "/project/.sddtoolkit.json",
            .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 },
        },
        .configured_roots = configured,
        .llm_provider_config_path = .{
            .relative_path = ".sddproviders.json",
            .canonical_project_root = "/project",
            .canonical_path = "/project/.sddproviders.json",
        },
    });
}
