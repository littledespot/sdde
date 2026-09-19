//! One execution's validated absent-to-present directory transition. This does
//! not replace bootstrap authority or permit a different feature/root identity.
const std = @import("std");
const bootstrap = @import("bootstrap_root_registry.zig");
const roots = @import("bootstrap_roots.zig");
const feature = @import("feature_directory.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidActiveFeatureDirectory};
pub const Capability = opaque {};
pub const Owner = opaque {};
pub const BoundInput = struct { binding: bootstrap.FeatureInputAdapterBinding, directory: feature.Directory };

const Storage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    bootstrap_binding: bootstrap.FeatureInputAdapterBinding,
    current: feature.Directory,
};

pub fn validatePrior(allocator: std.mem.Allocator, binding: bootstrap.FeatureInputAdapterBinding, prior: feature.Directory) Error!void {
    const selected = feature.validate(allocator, .{ .bytes = prior.selector.feature_id.bytes }, .{ .specs = binding.paths.specs, .archive = binding.paths.archive }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidFeatureDirectory => error.InvalidActiveFeatureDirectory,
    };
    defer allocator.free(selected.project_relative_path);
    if (!sameSelector(selected, prior.selector) or !sameObservation(binding.specs_observation, prior.root_observation) or
        (prior.root_observation == .absent and prior.observation != .absent)) return error.InvalidActiveFeatureDirectory;
}

pub fn createValidated(allocator: std.mem.Allocator, binding: bootstrap.FeatureInputAdapterBinding, prior: feature.Directory, current: feature.Directory) Error!*Owner {
    try validatePrior(allocator, binding, prior);
    if (!sameSelector(prior.selector, current.selector) or current.root_observation != .directory or current.observation != .directory or
        !preserves(prior.root_observation, current.root_observation) or !preserves(prior.observation, current.observation)) return error.InvalidActiveFeatureDirectory;
    const owner = try allocator.create(Storage);
    errdefer allocator.destroy(owner);
    owner.* = .{ .allocator = allocator, .arena = .init(allocator), .bootstrap_binding = binding, .current = current };
    errdefer owner.arena.deinit();
    const a = owner.arena.allocator();
    owner.bootstrap_binding.paths = .{
        .specs = try a.dupe(u8, binding.paths.specs),
        .archive = try a.dupe(u8, binding.paths.archive),
        .workflows = try a.dupe(u8, binding.paths.workflows),
    };
    owner.current.selector = .{
        .feature_id = .{ .bytes = try a.dupe(u8, current.selector.feature_id.bytes) },
        .project_relative_path = try a.dupe(u8, current.selector.project_relative_path),
    };
    return @ptrCast(owner);
}

pub fn capability(owner: *const Owner) *const Capability {
    return @ptrCast(owner);
}

pub fn directory(active: *const Capability) feature.Directory {
    return storage(active).current;
}

pub fn bindInput(active: *const Capability, supplied: bootstrap.FeatureInputAdapterBinding, observed: feature.Directory) ?BoundInput {
    const stored = storage(active);
    const original = stored.bootstrap_binding;
    if (!std.mem.eql(u8, original.paths.specs, supplied.paths.specs) or !std.mem.eql(u8, original.paths.archive, supplied.paths.archive) or
        !std.mem.eql(u8, original.paths.workflows, supplied.paths.workflows) or !original.workflows_identity.eql(supplied.workflows_identity) or
        (!sameObservation(original.specs_observation, supplied.specs_observation) and !sameObservation(stored.current.root_observation, supplied.specs_observation)) or
        !sameSelector(stored.current.selector, observed.selector) or !sameObservation(stored.current.root_observation, observed.root_observation) or
        !sameObservation(stored.current.observation, observed.observation)) return null;
    var effective = original;
    effective.specs_observation = stored.current.root_observation;
    return .{ .binding = effective, .directory = stored.current };
}

pub fn deinitOwner(owner: *Owner) void {
    const value: *Storage = @ptrCast(@alignCast(owner));
    const allocator = value.allocator;
    value.arena.deinit();
    allocator.destroy(value);
}

fn storage(active: *const Capability) *const Storage {
    return @ptrCast(@alignCast(active));
}

fn sameSelector(left: feature.Selector, right: feature.Selector) bool {
    return std.mem.eql(u8, left.feature_id.bytes, right.feature_id.bytes) and std.mem.eql(u8, left.project_relative_path, right.project_relative_path);
}

fn sameObservation(left: roots.RootObservation, right: roots.RootObservation) bool {
    return switch (left) {
        .absent => right == .absent,
        .directory => |identity| right == .directory and identity.eql(right.directory),
    };
}

fn preserves(prior: roots.RootObservation, current: roots.RootObservation) bool {
    return prior == .absent or sameObservation(prior, current);
}

test "activation admits only exact owned current observations and preserves existing identities" {
    const binding: bootstrap.FeatureInputAdapterBinding = .{ .paths = .{ .specs = "requirements", .archive = "archive", .workflows = "workflows" }, .specs_observation = .absent, .workflows_identity = .{ .filesystem_id = 1, .file_id = 2 } };
    const prior: feature.Directory = .{ .selector = .{ .feature_id = .{ .bytes = "Group/Café" }, .project_relative_path = "requirements/Group/Café" }, .root_observation = .absent, .observation = .absent };
    const current: feature.Directory = .{ .selector = prior.selector, .root_observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }, .observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 4 } } };
    const owner = try createValidated(std.testing.allocator, binding, prior, current);
    defer deinitOwner(owner);
    const active = capability(owner);
    try std.testing.expect(bindInput(active, binding, current) != null);
    try std.testing.expect(bindInput(active, binding, prior) == null);
    var foreign = binding;
    foreign.workflows_identity.file_id += 1;
    try std.testing.expect(bindInput(active, foreign, current) == null);
    var changed = current;
    changed.observation.directory.file_id += 1;
    try std.testing.expect(bindInput(active, binding, changed) == null);
    var changed_roots = binding;
    changed_roots.paths.specs = "different";
    try std.testing.expect(bindInput(active, changed_roots, current) == null);
    var present_binding = binding;
    present_binding.specs_observation = current.root_observation;
    try std.testing.expectError(error.InvalidActiveFeatureDirectory, createValidated(std.testing.allocator, present_binding, current, changed));
    changed = current;
    changed.root_observation.directory.file_id += 1;
    try std.testing.expectError(error.InvalidActiveFeatureDirectory, createValidated(std.testing.allocator, present_binding, current, changed));
    changed = current;
    changed.selector = .{ .feature_id = .{ .bytes = "other" }, .project_relative_path = "requirements/other" };
    try std.testing.expect(bindInput(active, binding, changed) == null);
    try std.testing.expectError(error.InvalidActiveFeatureDirectory, createValidated(std.testing.allocator, binding, prior, changed));
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    const binding: bootstrap.FeatureInputAdapterBinding = .{ .paths = .{ .specs = "requirements", .archive = "archive", .workflows = "workflows" }, .specs_observation = .absent, .workflows_identity = .{ .filesystem_id = 1, .file_id = 2 } };
    const prior: feature.Directory = .{ .selector = .{ .feature_id = .{ .bytes = "chosen" }, .project_relative_path = "requirements/chosen" }, .root_observation = .absent, .observation = .absent };
    const current: feature.Directory = .{ .selector = prior.selector, .root_observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }, .observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 4 } } };
    const owner = try createValidated(allocator, binding, prior, current);
    defer deinitOwner(owner);
    try std.testing.expectEqualStrings("requirements/chosen", directory(capability(owner)).selector.project_relative_path);
}

test "active feature authority releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "active directory capability owns borrowed feature and root text" {
    var specs = "requirements".*;
    var archive = "archive".*;
    var workflows = "workflows".*;
    var feature_id = "chosen".*;
    var feature_path = "requirements/chosen".*;
    const binding: bootstrap.FeatureInputAdapterBinding = .{ .paths = .{ .specs = &specs, .archive = &archive, .workflows = &workflows }, .specs_observation = .absent, .workflows_identity = .{ .filesystem_id = 1, .file_id = 2 } };
    const prior: feature.Directory = .{ .selector = .{ .feature_id = .{ .bytes = &feature_id }, .project_relative_path = &feature_path }, .root_observation = .absent, .observation = .absent };
    const current: feature.Directory = .{ .selector = prior.selector, .root_observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }, .observation = .{ .directory = .{ .filesystem_id = 1, .file_id = 4 } } };
    const owner = try createValidated(std.testing.allocator, binding, prior, current);
    defer deinitOwner(owner);
    @memset(&specs, 'x');
    @memset(&archive, 'x');
    @memset(&workflows, 'x');
    @memset(&feature_id, 'x');
    @memset(&feature_path, 'x');
    const saved = directory(capability(owner));
    try std.testing.expectEqualStrings("chosen", saved.selector.feature_id.bytes);
    try std.testing.expectEqualStrings("requirements/chosen", saved.selector.project_relative_path);
    const original: bootstrap.FeatureInputAdapterBinding = .{ .paths = .{ .specs = "requirements", .archive = "archive", .workflows = "workflows" }, .specs_observation = .absent, .workflows_identity = .{ .filesystem_id = 1, .file_id = 2 } };
    const rebound = bindInput(capability(owner), original, saved).?;
    try std.testing.expectEqualStrings("requirements", rebound.binding.paths.specs);
    try std.testing.expectEqualStrings("archive", rebound.binding.paths.archive);
    try std.testing.expectEqualStrings("workflows", rebound.binding.paths.workflows);
}
