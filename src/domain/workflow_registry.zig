const std = @import("std");
const bootstrap_root_registry = @import("bootstrap_root_registry.zig");
const filesystem_identity = @import("filesystem_identity.zig");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");

pub const schema_version = "1.0";
pub const definition_suffix = ".workflow.yaml";
pub const max_inventory_entries: usize = 4096;
pub const max_inventory_depth: usize = 16;
pub const max_inventory_duration_ms: i64 = 5000;
pub const max_definitions: usize = 256;
pub const max_definition_bytes: usize = 1_048_576;
pub const max_total_definition_bytes: usize = 16_777_216;
pub const max_nodes: usize = 256;
pub const max_parameters: usize = 32;
pub const max_transitions: usize = 1536;
pub const max_yaml_events: usize = 262_144;
pub const max_yaml_tokens: usize = 262_144;
pub const max_yaml_nesting_depth: usize = 16;
pub const max_yaml_scalar_bytes: usize = 128;

pub const WorkflowId = struct {
    bytes: []const u8,
    pub fn parse(bytes: []const u8) ?WorkflowId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};
pub const WorkflowNodeId = struct {
    bytes: []const u8,
    pub fn parse(bytes: []const u8) ?WorkflowNodeId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};
pub const WorkflowParameterId = struct {
    bytes: []const u8,
    pub fn parse(bytes: []const u8) ?WorkflowParameterId {
        return if (validLocalId(bytes)) .{ .bytes = bytes } else null;
    }
};
pub const RegisteredRef = struct {
    bytes: []const u8,
    pub fn parse(bytes: []const u8) ?RegisteredRef {
        if (bytes.len < 3 or bytes.len > 128) return null;
        const at = std.mem.lastIndexOfScalar(u8, bytes, '@') orelse return null;
        if (at == 0 or at + 1 == bytes.len or bytes[0] < 'a' or bytes[0] > 'z' or
            bytes[at + 1] == '0') return null;
        var separator = false;
        for (bytes[0..at], 0..) |byte, index| {
            const current_separator = byte == '.' or byte == '-';
            if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or current_separator) or
                (current_separator and (index == 0 or separator))) return null;
            separator = current_separator;
        }
        if (separator) return null;
        for (bytes[at + 1 ..]) |byte| if (!std.ascii.isDigit(byte)) return null;
        return .{ .bytes = bytes };
    }
};

fn validLocalId(bytes: []const u8) bool {
    if (bytes.len == 0 or bytes.len > 64 or bytes[0] < 'a' or bytes[0] > 'z') return false;
    var hyphen = false;
    for (bytes, 0..) |byte, index| {
        if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '-') or
            (byte == '-' and (index == 0 or hyphen))) return false;
        hyphen = byte == '-';
    }
    return !hyphen;
}

pub fn validInventoryPath(path: []const u8) bool {
    if (path.len == 0 or !std.unicode.utf8ValidateSlice(path) or std.fs.path.isAbsolute(path) or
        std.mem.indexOfScalar(u8, path, '\\') != null)
    {
        return false;
    }
    var iterator = std.mem.splitScalar(u8, path, '/');
    while (iterator.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return false;
        }
        if (component[component.len - 1] == '.' or component[component.len - 1] == ' ' or
            reservedPortableName(component)) return false;
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

pub fn portableInventoryPathEqual(left: []const u8, right: []const u8) bool {
    return std.ascii.eqlIgnoreCase(left, right);
}

pub fn reservedInventoryAlias(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, '/') != null) return false;
    const reserved = std.ascii.eqlIgnoreCase(path, "features") or
        std.ascii.eqlIgnoreCase(path, "transactions");
    return reserved and !std.mem.eql(u8, path, "features") and
        !std.mem.eql(u8, path, "transactions");
}

fn reservedPortableName(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    if (std.ascii.eqlIgnoreCase(stem, "con") or
        std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or
        std.ascii.eqlIgnoreCase(stem, "nul")) return true;
    if (stem.len != 4) return false;
    return (std.ascii.eqlIgnoreCase(stem[0..3], "com") or
        std.ascii.eqlIgnoreCase(stem[0..3], "lpt")) and
        stem[3] >= '1' and stem[3] <= '9';
}

fn hasEncodedDotOrSeparator(path: []const u8) bool {
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        if (path[index] != '%') continue;
        var token_index = index + 1;
        while (token_index + 1 < path.len and
            std.ascii.toLower(path[token_index]) == '2' and
            std.ascii.toLower(path[token_index + 1]) == '5') token_index += 2;
        if (token_index + 1 >= path.len) continue;
        const first = std.ascii.toLower(path[token_index]);
        const second = std.ascii.toLower(path[token_index + 1]);
        if ((first == '2' and (second == 'e' or second == 'f')) or
            (first == '5' and second == 'c')) return true;
    }
    return false;
}

pub const OutcomeTag = enum { ok, needs_user, invalid, blocked, failed, cancelled };
pub const ParameterKind = enum { boolean, integer, @"enum", registered_id };
pub const ParameterValue = union(ParameterKind) {
    boolean: bool,
    integer: i64,
    @"enum": WorkflowNodeId,
    registered_id: RegisteredRef,
};
pub const ParameterBinding = struct { id: WorkflowParameterId, value: ParameterValue };
pub const DeclarativeNode = struct {
    id: WorkflowNodeId,
    contract_id: RegisteredRef,
    parameters: []const ParameterBinding,
};
pub const TransitionTarget = union(enum) { node: WorkflowNodeId, terminal: OutcomeTag };
pub const Transition = struct {
    from: WorkflowNodeId,
    outcome: OutcomeTag,
    target: TransitionTarget,
};
pub const Definition = struct {
    source_ordinal: u16,
    workflow_id: WorkflowId,
    workflow_version: u32,
    shortcode: telemetry.WorkflowShortcode,
    invocation_contract_id: RegisteredRef,
    policy_profile_id: RegisteredRef,
    entry_node_id: WorkflowNodeId,
    nodes: []const DeclarativeNode,
    transitions: []const Transition,
};

pub const EntryKind = enum { directory, file, symlink, special };
pub const InventoryDescriptor = struct {
    path: []const u8,
    kind: EntryKind,
    identity: ?filesystem_identity.FileIdentity = null,
    size: ?u64 = null,
};
pub const Disposition = enum { directory, reserved_child, definition };
pub const InventoryAccount = struct { ordinal: u16, path: []const u8, disposition: Disposition };
pub const Layout = struct { capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability };
pub const Inventory = struct {
    capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
    descriptors: []const InventoryDescriptor,
    accounts: []const InventoryAccount,
    definition_ordinals: []const u16,
};
pub const Capture = struct { ordinal: u16, bytes: []const u8 };

pub const InventoryError = error{InvalidWorkflowInventory};

pub fn classifyInventoryDescriptor(descriptor: InventoryDescriptor) ?Disposition {
    if (std.mem.eql(u8, descriptor.path, "features") or
        std.mem.eql(u8, descriptor.path, "transactions"))
    {
        return if (descriptor.kind == .directory and descriptor.identity != null)
            .reserved_child
        else
            null;
    }
    return switch (descriptor.kind) {
        .directory => if (descriptor.identity != null) .directory else null,
        .file => if (definitionPath(descriptor.path) and descriptor.identity != null and
            descriptor.size != null and descriptor.size.? <= max_definition_bytes)
            .definition
        else
            null,
        .symlink, .special => null,
    };
}

pub fn validateInventory(inventory: Inventory) InventoryError!void {
    try validateInventoryEntries(
        inventory.descriptors,
        inventory.accounts,
        inventory.definition_ordinals,
    );
}

fn validateInventoryEntries(
    descriptors: []const InventoryDescriptor,
    accounts: []const InventoryAccount,
    definition_ordinals: []const u16,
) InventoryError!void {
    if (descriptors.len > max_inventory_entries or
        accounts.len != descriptors.len or
        definition_ordinals.len > max_definitions)
    {
        return error.InvalidWorkflowInventory;
    }
    var definition_index: usize = 0;
    for (descriptors, accounts, 0..) |descriptor, account, index| {
        if (!validInventoryPath(descriptor.path) or reservedInventoryAlias(descriptor.path) or
            reservedDescendant(descriptor.path) or account.ordinal != index + 1 or
            !std.mem.eql(u8, account.path, descriptor.path) or
            account.disposition != (classifyInventoryDescriptor(descriptor) orelse return error.InvalidWorkflowInventory))
        {
            return error.InvalidWorkflowInventory;
        }
        if (index > 0 and std.mem.order(u8, descriptors[index - 1].path, descriptor.path) != .lt) {
            return error.InvalidWorkflowInventory;
        }
        for (descriptors[0..index]) |prior| {
            if (portableInventoryPathEqual(prior.path, descriptor.path) or
                samePhysicalIdentity(prior, descriptor)) return error.InvalidWorkflowInventory;
        }
        if (account.disposition == .definition) {
            if (definition_index == definition_ordinals.len or
                definition_ordinals[definition_index] != account.ordinal)
            {
                return error.InvalidWorkflowInventory;
            }
            definition_index += 1;
        }
    }
    if (definition_index != definition_ordinals.len) return error.InvalidWorkflowInventory;
}

pub fn validateCaptureBudget(inventory: Inventory) InventoryError!void {
    try validateCaptureBudgetEntries(inventory.descriptors, inventory.definition_ordinals);
}

fn validateCaptureBudgetEntries(
    descriptors: []const InventoryDescriptor,
    definition_ordinals: []const u16,
) InventoryError!void {
    var total: u64 = 0;
    for (definition_ordinals) |ordinal| {
        if (ordinal == 0 or ordinal > descriptors.len) return error.InvalidWorkflowInventory;
        const descriptor = descriptors[ordinal - 1];
        const size = descriptor.size orelse return error.InvalidWorkflowInventory;
        if (size > max_definition_bytes) return error.InvalidWorkflowInventory;
        total = std.math.add(u64, total, size) catch return error.InvalidWorkflowInventory;
        if (total > max_total_definition_bytes) return error.InvalidWorkflowInventory;
    }
}

fn definitionPath(path: []const u8) bool {
    const basename = std.fs.path.basename(path);
    return basename.len > definition_suffix.len and
        std.mem.endsWith(u8, basename, definition_suffix);
}
fn reservedDescendant(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "features/") or
        std.mem.startsWith(u8, path, "transactions/");
}
fn samePhysicalIdentity(left: InventoryDescriptor, right: InventoryDescriptor) bool {
    if (left.identity == null or right.identity == null) return false;
    return left.identity.?.eql(right.identity.?);
}
pub const RawNode = union(enum) {
    null_value,
    boolean: bool,
    integer: i128,
    float: f64,
    scalar: []const u8,
    sequence: []const *RawNode,
    mapping: []const RawPair,
};
pub const RawPair = struct { key: *RawNode, value: *RawNode };
pub const RawDefinition = struct { ordinal: u16, root: *RawNode };

pub const ParameterDescriptor = struct {
    id: []const u8,
    kind: ParameterKind,
    required: bool,
    workflow_definition_safe: bool,
    integer_min: i64 = std.math.minInt(i64),
    integer_max: i64 = std.math.maxInt(i64),
    enum_members: []const []const u8 = &.{},
    registered_values: []const []const u8 = &.{},
};
pub const InvocationContract = struct {
    id: []const u8,
    capability_free: bool,
    produces: []const pipeline.DataKey,
};
pub const NodeContract = struct {
    id: []const u8,
    parameters: []const ParameterDescriptor,
    requires: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey = &.{},
    invalidates: []const pipeline.DataKey = &.{},
    outcomes: []const OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
};
pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const OutcomeTag,
};
pub const CompilerRegistry = struct {
    invocations: []const InvocationContract,
    nodes: []const NodeContract,
    policies: []const PolicyProfile,
    gates: []const []const u8,
    capabilities: []const []const u8,
};

pub const CompiledNode = struct {
    id: WorkflowNodeId,
    contract_id: RegisteredRef,
    parameters: []const ParameterBinding,
    requires: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const OutcomeTag,
    side_effect: pipeline.SideEffect,
    gates: []const []const u8,
    capabilities: []const []const u8,
};
pub const SemanticAuthority = struct {
    workflow_id: WorkflowId,
    workflow_version: u32,
    invocation_contract_id: RegisteredRef,
    policy_profile_id: RegisteredRef,
    entry_node_id: WorkflowNodeId,
    invocation_outputs: []const pipeline.DataKey,
    nodes: []const CompiledNode,
    transitions: []const Transition,
};
pub const CompiledWorkflow = struct {
    source_ordinal: u16,
    shortcode: telemetry.WorkflowShortcode,
    authority: SemanticAuthority,
};
pub const ValidatedGraphs = struct { values: []const CompiledWorkflow };
pub const RegistryCandidate = struct {
    inventory: Inventory,
    captures: []const Capture,
    definitions: []const Definition,
    graphs: []const CompiledWorkflow,
};

pub const ValidatedWorkflowDefinitionRegistry = opaque {
    pub fn count(self: *const ValidatedWorkflowDefinitionRegistry) usize {
        return registryStorage(self).entries.len;
    }

    pub fn resolve(
        self: *const ValidatedWorkflowDefinitionRegistry,
        id: WorkflowId,
    ) ?*const CompiledWorkflow {
        for (registryStorage(self).entries) |*entry| {
            if (std.mem.eql(u8, entry.authority.workflow_id.bytes, id.bytes)) return entry;
        }
        return null;
    }
};
pub const Owner = opaque {};
const RegistryStorage = struct { entries: []const CompiledWorkflow };
const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    registry: RegistryStorage,
};
pub const Error = error{InvalidWorkflowRegistry};

pub fn createValidated(allocator: std.mem.Allocator, candidate: RegistryCandidate) Error!*Owner {
    try validateCandidate(candidate);
    const owner = allocator.create(OwnerStorage) catch return error.InvalidWorkflowRegistry;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .registry = undefined };
    errdefer owner.arena.deinit();
    const entries = owner.arena.allocator().alloc(CompiledWorkflow, candidate.graphs.len) catch {
        return error.InvalidWorkflowRegistry;
    };
    for (entries, candidate.graphs) |*destination, source| {
        destination.* = cloneGraph(owner.arena.allocator(), source) catch {
            return error.InvalidWorkflowRegistry;
        };
    }
    owner.registry = .{ .entries = entries };
    return @ptrCast(owner);
}

pub fn registry(owner: *const Owner) *const ValidatedWorkflowDefinitionRegistry {
    return @ptrCast(&ownerStorageConst(owner).registry);
}
pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

fn validateCandidate(candidate: RegistryCandidate) Error!void {
    validateInventory(candidate.inventory) catch return error.InvalidWorkflowRegistry;
    validateCaptureBudget(candidate.inventory) catch return error.InvalidWorkflowRegistry;
    if (candidate.graphs.len > max_definitions or candidate.graphs.len != candidate.definitions.len or
        candidate.graphs.len != candidate.captures.len or
        candidate.graphs.len != candidate.inventory.definition_ordinals.len)
    {
        return error.InvalidWorkflowRegistry;
    }
    try validateCaptureDefinitionJoins(
        candidate.inventory.descriptors,
        candidate.inventory.definition_ordinals,
        candidate.captures,
        candidate.definitions,
    );
    for (candidate.inventory.accounts, 0..) |account, index| {
        if (account.ordinal != index + 1 or
            !std.mem.eql(u8, account.path, candidate.inventory.descriptors[index].path))
        {
            return error.InvalidWorkflowRegistry;
        }
    }
    for (candidate.graphs, 0..) |graph, index| {
        const definition = findDefinition(candidate.definitions, graph.source_ordinal) orelse {
            return error.InvalidWorkflowRegistry;
        };
        if (!graphProjectsDefinition(graph, definition) or
            !containsOrdinal(candidate.inventory.definition_ordinals, graph.source_ordinal))
        {
            return error.InvalidWorkflowRegistry;
        }
        for (candidate.graphs[0..index]) |previous| {
            if (std.mem.eql(u8, graph.authority.workflow_id.bytes, previous.authority.workflow_id.bytes) or
                std.mem.eql(u8, &graph.shortcode.bytes, &previous.shortcode.bytes) or
                graph.source_ordinal == previous.source_ordinal)
            {
                return error.InvalidWorkflowRegistry;
            }
        }
        if (index > 0 and std.mem.order(
            u8,
            candidate.graphs[index - 1].authority.workflow_id.bytes,
            graph.authority.workflow_id.bytes,
        ) != .lt) return error.InvalidWorkflowRegistry;
    }
}

fn graphProjectsDefinition(graph: CompiledWorkflow, definition: Definition) bool {
    if (graph.source_ordinal != definition.source_ordinal or
        !std.mem.eql(u8, graph.authority.workflow_id.bytes, definition.workflow_id.bytes) or
        graph.authority.workflow_version != definition.workflow_version or
        !std.mem.eql(u8, &graph.shortcode.bytes, &definition.shortcode.bytes) or
        !std.mem.eql(u8, graph.authority.invocation_contract_id.bytes, definition.invocation_contract_id.bytes) or
        !std.mem.eql(u8, graph.authority.policy_profile_id.bytes, definition.policy_profile_id.bytes) or
        !std.mem.eql(u8, graph.authority.entry_node_id.bytes, definition.entry_node_id.bytes) or
        graph.authority.nodes.len != definition.nodes.len or
        graph.authority.transitions.len != definition.transitions.len)
    {
        return false;
    }
    for (graph.authority.nodes, definition.nodes) |compiled, declared| {
        if (!std.mem.eql(u8, compiled.id.bytes, declared.id.bytes) or
            !std.mem.eql(u8, compiled.contract_id.bytes, declared.contract_id.bytes) or
            compiled.parameters.len != declared.parameters.len) return false;
        for (compiled.parameters, declared.parameters) |compiled_parameter, declared_parameter| {
            if (!sameParameter(compiled_parameter, declared_parameter)) return false;
        }
    }
    for (graph.authority.transitions, definition.transitions) |compiled, declared| {
        if (!sameTransition(compiled, declared)) return false;
    }
    return true;
}

fn sameParameter(left: ParameterBinding, right: ParameterBinding) bool {
    if (!std.mem.eql(u8, left.id.bytes, right.id.bytes) or
        std.meta.activeTag(left.value) != std.meta.activeTag(right.value)) return false;
    return switch (left.value) {
        .boolean => |value| value == right.value.boolean,
        .integer => |value| value == right.value.integer,
        .@"enum" => |value| std.mem.eql(u8, value.bytes, right.value.@"enum".bytes),
        .registered_id => |value| std.mem.eql(u8, value.bytes, right.value.registered_id.bytes),
    };
}

fn sameTransition(left: Transition, right: Transition) bool {
    if (!std.mem.eql(u8, left.from.bytes, right.from.bytes) or
        left.outcome != right.outcome or
        std.meta.activeTag(left.target) != std.meta.activeTag(right.target)) return false;
    return switch (left.target) {
        .node => |value| std.mem.eql(u8, value.bytes, right.target.node.bytes),
        .terminal => |value| value == right.target.terminal,
    };
}

fn validateCaptureDefinitionJoins(
    descriptors: []const InventoryDescriptor,
    definition_ordinals: []const u16,
    captures: []const Capture,
    definitions: []const Definition,
) Error!void {
    if (captures.len != definition_ordinals.len or definitions.len != captures.len) {
        return error.InvalidWorkflowRegistry;
    }
    for (captures, definitions, definition_ordinals) |capture, definition, ordinal| {
        if (ordinal == 0 or ordinal > descriptors.len) return error.InvalidWorkflowRegistry;
        const expected_size = descriptors[ordinal - 1].size orelse {
            return error.InvalidWorkflowRegistry;
        };
        if (capture.ordinal != ordinal or capture.bytes.len != expected_size or
            definition.source_ordinal != ordinal)
        {
            return error.InvalidWorkflowRegistry;
        }
    }
}

fn cloneGraph(allocator: std.mem.Allocator, source: CompiledWorkflow) !CompiledWorkflow {
    const nodes = try allocator.alloc(CompiledNode, source.authority.nodes.len);
    for (nodes, source.authority.nodes) |*destination, node| {
        destination.* = node;
        destination.id.bytes = try allocator.dupe(u8, node.id.bytes);
        destination.contract_id.bytes = try allocator.dupe(u8, node.contract_id.bytes);
        destination.parameters = try cloneParameters(allocator, node.parameters);
        destination.requires = try allocator.dupe(pipeline.DataKey, node.requires);
        destination.produces = try allocator.dupe(pipeline.DataKey, node.produces);
        destination.replaces = try allocator.dupe(pipeline.DataKey, node.replaces);
        destination.invalidates = try allocator.dupe(pipeline.DataKey, node.invalidates);
        destination.outcomes = try allocator.dupe(OutcomeTag, node.outcomes);
        destination.gates = try cloneStrings(allocator, node.gates);
        destination.capabilities = try cloneStrings(allocator, node.capabilities);
    }
    const transitions = try allocator.alloc(Transition, source.authority.transitions.len);
    for (transitions, source.authority.transitions) |*destination, transition| {
        destination.* = transition;
        destination.from.bytes = try allocator.dupe(u8, transition.from.bytes);
        if (transition.target == .node) destination.target.node.bytes = try allocator.dupe(
            u8,
            transition.target.node.bytes,
        );
    }
    return .{
        .source_ordinal = source.source_ordinal,
        .shortcode = source.shortcode,
        .authority = .{
            .workflow_id = .{ .bytes = try allocator.dupe(u8, source.authority.workflow_id.bytes) },
            .workflow_version = source.authority.workflow_version,
            .invocation_contract_id = .{ .bytes = try allocator.dupe(u8, source.authority.invocation_contract_id.bytes) },
            .policy_profile_id = .{ .bytes = try allocator.dupe(u8, source.authority.policy_profile_id.bytes) },
            .entry_node_id = .{ .bytes = try allocator.dupe(u8, source.authority.entry_node_id.bytes) },
            .invocation_outputs = try allocator.dupe(pipeline.DataKey, source.authority.invocation_outputs),
            .nodes = nodes,
            .transitions = transitions,
        },
    };
}

fn cloneParameters(allocator: std.mem.Allocator, source: []const ParameterBinding) ![]const ParameterBinding {
    const values = try allocator.alloc(ParameterBinding, source.len);
    for (values, source) |*destination, value| {
        destination.* = value;
        destination.id.bytes = try allocator.dupe(u8, value.id.bytes);
        switch (destination.value) {
            .@"enum" => |*item| item.bytes = try allocator.dupe(u8, item.bytes),
            .registered_id => |*item| item.bytes = try allocator.dupe(u8, item.bytes),
            else => {},
        }
    }
    return values;
}
fn cloneStrings(allocator: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    const values = try allocator.alloc([]const u8, source.len);
    for (values, source) |*destination, value| destination.* = try allocator.dupe(u8, value);
    return values;
}
fn findDefinition(values: []const Definition, ordinal: u16) ?Definition {
    for (values) |value| if (value.source_ordinal == ordinal) return value;
    return null;
}
fn containsOrdinal(values: []const u16, expected: u16) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}
fn registryStorage(value: *const ValidatedWorkflowDefinitionRegistry) *const RegistryStorage {
    return @ptrCast(@alignCast(value));
}
fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

test "workflow and registered identifiers are exact" {
    try std.testing.expect(WorkflowId.parse("custom-flow") != null);
    try std.testing.expect(WorkflowId.parse("Custom") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@1") != null);
    try std.testing.expect(RegisteredRef.parse("core.noop@01") == null);
    try std.testing.expect(RegisteredRef.parse("core.noop@999999999999999999999999999999") != null);
}

test "workflow inventory validation owns collision and accounting joins" {
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
    try validateInventoryEntries(&descriptors, &accounts, &definition_ordinals);

    var wrong_account = accounts;
    wrong_account[1].disposition = .reserved_child;
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateInventoryEntries(&descriptors, &wrong_account, &definition_ordinals),
    );

    const case_collision = [_]InventoryDescriptor{
        .{ .path = "Alpha", .kind = .directory, .identity = identities[0] },
        .{ .path = "alpha", .kind = .directory, .identity = identities[1] },
    };
    const case_collision_accounts = [_]InventoryAccount{
        .{ .ordinal = 1, .path = "Alpha", .disposition = .directory },
        .{ .ordinal = 2, .path = "alpha", .disposition = .directory },
    };
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateInventoryEntries(&case_collision, &case_collision_accounts, &.{}),
    );

    var physical_alias = descriptors;
    physical_alias[2].identity = identities[0];
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateInventoryEntries(&physical_alias, &accounts, &definition_ordinals),
    );

    const reserved_alias = [_]InventoryDescriptor{.{
        .path = "Features",
        .kind = .directory,
        .identity = identities[0],
    }};
    const reserved_alias_account = [_]InventoryAccount{.{
        .ordinal = 1,
        .path = "Features",
        .disposition = .directory,
    }};
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateInventoryEntries(&reserved_alias, &reserved_alias_account, &.{}),
    );

    const reserved_descendant = [_]InventoryDescriptor{.{
        .path = "features/hidden.workflow.yaml",
        .kind = .file,
        .identity = identities[0],
        .size = 1,
    }};
    const reserved_descendant_account = [_]InventoryAccount{.{
        .ordinal = 1,
        .path = "features/hidden.workflow.yaml",
        .disposition = .definition,
    }};
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateInventoryEntries(&reserved_descendant, &reserved_descendant_account, &.{1}),
    );
}

test "workflow aggregate capture bytes are bounded before reads" {
    var descriptors: [17]InventoryDescriptor = undefined;
    var ordinals: [17]u16 = undefined;
    for (&descriptors, &ordinals, 0..) |*descriptor, *ordinal, index| {
        descriptor.* = .{
            .path = "unused.workflow.yaml",
            .kind = .file,
            .size = if (index < 16) max_definition_bytes else 1,
        };
        ordinal.* = @intCast(index + 1);
    }
    try validateCaptureBudgetEntries(descriptors[0..16], ordinals[0..16]);
    try std.testing.expectError(
        error.InvalidWorkflowInventory,
        validateCaptureBudgetEntries(&descriptors, &ordinals),
    );
}

test "workflow definition captures join exact descriptors and definitions" {
    const descriptor = [_]InventoryDescriptor{.{
        .path = "hello.workflow.yaml",
        .kind = .file,
        .size = 3,
    }};
    const ordinals = [_]u16{1};
    const captures = [_]Capture{.{ .ordinal = 1, .bytes = "abc" }};
    const definitions = [_]Definition{.{
        .source_ordinal = 1,
        .workflow_id = .{ .bytes = "hello" },
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("HELO") catch unreachable,
        .invocation_contract_id = .{ .bytes = "core.empty@1" },
        .policy_profile_id = .{ .bytes = "core.safe@1" },
        .entry_node_id = .{ .bytes = "run" },
        .nodes = &.{},
        .transitions = &.{},
    }};
    try validateCaptureDefinitionJoins(&descriptor, &ordinals, &captures, &definitions);

    const wrong_size = [_]Capture{.{ .ordinal = 1, .bytes = "ab" }};
    try std.testing.expectError(
        error.InvalidWorkflowRegistry,
        validateCaptureDefinitionJoins(&descriptor, &ordinals, &wrong_size, &definitions),
    );
    var wrong_definition = definitions;
    wrong_definition[0].source_ordinal = 2;
    try std.testing.expectError(
        error.InvalidWorkflowRegistry,
        validateCaptureDefinitionJoins(&descriptor, &ordinals, &captures, &wrong_definition),
    );
}

test "compiled graphs retain the exact definition projection" {
    const shortcode = telemetry.WorkflowShortcode.parse("HELO") catch unreachable;
    const declared_node: DeclarativeNode = .{
        .id = WorkflowNodeId.parse("run").?,
        .contract_id = RegisteredRef.parse("core.noop@1").?,
        .parameters = &.{.{
            .id = WorkflowParameterId.parse("attempts").?,
            .value = .{ .integer = 2 },
        }},
    };
    const transition: Transition = .{
        .from = declared_node.id,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    };
    const definition: Definition = .{
        .source_ordinal = 1,
        .workflow_id = WorkflowId.parse("hello").?,
        .workflow_version = 1,
        .shortcode = shortcode,
        .invocation_contract_id = RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = RegisteredRef.parse("core.safe@1").?,
        .entry_node_id = declared_node.id,
        .nodes = &.{declared_node},
        .transitions = &.{transition},
    };
    const compiled_node: CompiledNode = .{
        .id = declared_node.id,
        .contract_id = declared_node.contract_id,
        .parameters = declared_node.parameters,
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
    };
    var graph: CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = shortcode,
        .authority = .{
            .workflow_id = definition.workflow_id,
            .workflow_version = definition.workflow_version,
            .invocation_contract_id = definition.invocation_contract_id,
            .policy_profile_id = definition.policy_profile_id,
            .entry_node_id = definition.entry_node_id,
            .invocation_outputs = &.{},
            .nodes = &.{compiled_node},
            .transitions = &.{transition},
        },
    };
    try std.testing.expect(graphProjectsDefinition(graph, definition));
    graph.authority.workflow_version = 2;
    try std.testing.expect(!graphProjectsDefinition(graph, definition));
}

test "workflow media paths are exact portable ASCII" {
    const identity: filesystem_identity.FileIdentity = .{ .filesystem_id = 1, .file_id = 1 };
    try std.testing.expect(classifyInventoryDescriptor(.{
        .path = "nested/hello.workflow.yaml",
        .kind = .file,
        .identity = identity,
        .size = 1,
    }) == .definition);
    const invalid = [_][]const u8{
        "hello.workflow.json",
        "hello.workflow.yml",
        "hello.WORKFLOW.YAML",
        ".workflow.yaml",
        "caf\xc3\xa9.workflow.yaml",
        "con.workflow.yaml",
        "nested/%2e%2e/hello.workflow.yaml",
    };
    for (invalid) |path| {
        try std.testing.expect(!validInventoryPath(path) or classifyInventoryDescriptor(.{
            .path = path,
            .kind = .file,
            .identity = identity,
            .size = 1,
        }) == null);
    }
}
