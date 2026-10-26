const std = @import("std");
const model_controls = @import("model_controls.zig");

pub const engine_config_basename = ".sddtoolkit.json";
pub const max_engine_config_bytes: usize = 1024 * 1024;

pub const LogsConfig = struct {
    level: []const u8,
    console: bool,
};

pub const ModelSlotConfig = struct {
    provider: []const u8,
    model: []const u8,
    reasoningEffort: ?[]const u8 = null,
};

pub const ModelsConfig = struct {
    slots: std.json.ArrayHashMap(ModelSlotConfig),
};

/// The total model tokens one workflow execution may use, shared by every call
/// (ADR 0037). Required, with no engine default; on the wire it is one positive
/// integer-written JSON number in the u32 range.
pub const WorkflowTokenBudget = struct {
    budget: @import("workflow_token_budget.zig").TotalTokenBudget,

    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!WorkflowTokenBudget {
        return .{ .budget = .{ .value = try @import("positive_json_integer.zig").jsonPositiveU32(a, source, options) } };
    }
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
    workflowTokenBudget: WorkflowTokenBudget,
    /// Sent on every inference request whose model takes a temperature, and on
    /// a runaway re-send respectively (ADR 0039). Required, with no default.
    temperature: model_controls.Temperature,
    temperatureRunawayRetry: model_controls.Temperature,
    paths: PathsConfig,
    principles: ?@import("principle_policy.zig").Config = null,
    validation: ValidationConfig = .{},

    pub fn temperatures(self: *const SDDToolKitConfig) model_controls.Temperatures {
        return .{ .configured = self.temperature, .runaway_retry = self.temperatureRunawayRetry };
    }
};

pub const ValidationConfig = struct {
    sourcePreservationCheck: bool = false,
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
