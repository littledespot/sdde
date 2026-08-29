const std = @import("std");
const config = @import("config.zig");
const roots = @import("bootstrap_roots.zig");

pub const Error = error{BootstrapRootRegistryInvalid};

pub const ConfiguredBaseRootCapability = opaque {
    pub fn pathKey(self: *const ConfiguredBaseRootCapability) roots.PathKey {
        return capabilityStorage(self).path_key;
    }

    pub fn role(self: *const ConfiguredBaseRootCapability) roots.ConfiguredRootRole {
        return capabilityStorage(self).root_role;
    }

    pub fn isPresent(self: *const ConfiguredBaseRootCapability) bool {
        return switch (capabilityStorage(self).observation) {
            .absent => false,
            .directory => true,
        };
    }
};

pub const BootstrapRootRegistry = opaque {
    pub fn workflowAuthority(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        const stored = &registryStorage(self).configured_roots[@intFromEnum(roots.PathKey.workflows)];
        return @ptrCast(stored);
    }
};

pub const Owner = opaque {};

const CapabilityStorage = struct {
    path_key: roots.PathKey,
    root_role: roots.ConfiguredRootRole,
    canonical_project_root: []const u8,
    configured_relative_path: []const u8,
    canonical_path: []const u8,
    access_class: roots.RootAccessClass,
    existence_policy: roots.ExistencePolicy,
    observation: roots.RootObservation,
};

const RegistryStorage = struct {
    id: roots.BootstrapRootRegistryId,
    config_location: roots.ExactEngineConfigLocation,
    configured_roots: [roots.PathKey.count]CapabilityStorage,
};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    registry: RegistryStorage,
};

pub fn createValidated(
    backing_allocator: std.mem.Allocator,
    candidate: roots.BootstrapRootRegistryCandidate,
) Error!*Owner {
    try validateIdentityAndLocation(candidate);
    try validateCapabilities(candidate);
    try validateCollisions(candidate.configured_roots);

    const owned = backing_allocator.create(OwnerStorage) catch {
        return error.BootstrapRootRegistryInvalid;
    };
    errdefer backing_allocator.destroy(owned);
    owned.* = .{
        .backing_allocator = backing_allocator,
        .arena = .init(backing_allocator),
        .registry = undefined,
    };
    errdefer owned.arena.deinit();

    const allocator = owned.arena.allocator();
    const project_root = allocator.dupe(u8, candidate.id.canonical_project_root) catch {
        return error.BootstrapRootRegistryInvalid;
    };
    const config_path = allocator.dupe(u8, candidate.config_location.canonical_config_path) catch {
        return error.BootstrapRootRegistryInvalid;
    };

    var configured_roots: [roots.PathKey.count]CapabilityStorage = undefined;
    for (&configured_roots, candidate.configured_roots) |*destination, source| {
        destination.* = .{
            .path_key = source.path_key,
            .root_role = source.root_role,
            .canonical_project_root = project_root,
            .configured_relative_path = allocator.dupe(
                u8,
                source.configured_relative_path,
            ) catch return error.BootstrapRootRegistryInvalid,
            .canonical_path = allocator.dupe(u8, source.canonical_path) catch {
                return error.BootstrapRootRegistryInvalid;
            },
            .access_class = source.access_class,
            .existence_policy = source.existence_policy,
            .observation = source.observation,
        };
    }

    owned.registry = .{
        .id = .{
            .canonical_project_root = project_root,
            .contract_version = roots.bootstrap_root_contract_version,
        },
        .config_location = .{
            .canonical_project_root = project_root,
            .canonical_config_path = config_path,
            .no_follow_file_identity = candidate.config_location.no_follow_file_identity,
        },
        .configured_roots = configured_roots,
    };
    return @ptrCast(owned);
}

pub fn registry(owner: *const Owner) *const BootstrapRootRegistry {
    return @ptrCast(&ownerStorageConst(owner).registry);
}

pub fn deinitOwner(owner: *Owner) void {
    const stored = ownerStorage(owner);
    const backing_allocator = stored.backing_allocator;
    stored.arena.deinit();
    backing_allocator.destroy(stored);
}

fn validateIdentityAndLocation(candidate: roots.BootstrapRootRegistryCandidate) Error!void {
    if (!std.mem.eql(
        u8,
        candidate.id.contract_version,
        roots.bootstrap_root_contract_version,
    ) or
        !std.fs.path.isAbsolute(candidate.id.canonical_project_root) or
        !std.mem.eql(
            u8,
            candidate.id.canonical_project_root,
            candidate.config_location.canonical_project_root,
        ))
    {
        return error.BootstrapRootRegistryInvalid;
    }

    const config_path = candidate.config_location.canonical_config_path;
    if (!std.fs.path.isAbsolute(config_path) or
        !std.mem.eql(u8, std.fs.path.basename(config_path), config.engine_config_basename) or
        !std.mem.eql(
            u8,
            std.fs.path.dirname(config_path) orelse "",
            candidate.id.canonical_project_root,
        ))
    {
        return error.BootstrapRootRegistryInvalid;
    }
}

fn validateCapabilities(candidate: roots.BootstrapRootRegistryCandidate) Error!void {
    for (candidate.configured_roots, 0..) |capability, index| {
        const expected_key: roots.PathKey = @enumFromInt(index);
        if (capability.path_key != expected_key or
            capability.root_role != expected_key.role() or
            capability.access_class != expected_key.accessClass() or
            capability.existence_policy != expected_key.existencePolicy() or
            !std.mem.eql(
                u8,
                capability.canonical_project_root,
                candidate.id.canonical_project_root,
            ) or
            capability.configured_relative_path.len == 0 or
            !matchesResolvedPath(
                candidate.id.canonical_project_root,
                capability.canonical_path,
                capability.configured_relative_path,
            ))
        {
            return error.BootstrapRootRegistryInvalid;
        }
        if (expected_key == .workflows and !capability.isPresent()) {
            return error.BootstrapRootRegistryInvalid;
        }
    }
}

fn validateCollisions(
    capabilities: [roots.PathKey.count]roots.ValidatedConfiguredRoot,
) Error!void {
    for (capabilities, 0..) |left, left_index| {
        for (capabilities[left_index + 1 ..]) |right| {
            if (portableEqual(left.configured_relative_path, right.configured_relative_path)) {
                return error.BootstrapRootRegistryInvalid;
            }

            const left_beneath_right = portableDescendant(
                left.configured_relative_path,
                right.configured_relative_path,
            );
            const right_beneath_left = portableDescendant(
                right.configured_relative_path,
                left.configured_relative_path,
            );
            if ((left_beneath_right or right_beneath_left) and
                !isAllowedArchiveNesting(
                    left,
                    right,
                    left_beneath_right,
                    right_beneath_left,
                ))
            {
                return error.BootstrapRootRegistryInvalid;
            }

            switch (left.observation) {
                .absent => {},
                .directory => |left_identity| switch (right.observation) {
                    .absent => {},
                    .directory => |right_identity| {
                        if (left_identity.eql(right_identity)) {
                            return error.BootstrapRootRegistryInvalid;
                        }
                    },
                },
            }
        }
    }
}

fn isAllowedArchiveNesting(
    left: roots.ValidatedConfiguredRoot,
    right: roots.ValidatedConfiguredRoot,
    left_beneath_right: bool,
    right_beneath_left: bool,
) bool {
    return (left.path_key == .specs_archive and
        right.path_key == .specs and
        left_beneath_right) or
        (right.path_key == .specs_archive and
            left.path_key == .specs and
            right_beneath_left);
}

fn portableEqual(left: []const u8, right: []const u8) bool {
    return std.ascii.eqlIgnoreCase(left, right);
}

fn portableDescendant(child: []const u8, parent: []const u8) bool {
    return child.len > parent.len and
        std.ascii.startsWithIgnoreCase(child, parent) and
        child[parent.len] == '/';
}

fn matchesResolvedPath(root: []const u8, child: []const u8, relative: []const u8) bool {
    if (!std.mem.startsWith(u8, child, root) or child.len <= root.len) return false;
    var child_index = root.len;
    if (!(root.len == 1 and std.fs.path.isSep(root[0]))) {
        if (!std.fs.path.isSep(child[child_index])) return false;
        child_index += 1;
    }
    if (child.len - child_index != relative.len) return false;
    for (child[child_index..], relative) |child_byte, relative_byte| {
        if (std.fs.path.isSep(child_byte) and relative_byte == '/') continue;
        if (child_byte != relative_byte) return false;
    }
    return true;
}

fn capabilityStorage(capability: *const ConfiguredBaseRootCapability) *const CapabilityStorage {
    return @ptrCast(@alignCast(capability));
}

fn registryStorage(registry_value: *const BootstrapRootRegistry) *const RegistryStorage {
    return @ptrCast(@alignCast(registry_value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
