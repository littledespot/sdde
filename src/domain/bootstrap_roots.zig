const std = @import("std");
const filesystem_identity = @import("filesystem_identity.zig");

pub const bootstrap_root_contract_version = "bootstrap-roots/v1";

pub const PathKey = enum {
    specs,
    references,
    specs_archive,
    workflows,
    toolchain_preset,
    principles,
    templates,

    pub const count = @typeInfo(PathKey).@"enum".fields.len;

    pub fn role(self: PathKey) ConfiguredRootRole {
        return switch (self) {
            .specs => .specs_artifacts,
            .references => .reference_sources,
            .specs_archive => .archived_specs,
            .workflows => .workflow_authority,
            .toolchain_preset => .toolchain_preset_registry,
            .principles => .project_principles,
            .templates => .initialization_templates,
        };
    }

    pub fn accessClass(self: PathKey) RootAccessClass {
        return switch (self) {
            .references => .reference_read_only,
            .templates => .inaccessible,
            else => .engine_only,
        };
    }

    pub fn existencePolicy(self: PathKey) ExistencePolicy {
        return switch (self) {
            .workflows => .required_directory,
            else => .optional_directory,
        };
    }
};

pub const ConfiguredRootRole = enum {
    specs_artifacts,
    reference_sources,
    archived_specs,
    workflow_authority,
    toolchain_preset_registry,
    project_principles,
    initialization_templates,
};

pub const RootAccessClass = enum {
    engine_only,
    inaccessible,
    reference_read_only,
};

pub const ExistencePolicy = enum {
    required_directory,
    optional_directory,
};

pub const WorkspacePathPolicy = struct {
    policy_id: enum { portable_ascii_workspace_v1 } = .portable_ascii_workspace_v1,
    max_component_bytes: usize,
    max_relative_path_bytes: usize,
    max_absolute_path_bytes: usize,
};

pub const NoFollowFileIdentity = filesystem_identity.FileIdentity;

pub const ExactEngineConfigLocation = struct {
    canonical_project_root: []const u8,
    canonical_config_path: []const u8,
    no_follow_file_identity: NoFollowFileIdentity,
};

pub const NormalizedConfiguredPath = struct {
    path_key: PathKey,
    root_role: ConfiguredRootRole,
    relative_path: []const u8,
};

pub const ConfiguredRootCandidate = struct {
    path: NormalizedConfiguredPath,
    canonical_project_root: []const u8,
    canonical_path: []const u8,
};

pub const PhysicalDirectoryIdentity = filesystem_identity.FileIdentity;

pub const RootObservation = union(enum) {
    absent,
    directory: PhysicalDirectoryIdentity,
};

pub const ValidatedConfiguredRoot = struct {
    path_key: PathKey,
    root_role: ConfiguredRootRole,
    canonical_project_root: []const u8,
    configured_relative_path: []const u8,
    canonical_path: []const u8,
    access_class: RootAccessClass,
    existence_policy: ExistencePolicy,
    observation: RootObservation,

    pub fn isPresent(self: *const ValidatedConfiguredRoot) bool {
        return switch (self.observation) {
            .absent => false,
            .directory => true,
        };
    }
};

pub const BootstrapRootRegistryId = struct {
    canonical_project_root: []const u8,
    contract_version: []const u8,
};

pub const BootstrapRootRegistryCandidate = struct {
    id: BootstrapRootRegistryId,
    config_location: ExactEngineConfigLocation,
    configured_roots: [PathKey.count]ValidatedConfiguredRoot,
};

test "path keys own one closed role access and existence mapping" {
    inline for (@typeInfo(PathKey).@"enum".fields) |field| {
        const key: PathKey = @enumFromInt(field.value);
        _ = key.role();
        _ = key.accessClass();
        _ = key.existencePolicy();
    }

    try std.testing.expectEqual(ConfiguredRootRole.workflow_authority, PathKey.workflows.role());
    try std.testing.expectEqual(ExistencePolicy.required_directory, PathKey.workflows.existencePolicy());
    try std.testing.expectEqual(RootAccessClass.inaccessible, PathKey.templates.accessClass());
}
