const std = @import("std");
const bootstrap = @import("bootstrap_root_registry.zig");
const log_binding = @import("feature_log_binding.zig");
const feature_identity = @import("feature_identity.zig");
const relative = @import("relative_directory_path.zig");
const directory = @import("feature_directory.zig");

pub const FeatureRoots = struct { specs: []const u8, archive: []const u8, workflows: []const u8 };
pub const Artifact = enum { specification, reference_context, clarification_forms, clarification_state, workflow_state, event_logs, prompt_logs };
pub const Root = enum { specs, workflows };
pub const ArtifactPath = struct { root: Root, root_relative: []const u8, project_relative: []const u8 };
/// A deterministic path projection, not an ownership registry or write grant.
pub const FeaturePaths = struct {
    feature: directory.Selector,
    entries: [@typeInfo(Artifact).@"enum".fields.len]ArtifactPath,

    pub fn get(self: FeaturePaths, artifact: Artifact) ArtifactPath {
        return self.entries[@intFromEnum(artifact)];
    }
};

pub fn resolveFeaturePaths(allocator: std.mem.Allocator, configured: FeatureRoots, selected: directory.Selector) (std.mem.Allocator.Error || error{InvalidFeatureArtifactPath})!FeaturePaths {
    const checked = directory.validate(allocator, .{ .bytes = selected.feature_id.bytes }, .{ .specs = configured.specs, .archive = configured.archive }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidFeatureDirectory => error.InvalidFeatureArtifactPath,
    };
    defer allocator.free(checked.project_relative_path);
    if (!std.mem.eql(u8, checked.project_relative_path, selected.project_relative_path)) return error.InvalidFeatureArtifactPath;
    var result: FeaturePaths = .{ .feature = selected, .entries = undefined };
    var initialized: usize = 0;
    errdefer for (result.entries[0..initialized]) |entry| {
        allocator.free(entry.root_relative);
        allocator.free(entry.project_relative);
    };
    inline for (.{
        .{ Artifact.specification, Root.specs, "spec.md" },
        .{ Artifact.reference_context, Root.specs, "reference-context.md" },
        .{ Artifact.clarification_forms, Root.specs, "clarify" },
        .{ Artifact.clarification_state, Root.workflows, "state/clarifications.json" },
        .{ Artifact.workflow_state, Root.workflows, "state/workflow.json" },
        .{ Artifact.event_logs, Root.specs, "logs/events" },
        .{ Artifact.prompt_logs, Root.specs, "logs/prompts" },
    }) |item| {
        const root = if (item[1] == .specs) configured.specs else configured.workflows;
        const prefix = if (item[1] == .specs) "" else "features/";
        const child = try std.mem.concat(allocator, u8, &.{ prefix, selected.feature_id.bytes, "/", item[2] });
        errdefer allocator.free(child);
        const project = try std.mem.concat(allocator, u8, &.{ root, "/", child });
        errdefer allocator.free(project);
        relative.validate(project) catch return error.InvalidFeatureArtifactPath;
        if (!relative.contains(root, project) or relative.contains(configured.archive, project)) return error.InvalidFeatureArtifactPath;
        result.entries[@intFromEnum(item[0])] = .{ .root = item[1], .root_relative = child, .project_relative = project };
        initialized += 1;
    }
    return result;
}

/// Canonical feature-state tuple; the namespace is fixed by this type.
/// A well-formed ID alone proves neither allocation nor committed authority.
pub const StateId = struct {
    feature_id: feature_identity.FeatureId,
    ordinal: u64,

    pub fn isValid(self: StateId) bool {
        return self.ordinal > 0 and feature_identity.FeatureId.parse(self.feature_id.bytes) != null;
    }

    pub fn eql(self: StateId, other: StateId) bool {
        return self.ordinal == other.ordinal and std.mem.eql(u8, self.feature_id.bytes, other.feature_id.bytes);
    }
};

pub const Error = error{InvalidWorkflowArtifactRegistry};

pub const WorkflowArtifactRegistry = opaque {};
pub const Owner = opaque {};

const Storage = struct {
    binding: log_binding.BindingCandidate,
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
    binding: *const log_binding.ValidatedFeatureLogBinding,
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
    const configured = roots.featureArtifactRoots();
    const selected = directory.validate(allocator, .{ .bytes = feature }, .{ .specs = configured.specs, .archive = configured.archive }) catch return error.InvalidWorkflowArtifactRegistry;
    const paths = resolveFeaturePaths(allocator, configured, selected) catch return error.InvalidWorkflowArtifactRegistry;
    const event_run = std.fmt.allocPrint(allocator, "{s}/{s}", .{ paths.get(.event_logs).root_relative, run }) catch return error.InvalidWorkflowArtifactRegistry;
    const prompt_run = std.fmt.allocPrint(allocator, "{s}/{s}", .{ paths.get(.prompt_logs).root_relative, run }) catch return error.InvalidWorkflowArtifactRegistry;
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
    expected_binding: log_binding.BindingCandidate,
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
    binding: *const log_binding.ValidatedFeatureLogBinding,
) ?FeatureLogSinkBinding {
    const stored = registryStorage(value);
    if (!log_binding.sameBinding(binding, stored.binding)) return null;
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
