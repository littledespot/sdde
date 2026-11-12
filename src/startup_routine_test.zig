const std = @import("std");
const startup = @import("application/startup_routine.zig");
const bootstrap_error = @import("domain/bootstrap_error.zig");
const bootstrap_roots = @import("domain/bootstrap_roots.zig");
const config = @import("domain/config.zig");
const definition = @import("domain/workflow_definition.zig");
const file_identity = @import("domain/filesystem_identity.zig");
const inventory = @import("domain/workflow_inventory.zig");
const inventory_building = @import("domain/workflow_authority_inventory_build.zig");
const log_policy = @import("domain/log_policy.zig");
const pipeline = @import("domain/pipeline.zig");
const telemetry = @import("domain/telemetry.zig");
const config_port = @import("ports/engine_config_source.zig");
const inspector_port = @import("ports/bootstrap_root_inspector.zig");
const parser_port = @import("ports/workflow_definition_parser.zig");
const source_port = @import("ports/workflow_authority_source.zig");
const schema_adapter = @import("adapters/parsers/model_result_schemas.zig");
const core_operations = @import("composition/core_workflow_operations.zig");

const step_count = @typeInfo(startup.Step).@"enum".fields.len;

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": false },
    \\  "workflowTokenBudget": 100000,
    \\  "temperature": 0.1,
    \\  "temperatureRunawayRetry": 1,
    \\  "models": { "slots": {} },
    \\  "paths": {
    \\    "specs": "specs", "references": "references",
    \\    "specsArchive": "specs/archive", "workflows": ".sdd/workflows",
    \\    "toolchainPreset": ".sdd/presets",
    \\    "principles": ".sdd/principles", "templates": ".sdd/templates",
    \\    "providers": ".sddproviders.json"
    \\  }
    \\}
;

const policy: bootstrap_roots.WorkspacePathPolicy = .{
    .max_component_bytes = 255,
    .max_relative_path_bytes = 1024,
    .max_absolute_path_bytes = 4096,
};

// A run against fake ports: each port records its call, so the order in which the routine reaches
// them is visible, and each can be told to reject or cancel.

const Call = enum { locate, read, inspect, enumerate, capture, parse };
const Behaviour = enum { ok, reject, cancel };

const World = struct {
    config_bytes: []const u8 = valid_config,
    locate: Behaviour = .ok,
    read: Behaviour = .ok,
    inspect: Behaviour = .ok,
    enumerate: Behaviour = .ok,
    capture: Behaviour = .ok,
    parse: Behaviour = .ok,
    workflows_present: bool = true,
    descriptors: []const inventory.InventoryDescriptor = &.{},
    observed_read_limit: usize = 0,
    schemas: schema_adapter.Adapter = .{},
    trace: [64]Call = undefined,
    trace_len: usize = 0,

    fn calls(self: *const World) []const Call {
        return self.trace[0..self.trace_len];
    }

    fn record(self: *World, call: Call) void {
        self.trace[self.trace_len] = call;
        self.trace_len += 1;
    }

    fn ports(self: *World) startup.Ports {
        return .{
            .config_locator = self.locator(),
            .root_inspector = .{ .context = self, .inspect_fn = inspectFn },
            .workflow_enumerator = .{ .context = self, .enumerate_fn = enumerateFn },
            .workflow_capturer = self.capturer(),
            .workflow_parser = .{ .context = self, .parse_fn = parseFn },
            .result_schema_compiler = self.schemas.compiler(),
        };
    }

    fn locator(self: *World) config_port.Locator {
        return .{ .context = self, .locate_fn = locateFn };
    }

    fn capturer(self: *World) source_port.Capturer {
        return .{ .context = self, .capture_fn = captureFn };
    }

    fn run(self: *World, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *startup.Diagnostic) startup.Outcome {
        return startup.run(self.ports(), allocator, runtime, diagnostic, .{
            .path_policy = policy,
            .operations = &core_operations.registry,
        });
    }

    fn of(context: *anyopaque) *World {
        return @ptrCast(@alignCast(context));
    }

    fn locateFn(context: *anyopaque, allocator: std.mem.Allocator) config_port.Error!config_port.ExactEngineConfigFile {
        const self = of(context);
        self.record(.locate);
        if (self.locate == .reject) return error.EngineConfigReadFailure;
        const root = allocator.dupeZ(u8, "/project") catch return error.EngineConfigReadFailure;
        errdefer allocator.free(root);
        const path = allocator.dupeZ(u8, "/project/.sddtoolkit.json") catch return error.EngineConfigReadFailure;
        return config_port.ExactEngineConfigFile.init(root, path, .{ .filesystem_id = 1, .file_id = 1 }, self, &file_vtable);
    }

    fn fileRead(context: *anyopaque, allocator: std.mem.Allocator, max_bytes: usize) config_port.Error!config_port.RawEngineConfig {
        const self = of(context);
        self.record(.read);
        self.observed_read_limit = max_bytes;
        if (self.read == .reject) return error.EngineConfigReadFailure;
        return .{ .bytes = allocator.dupe(u8, self.config_bytes) catch return error.EngineConfigReadFailure };
    }

    fn fileDeinit(_: *anyopaque, _: std.mem.Allocator) void {}

    const file_vtable: config_port.ExactEngineConfigFile.VTable = .{ .read = fileRead, .deinit = fileDeinit };

    fn inspectFn(context: *anyopaque, relative_path: []const u8) inspector_port.Error!bootstrap_roots.RootObservation {
        const self = of(context);
        self.record(.inspect);
        switch (self.inspect) {
            .cancel => return error.Cancelled,
            .reject => return error.BootstrapRootInspectionFailure,
            .ok => {},
        }
        if (self.workflows_present and std.mem.eql(u8, relative_path, ".sdd/workflows")) {
            return .{ .directory = .{ .filesystem_id = 1, .file_id = 4 } };
        }
        return .absent;
    }

    fn enumerateFn(
        context: *anyopaque,
        _: *const @import("domain/bootstrap_root_registry.zig").ConfiguredBaseRootCapability,
        allocator: std.mem.Allocator,
        _: pipeline.NodeRuntime,
    ) source_port.Error![]inventory.InventoryDescriptor {
        const self = of(context);
        self.record(.enumerate);
        switch (self.enumerate) {
            .cancel => return error.Cancelled,
            .reject => return error.InventoryInvalid,
            .ok => {},
        }
        return allocator.dupe(inventory.InventoryDescriptor, self.descriptors) catch error.InventoryInvalid;
    }

    fn captureFn(
        context: *anyopaque,
        _: *const @import("domain/bootstrap_root_registry.zig").ConfiguredBaseRootCapability,
        _: inventory.InventoryDescriptor,
        allocator: std.mem.Allocator,
        _: pipeline.NodeRuntime,
    ) source_port.Error![]const u8 {
        const self = of(context);
        self.record(.capture);
        switch (self.capture) {
            .cancel => return error.Cancelled,
            .reject => return error.DefinitionReadError,
            .ok => {},
        }
        return allocator.dupe(u8, "abc") catch error.DefinitionReadError;
    }

    fn parseFn(context: *anyopaque, allocator: std.mem.Allocator, _: []const inventory.Capture) parser_port.Error![]const definition.RawDefinition {
        const self = of(context);
        self.record(.parse);
        if (self.parse == .reject) return error.InvalidWorkflowDefinition;
        return allocator.alloc(definition.RawDefinition, 0) catch error.InvalidWorkflowDefinition;
    }
};

/// Reports `stop` at the check numbered `remaining`; every earlier check is active.
const Gate = struct {
    remaining: usize,
    stop: pipeline.RuntimeStatus,

    fn runtime(self: *Gate) pipeline.NodeRuntime {
        return .{ .context = self, .status_fn = status };
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Gate = @ptrCast(@alignCast(context.?));
        if (self.remaining == 0) return self.stop;
        self.remaining -= 1;
        return .active;
    }
};

fn expectFailure(
    world: *World,
    expected_step: startup.Step,
    expected_code: bootstrap_error.PublicError,
) !void {
    var diagnostic: startup.Diagnostic = .{};
    var outcome = world.run(std.testing.allocator, .{}, &diagnostic);
    defer outcome.deinit();
    try std.testing.expectEqual(expected_code, outcome.failed);
    try std.testing.expectEqual(@as(?startup.Step, expected_step), diagnostic.step);
}

fn expectCancelled(world: *World, expected_step: startup.Step) !void {
    var diagnostic: startup.Diagnostic = .{};
    var outcome = world.run(std.testing.allocator, .{}, &diagnostic);
    defer outcome.deinit();
    try std.testing.expect(outcome == .cancelled);
    try std.testing.expectEqual(@as(?startup.Step, expected_step), diagnostic.step);
}

test "a complete run reaches the ports in step order and publishes every validated owner" {
    var world: World = .{};
    var diagnostic: startup.Diagnostic = .{};
    var outcome = world.run(std.testing.allocator, .{}, &diagnostic);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
    try std.testing.expectEqual(@as(?startup.Step, null), diagnostic.step);
    try std.testing.expectEqualSlices(
        Call,
        &.{ .locate, .read, .inspect, .inspect, .inspect, .inspect, .inspect, .inspect, .inspect, .enumerate, .parse },
        world.calls(),
    );
    try std.testing.expectEqual(config.max_engine_config_bytes, world.observed_read_limit);
}

test "each failing step reports itself with its fixed public code and stops later steps" {
    {
        var world: World = .{ .locate = .reject };
        try expectFailure(&world, .locate_config, .ENGINE_CONFIG_READ_ERROR);
        try std.testing.expectEqualSlices(Call, &.{.locate}, world.calls());
    }
    {
        var world: World = .{ .read = .reject };
        try expectFailure(&world, .read_config, .ENGINE_CONFIG_READ_ERROR);
        try std.testing.expectEqualSlices(Call, &.{ .locate, .read }, world.calls());
    }
    {
        var world: World = .{ .config_bytes = "not json" };
        try expectFailure(&world, .decode_config, .ENGINE_CONFIG_PARSE_ERROR);
        try std.testing.expectEqualSlices(Call, &.{ .locate, .read }, world.calls());
    }
    {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, valid_config, "\"debug\"", "\"notice\"");
        defer std.testing.allocator.free(bytes);
        var world: World = .{ .config_bytes = bytes };
        try expectFailure(&world, .canonicalize_log_level, .LOGGING_POLICY_INVALID);
    }
    {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, valid_config, "\"specs\": \"specs\"", "\"specs\": \"/absolute\"");
        defer std.testing.allocator.free(bytes);
        var world: World = .{ .config_bytes = bytes };
        try expectFailure(&world, .validate_root_paths, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
        try std.testing.expectEqualSlices(Call, &.{ .locate, .read }, world.calls());
    }
    {
        const bytes = try std.mem.replaceOwned(u8, std.testing.allocator, valid_config, ".sddproviders.json", "providers.json");
        defer std.testing.allocator.free(bytes);
        var world: World = .{ .config_bytes = bytes };
        try expectFailure(&world, .validate_provider_path, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }
    {
        var world: World = .{ .workflows_present = false };
        try expectFailure(&world, .validate_roots, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }
    {
        var world: World = .{ .inspect = .reject };
        try expectFailure(&world, .validate_roots, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
        try std.testing.expectEqualSlices(Call, &.{ .locate, .read, .inspect }, world.calls());
    }
    {
        var world: World = .{ .enumerate = .reject };
        try expectFailure(&world, .enumerate_workflow_resources, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }
    {
        const invalid_entry = [_]inventory.InventoryDescriptor{.{
            .path = "../escape.md",
            .kind = .file,
            .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 9 },
            .size = 1,
        }};
        var world: World = .{ .descriptors = &invalid_entry };
        try expectFailure(&world, .normalize_workflow_entries, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }
    {
        const definition_entry = [_]inventory.InventoryDescriptor{.{
            .path = "flow.workflow.yaml",
            .kind = .file,
            .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 9 },
            .size = 3,
        }};
        var world: World = .{ .descriptors = &definition_entry, .capture = .reject };
        try expectFailure(&world, .capture_workflows, .WORKFLOW_DEFINITION_READ_ERROR);
        try std.testing.expectEqual(@as(usize, 0), std.mem.count(Call, world.calls(), &.{.parse}));
    }
    {
        var world: World = .{ .parse = .reject };
        try expectFailure(&world, .parse_workflows, .WORKFLOW_DEFINITION_PARSE_ERROR);
    }
}

test "explicit cancellation from a port stays distinct from failure" {
    {
        var world: World = .{ .inspect = .cancel };
        try expectCancelled(&world, .validate_roots);
    }
    {
        var world: World = .{ .enumerate = .cancel };
        try expectCancelled(&world, .enumerate_workflow_resources);
    }
    {
        const definition_entry = [_]inventory.InventoryDescriptor{.{
            .path = "flow.workflow.yaml",
            .kind = .file,
            .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 9 },
            .size = 3,
        }};
        var world: World = .{ .descriptors = &definition_entry, .capture = .cancel };
        try expectCancelled(&world, .capture_workflows);
    }
}

test "cancellation or deadline between any two steps stops with that step's report" {
    // The routine checks the runtime before the first step and after each step, so one more check
    // than there are steps; check k follows step k - 1, and check 0 belongs to the first step.
    for (0..step_count + 1) |check| {
        const expected: startup.Step = @enumFromInt(if (check == 0) 0 else check - 1);
        {
            var world: World = .{};
            var gate: Gate = .{ .remaining = check, .stop = .cancelled };
            var diagnostic: startup.Diagnostic = .{};
            var outcome = world.run(std.testing.allocator, gate.runtime(), &diagnostic);
            defer outcome.deinit();
            try std.testing.expect(outcome == .cancelled);
            try std.testing.expectEqual(@as(?startup.Step, expected), diagnostic.step);
        }
        {
            var world: World = .{};
            var gate: Gate = .{ .remaining = check, .stop = .deadline_exhausted };
            var diagnostic: startup.Diagnostic = .{};
            var outcome = world.run(std.testing.allocator, gate.runtime(), &diagnostic);
            defer outcome.deinit();
            try std.testing.expectEqual(startup.code(expected), outcome.failed);
            try std.testing.expectEqual(@as(?startup.Step, expected), diagnostic.step);
        }
    }
    var world: World = .{};
    var gate: Gate = .{ .remaining = step_count + 1, .stop = .cancelled };
    var diagnostic: startup.Diagnostic = .{};
    var outcome = world.run(std.testing.allocator, gate.runtime(), &diagnostic);
    defer outcome.deinit();
    try std.testing.expect(outcome == .ready);
}

test "an allocation failure in any step is that step's public failure and leaks nothing" {
    // Allocations happen in step order, so the failing step never moves earlier as the failing
    // allocation moves later: each reported step is a step the run had reached.
    var induced_any = false;
    var previous: usize = 0;
    var index: usize = 0;
    while (true) : (index += 1) {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        var world: World = .{};
        var diagnostic: startup.Diagnostic = .{};
        var outcome = world.run(failing.allocator(), .{}, &diagnostic);
        defer outcome.deinit();
        if (!failing.has_induced_failure) {
            try std.testing.expect(outcome == .ready);
            break;
        }
        induced_any = true;
        const step = diagnostic.step orelse return error.FailureWithoutStep;
        try std.testing.expectEqual(startup.code(step), outcome.failed);
        try std.testing.expect(@intFromEnum(step) >= previous);
        previous = @intFromEnum(step);
    }
    try std.testing.expect(induced_any);
    try std.testing.expect(previous > @intFromEnum(startup.Step.read_config));
}

test "public codes are pinned for one step of each family" {
    try std.testing.expectEqual(bootstrap_error.PublicError.ENGINE_CONFIG_READ_ERROR, startup.code(.read_config));
    try std.testing.expectEqual(bootstrap_error.PublicError.ENGINE_CONFIG_PARSE_ERROR, startup.code(.decode_config));
    try std.testing.expectEqual(bootstrap_error.PublicError.LOGGING_POLICY_INVALID, startup.code(.validate_logging_policy));
    try std.testing.expectEqual(bootstrap_error.PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR, startup.code(.validate_roots));
    try std.testing.expectEqual(bootstrap_error.PublicError.BOOTSTRAP_ROOT_REGISTRY_INVALID, startup.code(.build_registry_id));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_AUTHORITY_INVENTORY_INVALID, startup.code(.resolve_workflow_resources));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_DEFINITION_READ_ERROR, startup.code(.capture_workflow_resources));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_DEFINITION_PARSE_ERROR, startup.code(.parse_workflows));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_DEFINITION_SCHEMA_INVALID, startup.code(.validate_workflow_schema));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_GRAPH_COMPILE_INVALID, startup.code(.compile_workflows));
    try std.testing.expectEqual(bootstrap_error.PublicError.WORKFLOW_REGISTRY_INVALID, startup.code(.validate_workflow_registry));
}

test "the validated inventory is a distinct type that the later steps require" {
    try std.testing.expect(inventory_building.ValidatedInventory != inventory.Inventory);
    const validate_return = @typeInfo(@typeInfo(@TypeOf(startup.steps.validateWorkflowInventory)).@"fn".return_type.?).error_union.payload;
    try std.testing.expect(validate_return == inventory_building.ValidatedInventory);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.captureWorkflows)).@"fn".params[2].type.? == inventory_building.ValidatedInventory);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.resolveWorkflowResources)).@"fn".params[1].type.? == inventory_building.ValidatedInventory);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.captureWorkflowResources)).@"fn".params[2].type.? == inventory_building.ValidatedInventory);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.buildWorkflowRegistry)).@"fn".params[1].type.? == inventory_building.ValidatedInventory);
    // The operation registry and the graphs follow the same rule: the validating step returns a
    // distinct type and the next step requires exactly it.
    const operations_return = @typeInfo(@typeInfo(@TypeOf(startup.steps.validateWorkflowOperations)).@"fn".return_type.?).error_union.payload;
    try std.testing.expect(operations_return == startup.ValidatedOperations);
    try std.testing.expect(operations_return != *const @import("ports/workflow_operation_registry.zig").Registry);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.compileWorkflows)).@"fn".params[1].type.? == startup.ValidatedOperations);
    const graphs_return = @typeInfo(@typeInfo(@TypeOf(startup.steps.validateWorkflowGraphs)).@"fn".return_type.?).error_union.payload;
    const compilation = @import("domain/workflow_compilation.zig");
    try std.testing.expect(graphs_return == compilation.ValidatedGraphs);
    try std.testing.expect(graphs_return != []const compilation.CompiledWorkflow);
    try std.testing.expect(@typeInfo(@TypeOf(startup.steps.buildWorkflowRegistry)).@"fn".params[6].type.? == compilation.ValidatedGraphs);
}

test "locating maps a locator rejection without taking on read work" {
    var world: World = .{ .locate = .reject };
    try std.testing.expectError(error.EngineConfigReadFailure, startup.steps.locateConfig(world.locator(), std.testing.allocator));
    try std.testing.expectEqualSlices(Call, &.{.locate}, world.calls());
}

test "reading goes only through the exact-config-file capability at the compiler limit" {
    var world: World = .{ .config_bytes = "{}" };
    var exact = try startup.steps.locateConfig(world.locator(), std.testing.allocator);
    defer exact.deinit(std.testing.allocator);
    var raw = try startup.steps.readConfig(&exact, std.testing.allocator);
    defer raw.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("{}", raw.bytes);
    try std.testing.expectEqualSlices(Call, &.{ .locate, .read }, world.calls());
    try std.testing.expectEqual(config.max_engine_config_bytes, world.observed_read_limit);
}

test "log level canonicalization accepts case and only the two declared aliases" {
    const level = try startup.steps.canonicalizeLogLevel("ERROR");
    try std.testing.expectEqual(telemetry.CanonicalLogLevel.error_level, level.threshold);
    try std.testing.expectError(error.LoggingPolicyInvalid, startup.steps.canonicalizeLogLevel("NOTICE"));
}

test "logging policy validation rejects canonicalization evidence from a different config value" {
    const canonicalized = try log_policy.canonicalizeConfiguredLevel("debug");
    try std.testing.expectError(error.LoggingPolicyInvalid, startup.steps.validateLoggingPolicy(
        std.testing.allocator,
        .{ .level = "info", .console = false },
        canonicalized,
    ));
}

fn rootCandidate(key: bootstrap_roots.PathKey) bootstrap_roots.ConfiguredRootCandidate {
    return .{
        .path = .{ .path_key = key, .root_role = key.role(), .relative_path = "root" },
        .canonical_project_root = "/project",
        .canonical_path = "/project/root",
    };
}

test "root validation admits an absent optional root without granting creation authority" {
    var world: World = .{ .workflows_present = false };
    const inspector = world.ports().root_inspector;
    const capability = try startup.steps.validateRoot(inspector, rootCandidate(.specs));
    try std.testing.expect(!capability.isPresent());
    try std.testing.expectEqual(bootstrap_roots.ExistencePolicy.optional_directory, capability.existence_policy);
    try std.testing.expectEqualSlices(Call, &.{.inspect}, world.calls());
}

test "root validation requires the workflow authority directory at preselection" {
    var world: World = .{ .workflows_present = false };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        startup.steps.validateRoot(world.ports().root_inspector, rootCandidate(.workflows)),
    );
}

test "root validation rejects a structurally mismatched candidate before filesystem inspection" {
    var world: World = .{};
    var candidate = rootCandidate(.references);
    candidate.canonical_path = "/project/other";
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        startup.steps.validateRoot(world.ports().root_inspector, candidate),
    );
    try std.testing.expectEqual(@as(usize, 0), world.trace_len);
}

test "root validation maps an unreadable directory to resolution failure and keeps cancellation distinct" {
    var rejecting: World = .{ .inspect = .reject };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        startup.steps.validateRoot(rejecting.ports().root_inspector, rootCandidate(.workflows)),
    );
    var cancelling: World = .{ .inspect = .cancel };
    try std.testing.expectError(
        error.Cancelled,
        startup.steps.validateRoot(cancelling.ports().root_inspector, rootCandidate(.principles)),
    );
}

test "resource capture reads only the validated declared manifest" {
    const descriptors = [_]inventory.InventoryDescriptor{.{
        .path = "prompt.md",
        .kind = .file,
        .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 1 },
        .size = 3,
    }};
    const accounts = [_]inventory.InventoryAccount{.{ .ordinal = 1, .path = descriptors[0].path, .disposition = .resource }};
    const validated: inventory_building.ValidatedInventory = .{ .value = .{
        .capability = undefined,
        .descriptors = &descriptors,
        .accounts = &accounts,
        .definition_ordinals = &.{},
        .resource_ordinals = &.{1},
    } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var world: World = .{};
    try std.testing.expectError(
        error.WorkflowResourceReadError,
        startup.steps.captureWorkflowResources(world.capturer(), arena.allocator(), validated, .{ .bindings = &.{}, .resource_ordinals = &.{} }, .{}),
    );
    try std.testing.expectEqual(@as(usize, 0), world.trace_len);

    const captured = try startup.steps.captureWorkflowResources(world.capturer(), arena.allocator(), validated, .{ .bindings = &.{}, .resource_ordinals = &.{1} }, .{});
    try std.testing.expectEqual(@as(usize, 1), world.trace_len);
    try std.testing.expectEqualStrings("abc", captured[0].bytes);
}

test "definition capture reads only the budgeted definition ordinals" {
    const descriptors = [_]inventory.InventoryDescriptor{.{
        .path = "flow.workflow.yaml",
        .kind = .file,
        .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 1 },
        .size = 3,
    }};
    const accounts = [_]inventory.InventoryAccount{.{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition }};
    const validated: inventory_building.ValidatedInventory = .{ .value = .{
        .capability = undefined,
        .descriptors = &descriptors,
        .accounts = &accounts,
        .definition_ordinals = &.{1},
        .resource_ordinals = &.{},
    } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var world: World = .{};
    const captured = try startup.steps.captureWorkflows(world.capturer(), arena.allocator(), validated, .{});
    try std.testing.expectEqual(@as(usize, 1), captured.len);
    try std.testing.expectEqualStrings("abc", captured[0].bytes);
    try std.testing.expectEqualSlices(Call, &.{.capture}, world.calls());
}
