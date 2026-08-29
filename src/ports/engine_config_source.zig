const std = @import("std");
const filesystem_identity = @import("../domain/filesystem_identity.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{EngineConfigReadFailure};

pub const RawEngineConfig = struct {
    bytes: []u8,

    pub fn deinit(self: *RawEngineConfig, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const ObservedFileIdentity = filesystem_identity.FileIdentity;

pub const ExactEngineConfigFile = struct {
    canonical_project_root: [:0]u8,
    canonical_config_path: [:0]u8,
    no_follow_file_identity: ObservedFileIdentity,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (*anyopaque, Allocator, usize) Error!RawEngineConfig,
        deinit: *const fn (*anyopaque, Allocator) void,
    };

    pub fn init(
        canonical_project_root: [:0]u8,
        canonical_config_path: [:0]u8,
        no_follow_file_identity: ObservedFileIdentity,
        context: *anyopaque,
        vtable: *const VTable,
    ) ExactEngineConfigFile {
        return .{
            .canonical_project_root = canonical_project_root,
            .canonical_config_path = canonical_config_path,
            .no_follow_file_identity = no_follow_file_identity,
            .context = context,
            .vtable = vtable,
        };
    }

    pub fn read(
        self: *ExactEngineConfigFile,
        allocator: Allocator,
        max_bytes: usize,
    ) Error!RawEngineConfig {
        return self.vtable.read(self.context, allocator, max_bytes);
    }

    pub fn deinit(self: *ExactEngineConfigFile, allocator: Allocator) void {
        self.vtable.deinit(self.context, allocator);
        allocator.free(self.canonical_config_path);
        allocator.free(self.canonical_project_root);
        self.* = undefined;
    }
};

pub const Locator = struct {
    context: *anyopaque,
    locate_fn: *const fn (*anyopaque, Allocator) Error!ExactEngineConfigFile,

    pub fn locate(self: Locator, allocator: Allocator) Error!ExactEngineConfigFile {
        return self.locate_fn(self.context, allocator);
    }
};
