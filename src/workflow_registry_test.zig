const std = @import("std");
const inventory_action = @import("actions/workflow/inventory_workflow_authority.zig");
const capture_action = @import("actions/workflow/capture_workflow_definitions.zig");
const workflow_source = @import("adapters/filesystem/workflow_authority_source.zig");
const file_identity = @import("adapters/filesystem/file_identity.zig");
const bootstrap_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_roots = @import("domain/bootstrap_roots.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow_registry.zig");
const source_port = @import("ports/workflow_authority_source.zig");

test "workflow inventory enforces definition and entry cardinality boundaries" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var fake: FakeSource = .{ .descriptors = &.{} };
    const empty = try (inventory_action.Action{ .source = fake.port() }).execute(allocator, .{ .capability = capability }, .{});
    try std.testing.expectEqual(@as(usize, 0), empty.definition_ordinals.len);

    fake.descriptors = try definitionDescriptors(allocator, workflow.max_definitions);
    const exact = try (inventory_action.Action{ .source = fake.port() }).execute(allocator, .{ .capability = capability }, .{});
    try std.testing.expectEqual(workflow.max_definitions, exact.definition_ordinals.len);
    fake.descriptors = try definitionDescriptors(allocator, workflow.max_definitions + 1);
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (inventory_action.Action{ .source = fake.port() }).execute(allocator, .{ .capability = capability }, .{}));

    fake.descriptors = try directoryDescriptors(allocator, workflow.max_inventory_entries);
    const exact_entries = try (inventory_action.Action{ .source = fake.port() }).execute(allocator, .{ .capability = capability }, .{});
    try std.testing.expectEqual(workflow.max_inventory_entries, exact_entries.descriptors.len);
    fake.descriptors = try directoryDescriptors(allocator, workflow.max_inventory_entries + 1);
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (inventory_action.Action{ .source = fake.port() }).execute(allocator, .{ .capability = capability }, .{}));
}

test "workflow inventory sorts adapter order and preserves contiguous accounts" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    const values = [_]workflow.InventoryDescriptor{
        descriptor("z.workflow.yaml", .file, 1, 1),
        descriptor("a", .directory, 2, null),
        descriptor("m.workflow.yaml", .file, 3, 1),
    };
    var fake: FakeSource = .{ .descriptors = &values };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const inventory = try (inventory_action.Action{ .source = fake.port() }).execute(arena.allocator(), .{ .capability = capability }, .{});
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
    try std.testing.expectError(error.Cancelled, (inventory_action.Action{ .source = fake.port() }).execute(std.testing.allocator, .{ .capability = capability }, runtime));
    status = .deadline_exhausted;
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (inventory_action.Action{ .source = fake.port() }).execute(std.testing.allocator, .{ .capability = capability }, runtime));
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
    const inventory = try (inventory_action.Action{ .source = adapter.source() }).execute(arena.allocator(), .{ .capability = capability }, .{});
    try std.testing.expectEqual(@as(usize, 3), inventory.descriptors.len);
    try std.testing.expectEqual(workflow.Disposition.reserved_child, inventory.accounts[0].disposition);
    try std.testing.expectEqual(workflow.Disposition.definition, inventory.accounts[1].disposition);
    try std.testing.expectEqual(workflow.Disposition.reserved_child, inventory.accounts[2].disposition);
    for (inventory.descriptors) |item| try std.testing.expect(std.mem.indexOf(u8, item.path, "private") == null);

    var depth_path: std.ArrayList(u8) = .empty;
    defer depth_path.deinit(std.testing.allocator);
    try depth_path.appendSlice(std.testing.allocator, "workflows");
    for (0..workflow.max_inventory_depth) |_| try depth_path.appendSlice(std.testing.allocator, "/d");
    try project.dir.createDirPath(io, depth_path.items);
    var exact_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exact_arena.deinit();
    _ = try (inventory_action.Action{ .source = adapter.source() }).execute(exact_arena.allocator(), .{ .capability = capability }, .{});
    try depth_path.appendSlice(std.testing.allocator, "/d");
    try project.dir.createDirPath(io, depth_path.items);
    var exceeded_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exceeded_arena.deinit();
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (inventory_action.Action{ .source = adapter.source() }).execute(exceeded_arena.allocator(), .{ .capability = capability }, .{}));
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
        try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (inventory_action.Action{ .source = adapter.source() }).execute(arena.allocator(), .{ .capability = capability }, .{}));
    }
}

test "capture budget is enforced before any definition read" {
    const root_owner = try createRootOwner(std.testing.allocator, .{ .filesystem_id = 1, .file_id = 99 });
    defer bootstrap_registry.deinitOwner(root_owner);
    const capability = bootstrap_registry.registry(root_owner).workflowAuthority();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = try definitionDescriptors(arena.allocator(), 17);
    for (descriptors, 0..) |*item, index| item.size = if (index < 16) workflow.max_definition_bytes else 1;
    var fake: FakeSource = .{ .descriptors = descriptors };
    const inventory = try (inventory_action.Action{ .source = fake.port() }).execute(arena.allocator(), .{ .capability = capability }, .{});
    try std.testing.expectError(error.WorkflowDefinitionReadError, (capture_action.Action{ .source = fake.port() }).execute(arena.allocator(), inventory, .{}));
    try std.testing.expectEqual(@as(usize, 0), fake.capture_calls);
}

test "filesystem capture accepts the exact byte limit and rejects a changed file" {
    const io = std.testing.io;
    const exact_bytes = try std.testing.allocator.alloc(u8, workflow.max_definition_bytes);
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
    const exact_inventory = try (inventory_action.Action{ .source = exact_adapter.source() }).execute(exact_arena.allocator(), .{ .capability = exact_capability }, .{});
    const captures = try (capture_action.Action{ .source = exact_adapter.source() }).execute(exact_arena.allocator(), exact_inventory, .{});
    try std.testing.expectEqual(workflow.max_definition_bytes, captures[0].bytes.len);

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
        const inventory = try (inventory_action.Action{ .source = adapter.source() }).execute(arena.allocator(), .{ .capability = capability }, .{});
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
        try std.testing.expectError(error.WorkflowDefinitionReadError, (capture_action.Action{ .source = adapter.source() }).execute(arena.allocator(), inventory, .{}));
    }
}

const Unsupported = enum { regular, symlink, reserved_wrong_kind, reserved_alias };
const Mutation = enum { grow, shrink, replace, type_change };

const FakeSource = struct {
    descriptors: []const workflow.InventoryDescriptor,
    capture_calls: usize = 0,
    fn port(self: *FakeSource) source_port.Source {
        return .{ .context = self, .enumerate_fn = enumerate, .capture_fn = capture };
    }
    fn enumerate(context: *anyopaque, _: *const bootstrap_registry.ConfiguredBaseRootCapability, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime) source_port.Error![]workflow.InventoryDescriptor {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        return switch (runtime.status()) {
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.DeadlineExhausted,
            .active => allocator.dupe(workflow.InventoryDescriptor, self.descriptors) catch error.InventoryInvalid,
        };
    }
    fn capture(context: *anyopaque, _: *const bootstrap_registry.ConfiguredBaseRootCapability, descriptor_value: workflow.InventoryDescriptor, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime) source_port.Error![]const u8 {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        self.capture_calls += 1;
        return switch (runtime.status()) {
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.DeadlineExhausted,
            .active => allocator.alloc(u8, @intCast(descriptor_value.size orelse return error.DefinitionReadError)) catch error.DefinitionReadError,
        };
    }
};

fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
    const status: *pipeline.RuntimeStatus = @ptrCast(@alignCast(context.?));
    return status.*;
}

fn descriptor(path: []const u8, kind: workflow.EntryKind, file_id: u64, size: ?u64) workflow.InventoryDescriptor {
    return .{ .path = path, .kind = kind, .identity = .{ .filesystem_id = 1, .file_id = file_id }, .size = size };
}

fn definitionDescriptors(allocator: std.mem.Allocator, count: usize) ![]workflow.InventoryDescriptor {
    const values = try allocator.alloc(workflow.InventoryDescriptor, count);
    for (values, 0..) |*value, index| value.* = descriptor(try std.fmt.allocPrint(allocator, "w{d:0>4}.workflow.yaml", .{index}), .file, index + 1, 1);
    return values;
}

fn directoryDescriptors(allocator: std.mem.Allocator, count: usize) ![]workflow.InventoryDescriptor {
    const values = try allocator.alloc(workflow.InventoryDescriptor, count);
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
    });
}
