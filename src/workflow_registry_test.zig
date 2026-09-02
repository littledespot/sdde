const std = @import("std");
const enumerate_inventory = @import("actions/workflow/enumerate_workflow_authority_resources.zig");
const normalize_inventory = @import("actions/workflow/normalize_workflow_authority_entries.zig");
const build_inventory_accounts = @import("actions/workflow/build_workflow_authority_entry_accounts.zig");
const build_inventory = @import("actions/workflow/build_workflow_authority_inventory.zig");
const validate_inventory = @import("actions/workflow/validate_workflow_authority_inventory.zig");
const capture_action = @import("actions/workflow/capture_workflow_definitions.zig");
const registry_service = @import("application/workflow_definition_registry_service.zig");
const workflow_source = @import("adapters/filesystem/workflow_authority_source.zig");
const file_identity = @import("adapters/filesystem/file_identity.zig");
const bootstrap_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_roots = @import("domain/bootstrap_roots.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");
const workflow_definition = @import("domain/workflow_definition.zig");
const workflow_compilation = @import("domain/workflow_compilation.zig");
const workflow_inventory = @import("domain/workflow_inventory.zig");
const registry = @import("domain/workflow_registry.zig");
const source_port = @import("ports/workflow_authority_source.zig");

fn runInventoryStages(
    allocator: std.mem.Allocator,
    source: source_port.Enumerator,
    layout: workflow_inventory.Layout,
    runtime: pipeline.NodeRuntime,
) !workflow_inventory.Inventory {
    const raw = try (enumerate_inventory.Action{ .source = source }).execute(allocator, layout, runtime);
    const normalized = try (normalize_inventory.Action{}).execute(raw);
    const accounts = try (build_inventory_accounts.Action{}).execute(allocator, normalized);
    const candidate = (build_inventory.Action{}).execute(layout, normalized, accounts);
    return (validate_inventory.Action{}).execute(candidate);
}

test "workflow inventory enforces definition and entry cardinality boundaries" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fake: FakeSource = .{ .descriptors = &.{} };
    const empty = try runInventoryStages(allocator, fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(@as(usize, 0), empty.definition_ordinals.len);

    fake.descriptors = try definitionDescriptors(allocator, workflow_definition.max_definitions);
    const exact = try runInventoryStages(allocator, fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(workflow_definition.max_definitions, exact.definition_ordinals.len);
    fake.descriptors = try definitionDescriptors(allocator, workflow_definition.max_definitions + 1);
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, runInventoryStages(allocator, fake.enumerator(), .{ .capability = capability }, .{}));

    fake.descriptors = try directoryDescriptors(allocator, workflow_inventory.max_inventory_entries);
    const exact_entries = try runInventoryStages(allocator, fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(workflow_inventory.max_inventory_entries, exact_entries.descriptors.len);
    fake.descriptors = try directoryDescriptors(allocator, workflow_inventory.max_inventory_entries + 1);
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, runInventoryStages(allocator, fake.enumerator(), .{ .capability = capability }, .{}));
}

test "workflow inventory sorts adapter order and preserves contiguous accounts" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const values = [_]workflow_inventory.InventoryDescriptor{
        descriptor("z.workflow.yaml", .file, 1, 1),
        descriptor("a", .directory, 2, null),
        descriptor("m.workflow.yaml", .file, 3, 1),
    };
    var fake: FakeSource = .{ .descriptors = &values };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const inventory = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqualStrings("a", inventory.descriptors[0].path);
    try std.testing.expectEqualStrings("m.workflow.yaml", inventory.descriptors[1].path);
    try std.testing.expectEqualStrings("z.workflow.yaml", inventory.descriptors[2].path);
    for (inventory.accounts, 0..) |account, index| {
        try std.testing.expectEqual(@as(u16, @intCast(index + 1)), account.ordinal);
        try std.testing.expectEqualStrings(inventory.descriptors[index].path, account.path);
    }
    try std.testing.expectEqualSlices(u16, &.{ 2, 3 }, inventory.definition_ordinals);
}

test "workflow inventory preserves cancellation and maps deadline exhaustion" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var fake: FakeSource = .{ .descriptors = &.{} };
    var status = pipeline.RuntimeStatus.cancelled;
    const runtime: pipeline.NodeRuntime = .{ .context = &status, .status_fn = runtimeStatus };
    try std.testing.expectError(error.Cancelled, runInventoryStages(std.testing.allocator, fake.enumerator(), .{ .capability = capability }, runtime));
    status = .deadline_exhausted;
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, runInventoryStages(std.testing.allocator, fake.enumerator(), .{ .capability = capability }, runtime));
}

test "filesystem inventory excludes exact reserved descendants and enforces depth" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDirPath(io, "workflows/features/private");
    try project.dir.createDirPath(io, "workflows/transactions/private");
    try project.dir.writeFile(io, .{ .sub_path = "workflows/features/private/ignored.txt", .data = "ignored" });
    try project.dir.writeFile(io, .{ .sub_path = "workflows/transactions/private/ignored.txt", .data = "ignored" });
    try project.dir.writeFile(io, .{ .sub_path = "workflows/hello.workflow.yaml", .data = "value: ignored here\n" });
    var workflows = try project.dir.openDir(io, "workflows", .{ .iterate = true });
    defer workflows.close(io);
    const root_owner = try createRootOwner(std.testing.allocator, try file_identity.inspect(workflows.handle));
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var adapter = workflow_source.Adapter.init(io, project.dir);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const inventory = try runInventoryStages(arena.allocator(), adapter.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(@as(usize, 3), inventory.descriptors.len);
    try std.testing.expectEqual(workflow_inventory.Disposition.reserved_child, inventory.accounts[0].disposition);
    try std.testing.expectEqual(workflow_inventory.Disposition.definition, inventory.accounts[1].disposition);
    try std.testing.expectEqual(workflow_inventory.Disposition.reserved_child, inventory.accounts[2].disposition);
    for (inventory.descriptors) |item| try std.testing.expect(std.mem.indexOf(u8, item.path, "private") == null);

    var depth_path: std.ArrayList(u8) = .empty;
    defer depth_path.deinit(std.testing.allocator);
    try depth_path.appendSlice(std.testing.allocator, "workflows");
    for (0..workflow_inventory.max_inventory_depth) |_| try depth_path.appendSlice(std.testing.allocator, "/d");
    try project.dir.createDirPath(io, depth_path.items);
    var exact_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exact_arena.deinit();
    _ = try runInventoryStages(exact_arena.allocator(), adapter.enumerator(), .{ .capability = capability }, .{});
    try depth_path.appendSlice(std.testing.allocator, "/d");
    try project.dir.createDirPath(io, depth_path.items);
    var exceeded_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exceeded_arena.deinit();
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, runInventoryStages(exceeded_arena.allocator(), adapter.enumerator(), .{ .capability = capability }, .{}));
}

test "filesystem workflow inventory rejects unsupported siblings and reserved aliases" {
    const io = std.testing.io;
    inline for ([_]Unsupported{ .regular, .symlink, .reserved_wrong_kind, .reserved_alias }) |kind| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDirPath(io, "workflows");
        switch (kind) {
            .regular => try project.dir.writeFile(io, .{ .sub_path = "workflows/readme.txt", .data = "unsupported" }),
            .symlink => {
                try project.dir.writeFile(io, .{ .sub_path = "workflows/source.workflow.yaml", .data = "value: source\n" });
                try project.dir.symLink(io, "source.workflow.yaml", "workflows/linked.workflow.yaml", .{});
            },
            .reserved_wrong_kind => try project.dir.writeFile(io, .{ .sub_path = "workflows/features", .data = "wrong kind" }),
            .reserved_alias => try project.dir.createDir(io, "workflows/Features", .default_dir),
        }
        var workflows = try project.dir.openDir(io, "workflows", .{ .iterate = true });
        defer workflows.close(io);
        const root_owner = try createRootOwner(std.testing.allocator, try file_identity.inspect(workflows.handle));
        defer bootstrap_registry.deinitOwner(root_owner);
        const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
        var adapter = workflow_source.Adapter.init(io, project.dir);
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, runInventoryStages(arena.allocator(), adapter.enumerator(), .{ .capability = capability }, .{}));
    }
}

test "capture budget is enforced before any definition read" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = try definitionDescriptors(arena.allocator(), 17);
    for (descriptors, 0..) |*item, index| item.size = if (index < 16) workflow_definition.max_definition_bytes else 1;
    var fake: FakeSource = .{ .descriptors = descriptors };
    const inventory = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectError(error.WorkflowDefinitionReadError, (capture_action.Action{ .source = fake.capturer() }).execute(arena.allocator(), inventory, .{}));
    try std.testing.expectEqual(@as(usize, 0), fake.capture_calls);
}

test "definition capture maps incomplete reads and preserves cancellation" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const descriptors = [_]workflow_inventory.InventoryDescriptor{descriptor("one.workflow.yaml", .file, 1, 3)};
    var fake: FakeSource = .{ .descriptors = &descriptors, .capture_failure = true };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const inventory = try runInventoryStages(arena.allocator(), fake.enumerator(), .{ .capability = capability }, .{});
    try std.testing.expectError(
        error.WorkflowDefinitionReadError,
        (capture_action.Action{ .source = fake.capturer() }).execute(arena.allocator(), inventory, .{}),
    );
    try std.testing.expectEqual(@as(usize, 1), fake.capture_calls);

    fake.capture_failure = false;
    var status = pipeline.RuntimeStatus.cancelled;
    const runtime: pipeline.NodeRuntime = .{ .context = &status, .status_fn = runtimeStatus };
    try std.testing.expectError(
        error.Cancelled,
        (capture_action.Action{ .source = fake.capturer() }).execute(arena.allocator(), inventory, runtime),
    );
}

test "filesystem capture accepts the exact byte limit and rejects a changed file" {
    const io = std.testing.io;
    const exact_bytes = try std.testing.allocator.alloc(u8, workflow_definition.max_definition_bytes);
    defer std.testing.allocator.free(exact_bytes);
    @memset(exact_bytes, 'a');
    var exact_project = std.testing.tmpDir(.{});
    defer exact_project.cleanup();
    try exact_project.dir.createDirPath(io, "workflows");
    try exact_project.dir.writeFile(io, .{ .sub_path = "workflows/exact.workflow.yaml", .data = exact_bytes });
    var exact_root = try exact_project.dir.openDir(io, "workflows", .{ .iterate = true });
    defer exact_root.close(io);
    const exact_owner = try createRootOwner(std.testing.allocator, try file_identity.inspect(exact_root.handle));
    defer bootstrap_registry.deinitOwner(exact_owner);
    const exact_capability = bootstrap_registry.registry(exact_owner).workflowAuthority();
    var exact_adapter = workflow_source.Adapter.init(io, exact_project.dir);
    var exact_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exact_arena.deinit();
    const exact_inventory = try runInventoryStages(exact_arena.allocator(), exact_adapter.enumerator(), .{ .capability = exact_capability }, .{});
    const captures = try (capture_action.Action{ .source = exact_adapter.capturer() }).execute(exact_arena.allocator(), exact_inventory, .{});
    try std.testing.expectEqual(workflow_definition.max_definition_bytes, captures[0].bytes.len);

    const oversized_bytes = try std.testing.allocator.alloc(u8, workflow_definition.max_definition_bytes + 1);
    defer std.testing.allocator.free(oversized_bytes);
    @memset(oversized_bytes, 'a');
    var oversized_project = std.testing.tmpDir(.{});
    defer oversized_project.cleanup();
    try oversized_project.dir.createDirPath(io, "workflows");
    try oversized_project.dir.writeFile(io, .{ .sub_path = "workflows/oversized.workflow.yaml", .data = oversized_bytes });
    var oversized_root = try oversized_project.dir.openDir(io, "workflows", .{ .iterate = true });
    defer oversized_root.close(io);
    const oversized_owner = try createRootOwner(std.testing.allocator, try file_identity.inspect(oversized_root.handle));
    defer bootstrap_registry.deinitOwner(oversized_owner);
    const oversized_capability = bootstrap_registry.registry(oversized_owner).workflowAuthority();
    var oversized_adapter = workflow_source.Adapter.init(io, oversized_project.dir);
    var oversized_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer oversized_arena.deinit();
    try std.testing.expectError(
        error.WorkflowAuthorityInventoryInvalid,
        runInventoryStages(
            oversized_arena.allocator(),
            oversized_adapter.enumerator(),
            .{ .capability = oversized_capability },
            .{},
        ),
    );

    inline for ([_]Mutation{ .grow, .shrink, .replace, .type_change }) |mutation| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDirPath(io, "workflows");
        try project.dir.writeFile(io, .{ .sub_path = "workflows/test.workflow.yaml", .data = "original" });
        var root = try project.dir.openDir(io, "workflows", .{ .iterate = true });
        defer root.close(io);
        const owner = try createRootOwner(std.testing.allocator, try file_identity.inspect(root.handle));
        defer bootstrap_registry.deinitOwner(owner);
        const capability = bootstrap_registry.registry(owner).workflowAuthority();
        var adapter = workflow_source.Adapter.init(io, project.dir);
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const inventory = try runInventoryStages(arena.allocator(), adapter.enumerator(), .{ .capability = capability }, .{});
        switch (mutation) {
            .grow => {
                var file = try project.dir.openFile(io, "workflows/test.workflow.yaml", .{ .mode = .read_write });
                defer file.close(io);
                try file.writePositionalAll(io, "x", 8);
            },
            .shrink => {
                var file = try project.dir.openFile(io, "workflows/test.workflow.yaml", .{ .mode = .read_write });
                defer file.close(io);
                try file.setLength(io, 1);
            },
            .replace => {
                try project.dir.deleteFile(io, "workflows/test.workflow.yaml");
                try project.dir.writeFile(io, .{ .sub_path = "workflows/test.workflow.yaml", .data = "replaced" });
            },
            .type_change => {
                try project.dir.deleteFile(io, "workflows/test.workflow.yaml");
                try project.dir.createDir(io, "workflows/test.workflow.yaml", .default_dir);
            },
        }
        try std.testing.expectError(error.WorkflowDefinitionReadError, (capture_action.Action{ .source = adapter.capturer() }).execute(arena.allocator(), inventory, .{}));
    }
}

test "validated workflow registry accepts zero definitions and owns one immutable graph" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    var root_owner_live = true;
    defer if (root_owner_live) bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const empty_candidate: registry.RegistryCandidate = .{
        .inventory = .{ .capability = capability, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{} },
        .captures = &.{},
        .definitions = &.{},
        .graphs = &.{},
    };
    const empty_owner = try registry.createValidated(std.testing.allocator, empty_candidate);
    defer registry.deinitOwner(empty_owner);
    try std.testing.expectEqual(@as(usize, 0), registry.registry(empty_owner).count());

    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    var scratch_live = true;
    defer if (scratch_live) scratch.deinit();
    const allocator = scratch.allocator();
    const workflow_id = try allocator.dupe(u8, "hello");
    const definition = validDefinition(workflow_id, "HELO", 1);
    const graph = validGraph(definition);
    const path = try allocator.dupe(u8, "arbitrary.workflow.yaml");
    const descriptors = [_]workflow_inventory.InventoryDescriptor{descriptor(path, .file, 1, 3)};
    const accounts = [_]workflow_inventory.InventoryAccount{.{ .ordinal = 1, .path = path, .disposition = .definition }};
    const ordinals = [_]u16{1};
    const captures = [_]workflow_inventory.Capture{.{ .ordinal = 1, .bytes = "abc" }};
    const definitions = [_]workflow_definition.Definition{definition};
    const graphs = [_]workflow_compilation.CompiledWorkflow{graph};
    const owner = try registry.createValidated(std.testing.allocator, .{
        .inventory = .{ .capability = capability, .descriptors = &descriptors, .accounts = &accounts, .definition_ordinals = &ordinals },
        .captures = &captures,
        .definitions = &definitions,
        .graphs = &graphs,
    });
    scratch.deinit();
    scratch_live = false;
    bootstrap_registry.deinitOwner(root_owner);
    root_owner_live = false;
    var service = registry_service.WorkflowDefinitionRegistryService.init(owner);
    defer service.deinit();
    try std.testing.expect(service.registry() == service.registry());
    try std.testing.expectEqual(@as(usize, 1), service.registry().count());
    const resolved = service.registry().resolve(workflow.WorkflowId.parse("hello").?);
    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings("core.noop@1", resolved.?.authority.nodes[0].contract_id.bytes);
}

test "registry rejects global identity collisions and incomplete joins" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    inline for ([_]RegistryFault{ .workflow_id, .shortcode, .ordinal, .missing_graph, .extra_graph, .projection, .reserved_ordinal }) |fault| {
        var descriptors = [_]workflow_inventory.InventoryDescriptor{
            descriptor("a.workflow.yaml", .file, 1, 3),
            descriptor("b.workflow.yaml", .file, 2, 3),
        };
        var accounts = [_]workflow_inventory.InventoryAccount{
            .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
            .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .definition },
        };
        var ordinals = [_]u16{ 1, 2 };
        var captures = [_]workflow_inventory.Capture{
            .{ .ordinal = 1, .bytes = "one" },
            .{ .ordinal = 2, .bytes = "two" },
        };
        var definitions = [_]workflow_definition.Definition{
            validDefinition("alpha", "ALPH", 1),
            validDefinition("beta", "BETA", 2),
        };
        var graphs = [_]workflow_compilation.CompiledWorkflow{
            validGraph(definitions[0]),
            validGraph(definitions[1]),
            validGraph(definitions[1]),
        };
        var graph_values: []const workflow_compilation.CompiledWorkflow = graphs[0..2];
        switch (fault) {
            .workflow_id => {
                definitions[1].workflow_id = definitions[0].workflow_id;
                graphs[1] = validGraph(definitions[1]);
            },
            .shortcode => {
                definitions[1].shortcode = definitions[0].shortcode;
                graphs[1] = validGraph(definitions[1]);
            },
            .ordinal => {
                captures[1].ordinal = 1;
                definitions[1].source_ordinal = 1;
                graphs[1] = validGraph(definitions[1]);
            },
            .missing_graph => graph_values = graphs[0..1],
            .extra_graph => graph_values = graphs[0..3],
            .projection => graphs[1].authority.workflow_version += 1,
            .reserved_ordinal => {
                descriptors[1] = descriptor("features", .directory, 2, null);
                accounts[1].path = descriptors[1].path;
                accounts[1].disposition = .reserved_child;
            },
        }
        try std.testing.expectError(error.InvalidWorkflowRegistry, registry.createValidated(std.testing.allocator, .{
            .inventory = .{ .capability = capability, .descriptors = &descriptors, .accounts = &accounts, .definition_ordinals = &ordinals },
            .captures = &captures,
            .definitions = &definitions,
            .graphs = graph_values,
        }));
    }
}

const Unsupported = enum { regular, symlink, reserved_wrong_kind, reserved_alias };
const Mutation = enum { grow, shrink, replace, type_change };
const RegistryFault = enum { workflow_id, shortcode, ordinal, missing_graph, extra_graph, projection, reserved_ordinal };

const declared_nodes = [_]workflow.DeclarativeNode{.{
    .id = workflow.WorkflowNodeId.parse("run").?,
    .contract_id = workflow.RegisteredRef.parse("core.noop@1").?,
    .parameters = &.{},
}};
const declared_transitions = [_]workflow.Transition{.{
    .from = declared_nodes[0].id,
    .outcome = .ok,
    .target = .{ .terminal = .ok },
}};
const compiled_nodes = [_]workflow_compilation.CompiledNode{.{
    .id = declared_nodes[0].id,
    .contract_id = declared_nodes[0].contract_id,
    .parameters = &.{},
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = &.{.ok},
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{},
}};

fn validDefinition(id: []const u8, shortcode: []const u8, ordinal: u16) workflow_definition.Definition {
    return .{
        .source_ordinal = ordinal,
        .workflow_id = workflow.WorkflowId.parse(id).?,
        .workflow_version = 1,
        .shortcode = @import("domain/telemetry.zig").WorkflowShortcode.parse(shortcode) catch unreachable,
        .invocation_contract_id = workflow.RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .entry_node_id = declared_nodes[0].id,
        .nodes = &declared_nodes,
        .transitions = &declared_transitions,
    };
}

fn validGraph(definition: workflow_definition.Definition) workflow_compilation.CompiledWorkflow {
    return .{
        .source_ordinal = definition.source_ordinal,
        .shortcode = definition.shortcode,
        .authority = .{
            .workflow_id = definition.workflow_id,
            .workflow_version = definition.workflow_version,
            .invocation_contract_id = definition.invocation_contract_id,
            .policy_profile_id = definition.policy_profile_id,
            .entry_node_id = definition.entry_node_id,
            .invocation_outputs = &.{},
            .nodes = &compiled_nodes,
            .transitions = &declared_transitions,
        },
    };
}

const FakeSource = struct {
    descriptors: []const workflow_inventory.InventoryDescriptor,
    capture_calls: usize = 0,
    capture_failure: bool = false,
    fn enumerator(self: *FakeSource) source_port.Enumerator {
        return .{ .context = self, .enumerate_fn = enumerate };
    }
    fn capturer(self: *FakeSource) source_port.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }
    fn enumerate(context: *anyopaque, _: *const bootstrap_registry.ConfiguredBaseRootCapability, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime) source_port.Error![]workflow_inventory.InventoryDescriptor {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        return switch (runtime.status()) {
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.DeadlineExhausted,
            .active => allocator.dupe(workflow_inventory.InventoryDescriptor, self.descriptors) catch error.InventoryInvalid,
        };
    }
    fn capture(context: *anyopaque, _: *const bootstrap_registry.ConfiguredBaseRootCapability, descriptor_value: workflow_inventory.InventoryDescriptor, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime) source_port.Error![]const u8 {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        self.capture_calls += 1;
        if (self.capture_failure) return error.DefinitionReadError;
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

fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
    const status: *pipeline.RuntimeStatus = @ptrCast(@alignCast(context.?));
    return status.*;
}

fn descriptor(path: []const u8, kind: workflow_inventory.EntryKind, file_id: u64, size: ?u64) workflow_inventory.InventoryDescriptor {
    return .{ .path = path, .kind = kind, .identity = .{ .filesystem_id = 1, .file_id = file_id }, .size = size };
}

fn definitionDescriptors(allocator: std.mem.Allocator, count: usize) ![]workflow_inventory.InventoryDescriptor {
    const values = try allocator.alloc(workflow_inventory.InventoryDescriptor, count);
    for (values, 0..) |*value, index| value.* = descriptor(try std.fmt.allocPrint(allocator, "w{d:0>4}.workflow.yaml", .{index}), .file, index + 1, 1);
    return values;
}

fn directoryDescriptors(allocator: std.mem.Allocator, count: usize) ![]workflow_inventory.InventoryDescriptor {
    const values = try allocator.alloc(workflow_inventory.InventoryDescriptor, count);
    for (values, 0..) |*value, index| value.* = descriptor(try std.fmt.allocPrint(allocator, "d{d:0>4}", .{index}), .directory, index + 1, null);
    return values;
}

fn createRootOwner(allocator: std.mem.Allocator, workflow_identity: bootstrap_roots.PhysicalDirectoryIdentity) !*bootstrap_registry.Owner {
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
            .observation = if (key == .workflows) .{ .directory = workflow_identity } else .absent,
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
