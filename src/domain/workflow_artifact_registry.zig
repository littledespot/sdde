const std = @import("std");
const bootstrap = @import("bootstrap_root_registry.zig");
const log_runtime = @import("feature_log_runtime.zig");

pub const Error = error{InvalidWorkflowArtifactRegistry};

pub const WorkflowArtifactRegistry = opaque {};
pub const Owner = opaque {};

const Storage = struct {
    binding: log_runtime.BindingCandidate,
    specs_root_path: []const u8,
    specs_root_identity: @import("bootstrap_roots.zig").PhysicalDirectoryIdentity,
    event_run_path: []const u8,
    event_binding_path: []const u8,
    prompt_run_path: []const u8,
    prompt_binding_path: []const u8,
};
const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    registry: Storage,
};

pub fn createValidated(
    backing_allocator: std.mem.Allocator,
    roots: *const bootstrap.BootstrapRootRegistry,
    binding: *const log_runtime.ValidatedFeatureLogBinding,
) Error!*Owner {
    const specs = bootstrap.bindSpecsArtifactRegistry(roots.specsArtifacts()) orelse {
        return error.InvalidWorkflowArtifactRegistry;
    };
    const owner = backing_allocator.create(OwnerStorage) catch return error.InvalidWorkflowArtifactRegistry;
    errdefer backing_allocator.destroy(owner);
    owner.* = .{ .backing_allocator = backing_allocator, .arena = .init(backing_allocator), .registry = undefined };
    errdefer owner.arena.deinit();
    const allocator = owner.arena.allocator();
    const feature = binding.featureId().bytes;
    const run = binding.runId().bytes;
    const binding_id = binding.bindingId().bytes;
    const event_run = std.fmt.allocPrint(allocator, "{s}/logs/events/{s}", .{ feature, run }) catch return error.InvalidWorkflowArtifactRegistry;
    const prompt_run = std.fmt.allocPrint(allocator, "{s}/logs/prompts/{s}", .{ feature, run }) catch return error.InvalidWorkflowArtifactRegistry;
    owner.registry = .{
        .binding = .{
            .log_policy_id = .{ .bytes = allocator.dupe(u8, binding.logPolicyId().bytes) catch return error.InvalidWorkflowArtifactRegistry },
            .binding_id = .{ .bytes = allocator.dupe(u8, binding_id) catch return error.InvalidWorkflowArtifactRegistry },
            .run_id = .{ .bytes = allocator.dupe(u8, run) catch return error.InvalidWorkflowArtifactRegistry },
            .feature_id = .{ .bytes = allocator.dupe(u8, feature) catch return error.InvalidWorkflowArtifactRegistry },
        },
        .specs_root_path = allocator.dupe(u8, specs.project_relative_path) catch return error.InvalidWorkflowArtifactRegistry,
        .specs_root_identity = specs.physical_identity,
        .event_run_path = event_run,
        .event_binding_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ event_run, binding_id }) catch return error.InvalidWorkflowArtifactRegistry,
        .prompt_run_path = prompt_run,
        .prompt_binding_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ prompt_run, binding_id }) catch return error.InvalidWorkflowArtifactRegistry,
    };
    return @ptrCast(owner);
}

pub fn registry(owner: *const Owner) *const WorkflowArtifactRegistry {
    return @ptrCast(&ownerStorageConst(owner).registry);
}
pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

pub const FeatureLogSinkBinding = struct {
    expected_binding: log_runtime.BindingCandidate,
    specs_root_path: []const u8,
    specs_root_identity: @import("bootstrap_roots.zig").PhysicalDirectoryIdentity,
    event_run_path: []const u8,
    event_binding_path: []const u8,
    prompt_run_path: []const u8,
    prompt_binding_path: []const u8,
};

/// The sole concrete handoff from artifact authority to the feature-log sink.
pub fn bindFeatureLogSinkAdapter(
    value: *const WorkflowArtifactRegistry,
    binding: *const log_runtime.ValidatedFeatureLogBinding,
) ?FeatureLogSinkBinding {
    const stored = registryStorage(value);
    if (!log_runtime.sameBinding(binding, stored.binding)) return null;
    return .{
        .expected_binding = stored.binding,
        .specs_root_path = stored.specs_root_path,
        .specs_root_identity = stored.specs_root_identity,
        .event_run_path = stored.event_run_path,
        .event_binding_path = stored.event_binding_path,
        .prompt_run_path = stored.prompt_run_path,
        .prompt_binding_path = stored.prompt_binding_path,
    };
}

fn registryStorage(value: *const WorkflowArtifactRegistry) *const Storage {
    return @ptrCast(@alignCast(value));
}
fn ownerStorage(value: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(value));
}
fn ownerStorageConst(value: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(value));
}
