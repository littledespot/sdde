const filesystem_identity = @import("filesystem_identity.zig");

pub const project_schema = "project-toolchain/v1";
pub const preset_schema = "toolchain-preset/v1";
pub const project_filename = "toolchain.yaml";
pub const preset_suffix = ".toolchain-preset.yaml";
pub const max_document_bytes: usize = 1024 * 1024;
pub const max_total_bytes: usize = 16 * 1024 * 1024;
pub const max_presets: usize = 256;
pub const max_refs: usize = 32;
pub const max_policies: usize = 64;
pub const max_yaml_events: usize = 4096;
pub const max_yaml_tokens: usize = 4096;
pub const max_yaml_nesting_depth: usize = 16;
pub const max_yaml_scalar_bytes: usize = 4096;

pub const Error = error{InvalidToolchain};
pub const Entry = struct { name: []const u8, size: u64, identity: filesystem_identity.FileIdentity };
pub const Capture = struct { name: []const u8, bytes: []const u8 };

pub const RawNode = union(enum) {
    scalar: []const u8,
    sequence: []const *const RawNode,
    mapping: []const Pair,
};
pub const Pair = struct { key: *const RawNode, value: *const RawNode };
pub const RawDocument = struct { name: []const u8, root: *const RawNode };

pub const Layer = enum { language, runtime, framework, build, @"test", environment };
pub const Project = struct { presets: []const []const u8, policies: []const []const u8 };
pub const Preset = struct {
    package: []const u8,
    package_id: []const u8,
    layer: Layer,
    extends: []const []const u8,
    policies: []const []const u8,
};
pub const Registry = struct { presets: []const Preset };
pub const Resolved = struct { packages: []const *const Preset };
pub const Composed = struct { packages: []const []const u8, policies: []const []const u8 };
pub const PolicyContract = struct { id: []const u8, project_selectable: bool, locked_required: bool };
pub const PolicyRegistry = struct { contracts: []const PolicyContract };
