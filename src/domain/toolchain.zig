const std = @import("std");
const filesystem_identity = @import("filesystem_identity.zig");

pub const project_schema = "project-toolchain/v1";
pub const preset_schema = "toolchain-preset/v1";
pub const project_filename = "toolchain.yaml";
pub const preset_suffix = ".toolchain-preset.yaml";
pub const max_document_bytes: usize = 1024 * 1024;
pub const max_total_bytes: usize = 16 * 1024 * 1024;
pub const max_presets: usize = 256;
pub const max_refs: usize = 32;
pub const max_policies: usize = 64;
pub const max_yaml_events: usize = 4096;
pub const max_yaml_tokens: usize = 4096;
pub const max_yaml_nesting_depth: usize = 16;
pub const max_yaml_scalar_bytes: usize = 4096;

pub const Error = error{InvalidToolchain};
pub const Entry = struct { name: []const u8, size: u64, identity: filesystem_identity.FileIdentity };
pub const Capture = struct { name: []const u8, bytes: []const u8 };

pub const RawNode = union(enum) {
    scalar: []const u8,
    sequence: []const *RawNode,
    mapping: []const Pair,
};
pub const Pair = struct { key: *RawNode, value: *RawNode };
pub const RawDocument = struct { name: []const u8, root: *RawNode };

pub const Layer = enum { language, runtime, framework, build, @"test", environment };
pub const Project = struct { presets: []const []const u8, policies: []const []const u8 };
pub const Preset = struct {
    package: []const u8,
    package_id: []const u8,
    layer: Layer,
    extends: []const []const u8,
    policies: []const []const u8,
};
pub const Registry = struct { presets: []const Preset };
pub const Resolved = struct { packages: []const *const Preset };
pub const Composed = struct { packages: []const []const u8, policies: []const []const u8 };
pub const PolicyContract = struct { id: []const u8, project_selectable: bool, locked_required: bool };
pub const PolicyRegistry = struct { contracts: []const PolicyContract };
pub const ValidToolchain = opaque {
    pub fn packages(self: *const ValidToolchain) []const []const u8 {
        return validStorage(self).packages;
    }
    pub fn policies(self: *const ValidToolchain) []const PolicyContract {
        return validStorage(self).policies;
    }
};
const ValidToolchainStorage = struct { packages: []const []const u8, policies: []const PolicyContract };
pub const Owner = opaque {};
const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    value: ValidToolchainStorage,
};

pub fn parseProject(allocator: std.mem.Allocator, document: RawDocument) Error!Project {
    const map = mapping(document.root) orelse return error.InvalidToolchain;
    if (map.len != 3 or !scalarEquals(field(map, "schema"), project_schema)) return error.InvalidToolchain;
    return .{
        .presets = try refList(allocator, field(map, "presets"), max_refs, packageRefValid),
        .policies = try refList(allocator, field(map, "policies"), max_policies, policyRefValid),
    };
}

pub fn parseRegistry(allocator: std.mem.Allocator, documents: []const RawDocument) Error!Registry {
    if (documents.len > max_presets) return error.InvalidToolchain;
    const presets = allocator.alloc(Preset, documents.len) catch return error.InvalidToolchain;
    for (documents, presets) |document, *preset| {
        const map = mapping(document.root) orelse return error.InvalidToolchain;
        if (map.len != 5 or !scalarEquals(field(map, "schema"), preset_schema)) return error.InvalidToolchain;
        const package = scalar(field(map, "package")) orelse return error.InvalidToolchain;
        if (!packageRefValid(package)) return error.InvalidToolchain;
        const split = std.mem.lastIndexOfScalar(u8, package, '@') orelse return error.InvalidToolchain;
        preset.* = .{
            .package = package,
            .package_id = package[0..split],
            .layer = std.meta.stringToEnum(Layer, scalar(field(map, "layer")) orelse return error.InvalidToolchain) orelse return error.InvalidToolchain,
            .extends = try refList(allocator, field(map, "extends"), max_refs, packageRefValid),
            .policies = try refList(allocator, field(map, "policies"), max_policies, policyRefValid),
        };
    }
    std.mem.sort(Preset, presets, {}, lessPreset);
    for (presets, 0..) |preset, index| {
        if (index != 0 and std.mem.eql(u8, presets[index - 1].package, preset.package)) return error.InvalidToolchain;
    }
    const registry: Registry = .{ .presets = presets };
    try validateCompleteRegistry(allocator, registry);
    return registry;
}

pub fn validateCaptureBudget(project: Capture, presets: []const Entry) Error!void {
    if (project.bytes.len > max_document_bytes or presets.len > max_presets) {
        return error.InvalidToolchain;
    }
    var total: u64 = project.bytes.len;
    for (presets) |preset| {
        if (preset.size > max_document_bytes) return error.InvalidToolchain;
        total = std.math.add(u64, total, preset.size) catch return error.InvalidToolchain;
        if (total > max_total_bytes) return error.InvalidToolchain;
    }
}

pub fn resolve(allocator: std.mem.Allocator, project: Project, registry: Registry) Error!Resolved {
    var ordered: std.ArrayList(*const Preset) = .empty;
    errdefer ordered.deinit(allocator);
    const selected = allocator.alloc(u8, registry.presets.len) catch return error.InvalidToolchain;
    defer allocator.free(selected);
    @memset(selected, 0);
    for (project.presets) |reference| try markSelected(registry, reference, selected);
    // One version per package ID in the selected closure.
    for (registry.presets, 0..) |left, index| {
        if (selected[index] == 0) continue;
        for (registry.presets[index + 1 ..], index + 1..) |right, right_index| {
            if (selected[right_index] != 0 and std.mem.eql(u8, left.package_id, right.package_id) and !std.mem.eql(u8, left.package, right.package)) return error.InvalidToolchain;
        }
    }
    const emitted = allocator.alloc(bool, registry.presets.len) catch return error.InvalidToolchain;
    defer allocator.free(emitted);
    @memset(emitted, false);
    while (true) {
        var next: ?usize = null;
        for (registry.presets, 0..) |preset, index| {
            if (selected[index] == 0 or emitted[index] or !dependenciesEmitted(registry, preset, emitted)) continue;
            if (next == null or lessPreset({}, preset, registry.presets[next.?])) next = index;
        }
        const index = next orelse break;
        emitted[index] = true;
        ordered.append(allocator, &registry.presets[index]) catch return error.InvalidToolchain;
    }
    var selected_count: usize = 0;
    for (selected) |state| if (state != 0) {
        selected_count += 1;
    };
    if (ordered.items.len != selected_count) return error.InvalidToolchain;
    return .{ .packages = ordered.toOwnedSlice(allocator) catch return error.InvalidToolchain };
}

pub fn compose(allocator: std.mem.Allocator, project: Project, resolved: Resolved) Error!Composed {
    const packages = allocator.alloc([]const u8, resolved.packages.len) catch return error.InvalidToolchain;
    var policies: std.ArrayList([]const u8) = .empty;
    for (resolved.packages, packages) |preset, *package| {
        package.* = preset.package;
        for (preset.policies) |policy| try appendUnique(allocator, &policies, policy);
    }
    for (project.policies) |policy| try appendUnique(allocator, &policies, policy);
    return .{ .packages = packages, .policies = policies.toOwnedSlice(allocator) catch return error.InvalidToolchain };
}

pub fn validateSafety(backing_allocator: std.mem.Allocator, composed: Composed, registry: PolicyRegistry) Error!*Owner {
    for (registry.contracts, 0..) |contract, index| for (registry.contracts[0..index]) |prior| {
        if (std.mem.eql(u8, contract.id, prior.id)) return error.InvalidToolchain;
    };
    const owner = backing_allocator.create(OwnerStorage) catch return error.InvalidToolchain;
    errdefer backing_allocator.destroy(owner);
    owner.* = .{ .backing_allocator = backing_allocator, .arena = .init(backing_allocator), .value = undefined };
    errdefer owner.arena.deinit();
    const allocator = owner.arena.allocator();
    const packages = allocator.alloc([]const u8, composed.packages.len) catch return error.InvalidToolchain;
    for (composed.packages, packages) |package, *copy| copy.* = allocator.dupe(u8, package) catch return error.InvalidToolchain;
    var selected: std.ArrayList(*const PolicyContract) = .empty;
    for (registry.contracts) |*contract| if (contract.locked_required) try appendPolicy(allocator, &selected, contract);
    for (composed.policies) |id| {
        const contract = findPolicy(registry, id) orelse return error.InvalidToolchain;
        if (!contract.project_selectable) return error.InvalidToolchain;
        try appendPolicy(allocator, &selected, contract);
    }
    const policies = allocator.alloc(PolicyContract, selected.items.len) catch return error.InvalidToolchain;
    for (selected.items, policies) |contract, *copy| copy.* = .{
        .id = allocator.dupe(u8, contract.id) catch return error.InvalidToolchain,
        .project_selectable = contract.project_selectable,
        .locked_required = contract.locked_required,
    };
    owner.value = .{ .packages = packages, .policies = policies };
    return @ptrCast(owner);
}

pub fn value(owner: *const Owner) *const ValidToolchain {
    return @ptrCast(&ownerStorageConst(owner).value);
}
pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

fn markSelected(registry: Registry, reference: []const u8, states: []u8) Error!void {
    const index = findPreset(registry, reference) orelse return error.InvalidToolchain;
    if (states[index] == 1) return error.InvalidToolchain;
    if (states[index] == 2) return;
    states[index] = 1;
    for (registry.presets[index].extends) |dependency| try markSelected(registry, dependency, states);
    states[index] = 2;
}

fn validateCompleteRegistry(allocator: std.mem.Allocator, registry: Registry) Error!void {
    for (registry.presets) |preset| {
        const selected = [_][]const u8{preset.package};
        const resolved = try resolve(allocator, .{ .presets = &selected, .policies = &.{} }, registry);
        allocator.free(resolved.packages);
    }
}
fn dependenciesEmitted(registry: Registry, preset: Preset, emitted: []const bool) bool {
    for (preset.extends) |dependency| {
        const index = findPreset(registry, dependency) orelse return false;
        if (!emitted[index]) return false;
    }
    return true;
}
fn findPreset(registry: Registry, reference: []const u8) ?usize {
    for (registry.presets, 0..) |preset, index| if (std.mem.eql(u8, preset.package, reference)) return index;
    return null;
}
fn findPolicy(registry: PolicyRegistry, id: []const u8) ?*const PolicyContract {
    for (registry.contracts) |*contract| if (std.mem.eql(u8, contract.id, id)) return contract;
    return null;
}
fn appendUnique(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value_: []const u8) Error!void {
    for (list.items) |present| if (std.mem.eql(u8, present, value_)) return;
    list.append(allocator, value_) catch return error.InvalidToolchain;
}
fn appendPolicy(allocator: std.mem.Allocator, list: *std.ArrayList(*const PolicyContract), value_: *const PolicyContract) Error!void {
    for (list.items) |present| if (std.mem.eql(u8, present.id, value_.id)) return;
    list.append(allocator, value_) catch return error.InvalidToolchain;
}
fn lessPreset(_: void, left: Preset, right: Preset) bool {
    const layer = @intFromEnum(left.layer) < @intFromEnum(right.layer);
    return if (left.layer != right.layer) layer else std.mem.order(u8, left.package, right.package) == .lt;
}
fn mapping(node: *RawNode) ?[]const Pair {
    return switch (node.*) {
        .mapping => |value_| value_,
        else => null,
    };
}
fn scalar(node: ?*RawNode) ?[]const u8 {
    const present = node orelse return null;
    return switch (present.*) {
        .scalar => |value_| value_,
        else => null,
    };
}
fn scalarEquals(node: ?*RawNode, expected: []const u8) bool {
    return if (scalar(node)) |actual| std.mem.eql(u8, actual, expected) else false;
}
fn field(map: []const Pair, name: []const u8) ?*RawNode {
    for (map) |pair| {
        const key = scalar(pair.key) orelse return null;
        if (std.mem.eql(u8, key, name)) return pair.value;
    }
    return null;
}
fn refList(allocator: std.mem.Allocator, node: ?*RawNode, maximum: usize, validator: *const fn ([]const u8) bool) Error![]const []const u8 {
    const present = node orelse return error.InvalidToolchain;
    const values = switch (present.*) {
        .sequence => |items| items,
        else => return error.InvalidToolchain,
    };
    if (values.len > maximum) return error.InvalidToolchain;
    const result = allocator.alloc([]const u8, values.len) catch return error.InvalidToolchain;
    for (values, result, 0..) |item, *destination, index| {
        destination.* = scalar(item) orelse return error.InvalidToolchain;
        if (!validator(destination.*)) return error.InvalidToolchain;
        for (result[0..index]) |prior| if (std.mem.eql(u8, prior, destination.*)) return error.InvalidToolchain;
    }
    return result;
}
fn packageRefValid(reference: []const u8) bool {
    const split = std.mem.lastIndexOfScalar(u8, reference, '@') orelse return false;
    return idValid(reference[0..split]) and semverValid(reference[split + 1 ..]);
}
fn policyRefValid(reference: []const u8) bool {
    const split = std.mem.lastIndexOfScalar(u8, reference, '@') orelse return false;
    if (!idValid(reference[0..split])) return false;
    const version = reference[split + 1 ..];
    if (version.len == 0 or version[0] == '0') return false;
    for (version) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}
fn idValid(id: []const u8) bool {
    if (id.len == 0 or !std.ascii.isLower(id[0])) return false;
    var separator = false;
    for (id) |byte| if (std.ascii.isLower(byte) or std.ascii.isDigit(byte)) {
        separator = false;
    } else if (byte == '.' or byte == '-') {
        if (separator) return false;
        separator = true;
    } else return false;
    return !separator;
}
fn semverValid(version: []const u8) bool {
    var parts = std.mem.splitScalar(u8, version, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        count += 1;
        if (part.len == 0 or (part.len > 1 and part[0] == '0')) return false;
        for (part) |byte| if (!std.ascii.isDigit(byte)) return false;
    }
    return count == 3;
}
fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn validStorage(value_: *const ValidToolchain) *const ValidToolchainStorage {
    return @ptrCast(@alignCast(value_));
}

test "closed references reject ranges latest and leading zero versions" {
    try std.testing.expect(packageRefValid("zig@0.16.0"));
    try std.testing.expect(!packageRefValid("zig@latest"));
    try std.testing.expect(!packageRefValid("zig@^0.16.0"));
    try std.testing.expect(!packageRefValid("zig@00.16.0"));
}

test "inheritance is dependency first and safety injects locked policy" {
    const presets = [_]Preset{
        .{ .package = "base@1.0.0", .package_id = "base", .layer = .language, .extends = &.{}, .policies = &.{"project.zig@1"} },
        .{ .package = "app@1.0.0", .package_id = "app", .layer = .framework, .extends = &.{"base@1.0.0"}, .policies = &.{} },
    };
    const resolved = try resolve(std.testing.allocator, .{ .presets = &.{"app@1.0.0"}, .policies = &.{} }, .{ .presets = &presets });
    defer std.testing.allocator.free(resolved.packages);
    try std.testing.expectEqualStrings("base@1.0.0", resolved.packages[0].package);
    const composed = try compose(std.testing.allocator, .{ .presets = &.{"app@1.0.0"}, .policies = &.{} }, resolved);
    defer std.testing.allocator.free(composed.packages);
    defer std.testing.allocator.free(composed.policies);
    const registry: PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
        .{ .id = "project.zig@1", .project_selectable = true, .locked_required = false },
    } };
    const owner = try validateSafety(std.testing.allocator, composed, registry);
    defer deinitOwner(owner);
    try std.testing.expectEqual(@as(usize, 2), value(owner).packages().len);
    try std.testing.expectEqualStrings("core.safety@1", value(owner).policies()[0].id);
}

test "inheritance rejects cycles and conflicting package versions" {
    const cyclic = [_]Preset{
        .{ .package = "a@1.0.0", .package_id = "a", .layer = .language, .extends = &.{"b@1.0.0"}, .policies = &.{} },
        .{ .package = "b@1.0.0", .package_id = "b", .layer = .runtime, .extends = &.{"a@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, resolve(std.testing.allocator, .{ .presets = &.{"a@1.0.0"}, .policies = &.{} }, .{ .presets = &cyclic }));
    const conflicting = [_]Preset{
        .{ .package = "a@1.0.0", .package_id = "a", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "a@2.0.0", .package_id = "a", .layer = .language, .extends = &.{}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, resolve(std.testing.allocator, .{ .presets = &.{ "a@1.0.0", "a@2.0.0" }, .policies = &.{} }, .{ .presets = &conflicting }));
}

test "complete registry rejects invalid unselected closures" {
    const missing = [_]Preset{
        .{ .package = "selected@1.0.0", .package_id = "selected", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "unused@1.0.0", .package_id = "unused", .layer = .runtime, .extends = &.{"absent@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, validateCompleteRegistry(std.testing.allocator, .{ .presets = &missing }));

    const cycle = [_]Preset{
        .{ .package = "selected@1.0.0", .package_id = "selected", .layer = .language, .extends = &.{}, .policies = &.{} },
        .{ .package = "unused-a@1.0.0", .package_id = "unused-a", .layer = .runtime, .extends = &.{"unused-b@1.0.0"}, .policies = &.{} },
        .{ .package = "unused-b@1.0.0", .package_id = "unused-b", .layer = .framework, .extends = &.{"unused-a@1.0.0"}, .policies = &.{} },
    };
    try std.testing.expectError(error.InvalidToolchain, validateCompleteRegistry(std.testing.allocator, .{ .presets = &cycle }));
}

test "capture budget includes project and every preset exactly once" {
    const one_mebibyte = try std.testing.allocator.alloc(u8, max_document_bytes);
    defer std.testing.allocator.free(one_mebibyte);
    const project: Capture = .{ .name = project_filename, .bytes = one_mebibyte };
    var presets: [16]Entry = undefined;
    for (&presets, 0..) |*preset, index| preset.* = .{
        .name = "preset",
        .size = max_document_bytes,
        .identity = .{ .filesystem_id = 1, .file_id = index + 1 },
    };
    try validateCaptureBudget(project, presets[0..15]);
    try std.testing.expectError(error.InvalidToolchain, validateCaptureBudget(project, &presets));
}

test "safety validation rejects unknown nonselectable and duplicate policy authority" {
    const composed: Composed = .{ .packages = &.{}, .policies = &.{"unknown@1"} };
    const registry: PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
    } };
    try std.testing.expectError(error.InvalidToolchain, validateSafety(std.testing.allocator, composed, registry));

    const nonselectable: Composed = .{ .packages = &.{}, .policies = &.{"core.safety@1"} };
    try std.testing.expectError(error.InvalidToolchain, validateSafety(std.testing.allocator, nonselectable, registry));

    const duplicate: PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
    } };
    try std.testing.expectError(
        error.InvalidToolchain,
        validateSafety(std.testing.allocator, .{ .packages = &.{}, .policies = &.{} }, duplicate),
    );
}
