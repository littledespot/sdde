const std = @import("std");
const workflow_definition = @import("../domain/workflow_definition.zig");
const workflow_compilation = @import("../domain/workflow_compilation.zig");
const workflow_inventory = @import("../domain/workflow_inventory.zig");
const workflow_registry = @import("../domain/workflow_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const build_layout = @import("../actions/workflow/build_workflow_authority_layout.zig");
const enumerate_resources = @import("../actions/workflow/enumerate_workflow_authority_resources.zig");
const normalize_entries = @import("../actions/workflow/normalize_workflow_authority_entries.zig");
const build_accounts = @import("../actions/workflow/build_workflow_authority_entry_accounts.zig");
const build_inventory = @import("../actions/workflow/build_workflow_authority_inventory.zig");
const validate_inventory = @import("../actions/workflow/validate_workflow_authority_inventory.zig");
const capture_definitions = @import("../actions/workflow/capture_workflow_definitions.zig");
const parse_definitions = @import("../actions/workflow/parse_workflow_definitions.zig");
const validate_schema = @import("../actions/workflow/validate_workflow_definition_schema.zig");
const resolve_resources = @import("../actions/workflow/resolve_workflow_resources.zig");
const capture_resources = @import("../actions/workflow/capture_workflow_resources.zig");
const validate_operations = @import("../actions/workflow/validate_workflow_operation_registry.zig");
const compile_graphs = @import("../actions/workflow/compile_workflow_graphs.zig");
const validate_graphs = @import("../actions/workflow/validate_compiled_workflow_graphs.zig");
const build_registry = @import("../actions/workflow/build_workflow_definition_registry.zig");
const validate_registry = @import("../actions/workflow/validate_workflow_definition_registry.zig");
const root_runner = @import("bootstrap_root_runner.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const execution = @import("bootstrap_execution.zig");

comptime {
    pipeline.validateLinear(
        &.{ .bootstrap_root_registry, .workflow_operation_registry },
        &.{
            build_layout.Action.contract,
            enumerate_resources.Action.contract,
            normalize_entries.Action.contract,
            build_accounts.Action.contract,
            build_inventory.Action.contract,
            validate_inventory.Action.contract,
            capture_definitions.Action.contract,
            parse_definitions.Action.contract,
            validate_schema.Action.contract,
            resolve_resources.Action.contract,
            capture_resources.Action.contract,
            validate_operations.Action.contract,
            compile_graphs.Action.contract,
            validate_graphs.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    execution: *execution.State,
    roots: *root_runner.Runner,
    build_layout_action: build_layout.Action,
    enumerate_resources_action: enumerate_resources.Action,
    normalize_entries_action: normalize_entries.Action,
    build_accounts_action: build_accounts.Action,
    build_inventory_action: build_inventory.Action,
    validate_inventory_action: validate_inventory.Action,
    capture_definitions_action: capture_definitions.Action,
    parse_definitions_action: parse_definitions.Action,
    validate_schema_action: validate_schema.Action,
    resolve_resources_action: resolve_resources.Action,
    capture_resources_action: capture_resources.Action,
    validate_operations_action: validate_operations.Action,
    compile_graphs_action: compile_graphs.Action,
    validate_graphs_action: validate_graphs.Action,
    build_registry_action: build_registry.Action,
    validate_registry_action: validate_registry.Action,
    scratch: std.heap.ArenaAllocator,
    layout: ?workflow_inventory.Layout = null,
    raw_entries: ?[]workflow_inventory.InventoryDescriptor = null,
    normalized_entries: ?[]workflow_inventory.InventoryDescriptor = null,
    entry_accounts: ?workflow_inventory.AccountSet = null,
    inventory_candidate: ?workflow_inventory.Inventory = null,
    inventory: ?workflow_inventory.Inventory = null,
    captures: ?[]const workflow_inventory.Capture = null,
    raw_definitions: ?[]const workflow_definition.RawDefinition = null,
    definitions: ?[]const workflow_definition.Definition = null,
    resource_manifest: ?workflow_inventory.ResourceManifest = null,
    resource_captures: ?[]const workflow_inventory.Capture = null,
    compiled_graphs: ?[]const workflow_compilation.CompiledWorkflow = null,
    validated_graphs: ?workflow_compilation.ValidatedGraphs = null,
    registry_candidate: ?workflow_registry.RegistryCandidate = null,
    validated_owner: ?*workflow_registry.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        execution_state: *execution.State,
        roots: *root_runner.Runner,
        build_layout_action: build_layout.Action,
        enumerate_resources_action: enumerate_resources.Action,
        normalize_entries_action: normalize_entries.Action,
        build_accounts_action: build_accounts.Action,
        build_inventory_action: build_inventory.Action,
        validate_inventory_action: validate_inventory.Action,
        capture_definitions_action: capture_definitions.Action,
        parse_definitions_action: parse_definitions.Action,
        validate_schema_action: validate_schema.Action,
        resolve_resources_action: resolve_resources.Action,
        capture_resources_action: capture_resources.Action,
        validate_operations_action: validate_operations.Action,
        compile_graphs_action: compile_graphs.Action,
        validate_graphs_action: validate_graphs.Action,
        build_registry_action: build_registry.Action,
        validate_registry_action: validate_registry.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .execution = execution_state,
            .roots = roots,
            .build_layout_action = build_layout_action,
            .enumerate_resources_action = enumerate_resources_action,
            .normalize_entries_action = normalize_entries_action,
            .build_accounts_action = build_accounts_action,
            .build_inventory_action = build_inventory_action,
            .validate_inventory_action = validate_inventory_action,
            .capture_definitions_action = capture_definitions_action,
            .parse_definitions_action = parse_definitions_action,
            .validate_schema_action = validate_schema_action,
            .resolve_resources_action = resolve_resources_action,
            .capture_resources_action = capture_resources_action,
            .validate_operations_action = validate_operations_action,
            .compile_graphs_action = compile_graphs_action,
            .validate_graphs_action = validate_graphs_action,
            .build_registry_action = build_registry_action,
            .validate_registry_action = validate_registry_action,
            .scratch = .init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.validated_owner) |owner| workflow_registry.deinitOwner(owner);
        self.scratch.deinit();
        self.* = undefined;
    }

    pub fn invokeBuildLayout(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_layout.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.layout = self.build_layout_action.execute(self.roots.registry()) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.execution.finish(build_layout.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeEnumerateResources(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(enumerate_resources.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.raw_entries = self.enumerate_resources_action.execute(
            self.scratch.allocator(),
            self.layout.?,
            self.execution.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.WorkflowAuthorityInventoryInvalid => .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID },
        };
        return self.execution.finish(enumerate_resources.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeNormalizeEntries(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(normalize_entries.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.normalized_entries = self.normalize_entries_action.execute(self.raw_entries.?) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.execution.finish(normalize_entries.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeBuildAccounts(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_accounts.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.entry_accounts = self.build_accounts_action.execute(
            self.scratch.allocator(),
            self.normalized_entries.?,
        ) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.execution.finish(build_accounts.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeBuildInventory(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_inventory.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.inventory_candidate = self.build_inventory_action.execute(self.layout.?, self.normalized_entries.?, self.entry_accounts.?);
        return self.execution.finish(build_inventory.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeValidateInventory(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_inventory.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.inventory = self.validate_inventory_action.execute(self.inventory_candidate.?) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.execution.finish(validate_inventory.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeCaptureDefinitions(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(capture_definitions.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR)) |outcome| return outcome;
        self.captures = self.capture_definitions_action.execute(
            self.scratch.allocator(),
            self.inventory.?,
            self.execution.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.WorkflowDefinitionReadError => .{ .failed = .WORKFLOW_DEFINITION_READ_ERROR },
        };
        return self.execution.finish(capture_definitions.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR);
    }

    pub fn invokeParseDefinitions(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(parse_definitions.Action.contract, .WORKFLOW_DEFINITION_PARSE_ERROR)) |outcome| return outcome;
        self.raw_definitions = self.parse_definitions_action.execute(
            self.scratch.allocator(),
            self.captures.?,
        ) catch return .{ .failed = .WORKFLOW_DEFINITION_PARSE_ERROR };
        return self.execution.finish(parse_definitions.Action.contract, .WORKFLOW_DEFINITION_PARSE_ERROR);
    }

    pub fn invokeValidateSchema(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_schema.Action.contract, .WORKFLOW_DEFINITION_SCHEMA_INVALID)) |outcome| return outcome;
        self.definitions = self.validate_schema_action.execute(
            self.scratch.allocator(),
            self.raw_definitions.?,
        ) catch return .{ .failed = .WORKFLOW_DEFINITION_SCHEMA_INVALID };
        return self.execution.finish(validate_schema.Action.contract, .WORKFLOW_DEFINITION_SCHEMA_INVALID);
    }

    pub fn invokeCompileGraphs(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(compile_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID)) |outcome| return outcome;
        self.compiled_graphs = self.compile_graphs_action.execute(
            self.scratch.allocator(),
            self.definitions.?,
            self.inventory.?,
            self.resource_manifest.?,
            self.resource_captures.?,
        ) catch return .{ .failed = .WORKFLOW_GRAPH_COMPILE_INVALID };
        return self.execution.finish(compile_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID);
    }

    pub fn invokeResolveResources(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(resolve_resources.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.resource_manifest = self.resolve_resources_action.execute(
            self.scratch.allocator(),
            self.inventory.?,
            self.definitions.?,
        ) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.execution.finish(resolve_resources.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    pub fn invokeCaptureResources(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(capture_resources.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR)) |outcome| return outcome;
        self.resource_captures = self.capture_resources_action.execute(
            self.scratch.allocator(),
            self.inventory.?,
            self.resource_manifest.?,
            self.execution.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.WorkflowResourceReadError => .{ .failed = .WORKFLOW_DEFINITION_READ_ERROR },
        };
        return self.execution.finish(capture_resources.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR);
    }

    pub fn invokeValidateOperations(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_operations.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID)) |outcome| return outcome;
        self.validate_operations_action.execute(self.compile_graphs_action.registry) catch {
            return .{ .failed = .WORKFLOW_GRAPH_COMPILE_INVALID };
        };
        return self.execution.finish(validate_operations.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID);
    }

    pub fn invokeValidateGraphs(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID)) |outcome| return outcome;
        self.validated_graphs = self.validate_graphs_action.execute(
            self.scratch.allocator(),
            self.compiled_graphs.?,
        ) catch return .{ .failed = .WORKFLOW_GRAPH_COMPILE_INVALID };
        return self.execution.finish(validate_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID);
    }

    pub fn invokeBuildRegistry(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID)) |outcome| return outcome;
        self.registry_candidate = self.build_registry_action.execute(
            self.scratch.allocator(),
            self.inventory.?,
            self.captures.?,
            self.resource_manifest.?,
            self.resource_captures.?,
            self.definitions.?,
            self.validated_graphs.?,
        ) catch return .{ .failed = .WORKFLOW_REGISTRY_INVALID };
        return self.execution.finish(build_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID);
    }

    pub fn invokeValidateRegistry(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID)) |outcome| return outcome;
        self.validated_owner = self.validate_registry_action.execute(
            self.allocator,
            self.registry_candidate.?,
        ) catch return .{ .failed = .WORKFLOW_REGISTRY_INVALID };
        return self.execution.finish(validate_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID);
    }

    pub fn takeRegistry(self: *Runner) *workflow_registry.Owner {
        const owner = self.validated_owner.?;
        self.validated_owner = null;
        return owner;
    }
};
