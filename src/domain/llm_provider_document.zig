const std = @import("std");

pub const max_bytes: usize = 1024 * 1024;
pub const max_nesting_depth: usize = 16;
pub const max_providers: usize = 16;
pub const max_models_per_provider: usize = 256;
pub const max_models_total: usize = 256;

pub const RawProviderModelDefinition = struct {
    model: []const u8,
    config: std.json.Value,
};

pub const RawProviderDefinition = struct {
    provider: []const u8,
    models: []const RawProviderModelDefinition,
};

pub const RawLLMProviderDocument = struct {
    providers: []const RawProviderDefinition,
};

pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    document: RawLLMProviderDocument,

    pub fn init(backing_allocator: std.mem.Allocator) Owned {
        return .{ .arena = .init(backing_allocator), .document = undefined };
    }

    pub fn allocator(self: *Owned) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn value(self: *const Owned) *const RawLLMProviderDocument {
        return &self.document;
    }

    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
