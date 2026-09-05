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

pub const LLMProviderConfigCapability = opaque {};
pub const FeatureDirectoryReadCapability = opaque {};
pub const FeatureInputReadCapability = opaque {};
pub const ReferenceContentReadCapability = opaque {};

pub const BootstrapRootRegistry = opaque {
    pub fn referenceContentRead(self: *const BootstrapRootRegistry) *const ReferenceContentReadCapability {
        return @ptrCast(self.referenceSources());
    }
    pub fn featureInputRead(self: *const BootstrapRootRegistry) *const FeatureInputReadCapability {
        return @ptrCast(self);
    }

    pub fn featureArtifactRoots(self: *const BootstrapRootRegistry) @import("workflow_artifact_registry.zig").FeatureRoots {
        const paths = self.featureDirectoryRoots();
        return .{ .specs = paths.specs, .archive = paths.archive, .workflows = capabilityStorage(self.workflowAuthority()).configured_relative_path };
    }

    pub fn featureDirectoryRead(self: *const BootstrapRootRegistry) *const FeatureDirectoryReadCapability {
        return @ptrCast(self);
    }

    pub fn featureDirectoryRoots(self: *const BootstrapRootRegistry) @import("feature_directory.zig").Roots {
        return .{
            .specs = capabilityStorage(self.specsArtifacts()).configured_relative_path,
            .archive = capabilityStorage(self.archivedSpecs()).configured_relative_path,
        };
    }

    pub fn specsArtifacts(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .specs);
    }

    pub fn referenceSources(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .references);
    }

    pub fn archivedSpecs(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .specs_archive);
    }

    pub fn workflowAuthority(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .workflows);
    }

    pub fn toolchainPresetRegistry(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .toolchain_preset);
    }

    pub fn projectPrinciples(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .principles);
    }

    pub fn initializationTemplates(
        self: *const BootstrapRootRegistry,
    ) *const ConfiguredBaseRootCapability {
        return capabilityFor(self, .templates);
    }

    pub fn llmProviderConfig(
        self: *const BootstrapRootRegistry,
    ) *const LLMProviderConfigCapability {
        return @ptrCast(&registryStorage(self).llm_provider_config_path);
    }
};

/// Internal adapter handoff. Architecture tests restrict this function to the
/// workflow-authority filesystem adapter; services and consumers retain only
/// the opaque capability.
pub const WorkflowAuthorityAdapterBinding = struct {
    project_relative_path: []const u8,
    physical_identity: roots.PhysicalDirectoryIdentity,
};

pub fn bindWorkflowAuthorityAdapter(
    capability: *const ConfiguredBaseRootCapability,
) ?WorkflowAuthorityAdapterBinding {
    const stored = capabilityStorage(capability);
    if (stored.path_key != .workflows or stored.root_role != .workflow_authority or
        stored.access_class != .engine_only or stored.existence_policy != .required_directory)
    {
        return null;
    }
    return switch (stored.observation) {
        .absent => null,
        .directory => |identity| .{
            .project_relative_path = stored.configured_relative_path,
            .physical_identity = identity,
        },
    };
}

pub const ToolchainAuthorityKind = enum { principles, preset_registry };
pub const ReferenceSourcesAdapterBinding = struct {
    project_relative_path: []const u8,
    physical_identity: roots.PhysicalDirectoryIdentity,
};

/// Content readers have a separate capability from metadata-only inspection.
pub fn bindReferenceContentAdapter(capability: *const ReferenceContentReadCapability) ?ReferenceSourcesAdapterBinding {
    return bindReferenceSourcesAdapter(@ptrCast(capability));
}

/// Internal handoff restricted to the read-only reference directory adapter.
pub fn bindReferenceSourcesAdapter(capability: *const ConfiguredBaseRootCapability) ?ReferenceSourcesAdapterBinding {
    const stored = capabilityStorage(capability);
    if (stored.path_key != .references or stored.root_role != .reference_sources or
        stored.access_class != .reference_read_only or stored.existence_policy != .optional_directory) return null;
    return switch (stored.observation) {
        .absent => null,
        .directory => |identity| .{ .project_relative_path = stored.configured_relative_path, .physical_identity = identity },
    };
}

pub const ToolchainAuthorityAdapterBinding = struct {
    kind: ToolchainAuthorityKind,
    project_relative_path: []const u8,
    physical_identity: roots.PhysicalDirectoryIdentity,
};

/// Internal handoff restricted to the toolchain filesystem adapter.
pub fn bindToolchainAuthorityAdapter(
    capability: *const ConfiguredBaseRootCapability,
) ?ToolchainAuthorityAdapterBinding {
    const stored = capabilityStorage(capability);
    const kind: ToolchainAuthorityKind = switch (stored.path_key) {
        .principles => if (stored.root_role == .project_principles) .principles else return null,
        .toolchain_preset => if (stored.root_role == .toolchain_preset_registry) .preset_registry else return null,
        else => return null,
    };
    if (stored.access_class != .engine_only or stored.existence_policy != .optional_directory) return null;
    return switch (stored.observation) {
        .absent => null,
        .directory => |identity| .{ .kind = kind, .project_relative_path = stored.configured_relative_path, .physical_identity = identity },
    };
}

pub const SpecsArtifactAdapterBinding = struct {
    project_relative_path: []const u8,
    physical_identity: roots.PhysicalDirectoryIdentity,
};

pub const FeatureDirectoryAdapterBinding = struct {
    paths: @import("feature_directory.zig").Roots,
    observation: roots.RootObservation,
};

pub const FeatureInputAdapterBinding = struct {
    paths: @import("workflow_artifact_registry.zig").FeatureRoots,
    specs_observation: roots.RootObservation,
    workflows_identity: roots.PhysicalDirectoryIdentity,
};

/// Internal handoff restricted to the bounded selected-feature input reader.
pub fn bindFeatureInputAdapter(capability: *const FeatureInputReadCapability) FeatureInputAdapterBinding {
    const registry_value: *const BootstrapRootRegistry = @ptrCast(capability);
    return .{
        .paths = registry_value.featureArtifactRoots(),
        .specs_observation = capabilityStorage(registry_value.specsArtifacts()).observation,
        .workflows_identity = capabilityStorage(registry_value.workflowAuthority()).observation.directory,
    };
}

/// Internal handoff restricted to the read-only feature directory inspector.
pub fn bindFeatureDirectoryAdapter(capability: *const FeatureDirectoryReadCapability) FeatureDirectoryAdapterBinding {
    const registry_value: *const BootstrapRootRegistry = @ptrCast(capability);
    return .{
        .paths = registry_value.featureDirectoryRoots(),
        .observation = capabilityStorage(registry_value.specsArtifacts()).observation,
    };
}

/// Internal handoff restricted to the workflow-artifact registry builder.
pub fn bindSpecsArtifactRegistry(
    capability: *const ConfiguredBaseRootCapability,
) ?SpecsArtifactAdapterBinding {
    const stored = capabilityStorage(capability);
    if (stored.path_key != .specs or stored.root_role != .specs_artifacts or
        stored.access_class != .engine_only or stored.existence_policy != .optional_directory)
    {
        return null;
    }
    return switch (stored.observation) {
        .absent => null,
        .directory => |identity| .{
            .project_relative_path = stored.configured_relative_path,
            .physical_identity = identity,
        },
    };
}

pub const LLMProviderConfigAdapterBinding = struct {
    project_relative_path: []const u8,
    engine_config_identity: roots.NoFollowFileIdentity,
};

/// Internal handoff restricted to the LLM-provider config filesystem adapter.
pub fn bindLLMProviderConfigSource(
    capability: *const LLMProviderConfigCapability,
) ?LLMProviderConfigAdapterBinding {
    const stored: *const LLMProviderConfigStorage = @ptrCast(@alignCast(capability));
    if (!std.mem.eql(
        u8,
        std.fs.path.basename(stored.configured_relative_path),
        roots.llm_provider_config_basename,
    )) return null;
    return .{
        .project_relative_path = stored.configured_relative_path,
        .engine_config_identity = stored.engine_config_identity,
    };
}

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

const LLMProviderConfigStorage = struct {
    canonical_project_root: []const u8,
    configured_relative_path: []const u8,
    canonical_path: []const u8,
    engine_config_identity: roots.NoFollowFileIdentity,
};

const RegistryStorage = struct {
    id: roots.BootstrapRootRegistryId,
    config_location: roots.ExactEngineConfigLocation,
    configured_roots: [roots.PathKey.count]CapabilityStorage,
    llm_provider_config_path: LLMProviderConfigStorage,
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
    try validateProviderConfigPath(candidate);
    try validateCollisions(
        candidate.configured_roots,
        candidate.llm_provider_config_path.relative_path,
    );

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
        .llm_provider_config_path = .{
            .canonical_project_root = project_root,
            .configured_relative_path = allocator.dupe(
                u8,
                candidate.llm_provider_config_path.relative_path,
            ) catch return error.BootstrapRootRegistryInvalid,
            .canonical_path = allocator.dupe(
                u8,
                candidate.llm_provider_config_path.canonical_path,
            ) catch return error.BootstrapRootRegistryInvalid,
            .engine_config_identity = candidate.config_location.no_follow_file_identity,
        },
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
    if (!candidate.id.isValid() or
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
            !roots.matchesResolvedPath(
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

fn validateProviderConfigPath(candidate: roots.BootstrapRootRegistryCandidate) Error!void {
    const provider_path = candidate.llm_provider_config_path;
    if (!provider_path.isStructurallyValid() or
        !std.mem.eql(
            u8,
            provider_path.canonical_project_root,
            candidate.id.canonical_project_root,
        ) or
        portableEqual(
            provider_path.canonical_path,
            candidate.config_location.canonical_config_path,
        ) or
        portableDescendant(
            provider_path.canonical_path,
            candidate.config_location.canonical_config_path,
        ) or
        portableDescendant(
            candidate.config_location.canonical_config_path,
            provider_path.canonical_path,
        ))
    {
        return error.BootstrapRootRegistryInvalid;
    }
}

fn validateCollisions(
    capabilities: [roots.PathKey.count]roots.ValidatedConfiguredRoot,
    provider_config_relative_path: []const u8,
) Error!void {
    for (capabilities, 0..) |left, left_index| {
        if (portableEqual(left.configured_relative_path, provider_config_relative_path) or
            portableDescendant(provider_config_relative_path, left.configured_relative_path) or
            portableDescendant(left.configured_relative_path, provider_config_relative_path))
        {
            return error.BootstrapRootRegistryInvalid;
        }
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

fn capabilityFor(
    registry_value: *const BootstrapRootRegistry,
    key: roots.PathKey,
) *const ConfiguredBaseRootCapability {
    const stored = &registryStorage(registry_value).configured_roots[@intFromEnum(key)];
    return @ptrCast(stored);
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
