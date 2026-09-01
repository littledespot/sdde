const std = @import("std");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const filesystem_identity = @import("../domain/filesystem_identity.zig");
const llm_provider_config = @import("../domain/llm_provider_config.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Error = error{ LLMProviderConfigReadFailure, Cancelled, DeadlineExhausted };

pub const ExactFile = struct {
    identity: filesystem_identity.FileIdentity,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (
            *anyopaque,
            std.mem.Allocator,
            usize,
            pipeline.NodeRuntime,
        ) Error!llm_provider_config.Raw,
        deinit: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    pub fn read(
        self: *ExactFile,
        allocator: std.mem.Allocator,
        max_bytes: usize,
        runtime: pipeline.NodeRuntime,
    ) Error!llm_provider_config.Raw {
        return self.vtable.read(self.context, allocator, max_bytes, runtime);
    }

    pub fn deinit(self: *ExactFile, allocator: std.mem.Allocator) void {
        self.vtable.deinit(self.context, allocator);
        self.* = undefined;
    }
};

pub const Locator = struct {
    context: *anyopaque,
    locate_fn: *const fn (
        *anyopaque,
        *const bootstrap_root_registry.LLMProviderConfigCapability,
        std.mem.Allocator,
        pipeline.NodeRuntime,
    ) Error!ExactFile,

    pub fn locate(
        self: Locator,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) Error!ExactFile {
        return self.locate_fn(self.context, capability, allocator, runtime);
    }
};
