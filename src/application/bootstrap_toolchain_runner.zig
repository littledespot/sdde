const std = @import("std");
const toolchain = @import("../domain/toolchain.zig");
const toolchain_safety = @import("../domain/toolchain_safety.zig");
const pipeline = @import("../domain/pipeline.zig");
const capture_project = @import("../actions/toolchain/capture_project_toolchain.zig");
const inventory_presets = @import("../actions/toolchain/inventory_toolchain_presets.zig");
const capture_presets = @import("../actions/toolchain/capture_toolchain_presets.zig");
const parse_documents = @import("../actions/toolchain/parse_toolchain_documents.zig");
const validate_project_schema = @import("../actions/toolchain/validate_project_toolchain_schema.zig");
const validate_preset_registry = @import("../actions/toolchain/validate_toolchain_preset_registry.zig");
const resolve_inheritance = @import("../actions/toolchain/resolve_toolchain_inheritance.zig");
const compose = @import("../actions/toolchain/compose_toolchain.zig");
const validate_safety = @import("../actions/toolchain/validate_toolchain_safety.zig");
const root_runner = @import("bootstrap_root_runner.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const execution = @import("bootstrap_execution.zig");

comptime {
    pipeline.validateLinear(
        &.{.bootstrap_root_registry},
        &.{
            capture_project.Action.contract,
            inventory_presets.Action.contract,
            capture_presets.Action.contract,
            parse_documents.Action.contract,
            validate_project_schema.Action.contract,
            validate_preset_registry.Action.contract,
            resolve_inheritance.Action.contract,
            compose.Action.contract,
            validate_safety.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    execution: *execution.State,
    roots: *root_runner.Runner,
    capture_project_action: capture_project.Action,
    inventory_presets_action: inventory_presets.Action,
    capture_presets_action: capture_presets.Action,
    parse_documents_action: parse_documents.Action,
    validate_project_schema_action: validate_project_schema.Action,
    validate_preset_registry_action: validate_preset_registry.Action,
    resolve_inheritance_action: resolve_inheritance.Action,
    compose_action: compose.Action,
    validate_safety_action: validate_safety.Action,
    scratch: std.heap.ArenaAllocator,
    project_capture: ?toolchain.Capture = null,
    preset_inventory: ?[]const toolchain.Entry = null,
    preset_captures: ?[]const toolchain.Capture = null,
    raw_documents: ?[]const toolchain.RawDocument = null,
    project: ?toolchain.Project = null,
    registry: ?toolchain.Registry = null,
    resolved: ?toolchain.Resolved = null,
    composed: ?toolchain.Composed = null,
    validated_owner: ?*toolchain_safety.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        execution_state: *execution.State,
        roots: *root_runner.Runner,
        capture_project_action: capture_project.Action,
        inventory_presets_action: inventory_presets.Action,
        capture_presets_action: capture_presets.Action,
        parse_documents_action: parse_documents.Action,
        validate_project_schema_action: validate_project_schema.Action,
        validate_preset_registry_action: validate_preset_registry.Action,
        resolve_inheritance_action: resolve_inheritance.Action,
        compose_action: compose.Action,
        validate_safety_action: validate_safety.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .execution = execution_state,
            .roots = roots,
            .capture_project_action = capture_project_action,
            .inventory_presets_action = inventory_presets_action,
            .capture_presets_action = capture_presets_action,
            .parse_documents_action = parse_documents_action,
            .validate_project_schema_action = validate_project_schema_action,
            .validate_preset_registry_action = validate_preset_registry_action,
            .resolve_inheritance_action = resolve_inheritance_action,
            .compose_action = compose_action,
            .validate_safety_action = validate_safety_action,
            .scratch = .init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.validated_owner) |owner| toolchain_safety.deinitOwner(owner);
        self.scratch.deinit();
        self.* = undefined;
    }

    pub fn invokeCaptureProject(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(capture_project.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.project_capture = self.capture_project_action.execute(
            self.scratch.allocator(),
            self.roots.registry(),
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(capture_project.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeInventoryPresets(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(inventory_presets.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.preset_inventory = self.inventory_presets_action.execute(
            self.scratch.allocator(),
            self.roots.registry(),
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(inventory_presets.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeCapturePresets(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(capture_presets.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.preset_captures = self.capture_presets_action.execute(
            self.scratch.allocator(),
            self.roots.registry(),
            self.project_capture.?,
            self.preset_inventory.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(capture_presets.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeParseDocuments(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(parse_documents.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.raw_documents = self.parse_documents_action.execute(
            self.scratch.allocator(),
            self.project_capture.?,
            self.preset_captures.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(parse_documents.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeValidateProjectSchema(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_project_schema.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.project = self.validate_project_schema_action.execute(
            self.scratch.allocator(),
            self.raw_documents.?[0],
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(validate_project_schema.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeValidatePresetRegistry(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_preset_registry.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.registry = self.validate_preset_registry_action.execute(
            self.scratch.allocator(),
            self.raw_documents.?[1..],
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(validate_preset_registry.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeResolveInheritance(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(resolve_inheritance.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.resolved = self.resolve_inheritance_action.execute(
            self.scratch.allocator(),
            self.project.?,
            self.registry.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(resolve_inheritance.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeCompose(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(compose.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.composed = self.compose_action.execute(
            self.scratch.allocator(),
            self.project.?,
            self.resolved.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(compose.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn invokeValidateSafety(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_safety.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.validated_owner = self.validate_safety_action.execute(
            self.allocator,
            self.composed.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.execution.finish(validate_safety.Action.contract, .TOOLCHAIN_INVALID);
    }

    pub fn takeToolchain(self: *Runner) *toolchain_safety.Owner {
        const owner = self.validated_owner.?;
        self.validated_owner = null;
        return owner;
    }
};
