const std = @import("std");

// Engine-selected profile; never an additional model-visible envelope field.
pub const profile = "model-result-schema/v1";
pub const max_bytes = @import("workflow_definition.zig").max_resource_bytes;
pub const max_json_depth = 64;
pub const max_depth = 16;
pub const max_nodes = 4096;
pub const max_properties = 256;
pub const max_choices = 1024;
/// ADR 0006's bound on one native integer choice, including an assignment's
/// exact member set. A larger choice rejects before invocation and is never split.
pub const ChoiceBoundError = error{ChoiceBoundExceeded};
pub fn withinChoiceBound(count: usize) bool {
    return count <= max_choices;
}
pub const max_variants = 32;

pub const DefinitionId = struct {
    bytes: []const u8,

    pub fn parse(value: []const u8) ?DefinitionId {
        if (value.len == 0 or value.len > 64 or !std.ascii.isLower(value[0])) return null;
        for (value) |byte| if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_' and byte != '-') return null;
        return .{ .bytes = value };
    }
};

pub const Error = error{InvalidModelResultSchema} || std.mem.Allocator.Error;

pub const Scalar = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
    null_value,
};

pub const Property = struct {
    name: []const u8,
    required: bool,
    schema: *const Node,
};

/// Native whole-assignment membership: each value appears exactly once as the
/// integer `property` of one array item. Response admission enforces it; the
/// provider schema can express only the item count, so uniqueness stays native.
pub const Members = struct { property: []const u8, values: []const i64 };
/// Native cross-item coverage on an array of objects (ADR 0038): every value an
/// item of a `covered` kind names in its integer list `property` must also be
/// named by an item of a `covering` kind. An item's kind is the `kind` of its
/// `kind_property` object. Response admission enforces it; the provider schema
/// can't express it.
pub const Coverage = struct { property: []const u8, rule: ItemCoverage };
pub const ItemCoverage = struct {
    kind_property: []const u8,
    covered: []const []const u8,
    covering: []const []const u8,

    pub fn clone(self: ItemCoverage, a: std.mem.Allocator) std.mem.Allocator.Error!ItemCoverage {
        return .{ .kind_property = try a.dupe(u8, self.kind_property), .covered = try cloneStrings(a, self.covered), .covering = try cloneStrings(a, self.covering) };
    }
};
pub const Node = union(enum) {
    object: []const Property,
    string: struct { minimum: u32, maximum: u32 },
    integer: struct { minimum: i64, maximum: i64 },
    boolean,
    null_value,
    constant: Scalar,
    enumeration: []const []const u8,
    integer_enumeration: []const i64,
    array: struct { minimum: u32, maximum: u32, items: *const Node, members: ?Members = null, coverage: ?Coverage = null, required_when: ?RequiredWhen = null },
    one_of: []const *const Node,
};

/// Native evidence can exclude unavailable tagged alternatives, never add a
/// shape or select content. Tags have the compiler's existing `kind` meaning.
pub const ExcludedVariant = struct { kind: []const u8 };
/// Native schema selections: typed atoms retain their shared tag identity;
/// other selectors name an exact property/items location in one definition.
pub const ChoiceStep = union(enum) { property: []const u8, items: void };
pub const ChoiceTarget = union(enum) {
    tagged: struct { kind: []const u8, field: []const u8 },
    path: []const ChoiceStep,
};
pub const IntegerChoice = struct {
    target: ChoiceTarget,
    definition: ?DefinitionId = null,
    allowed: []const i64,
    /// A native unique-selection invariant also bounds collection cardinality.
    /// Duplicate admission remains with the native owner; the schema profile
    /// has no uniqueness keyword. Sequence selectors keep canonical bounds.
    /// `exact_members` selects an integer property of array items: the array
    /// must name every allowed value exactly once (one complete assignment).
    collection: enum { sequence, unique_subset, exact_members } = .sequence,
    /// With `exact_members`, whether the guidance schema states the item count.
    /// `native` keeps the canonical bounds; admission alone enforces the members.
    member_count: enum { stated, native } = .stated,
    /// With a `unique_subset` selector on `<array>/items/<property>`, native
    /// cross-item coverage over that array.
    coverage: ?ItemCoverage = null,
    /// Explicit native authority: only a determined tagged field is omitted.
    singleton: enum { select, construct } = .select,

    pub fn constructedValue(self: IntegerChoice) ?i64 {
        return if (self.singleton == .construct and self.allowed.len == 1) self.allowed[0] else null;
    }
};
/// An applied `exact_members` selection. Model schema bytes carry at most its
/// item count and values, so request descriptions record it and replay
/// reapplies it natively over the recorded bounds.
pub const MemberChoice = struct { path: []const ChoiceStep, allowed: []const i64 };
/// An applied coverage selection, recorded for the same reason.
pub const CoverageChoice = struct { path: []const ChoiceStep, allowed: []const i64, coverage: ItemCoverage };
/// Native conditional requiredness (ADR 0042): an array needs at least one item
/// when a sibling scalar `property` of its object has one of `values`. Response
/// admission enforces it; the provider schema can't express it.
pub const RequiredWhen = struct {
    property: []const u8,
    values: []const []const u8,

    pub fn clone(self: RequiredWhen, a: std.mem.Allocator) std.mem.Allocator.Error!RequiredWhen {
        return .{ .property = try a.dupe(u8, self.property), .values = try cloneStrings(a, self.values) };
    }
};
/// A required-items selection; `path` ends at the conditioned array property.
/// Request descriptions record it, so replay reapplies it.
pub const RequiredItems = struct {
    path: []const ChoiceStep,
    when: RequiredWhen,

    pub fn clone(self: RequiredItems, a: std.mem.Allocator) std.mem.Allocator.Error!RequiredItems {
        return .{ .path = try cloneChoicePath(a, self.path), .when = try self.when.clone(a) };
    }
};

fn sameDefinition(left: ?DefinitionId, right: ?DefinitionId) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?.bytes, right.?.bytes);
}
fn validatedDefinition(canonical: *const Schema, entry: IntegerChoice) ?DefinitionId {
    const id = entry.definition orelse return null;
    const current = storage(canonical).definition_id orelse return id;
    return if (std.mem.eql(u8, id.bytes, current.bytes)) null else id;
}
fn sameTarget(left: ChoiceTarget, right: ChoiceTarget) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .tagged => |tag| std.mem.eql(u8, tag.kind, right.tagged.kind) and std.mem.eql(u8, tag.field, right.tagged.field),
        .path => |path| blk: {
            if (path.len != right.path.len) break :blk false;
            for (path, right.path) |l, r| {
                if (std.meta.activeTag(l) != std.meta.activeTag(r)) break :blk false;
                if (l == .property and !std.mem.eql(u8, l.property, r.property)) break :blk false;
            }
            break :blk true;
        },
    };
}

pub const Restricted = opaque {
    pub fn canonical(self: *const Restricted) *const Schema {
        return restrictedStorage(self).canonical;
    }
    pub fn selected(self: *const Restricted) *const Schema {
        return restrictedStorage(self).selected;
    }
    pub fn retain(self: *Restricted) void {
        restrictedStorage(self).references += 1;
    }
    pub fn release(self: *Restricted) void {
        const owned = restrictedStorage(self);
        owned.references -= 1;
        if (owned.references != 0) return;
        owned.arena.deinit();
        owned.allocator.destroy(owned);
    }
};
const RestrictedStorage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    references: usize = 1,
    canonical: *const Schema,
    selected: *const Schema,
    handle: RestrictedHandle,
};
const RestrictedHandle = struct { owner: *RestrictedStorage };
fn restrictedStorage(value: *const Restricted) *RestrictedStorage {
    const handle: *const RestrictedHandle = @ptrCast(@alignCast(value));
    return handle.owner;
}

pub fn restrict(allocator: std.mem.Allocator, canonical: *const Schema, excluded: []const ExcludedVariant, integer_choices: []const IntegerChoice) Error!*Restricted {
    return restrictFieldPolicies(allocator, canonical, excluded, integer_choices, &.{}, &.{});
}

/// Native field semantics add only restrictions to the existing generic schema.
pub fn restrictFieldPolicies(allocator: std.mem.Allocator, canonical: *const Schema, excluded: []const ExcludedVariant, integer_choices: []const IntegerChoice, field_policies: []const @import("model_text_field.zig").Binding, required_items: []const RequiredItems) Error!*Restricted {
    const owned = try allocator.create(RestrictedStorage);
    errdefer allocator.destroy(owned);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();
    for (integer_choices, 0..) |entry, index| {
        if (!withinChoiceBound(entry.allowed.len)) return invalid();
        if (entry.singleton == .construct and (entry.target != .tagged or entry.definition != null)) return invalid();
        if (entry.definition) |id| _ = DefinitionId.parse(id.bytes) orelse return invalid();
        switch (entry.target) {
            .tagged => |tag| if (tag.kind.len == 0 or tag.field.len == 0) return invalid(),
            .path => |path| {
                if (path.len == 0 or path.len > max_depth) return invalid();
                for (path) |step| if (step == .property and step.property.len == 0) return invalid();
            },
        }
        if (entry.member_count == .native and entry.collection != .exact_members) return invalid();
        if (entry.collection == .exact_members) {
            const path = if (entry.target == .path) entry.target.path else return invalid();
            if (entry.allowed.len == 0 or path.len < 2 or path[path.len - 2] != .items or path[path.len - 1] != .property) return invalid();
            // One complete member set: an outer array would repeat or omit it.
            for (path[0 .. path.len - 2]) |step| if (step == .items) return invalid();
        }
        if (entry.coverage) |rule| {
            const path = if (entry.target == .path) entry.target.path else return invalid();
            if (entry.collection != .unique_subset or path.len < 2 or path[path.len - 2] != .items or path[path.len - 1] != .property) return invalid();
            if (rule.kind_property.len == 0 or rule.covered.len == 0 or rule.covering.len == 0) return invalid();
            // Kinds are distinct and disjoint; an item that covers itself makes the rule vacuous.
            const kinds = [_][]const []const u8{ rule.covered, rule.covering };
            for (kinds, 0..) |names, group| for (names, 0..) |kind, position| {
                if (kind.len == 0) return invalid();
                for (names[0..position]) |prior| if (std.mem.eql(u8, prior, kind)) return invalid();
                if (group == 1) for (rule.covered) |covered| if (std.mem.eql(u8, covered, kind)) return invalid();
            };
        }
        // A choice naming the selected definition targets the same schema as one
        // naming none; restating either target would stack incompatible narrowings.
        for (integer_choices[0..index]) |prior| if (sameDefinition(validatedDefinition(canonical, prior), validatedDefinition(canonical, entry)) and sameTarget(prior.target, entry.target)) return invalid();
        for (entry.allowed, 0..) |choice, choice_index| for (entry.allowed[0..choice_index]) |prior| {
            if (choice == prior) return invalid();
        };
    }
    for (required_items, 0..) |entry, index| {
        const path = entry.path;
        if (path.len == 0 or path.len > max_depth or path[path.len - 1] != .property) return invalid();
        for (path) |step| if (step == .property and step.property.len == 0) return invalid();
        const when = entry.when;
        if (when.property.len == 0 or std.mem.eql(u8, when.property, path[path.len - 1].property) or when.values.len == 0 or !withinChoiceBound(when.values.len)) return invalid();
        for (when.values, 0..) |value, position| {
            if (value.len == 0) return invalid();
            for (when.values[0..position]) |prior| if (std.mem.eql(u8, prior, value)) return invalid();
        }
        for (required_items[0..index]) |prior| if (sameTarget(.{ .path = prior.path }, .{ .path = path })) return invalid();
    }
    var root = try restrictNode(arena.allocator(), canonical.root(), excluded);
    if (field_policies.len != 0) root = (try @import("model_text_field.zig").project(arena.allocator(), root, field_policies, true)).root;
    for (integer_choices) |entry| {
        if (entry.definition) |id| {
            const current = storage(canonical).definition_id orelse return invalid();
            if (!std.mem.eql(u8, id.bytes, current.bytes)) {
                const other = for (storage(canonical).choice_definitions) |definition| {
                    if (std.mem.eql(u8, id.bytes, definition.id.bytes)) break definition.root;
                } else return invalid();
                // Membership and coverage must constrain the schema actually validated.
                if (entry.collection == .exact_members or entry.coverage != null) return invalid();
                if (!(try narrowChoice(arena.allocator(), other, entry.target, entry.allowed, entry.collection, entry.member_count, null)).matched) return invalid();
                continue;
            }
        }
        const narrowed = try narrowChoice(arena.allocator(), root, entry.target, entry.allowed, entry.collection, entry.member_count, entry.coverage);
        if (!narrowed.matched and (entry.collection == .exact_members or entry.coverage != null)) return invalid();
        if (!narrowed.matched and entry.target == .path) {
            const parent = storage(canonical).projection_of orelse return invalid();
            if (!(try narrowChoice(arena.allocator(), parent.root(), entry.target, entry.allowed, entry.collection, entry.member_count, null)).matched) return invalid();
        }
        root = if (entry.constructedValue() != null)
            try omitConstructedField(arena.allocator(), narrowed.node, entry.target.tagged)
        else
            narrowed.node;
    }
    // Required items apply to the selected schema after every choice narrowed it.
    for (required_items) |entry| {
        const marked = try requireItems(arena.allocator(), root, entry.path, entry.when);
        if (!marked.matched) return invalid();
        root = marked.node;
    }
    // Whatever form a later choice took, each member key must still offer exactly
    // its member set; otherwise no response could satisfy the restriction.
    if (!membersIntact(root)) return invalid();
    var members: std.ArrayList(MemberChoice) = .empty;
    var coverages: std.ArrayList(CoverageChoice) = .empty;
    for (integer_choices) |entry| {
        if (entry.collection == .exact_members) try members.append(arena.allocator(), .{ .path = try cloneChoicePath(arena.allocator(), entry.target.path), .allowed = try arena.allocator().dupe(i64, entry.allowed) });
        if (entry.coverage) |rule| try coverages.append(arena.allocator(), .{ .path = try cloneChoicePath(arena.allocator(), entry.target.path), .allowed = try arena.allocator().dupe(i64, entry.allowed), .coverage = try rule.clone(arena.allocator()) });
    }
    const required = try arena.allocator().alloc(RequiredItems, required_items.len);
    for (required_items, required) |entry, *destination| destination.* = try entry.clone(arena.allocator());
    const selected = try createSchema(arena.allocator(), root, canonical.bytes(), &.{}, .{ .restriction_of = canonical, .definition_id = storage(canonical).definition_id, .projection_of = storage(canonical).projection_of, .choice_definitions = storage(canonical).choice_definitions, .member_choices = members.items, .coverage_choices = coverages.items, .required_items = required });
    owned.* = .{ .allocator = allocator, .arena = arena, .canonical = canonical, .selected = selected, .handle = .{ .owner = owned } };
    return @ptrCast(&owned.handle);
}

/// Reapply recorded membership, coverage and required items to a schema
/// reconstructed from model bytes.
pub fn restrictRecorded(allocator: std.mem.Allocator, selected: *const Schema, members: []const MemberChoice, coverages: []const CoverageChoice, required: []const RequiredItems) Error!*Restricted {
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const choices = try scratch.allocator().alloc(IntegerChoice, members.len + coverages.len);
    // The recorded bytes already carry whatever item count the request stated.
    for (members, choices[0..members.len]) |member, *choice| choice.* = .{ .target = .{ .path = member.path }, .allowed = member.allowed, .collection = .exact_members, .member_count = .native };
    for (coverages, choices[members.len..]) |recorded, *choice| choice.* = .{ .target = .{ .path = recorded.path }, .allowed = recorded.allowed, .collection = .unique_subset, .coverage = recorded.coverage };
    return restrictFieldPolicies(allocator, selected, &.{}, choices, &.{}, required);
}

fn cloneStrings(a: std.mem.Allocator, values: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const copy = try a.alloc([]const u8, values.len);
    for (copy, values) |*destination, value| destination.* = try a.dupe(u8, value);
    return copy;
}

fn cloneChoicePath(a: std.mem.Allocator, path: []const ChoiceStep) std.mem.Allocator.Error![]const ChoiceStep {
    const copy = try a.dupe(ChoiceStep, path);
    for (copy) |*step| if (step.* == .property) {
        step.* = .{ .property = try a.dupe(u8, step.property) };
    };
    return copy;
}

/// The caller first narrows and checks the native value against the canonical
/// field. Removing it from the closed selected object rejects model echoes.
fn omitConstructedField(a: std.mem.Allocator, node: *const Node, target: @FieldType(ChoiceTarget, "tagged")) Error!*const Node {
    const result = try a.create(Node);
    result.* = node.*;
    switch (node.*) {
        .object => |properties| {
            const kind = findProperty(properties, "kind");
            const selected = kind != null and kind.?.schema.* == .constant and kind.?.schema.constant == .string and std.mem.eql(u8, kind.?.schema.constant.string, target.kind);
            var copy: std.ArrayList(Property) = .empty;
            for (properties) |property| {
                if (selected and std.mem.eql(u8, property.name, target.field)) {
                    if (!property.required or property.schema.* != .integer_enumeration or property.schema.integer_enumeration.len != 1) return invalid();
                    continue;
                }
                var retained = property;
                retained.schema = try omitConstructedField(a, property.schema, target);
                try copy.append(a, retained);
            }
            result.* = .{ .object = try copy.toOwnedSlice(a) };
        },
        .array => |items| result.array.items = try omitConstructedField(a, items.items, target),
        .one_of => |variants| {
            const copy = try a.alloc(*const Node, variants.len);
            for (variants, copy) |variant, *destination| destination.* = try omitConstructedField(a, variant, target);
            result.* = .{ .one_of = copy };
        },
        else => {},
    }
    return result;
}

fn restrictNode(a: std.mem.Allocator, node: *const Node, excluded: []const ExcludedVariant) Error!*const Node {
    const result = try a.create(Node);
    result.* = node.*;
    switch (node.*) {
        .one_of => |choices| {
            var remaining: std.ArrayList(*const Node) = .empty;
            for (choices) |choice| {
                if (excludedVariant(choice, excluded)) continue;
                try remaining.append(a, try restrictNode(a, choice, excluded));
            }
            if (remaining.items.len == 0) return invalid();
            result.* = if (remaining.items.len == 1) remaining.items[0].* else .{ .one_of = try remaining.toOwnedSlice(a) };
        },
        .object => |properties| {
            if (excludedVariant(node, excluded)) return invalid();
            const copy = try a.dupe(Property, properties);
            for (copy) |*property| property.schema = try restrictNode(a, property.schema, excluded);
            result.* = .{ .object = copy };
        },
        .array => |items| result.array.items = try restrictNode(a, items.items, excluded),
        else => {},
    }
    return result;
}

const Narrowed = struct { node: *const Node, matched: bool };
fn narrowChoice(a: std.mem.Allocator, node: *const Node, target: ChoiceTarget, allowed: ?[]const i64, collection: @FieldType(IntegerChoice, "collection"), member_count: @FieldType(IntegerChoice, "member_count"), coverage: ?ItemCoverage) Error!Narrowed {
    if (target == .path and target.path.len == 0 and node.* != .one_of) {
        // A nullable field keeps its explicit absence alternative. The selector
        // still has to match and constrain an integer-bearing sibling below.
        if (jsonType(node) == .null_value) return .{ .node = node, .matched = false };
        if (node.* != .integer and node.* != .integer_enumeration and (node.* != .array or (node.array.items.* != .integer and node.array.items.* != .integer_enumeration))) return invalid();
        if (collection == .unique_subset and node.* != .array) return invalid();
        const values = allowed orelse return .{ .node = node, .matched = true };
        const result = try a.create(Node);
        result.* = node.*;
        if (node.* == .array) {
            if (values.len == 0) {
                if (node.array.minimum != 0) return invalid();
                result.array.maximum = 0;
            } else {
                result.array.items = try narrowInteger(a, node.array.items, values);
                if (collection == .unique_subset) {
                    result.array.maximum = @min(result.array.maximum, @as(u32, @intCast(values.len)));
                    if (result.array.minimum > result.array.maximum) return invalid();
                }
            }
        } else result.* = (try narrowInteger(a, node, values)).*;
        return .{ .node = result, .matched = true };
    }
    switch (node.*) {
        .one_of => |variants| {
            const copy = try a.dupe(*const Node, variants);
            var matched = false;
            for (copy) |*variant| {
                const selected = try narrowChoice(a, variant.*, target, allowed, collection, member_count, coverage);
                // Membership must hold in every alternative, or one escapes it.
                if (collection == .exact_members and !selected.matched) return invalid();
                variant.* = selected.node;
                matched = selected.matched or matched;
            }
            const result = try a.create(Node);
            result.* = .{ .one_of = copy };
            return .{ .node = result, .matched = matched };
        },
        .object => |properties| {
            if (target == .tagged) {
                const tag = findProperty(properties, "kind");
                if (tag != null and tag.?.schema.* == .constant and tag.?.schema.constant == .string and std.mem.eql(u8, tag.?.schema.constant.string, target.tagged.kind)) {
                    if (findProperty(properties, target.tagged.field) == null) return invalid();
                    return narrowChoice(a, node, .{ .path = &.{.{ .property = target.tagged.field }} }, allowed, collection, member_count, coverage);
                }
            }
            const copy = try a.dupe(Property, properties);
            var matched = false;
            for (copy) |*property| {
                const next: ChoiceTarget = if (target == .tagged) target else blk: {
                    if (target.path[0] != .property or !std.mem.eql(u8, target.path[0].property, property.name)) continue;
                    break :blk .{ .path = target.path[1..] };
                };
                const selected = try narrowChoice(a, property.schema, next, allowed, collection, member_count, coverage);
                // An absent optional property would escape membership entirely.
                if (collection == .exact_members and selected.matched and !property.required) return invalid();
                property.schema = selected.node;
                matched = selected.matched or matched;
            }
            const result = try a.create(Node);
            result.* = .{ .object = copy };
            return .{ .node = result, .matched = matched };
        },
        .array => |items| {
            const next: ChoiceTarget = if (target == .tagged) target else blk: {
                if (target.path[0] != .items) return .{ .node = node, .matched = false };
                break :blk .{ .path = target.path[1..] };
            };
            if (target == .path and allowed != null and allowed.?.len == 0 and items.minimum == 0) {
                const checked = try narrowChoice(a, items.items, next, null, collection, member_count, null);
                if (checked.matched) {
                    const empty = try a.create(Node);
                    empty.* = node.*;
                    empty.array.maximum = 0;
                    return .{ .node = empty, .matched = true };
                }
            }
            const selected = try narrowChoice(a, items.items, next, allowed, collection, member_count, coverage);
            const result = try a.create(Node);
            result.* = node.*;
            result.array.items = selected.node;
            if (coverage) |rule| if (selected.matched and next == .path and next.path.len == 1 and next.path[0] == .property) {
                if (items.coverage != null) return invalid();
                result.array.coverage = .{ .property = try a.dupe(u8, next.path[0].property), .rule = try rule.clone(a) };
            };
            if (collection == .exact_members and selected.matched and next == .path and next.path.len == 1 and next.path[0] == .property) {
                if (!requiredIntegerKey(items.items, next.path[0].property)) return invalid();
                const values = allowed orelse return invalid();
                const count = std.math.cast(u32, values.len) orelse return invalid();
                if (count < items.minimum or count > items.maximum or items.members != null) return invalid();
                if (member_count == .stated) {
                    result.array.minimum = count;
                    result.array.maximum = count;
                }
                result.array.members = .{ .property = try a.dupe(u8, next.path[0].property), .values = try a.dupe(i64, values) };
            }
            return .{ .node = result, .matched = selected.matched };
        },
        else => return .{ .node = node, .matched = false },
    }
}
/// Mark the array `path` reaches. Its object must require it and a scalar
/// sibling that can take every listed value; otherwise the rule could never
/// hold or never apply.
fn requireItems(a: std.mem.Allocator, node: *const Node, path: []const ChoiceStep, when: RequiredWhen) Error!Narrowed {
    switch (node.*) {
        .one_of => |variants| {
            const copy = try a.dupe(*const Node, variants);
            var matched = false;
            for (copy) |*variant| {
                const selected = try requireItems(a, variant.*, path, when);
                variant.* = selected.node;
                matched = selected.matched or matched;
            }
            const result = try a.create(Node);
            result.* = .{ .one_of = copy };
            return .{ .node = result, .matched = matched };
        },
        .object => |properties| {
            if (path[0] != .property) return .{ .node = node, .matched = false };
            const copy = try a.dupe(Property, properties);
            var matched = false;
            for (copy) |*property| {
                if (!std.mem.eql(u8, property.name, path[0].property)) continue;
                if (path.len > 1) {
                    const selected = try requireItems(a, property.schema, path[1..], when);
                    property.schema = selected.node;
                    matched = selected.matched;
                    continue;
                }
                if (!property.required or property.schema.* != .array or property.schema.array.required_when != null) return invalid();
                const sibling = findProperty(properties, when.property) orelse return invalid();
                if (!sibling.required or !offersValues(sibling.schema, when.values)) return invalid();
                const marked = try a.create(Node);
                marked.* = property.schema.*;
                marked.array.required_when = try when.clone(a);
                property.schema = marked;
                matched = true;
            }
            const result = try a.create(Node);
            result.* = .{ .object = copy };
            return .{ .node = result, .matched = matched };
        },
        .array => |items| {
            if (path[0] != .items) return .{ .node = node, .matched = false };
            const selected = try requireItems(a, items.items, path[1..], when);
            const result = try a.create(Node);
            result.* = node.*;
            result.array.items = selected.node;
            return .{ .node = result, .matched = selected.matched };
        },
        else => return .{ .node = node, .matched = false },
    }
}
fn offersValues(node: *const Node, values: []const []const u8) bool {
    for (values) |value| switch (node.*) {
        .enumeration => |choices| for (choices) |choice| {
            if (std.mem.eql(u8, choice, value)) break;
        } else return false,
        .string => |bounds| {
            const length = std.unicode.utf8CountCodepoints(value) catch return false;
            if (length < bounds.minimum or length > bounds.maximum) return false;
        },
        else => return false,
    };
    return true;
}
fn membersIntact(node: *const Node) bool {
    return switch (node.*) {
        .object => |properties| for (properties) |property| {
            if (!membersIntact(property.schema)) break false;
        } else true,
        .one_of => |variants| for (variants) |variant| {
            if (!membersIntact(variant)) break false;
        } else true,
        .array => |array| membersIntact(array.items) and (if (array.members) |members| keyEnumerates(array.items, members) else true) and
            if (array.coverage) |coverage| coverageApplies(array.items, coverage) else true,
        else => true,
    };
}
/// Coverage needs object items with a required integer list and a required kind
/// object offering every kind the rule names; otherwise it could never apply.
fn coverageApplies(node: *const Node, coverage: Coverage) bool {
    if (node.* != .object) return false;
    const listed = findProperty(node.object, coverage.property) orelse return false;
    if (!listed.required or listed.schema.* != .array or (listed.schema.array.items.* != .integer and listed.schema.array.items.* != .integer_enumeration)) return false;
    const kinds = findProperty(node.object, coverage.rule.kind_property) orelse return false;
    if (!kinds.required) return false;
    for ([_][]const []const u8{ coverage.rule.covered, coverage.rule.covering }) |names| for (names) |name| {
        if (!offersKind(kinds.schema, name)) return false;
    };
    return true;
}
fn offersKind(node: *const Node, kind: []const u8) bool {
    return switch (node.*) {
        .object => if (discriminator(node)) |declared| std.mem.eql(u8, declared, kind) else false,
        .one_of => |variants| for (variants) |variant| {
            if (offersKind(variant, kind)) break true;
        } else false,
        else => false,
    };
}
fn keyEnumerates(node: *const Node, members: Members) bool {
    return switch (node.*) {
        .object => |properties| blk: {
            const property = findProperty(properties, members.property) orelse break :blk false;
            if (property.schema.* != .integer_enumeration or property.schema.integer_enumeration.len != members.values.len) break :blk false;
            for (members.values) |value| if (std.mem.indexOfScalar(i64, property.schema.integer_enumeration, value) == null) break :blk false;
            break :blk true;
        },
        .one_of => |variants| for (variants) |variant| {
            if (!keyEnumerates(variant, members)) break false;
        } else variants.len != 0,
        else => false,
    };
}
/// A membership key is a required, non-nullable scalar integer in every item variant.
fn requiredIntegerKey(node: *const Node, name: []const u8) bool {
    return switch (node.*) {
        .object => |properties| blk: {
            const property = findProperty(properties, name) orelse break :blk false;
            break :blk property.required and (property.schema.* == .integer or property.schema.* == .integer_enumeration);
        },
        .one_of => |variants| for (variants) |variant| {
            if (!requiredIntegerKey(variant, name)) break false;
        } else variants.len != 0,
        else => false,
    };
}
fn narrowInteger(a: std.mem.Allocator, node: *const Node, allowed: []const i64) Error!*const Node {
    if (allowed.len == 0) return invalid();
    for (allowed) |choice| switch (node.*) {
        .integer => |bounds| if (choice < bounds.minimum or choice > bounds.maximum) return invalid(),
        .integer_enumeration => |values| if (std.mem.indexOfScalar(i64, values, choice) == null) return invalid(),
        else => return invalid(),
    };
    const result = try a.create(Node);
    result.* = .{ .integer_enumeration = try a.dupe(i64, allowed) };
    return result;
}

fn excludedVariant(node: *const Node, excluded: []const ExcludedVariant) bool {
    if (node.* != .object) return false;
    const tag = findProperty(node.object, "kind") orelse return false;
    if (tag.schema.* != .constant or tag.schema.constant != .string) return false;
    for (excluded) |entry| if (std.mem.eql(u8, entry.kind, tag.schema.constant.string)) return true;
    return false;
}

// Syntax/semantic compilation is the only producer. Consumers cannot construct
// a result-schema resource from a raw byte slice or a nominal schema ID.
pub const Schema = opaque {
    pub fn isRestrictionOf(self: *const Schema, canonical: *const Schema) bool {
        return self == canonical or storage(self).restriction_of == canonical;
    }
    pub fn root(self: *const Schema) *const Node {
        return &storage(self).root;
    }

    pub fn bytes(self: *const Schema) []const u8 {
        return storage(self).bytes;
    }

    pub fn modelBytes(self: *const Schema) []const u8 {
        return storage(self).model_bytes;
    }

    pub fn memberChoices(self: *const Schema) []const MemberChoice {
        return storage(self).member_choices;
    }

    pub fn coverageChoices(self: *const Schema) []const CoverageChoice {
        return storage(self).coverage_choices;
    }

    pub fn requiredItems(self: *const Schema) []const RequiredItems {
        return storage(self).required_items;
    }

    pub fn select(self: *const Schema, id: DefinitionId) ?*const Schema {
        for (storage(self).definitions) |entry| {
            if (std.mem.eql(u8, entry.id.bytes, id.bytes)) return entry.result;
        }
        return null;
    }

    // Destination allocations belong to the caller's graph/registry arena.
    pub fn clone(self: *const Schema, allocator: std.mem.Allocator) std.mem.Allocator.Error!*const Schema {
        return cloneSchema(allocator, self, try allocator.dupe(u8, self.bytes()));
    }
};

const Definition = struct { id: DefinitionId, result: ?*const Schema };
const DefinitionShape = struct { id: DefinitionId, root: *const Node };
const Storage = struct { bytes: []const u8, model_bytes: []const u8, root: Node, definitions: []const Definition = &.{}, restriction_of: ?*const Schema = null, definition_id: ?DefinitionId = null, projection_of: ?*const Schema = null, choice_definitions: []const DefinitionShape = &.{}, member_choices: []const MemberChoice = &.{}, coverage_choices: []const CoverageChoice = &.{}, required_items: []const RequiredItems = &.{} };

fn cloneSchema(allocator: std.mem.Allocator, source: *const Schema, bytes: []const u8) std.mem.Allocator.Error!*const Schema {
    const copy = try allocator.create(Storage);
    const definitions = try allocator.alloc(Definition, storage(source).definitions.len);
    for (storage(source).definitions, definitions) |entry, *destination| {
        destination.* = .{
            .id = .{ .bytes = try allocator.dupe(u8, entry.id.bytes) },
            .result = if (entry.result) |value| try cloneSchema(allocator, value, bytes) else null,
        };
    }
    const shapes = try allocator.alloc(DefinitionShape, storage(source).choice_definitions.len);
    for (storage(source).choice_definitions, shapes) |shape, *destination| {
        const root = try allocator.create(Node);
        root.* = try cloneNode(allocator, shape.root.*);
        destination.* = .{ .id = .{ .bytes = try allocator.dupe(u8, shape.id.bytes) }, .root = root };
    }
    const members = try allocator.alloc(MemberChoice, storage(source).member_choices.len);
    for (storage(source).member_choices, members) |member, *destination| destination.* = .{ .path = try cloneChoicePath(allocator, member.path), .allowed = try allocator.dupe(i64, member.allowed) };
    const coverages = try allocator.alloc(CoverageChoice, storage(source).coverage_choices.len);
    for (storage(source).coverage_choices, coverages) |recorded, *destination| destination.* = .{ .path = try cloneChoicePath(allocator, recorded.path), .allowed = try allocator.dupe(i64, recorded.allowed), .coverage = try recorded.coverage.clone(allocator) };
    const required = try allocator.alloc(RequiredItems, storage(source).required_items.len);
    for (storage(source).required_items, required) |recorded, *destination| destination.* = try recorded.clone(allocator);
    copy.* = .{ .bytes = bytes, .model_bytes = try allocator.dupe(u8, source.modelBytes()), .root = try cloneNode(allocator, source.root().*), .definitions = definitions, .definition_id = if (storage(source).definition_id) |id| .{ .bytes = try allocator.dupe(u8, id.bytes) } else null, .projection_of = if (storage(source).projection_of) |parent| try cloneSchema(allocator, parent, bytes) else null, .choice_definitions = shapes, .member_choices = members, .coverage_choices = coverages, .required_items = required };
    return @ptrCast(copy);
}

fn storage(value: *const Schema) *const Storage {
    return @ptrCast(@alignCast(value));
}

// The narrow syntax adapter supplies the complete decoded document and its
// exact source bytes. All output allocations belong to the caller's arena;
// that arena must be discarded on rejection/allocation failure.
pub fn compile(allocator: std.mem.Allocator, raw: std.json.Value, bytes: []const u8) Error!*const Schema {
    return compileResult(allocator, raw, bytes, .complete);
}

/// Reconstruct a captured selected response shape for diagnostic inspection/replay.
/// Composition may select a single constant-tagged object. This does not relax
/// the external workflow-resource profile or admit scalar response roots.
pub fn compileSelected(allocator: std.mem.Allocator, raw: std.json.Value, bytes: []const u8) Error!*const Schema {
    return compileResult(allocator, raw, bytes, .selected);
}

fn compileResult(allocator: std.mem.Allocator, raw: std.json.Value, bytes: []const u8, kind: enum { complete, selected }) Error!*const Schema {
    if (raw != .object) return invalid();
    var compiler: Compiler = .{ .allocator = allocator };
    var root_value = raw;
    if (raw.object.get("$defs")) |defs| {
        if (defs != .object or defs.object.count() == 0 or defs.object.count() > max_properties) return invalid();
        compiler.definitions = defs.object;
        root_value.object = try raw.object.clone(allocator);
        _ = root_value.object.swapRemove("$defs");
    }
    const captured = try allocator.dupe(u8, bytes);
    const definitions = try allocator.alloc(Definition, compiler.definitions.count());
    var shapes: std.ArrayList(DefinitionShape) = .empty;
    var iterator = compiler.definitions.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        const id = DefinitionId.parse(entry.key_ptr.*) orelse return invalid();
        compiler.node_count = 0;
        const node = try compiler.reference(id, 1);
        if (isResult(node)) try shapes.append(allocator, .{ .id = .{ .bytes = try allocator.dupe(u8, id.bytes) }, .root = node });
        definitions[index] = .{
            .id = .{ .bytes = try allocator.dupe(u8, id.bytes) },
            .result = null,
        };
    }
    const choice_definitions = try shapes.toOwnedSlice(allocator);
    for (definitions) |*entry| for (choice_definitions) |shape| {
        if (!std.mem.eql(u8, entry.id.bytes, shape.id.bytes)) continue;
        entry.result = try createSchema(allocator, shape.root, captured, &.{}, .{ .definition_id = entry.id, .choice_definitions = choice_definitions });
        break;
    };
    // The existing expansion bound applies independently to the selected root.
    compiler.node_count = 0;
    const root = try compiler.node(root_value, 1);
    switch (kind) {
        .complete => if (!isResult(root)) return invalid(),
        .selected => if (!objectResult(root)) return invalid(),
    }
    return createSchema(allocator, root, captured, definitions, .{});
}

fn isResult(root: *const Node) bool {
    return switch (root.*) {
        .object => |properties| {
            if (findProperty(properties, "kind")) |property| switch (property.schema.*) {
                .constant => return false,
                .enumeration => |values| if (values.len == 1) return false,
                .integer_enumeration => |values| if (values.len == 1) return false,
                else => {},
            };
            return true;
        },
        .one_of => objectResult(root),
        else => false,
    };
}

const Association = struct { restriction_of: ?*const Schema = null, definition_id: ?DefinitionId = null, projection_of: ?*const Schema = null, choice_definitions: []const DefinitionShape = &.{}, member_choices: []const MemberChoice = &.{}, coverage_choices: []const CoverageChoice = &.{}, required_items: []const RequiredItems = &.{} };
fn createSchema(allocator: std.mem.Allocator, root: *const Node, bytes: []const u8, definitions: []const Definition, association: Association) std.mem.Allocator.Error!*const Schema {
    const result = try allocator.create(Storage);
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const model_bytes = try std.json.Stringify.valueAlloc(allocator, try @import("model_schema_projection.zig").value(scratch.allocator(), root, .complete), .{});
    result.* = .{ .bytes = bytes, .model_bytes = model_bytes, .root = root.*, .definitions = definitions, .restriction_of = association.restriction_of, .definition_id = association.definition_id, .projection_of = association.projection_of, .choice_definitions = association.choice_definitions, .member_choices = association.member_choices, .coverage_choices = association.coverage_choices, .required_items = association.required_items };
    return @ptrCast(result);
}

/// The composition compiler derives these nodes from an already compiled schema.
/// It preserves closed objects and variant tags, including a selected constant
/// tag that is intentionally not accepted as an independent external result.
pub fn project(allocator: std.mem.Allocator, canonical: *const Schema, root: *const Node) std.mem.Allocator.Error!*const Schema {
    return createSchema(allocator, root, canonical.bytes(), &.{}, .{ .definition_id = storage(canonical).definition_id, .projection_of = canonical, .choice_definitions = storage(canonical).choice_definitions });
}

const Compiler = struct {
    allocator: std.mem.Allocator,
    node_count: usize = 0,
    definitions: std.json.ObjectMap = .{},
    reference_stack: [max_depth]DefinitionId = undefined,
    reference_depth: usize = 0,

    fn reference(self: *Compiler, id: DefinitionId, depth: usize) Error!*const Node {
        if (self.reference_depth == max_depth) return invalid();
        for (self.reference_stack[0..self.reference_depth]) |prior| if (std.mem.eql(u8, prior.bytes, id.bytes)) return invalid();
        const raw = self.definitions.get(id.bytes) orelse return invalid();
        self.reference_stack[self.reference_depth] = id;
        self.reference_depth += 1;
        defer self.reference_depth -= 1;
        return self.node(raw, depth);
    }

    fn node(self: *Compiler, raw: std.json.Value, depth: usize) Error!*const Node {
        if (depth > max_depth or raw != .object) return invalid();
        const object = raw.object;
        if (object.get("$ref")) |ref_value| {
            try fields(object, &.{"$ref"});
            if (ref_value != .string or !std.mem.startsWith(u8, ref_value.string, "#/$defs/")) return invalid();
            const id = DefinitionId.parse(ref_value.string[8..]) orelse return invalid();
            return self.reference(id, depth);
        }
        if (self.node_count == max_nodes) return invalid();
        self.node_count += 1;
        const result = try self.allocator.create(Node);
        if (object.get("oneOf")) |variants| {
            try fields(object, &.{"oneOf"});
            if (variants != .array or variants.array.items.len < 2 or variants.array.items.len > max_variants) return invalid();
            const choices = try self.allocator.alloc(*const Node, variants.array.items.len);
            for (variants.array.items, choices, 0..) |value, *choice, index| {
                choice.* = try self.node(value, depth + 1);
                const shape = jsonType(choice.*) orelse return invalid();
                for (choices[0..index]) |prior| if (shape == jsonType(prior).?) {
                    // Distinct JSON types already select one branch. Objects
                    // need disjoint tags only when another object competes.
                    if (shape != .object or std.mem.eql(u8, try variantKind(choice.*), try variantKind(prior))) return invalid();
                };
            }
            result.* = .{ .one_of = choices };
        } else if (object.get("const")) |value| {
            try fields(object, &.{"const"});
            result.* = .{ .constant = try self.scalar(value) };
        } else if (object.get("enum")) |values| {
            try fields(object, &.{"enum"});
            if (values != .array or values.array.items.len == 0 or !withinChoiceBound(values.array.items.len)) return invalid();
            const first = values.array.items[0];
            switch (first) {
                .string => {
                    const choices = try self.allocator.alloc([]const u8, values.array.items.len);
                    for (values.array.items, choices, 0..) |value, *choice, index| {
                        if (value != .string) return invalid();
                        for (choices[0..index]) |prior| if (std.mem.eql(u8, prior, value.string)) return invalid();
                        choice.* = try self.copyString(value.string);
                    }
                    result.* = .{ .enumeration = choices };
                },
                .integer => {
                    const choices = try self.allocator.alloc(i64, values.array.items.len);
                    for (values.array.items, choices, 0..) |value, *choice, index| {
                        if (value != .integer) return invalid();
                        for (choices[0..index]) |prior| if (prior == value.integer) return invalid();
                        choice.* = value.integer;
                    }
                    result.* = .{ .integer_enumeration = choices };
                },
                else => return invalid(),
            }
        } else {
            const kind = object.get("type") orelse return invalid();
            if (kind != .string) return invalid();
            if (std.mem.eql(u8, kind.string, "object")) {
                try fields(object, &.{ "type", "properties", "required", "additionalProperties" });
                const properties = object.get("properties") orelse return invalid();
                const required = object.get("required") orelse return invalid();
                const extra = object.get("additionalProperties") orelse return invalid();
                if (properties != .object or properties.object.count() > max_properties or
                    required != .array or required.array.items.len > properties.object.count() or
                    extra != .bool or extra.bool) return invalid();
                for (required.array.items, 0..) |name, index| {
                    if (name != .string or !properties.object.contains(name.string)) return invalid();
                    for (required.array.items[0..index]) |prior| if (std.mem.eql(u8, prior.string, name.string)) return invalid();
                }
                const compiled = try self.allocator.alloc(Property, properties.object.count());
                var iterator = properties.object.iterator();
                var index: usize = 0;
                while (iterator.next()) |entry| : (index += 1) {
                    var is_required = false;
                    for (required.array.items) |name| if (std.mem.eql(u8, name.string, entry.key_ptr.*)) {
                        is_required = true;
                    };
                    compiled[index] = .{
                        .name = try self.copyString(entry.key_ptr.*),
                        .required = is_required,
                        .schema = try self.node(entry.value_ptr.*, depth + 1),
                    };
                }
                result.* = .{ .object = compiled };
            } else if (std.mem.eql(u8, kind.string, "string")) {
                try fields(object, &.{ "type", "minLength", "maxLength" });
                const bounds = try lengthBounds(object, "minLength", "maxLength");
                result.* = .{ .string = .{ .minimum = bounds[0], .maximum = bounds[1] } };
            } else if (std.mem.eql(u8, kind.string, "integer")) {
                try fields(object, &.{ "type", "minimum", "maximum" });
                const minimum = try integer(object.get("minimum") orelse return invalid());
                const maximum = try integer(object.get("maximum") orelse return invalid());
                if (minimum > maximum) return invalid();
                result.* = .{ .integer = .{ .minimum = minimum, .maximum = maximum } };
            } else if (std.mem.eql(u8, kind.string, "array")) {
                try fields(object, &.{ "type", "items", "minItems", "maxItems" });
                const bounds = try lengthBounds(object, "minItems", "maxItems");
                result.* = .{ .array = .{
                    .minimum = bounds[0],
                    .maximum = bounds[1],
                    .items = try self.node(object.get("items") orelse return invalid(), depth + 1),
                } };
            } else if (std.mem.eql(u8, kind.string, "boolean")) {
                try fields(object, &.{"type"});
                result.* = .boolean;
            } else if (std.mem.eql(u8, kind.string, "null")) {
                try fields(object, &.{"type"});
                result.* = .null_value;
            } else return invalid();
        }
        return result;
    }

    fn scalar(self: *Compiler, value: std.json.Value) Error!Scalar {
        return switch (value) {
            .string => |text| .{ .string = try self.copyString(text) },
            .integer => |number| .{ .integer = number },
            .bool => |boolean| .{ .boolean = boolean },
            .null => .null_value,
            else => invalid(),
        };
    }

    fn copyString(self: *Compiler, value: []const u8) Error![]const u8 {
        if (!std.unicode.utf8ValidateSlice(value)) return invalid();
        return self.allocator.dupe(u8, value);
    }
};

fn fields(object: std.json.ObjectMap, allowed: []const []const u8) Error!void {
    for (object.keys()) |key| {
        for (allowed) |name| {
            if (std.mem.eql(u8, key, name)) break;
        } else return invalid();
    }
}

fn integer(value: std.json.Value) Error!i64 {
    return if (value == .integer) value.integer else invalid();
}

fn lengthBounds(object: std.json.ObjectMap, min_key: []const u8, max_key: []const u8) Error![2]u32 {
    const minimum = if (object.get(min_key)) |value| try integer(value) else 0;
    const maximum = try integer(object.get(max_key) orelse return invalid());
    if (minimum < 0 or maximum < minimum or maximum > std.math.maxInt(u32)) return invalid();
    return .{ @intCast(minimum), @intCast(maximum) };
}

pub fn findProperty(properties: []const Property, name: []const u8) ?Property {
    for (properties) |property| if (std.mem.eql(u8, property.name, name)) return property;
    return null;
}

/// Disjoint primitive types plus explicitly tagged object alternatives.
pub const JsonType = enum { object, array, string, number, boolean, null_value };
pub fn jsonType(node: *const Node) ?JsonType {
    return switch (node.*) {
        .object => .object,
        .array => .array,
        .string, .enumeration => .string,
        .integer, .integer_enumeration => .number,
        .boolean => .boolean,
        .null_value => .null_value,
        .constant => |value| switch (value) {
            .string => .string,
            .integer => .number,
            .boolean => .boolean,
            .null_value => .null_value,
        },
        .one_of => null,
    };
}
fn objectResult(node: *const Node) bool {
    if (node.* == .object) return true;
    if (node.* != .one_of) return false;
    for (node.one_of) |variant| if (variant.* != .object) return false;
    return true;
}

fn variantKind(node: *const Node) Error![]const u8 {
    return discriminator(node) orelse return invalid();
}

/// Optional object discriminator. A sole object in a type-disjoint alternative
/// set needs none; competing object variants are compiler-checked to have one.
pub fn discriminator(node: *const Node) ?[]const u8 {
    if (node.* != .object) return null;
    const property = findProperty(node.object, "kind") orelse return null;
    if (!property.required or property.schema.* != .constant or property.schema.constant != .string or property.schema.constant.string.len == 0) return null;
    return property.schema.constant.string;
}

fn cloneNode(allocator: std.mem.Allocator, source: Node) std.mem.Allocator.Error!Node {
    return switch (source) {
        .object => |properties| blk: {
            const copy = try allocator.dupe(Property, properties);
            for (copy) |*property| {
                property.name = try allocator.dupe(u8, property.name);
                property.schema = try cloneChild(allocator, property.schema);
            }
            break :blk .{ .object = copy };
        },
        .constant => |value| .{ .constant = switch (value) {
            .string => |text| .{ .string = try allocator.dupe(u8, text) },
            else => value,
        } },
        .enumeration => |choices| blk: {
            const copy = try allocator.alloc([]const u8, choices.len);
            for (copy, choices) |*destination, choice| destination.* = try allocator.dupe(u8, choice);
            break :blk .{ .enumeration = copy };
        },
        .integer_enumeration => |choices| .{ .integer_enumeration = try allocator.dupe(i64, choices) },
        .array => |array| .{ .array = .{ .minimum = array.minimum, .maximum = array.maximum, .items = try cloneChild(allocator, array.items), .members = if (array.members) |members| .{ .property = try allocator.dupe(u8, members.property), .values = try allocator.dupe(i64, members.values) } else null, .coverage = if (array.coverage) |coverage| .{ .property = try allocator.dupe(u8, coverage.property), .rule = try coverage.rule.clone(allocator) } else null, .required_when = if (array.required_when) |rule| try rule.clone(allocator) else null } },
        .one_of => |choices| blk: {
            const copy = try allocator.alloc(*const Node, choices.len);
            for (copy, choices) |*destination, choice| destination.* = try cloneChild(allocator, choice);
            break :blk .{ .one_of = copy };
        },
        else => source,
    };
}

fn cloneChild(allocator: std.mem.Allocator, source: *const Node) std.mem.Allocator.Error!*const Node {
    const copy = try allocator.create(Node);
    copy.* = try cloneNode(allocator, source.*);
    return copy;
}

fn invalid() error{InvalidModelResultSchema} {
    return error.InvalidModelResultSchema;
}
