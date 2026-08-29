const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Error = error{EngineConfigReadFailure};

pub const RawEngineConfig = struct {
    bytes: []u8,

    pub fn deinit(self: *RawEngineConfig, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const ExactEngineConfig = struct {
    canonical_project_root: [:0]u8,
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (*anyopaque, Allocator, usize) Error!RawEngineConfig,
        deinit: *const fn (*anyopaque, Allocator) void,
    };

    pub fn init(
        canonical_project_root: [:0]u8,
        context: *anyopaque,
        vtable: *const VTable,
    ) ExactEngineConfig {
        return .{
            .canonical_project_root = canonical_project_root,
            .context = context,
            .vtable = vtable,
        };
    }

    pub fn read(
        self: *ExactEngineConfig,
        allocator: Allocator,
        max_bytes: usize,
    ) Error!RawEngineConfig {
        return self.vtable.read(self.context, allocator, max_bytes);
    }

    pub fn deinit(self: *ExactEngineConfig, allocator: Allocator) void {
        self.vtable.deinit(self.context, allocator);
        allocator.free(self.canonical_project_root);
        self.* = undefined;
    }
};

pub const Locator = struct {
    context: *anyopaque,
    locate_fn: *const fn (*anyopaque, Allocator) Error!ExactEngineConfig,

    pub fn locate(self: Locator, allocator: Allocator) Error!ExactEngineConfig {
        return self.locate_fn(self.context, allocator);
    }
};
