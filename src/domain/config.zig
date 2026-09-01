const std = @import("std");

pub const engine_config_basename = ".sddtoolkit.json";
pub const max_engine_config_bytes: usize = 1024 * 1024;

pub const PromptCapture = enum {
    request,
    response,
    reference_body,
    code_body,
};

pub const LogsConfig = struct {
    level: []const u8,
    console: bool,
    promptCapture: []const PromptCapture,
};

pub const ModelSlotConfig = struct {
    provider: []const u8,
    model: []const u8,
    reasoningEffort: ?[]const u8 = null,
};

pub const ModelsConfig = struct {
    slots: std.json.ArrayHashMap(ModelSlotConfig),
};

pub const PathsConfig = struct {
    specs: []const u8,
    references: []const u8,
    specsArchive: []const u8,
    workflows: []const u8,
    toolchainPreset: []const u8,
    principles: []const u8,
    templates: []const u8,
    providers: []const u8,
};

pub const SDDToolKitConfig = struct {
    logs: LogsConfig,
    models: ModelsConfig,
    paths: PathsConfig,
};

pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    config: SDDToolKitConfig,

    pub fn init(backing_allocator: std.mem.Allocator) Owned {
        return .{
            .arena = .init(backing_allocator),
            .config = undefined,
        };
    }

    pub fn allocator(self: *Owned) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn value(self: *const Owned) *const SDDToolKitConfig {
        return &self.config;
    }

    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
