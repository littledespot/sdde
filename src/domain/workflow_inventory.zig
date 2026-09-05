const std = @import("std");
const bootstrap_root_registry = @import("bootstrap_root_registry.zig");
const filesystem_identity = @import("filesystem_identity.zig");
const definition = @import("workflow_definition.zig");

pub const definition_suffix = ".workflow.yaml";
const reserved_child = "features";
pub const max_inventory_entries: usize = 4096;
pub const max_inventory_depth: usize = 16;
pub const max_inventory_duration_ms: i64 = 5000;
pub const max_total_definition_bytes: usize = 16_777_216;

pub const EntryKind = enum { directory, file, symlink, special };
pub const InventoryDescriptor = struct {
    path: []const u8,
    kind: EntryKind,
    identity: ?filesystem_identity.FileIdentity = null,
    size: ?u64 = null,
};
pub const Disposition = enum { directory, reserved_child, definition, resource };
pub const InventoryAccount = struct { ordinal: u16, path: []const u8, disposition: Disposition };
pub const AccountSet = struct {
    accounts: []const InventoryAccount,
    definition_ordinals: []const u16,
    resource_ordinals: []const u16,
};
pub const Layout = struct { capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability };
pub const Inventory = struct {
    capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
    descriptors: []const InventoryDescriptor,
    accounts: []const InventoryAccount,
    definition_ordinals: []const u16,
    resource_ordinals: []const u16,
};
pub const Capture = struct { ordinal: u16, bytes: []const u8 };
pub const ResourceBinding = struct {
    definition_ordinal: u16,
    resource_id: @import("workflow.zig").WorkflowResourceId,
    resource_ordinal: u16,
};
pub const ResourceManifest = struct {
    bindings: []const ResourceBinding,
    resource_ordinals: []const u16,
};
pub const Error = error{InvalidWorkflowInventory};

pub fn classifyInventoryDescriptor(descriptor: InventoryDescriptor) ?Disposition {
    if (isReservedRootChild(descriptor.path)) {
        return if (descriptor.kind == .directory and descriptor.identity != null)
            .reserved_child
        else
            null;
    }
    return switch (descriptor.kind) {
        .directory => if (descriptor.identity != null) .directory else null,
        .file => if (descriptor.identity == null or descriptor.size == null)
            null
        else if (definitionPath(descriptor.path))
            if (descriptor.size.? <= definition.max_definition_bytes) .definition else null
        else if (descriptor.size.? <= definition.max_resource_bytes)
            .resource
        else
            null,
        .symlink, .special => null,
    };
}

pub fn validate(inventory: Inventory) Error!void {
    try validateEntries(inventory.descriptors, inventory.accounts, inventory.definition_ordinals, inventory.resource_ordinals);
}

pub fn validateResourceCaptureBudget(inventory: Inventory, manifest: ResourceManifest) Error!void {
    if (manifest.resource_ordinals.len != inventory.resource_ordinals.len) return error.InvalidWorkflowInventory;
    var total: u64 = 0;
    for (manifest.resource_ordinals, inventory.resource_ordinals) |ordinal, expected| {
        if (ordinal != expected or ordinal == 0 or ordinal > inventory.descriptors.len) return error.InvalidWorkflowInventory;
        const descriptor = inventory.descriptors[ordinal - 1];
        const size = descriptor.size orelse return error.InvalidWorkflowInventory;
        if (inventory.accounts[ordinal - 1].disposition != .resource or size > definition.max_resource_bytes) {
            return error.InvalidWorkflowInventory;
        }
        total = std.math.add(u64, total, size) catch return error.InvalidWorkflowInventory;
        if (total > definition.max_total_resource_bytes) return error.InvalidWorkflowInventory;
    }
}

pub fn validateCaptureBudget(inventory: Inventory) Error!void {
    try validateCaptureBudgetEntries(inventory.descriptors, inventory.definition_ordinals);
}

fn validateCaptureBudgetEntries(descriptors: []const InventoryDescriptor, definition_ordinals: []const u16) Error!void {
    var total: u64 = 0;
    for (definition_ordinals) |ordinal| {
        if (ordinal == 0 or ordinal > descriptors.len) return error.InvalidWorkflowInventory;
        const descriptor = descriptors[ordinal - 1];
        const size = descriptor.size orelse return error.InvalidWorkflowInventory;
        if (size > definition.max_definition_bytes) return error.InvalidWorkflowInventory;
        total = std.math.add(u64, total, size) catch return error.InvalidWorkflowInventory;
        if (total > max_total_definition_bytes) return error.InvalidWorkflowInventory;
    }
}

pub fn validPath(path: []const u8) bool {
    if (path.len == 0 or !std.unicode.utf8ValidateSlice(path) or std.fs.path.isAbsolute(path) or
        std.mem.indexOfScalar(u8, path, '\\') != null)
    {
        return false;
    }
    var iterator = std.mem.splitScalar(u8, path, '/');
    while (iterator.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return false;
        if (component[component.len - 1] == '.' or component[component.len - 1] == ' ' or reservedPortableName(component)) return false;
        for (component) |byte| {
            if (byte == 0 or byte < 0x20 or byte == 0x7f or byte >= 0x80) return false;
            switch (byte) {
                '<', '>', ':', '"', '|', '?', '*' => return false,
                else => {},
            }
        }
    }
    return !hasEncodedDotOrSeparator(path);
}

pub fn portablePathEqual(left: []const u8, right: []const u8) bool {
    return std.ascii.eqlIgnoreCase(left, right);
}

pub fn isReservedRootChild(path: []const u8) bool {
    return std.mem.eql(u8, path, reserved_child);
}

pub fn reservedAlias(path: []const u8) bool {
    return std.ascii.eqlIgnoreCase(path, reserved_child) and !isReservedRootChild(path);
}

fn validateEntries(
    descriptors: []const InventoryDescriptor,
    accounts: []const InventoryAccount,
    definition_ordinals: []const u16,
    resource_ordinals: []const u16,
) Error!void {
    if (descriptors.len > max_inventory_entries or accounts.len != descriptors.len or
        definition_ordinals.len > definition.max_definitions) return error.InvalidWorkflowInventory;
    var definition_index: usize = 0;
    var resource_index: usize = 0;
    for (descriptors, accounts, 0..) |descriptor, account, index| {
        if (!validPath(descriptor.path) or reservedAlias(descriptor.path) or reservedDescendant(descriptor.path) or
            account.ordinal != index + 1 or !std.mem.eql(u8, account.path, descriptor.path) or
            account.disposition != (classifyInventoryDescriptor(descriptor) orelse return error.InvalidWorkflowInventory))
        {
            return error.InvalidWorkflowInventory;
        }
        if (index > 0 and std.mem.order(u8, descriptors[index - 1].path, descriptor.path) != .lt) return error.InvalidWorkflowInventory;
        for (descriptors[0..index]) |prior| {
            if (portablePathEqual(prior.path, descriptor.path) or samePhysicalIdentity(prior, descriptor)) return error.InvalidWorkflowInventory;
        }
        if (account.disposition == .definition) {
            if (definition_index == definition_ordinals.len or definition_ordinals[definition_index] != account.ordinal) {
                return error.InvalidWorkflowInventory;
            }
            definition_index += 1;
        } else if (account.disposition == .resource) {
            if (resource_index == resource_ordinals.len or resource_ordinals[resource_index] != account.ordinal) {
                return error.InvalidWorkflowInventory;
            }
            resource_index += 1;
        }
    }
    if (definition_index != definition_ordinals.len or resource_index != resource_ordinals.len) {
        return error.InvalidWorkflowInventory;
    }
}

fn definitionPath(path: []const u8) bool {
    const basename = std.fs.path.basename(path);
    return basename.len > definition_suffix.len and std.mem.endsWith(u8, basename, definition_suffix);
}

fn reservedDescendant(path: []const u8) bool {
    return std.mem.startsWith(u8, path, reserved_child ++ "/");
}

fn samePhysicalIdentity(left: InventoryDescriptor, right: InventoryDescriptor) bool {
    if (left.identity == null or right.identity == null) return false;
    return left.identity.?.eql(right.identity.?);
}

fn reservedPortableName(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    if (std.ascii.eqlIgnoreCase(stem, "con") or std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or std.ascii.eqlIgnoreCase(stem, "nul")) return true;
    if (stem.len != 4) return false;
    return (std.ascii.eqlIgnoreCase(stem[0..3], "com") or std.ascii.eqlIgnoreCase(stem[0..3], "lpt")) and
        stem[3] >= '1' and stem[3] <= '9';
}

fn hasEncodedDotOrSeparator(path: []const u8) bool {
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        if (path[index] != '%') continue;
        var token_index = index + 1;
        while (token_index + 1 < path.len and std.ascii.toLower(path[token_index]) == '2' and
            std.ascii.toLower(path[token_index + 1]) == '5') token_index += 2;
        if (token_index + 1 >= path.len) continue;
        const first = std.ascii.toLower(path[token_index]);
        const second = std.ascii.toLower(path[token_index + 1]);
        if ((first == '2' and (second == 'e' or second == 'f')) or (first == '5' and second == 'c')) return true;
    }
    return false;
}

test "inventory validation owns collision and accounting joins" {
    const identities = [_]filesystem_identity.FileIdentity{
        .{ .filesystem_id = 1, .file_id = 1 },
        .{ .filesystem_id = 1, .file_id = 2 },
        .{ .filesystem_id = 1, .file_id = 3 },
    };
    const descriptors = [_]InventoryDescriptor{
        .{ .path = "alpha.workflow.yaml", .kind = .file, .identity = identities[0], .size = 10 },
        .{ .path = "nested", .kind = .directory, .identity = identities[1] },
        .{ .path = "nested/beta.workflow.yaml", .kind = .file, .identity = identities[2], .size = 20 },
    };
    const accounts = [_]InventoryAccount{
        .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
        .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .directory },
        .{ .ordinal = 3, .path = descriptors[2].path, .disposition = .definition },
    };
    const definition_ordinals = [_]u16{ 1, 3 };
    try validateEntries(&descriptors, &accounts, &definition_ordinals, &.{});

    var wrong_account = accounts;
    wrong_account[1].disposition = .reserved_child;
    try std.testing.expectError(error.InvalidWorkflowInventory, validateEntries(&descriptors, &wrong_account, &definition_ordinals, &.{}));

    const case_collision = [_]InventoryDescriptor{
        .{ .path = "Alpha", .kind = .directory, .identity = identities[0] },
        .{ .path = "alpha", .kind = .directory, .identity = identities[1] },
    };
    const case_accounts = [_]InventoryAccount{
        .{ .ordinal = 1, .path = "Alpha", .disposition = .directory },
        .{ .ordinal = 2, .path = "alpha", .disposition = .directory },
    };
    try std.testing.expectError(error.InvalidWorkflowInventory, validateEntries(&case_collision, &case_accounts, &.{}, &.{}));

    var physical_alias = descriptors;
    physical_alias[2].identity = identities[0];
    try std.testing.expectError(error.InvalidWorkflowInventory, validateEntries(&physical_alias, &accounts, &definition_ordinals, &.{}));
}

test "only the exact feature root is reserved and ordinary descendants are fully accounted" {
    const root_identity: filesystem_identity.FileIdentity = .{ .filesystem_id = 1, .file_id = 1 };
    try std.testing.expect(isReservedRootChild("features"));
    try std.testing.expect(classifyInventoryDescriptor(.{ .path = "features", .kind = .directory, .identity = root_identity }) == .reserved_child);
    for ([_]EntryKind{ .file, .symlink, .special }) |kind| {
        try std.testing.expect(classifyInventoryDescriptor(.{ .path = "features", .kind = kind, .identity = root_identity, .size = 1 }) == null);
    }
    for ([_][]const u8{ "Features", "FEATURES" }) |alias| try std.testing.expect(reservedAlias(alias));
    try std.testing.expect(reservedDescendant("features/state.json"));
    try std.testing.expect(!reservedAlias("features"));

    for ([_][]const u8{ "transactions", "Transactions", "utilities", "nested/features" }) |directory| {
        try std.testing.expect(!isReservedRootChild(directory));
        try std.testing.expect(!reservedAlias(directory));
        const child = try std.fmt.allocPrint(std.testing.allocator, "{s}/check.workflow.yaml", .{directory});
        defer std.testing.allocator.free(child);
        const descriptors = [_]InventoryDescriptor{
            .{ .path = directory, .kind = .directory, .identity = root_identity },
            .{ .path = child, .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = 2 }, .size = 1 },
        };
        const accounts = [_]InventoryAccount{
            .{ .ordinal = 1, .path = directory, .disposition = .directory },
            .{ .ordinal = 2, .path = child, .disposition = .definition },
        };
        try validateEntries(&descriptors, &accounts, &.{2}, &.{});
        var skipped = accounts;
        skipped[0].disposition = .reserved_child;
        try std.testing.expectError(error.InvalidWorkflowInventory, validateEntries(&descriptors, &skipped, &.{2}, &.{}));
        try std.testing.expectError(error.InvalidWorkflowInventory, validateEntries(&descriptors, &accounts, &.{}, &.{}));
    }
}

test "aggregate capture bytes are bounded before reads" {
    var descriptors: [17]InventoryDescriptor = undefined;
    var ordinals: [17]u16 = undefined;
    for (&descriptors, &ordinals, 0..) |*descriptor, *ordinal, index| {
        descriptor.* = .{ .path = "unused.workflow.yaml", .kind = .file, .size = if (index < 16) definition.max_definition_bytes else 1 };
        ordinal.* = @intCast(index + 1);
    }
    try validateCaptureBudgetEntries(descriptors[0..16], ordinals[0..16]);
    try std.testing.expectError(error.InvalidWorkflowInventory, validateCaptureBudgetEntries(&descriptors, &ordinals));
}

test "workflow media paths are exact portable ASCII" {
    const identity: filesystem_identity.FileIdentity = .{ .filesystem_id = 1, .file_id = 1 };
    try std.testing.expect(classifyInventoryDescriptor(.{ .path = "nested/hello.workflow.yaml", .kind = .file, .identity = identity, .size = 1 }) == .definition);
    const resources = [_][]const u8{ "hello.workflow.json", "hello.workflow.yml", "hello.WORKFLOW.YAML", ".workflow.yaml" };
    for (resources) |path| {
        try std.testing.expect(classifyInventoryDescriptor(.{ .path = path, .kind = .file, .identity = identity, .size = 1 }) == .resource);
    }
    const invalid = [_][]const u8{
        "caf\xc3\xa9.workflow.yaml",
        "con.workflow.yaml",
        "nested/%2e%2e/hello.workflow.yaml",
    };
    for (invalid) |path| {
        try std.testing.expect(!validPath(path));
    }
}
