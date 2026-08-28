const std = @import("std");

pub const engine_config_key = "engine.config@1";
pub const version = "2.0";
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
};

pub const SDDToolKitConfig = struct {
    version: []const u8,
    logs: LogsConfig,
    models: ModelsConfig,
    paths: PathsConfig,
};

pub const Owned = struct {
    parsed: std.json.Parsed(SDDToolKitConfig),

    pub fn value(self: *const Owned) *const SDDToolKitConfig {
        return &self.parsed.value;
    }

    pub fn deinit(self: *Owned) void {
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub const PublicError = enum {
    ENGINE_CONFIG_READ_ERROR,
    ENGINE_CONFIG_PARSE_ERROR,

    pub fn text(self: PublicError) []const u8 {
        return @tagName(self);
    }
};

pub const Registry = struct {
    config: Owned,

    pub fn init(config: Owned) Registry {
        return .{ .config = config };
    }

    pub fn query(self: *const Registry) *const SDDToolKitConfig {
        return self.config.value();
    }

    pub fn deinit(self: *Registry) void {
        self.config.deinit();
        self.* = undefined;
    }
};
