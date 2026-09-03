const std = @import("std");
const enumerate_inventory = @import("actions/workflow/enumerate_workflow_authority_resources.zig");
const normalize_inventory = @import("actions/workflow/normalize_workflow_authority_entries.zig");
const build_inventory_accounts = @import("actions/workflow/build_workflow_authority_entry_accounts.zig");
const build_inventory = @import("actions/workflow/build_workflow_authority_inventory.zig");
const validate_inventory = @import("actions/workflow/validate_workflow_authority_inventory.zig");
const capture_definitions = @import("actions/workflow/capture_workflow_definitions.zig");
const registry_service = @import("application/workflow_definition_registry_service.zig");
const bootstrap_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_roots = @import("domain/bootstrap_roots.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");
const definition = @import("domain/workflow_definition.zig");
const compilation = @import("domain/workflow_compilation.zig");
const inventory = @import("domain/workflow_inventory.zig");
const registry = @import("domain/workflow_registry.zig");
const source_port = @import("ports/workflow_authority_source.zig");

fn runInventoryStages(
    allocator: std.mem.Allocator,
    source: source_port.Enumerator,
    layout: inventory.Layout,
    runtime: pipeline.NodeRuntime,
) !inventory.Inventory {
    const raw = try (enumerate_inventory.Action{ .source = source }).execute(allocator, layout, runtime);
    const normalized = try (normalize_inventory.Action{}).execute(raw);
    const accounts = try (build_inventory_accounts.Action{}).execute(allocator, normalized);
    const candidate = (build_inventory.Action{}).execute(layout, normalized, accounts);
    return (validate_inventory.Action{}).execute(candidate);
}

test "workflow inventory sorts and classifies definitions and resource candidates" {
    const root_owner = try createRootOwner(std.testing.allocator);
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const values = [_]inventory.InventoryDescriptor{
        descriptor("prompts/generate.md", .file, 3, 7),
        descriptor("flow.workflow.yaml", .file, 2, 9),
        descriptor("prompts", .directory, 1, null),
    };
    var fake: FakeSource = .{ .descriptors = &values };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqualStrings("flow.workflow.yaml", result.descriptors[0].path);
    try std.testing.expectEqualSlices(u16, &.{1}, result.definition_ordinals);
    try std.testing.expectEqualSlices(u16, &.{3}, result.resource_ordinals);
    try std.testing.expectEqual(inventory.Disposition.resource, result.accounts[2].disposition);
}

test "workflow inventory enforces definition and total-entry bounds" {
    const root_owner = try createRootOwner(std.testing.allocator);
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var fake: FakeSource = .{ .descriptors = try definitionDescriptors(arena.allocator(), definition.max_definitions) };
    const exact = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(definition.max_definitions, exact.definition_ordinals.len);
    fake.descriptors = try definitionDescriptors(arena.allocator(), definition.max_definitions + 1);
    try std.testing.expectError(
        error.WorkflowAuthorityInventoryInvalid,
        runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{}),
    );
}

test "workflow inventory preserves cancellation and rejects aliases" {
    const root_owner = try createRootOwner(std.testing.allocator);
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const invalid = [_]inventory.InventoryDescriptor{descriptor("Features", .directory, 1, null)};
    var fake: FakeSource = .{ .descriptors = &invalid };
    try std.testing.expectError(
        error.WorkflowAuthorityInventoryInvalid,
        runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{}),
    );
    fake.descriptors = &.{};
    var status = pipeline.RuntimeStatus.cancelled;
    try std.testing.expectError(
        error.Cancelled,
        runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{ .context = &status, .status_fn = runtimeStatus }),
    );
}

test "definition capture budget fails before filesystem reads" {
    const root_owner = try createRootOwner(std.testing.allocator);
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = try definitionDescriptors(arena.allocator(), 17);
    for (descriptors, 0..) |*item, index| item.size = if (index < 16) definition.max_definition_bytes else 1;
    var fake: FakeSource = .{ .descriptors = descriptors };
    const result = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectError(
        error.WorkflowDefinitionReadError,
        (capture_definitions.Action{ .source = fake.capturer() }).execute(arena.allocator(), result, .{}),
    );
    try std.testing.expectEqual(@as(usize, 0), fake.capture_calls);
}

test "validated workflow registry accepts zero definitions and owns its graph resources" {
    const root_owner = try createRootOwner(std.testing.allocator);
    var root_live = true;
    defer if (root_live) bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const empty_owner = try registry.createValidated(std.testing.allocator, .{
        .inventory = emptyInventory(capability),
        .definition_captures = &.{},
        .resource_manifest = .{ .bindings = &.{}, .resource_ordinals = &.{} },
        .resource_captures = &.{},
        .definitions = &.{},
        .graphs = &.{},
    });
    defer registry.deinitOwner(empty_owner);
    try std.testing.expectEqual(@as(usize, 0), registry.registry(empty_owner).count());

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    const workflow_id = try scratch.allocator().dupe(u8, "hello");
    const resource_name = try scratch.allocator().dupe(u8, "prompt.md");
    const resource_bytes = try scratch.allocator().dupe(u8, "immutable prompt");
    const resource_id = workflow.WorkflowResourceId.parse("prompt").?;
    const declared_resources = [_]workflow.ResourceDeclaration{.{ .id = resource_id, .name = resource_name }};
    var declared = validDefinition(workflow_id, "HELO", 1);
    declared.resources = &declared_resources;
    const compiled_resources = [_]compilation.CompiledResource{.{ .id = resource_id, .kind = .prompt, .bytes = resource_bytes }};
    var graph = validGraph(declared);
    graph.authority.resources = &compiled_resources;
    const descriptors = [_]inventory.InventoryDescriptor{
        descriptor("arbitrary.workflow.yaml", .file, 1, 3),
        descriptor(resource_name, .file, 2, resource_bytes.len),
    };
    const accounts = [_]inventory.InventoryAccount{
        .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
        .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .resource },
    };
    const captures = [_]inventory.Capture{.{ .ordinal = 1, .bytes = "abc" }};
    const resource_captures = [_]inventory.Capture{.{ .ordinal = 2, .bytes = resource_bytes }};
    const owner = try registry.createValidated(std.testing.allocator, .{
        .inventory = .{
            .capability = capability,
            .descriptors = &descriptors,
            .accounts = &accounts,
            .definition_ordinals = &.{1},
            .resource_ordinals = &.{2},
        },
        .definition_captures = &captures,
        .resource_manifest = .{
            .bindings = &.{.{ .definition_ordinal = 1, .resource_id = resource_id, .resource_ordinal = 2 }},
            .resource_ordinals = &.{2},
        },
        .resource_captures = &resource_captures,
        .definitions = &.{declared},
        .graphs = &.{graph},
    });
    scratch.deinit();
    bootstrap_registry.deinitOwner(root_owner);
    root_live = false;
    var service = registry_service.WorkflowDefinitionRegistryService.init(owner);
    defer service.deinit();
    const resolved = service.registry().resolve(workflow.WorkflowId.parse("hello").?).?;
    try std.testing.expectEqualStrings("core.noop@1", resolved.authority.steps[0].operation_id.bytes);
    try std.testing.expectEqualStrings("immutable prompt", resolved.authority.resources[0].bytes);
}

test "registry rejects a partially valid duplicate identity set" {
    const root_owner = try createRootOwner(std.testing.allocator);
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const definitions = [_]definition.Definition{
        validDefinition("duplicate", "ONE1", 1),
        validDefinition("duplicate", "TWO2", 2),
    };
    const graphs = [_]compilation.CompiledWorkflow{ validGraph(definitions[0]), validGraph(definitions[1]) };
    const descriptors = [_]inventory.InventoryDescriptor{
        descriptor("a.workflow.yaml", .file, 1, 1),
        descriptor("b.workflow.yaml", .file, 2, 1),
    };
    const accounts = [_]inventory.InventoryAccount{
        .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
        .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .definition },
    };
    const captures = [_]inventory.Capture{ .{ .ordinal = 1, .bytes = "a" }, .{ .ordinal = 2, .bytes = "b" } };
    try std.testing.expectError(error.InvalidWorkflowRegistry, registry.createValidated(std.testing.allocator, .{
        .inventory = .{
            .capability = capability,
            .descriptors = &descriptors,
            .accounts = &accounts,
            .definition_ordinals = &.{ 1, 2 },
            .resource_ordinals = &.{},
        },
        .definition_captures = &captures,
        .resource_manifest = .{ .bindings = &.{}, .resource_ordinals = &.{} },
        .resource_captures = &.{},
        .definitions = &definitions,
        .graphs = &graphs,
    }));
}

const declared_steps = [_]workflow.DeclarativeStep{.{
    .id = workflow.WorkflowStepId.parse("run").?,
    .operation_id = workflow.RegisteredRef.parse("core.noop@1").?,
    .parameters = &.{},
    .outcomes = &.{.{ .outcome = .ok, .target = .{ .terminal = .ok } }},
}};
const compiled_steps = [_]compilation.CompiledStep{.{
    .id = declared_steps[0].id,
    .operation_id = declared_steps[0].operation_id,
    .parameters = &.{},
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = &.{.ok},
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{},
    .loop_limit = null,
}};
const transitions = [_]workflow.Transition{.{
    .from = declared_steps[0].id,
    .outcome = .ok,
    .target = .{ .terminal = .ok },
}};

fn validDefinition(id: []const u8, shortcode: []const u8, ordinal: u16) definition.Definition {
    return .{
        .source_ordinal = ordinal,
        .workflow_id = workflow.WorkflowId.parse(id).?,
        .workflow_version = 1,
        .shortcode = @import("domain/telemetry.zig").WorkflowShortcode.parse(shortcode) catch unreachable,
        .invocation_operation_id = workflow.RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .start_step_id = declared_steps[0].id,
        .resources = &.{},
        .steps = &declared_steps,
    };
}

fn validGraph(declared: definition.Definition) compilation.CompiledWorkflow {
    return .{
        .source_ordinal = declared.source_ordinal,
        .shortcode = declared.shortcode,
        .authority = .{
            .workflow_id = declared.workflow_id,
            .workflow_version = declared.workflow_version,
            .invocation_operation_id = declared.invocation_operation_id,
            .policy_profile_id = declared.policy_profile_id,
            .start_step_id = declared.start_step_id,
            .invocation_outputs = &.{},
            .resources = &.{},
            .steps = &compiled_steps,
            .transitions = &transitions,
            .maximum_step_executions = 1,
        },
    };
}

const FakeSource = struct {
    descriptors: []const inventory.InventoryDescriptor,
    capture_calls: usize = 0,

    fn enumerator(self: *FakeSource) source_port.Enumerator {
        return .{ .context = self, .enumerate_fn = enumerate };
    }
    fn capturer(self: *FakeSource) source_port.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }
    fn enumerate(
        context: *anyopaque,
        _: *const bootstrap_registry.ConfiguredBaseRootCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) source_port.Error![]inventory.InventoryDescriptor {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        return switch (runtime.status()) {
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.DeadlineExhausted,
            .active => allocator.dupe(inventory.InventoryDescriptor, self.descriptors) catch error.InventoryInvalid,
        };
    }
    fn capture(
        context: *anyopaque,
        _: *const bootstrap_registry.ConfiguredBaseRootCapability,
        descriptor_value: inventory.InventoryDescriptor,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) source_port.Error![]const u8 {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        self.capture_calls += 1;
        return switch (runtime.status()) {
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.DeadlineExhausted,
            .active => blk: {
                const bytes = allocator.alloc(u8, @intCast(descriptor_value.size orelse return error.DefinitionReadError)) catch return error.DefinitionReadError;
                @memset(bytes, 0);
                break :blk bytes;
            },
        };
    }
};

fn emptyInventory(capability: *const bootstrap_registry.ConfiguredBaseRootCapability) inventory.Inventory {
    return .{
        .capability = capability,
        .descriptors = &.{},
        .accounts = &.{},
        .definition_ordinals = &.{},
        .resource_ordinals = &.{},
    };
}
fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
    const status: *pipeline.RuntimeStatus = @ptrCast(@alignCast(context.?));
    return status.*;
}
fn descriptor(path: []const u8, kind: inventory.EntryKind, file_id: u64, size: ?u64) inventory.InventoryDescriptor {
    return .{ .path = path, .kind = kind, .identity = .{ .filesystem_id = 1, .file_id = file_id }, .size = size };
}
fn definitionDescriptors(allocator: std.mem.Allocator, count: usize) ![]inventory.InventoryDescriptor {
    const values = try allocator.alloc(inventory.InventoryDescriptor, count);
    for (values, 0..) |*value, index| {
        value.* = descriptor(try std.fmt.allocPrint(allocator, "w{d:0>4}.workflow.yaml", .{index}), .file, index + 1, 1);
    }
    return values;
}

fn createRootOwner(allocator: std.mem.Allocator) !*bootstrap_registry.Owner {
    const paths = [_][]const u8{ "specs", "references", "specs/archive", "workflows", "presets", "principles", "templates" };
    const canonical = [_][]const u8{ "/project/specs", "/project/references", "/project/specs/archive", "/project/workflows", "/project/presets", "/project/principles", "/project/templates" };
    var roots: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
    for (&roots, 0..) |*root, index| {
        const key: bootstrap_roots.PathKey = @enumFromInt(index);
        root.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = paths[index],
            .canonical_path = canonical[index],
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = if (key == .workflows) .{ .directory = .{ .filesystem_id = 1, .file_id = 99 } } else .absent,
        };
    }
    return bootstrap_registry.createValidated(allocator, .{
        .id = .{ .canonical_project_root = "/project", .contract_version = bootstrap_roots.bootstrap_root_contract_version },
        .config_location = .{ .canonical_project_root = "/project", .canonical_config_path = "/project/.sddtoolkit.json", .no_follow_file_identity = .{ .filesystem_id = 9, .file_id = 9 } },
        .configured_roots = roots,
        .llm_provider_config_path = .{
            .relative_path = ".sddproviders.json",
            .canonical_project_root = "/project",
            .canonical_path = "/project/.sddproviders.json",
        },
    });
}
