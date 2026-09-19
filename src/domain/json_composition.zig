//! Compile configured object partitions against one canonical result schema.
//! All allocations belong to the caller's graph arena, including on rejection.
const std = @import("std");
const schema = @import("model_result_schema.zig");
const pointer = @import("json_pointer.zig");
const workflow = @import("workflow.zig");

pub const version = "json-composition/v1";
pub const Error = error{InvalidJsonComposition} || std.mem.Allocator.Error;
pub const SelectionError = error{InvalidCompositionSelection};
pub const Pointer = pointer.Pointer;
pub const PartId = workflow.WorkflowResourceId;
pub const Condition = struct { producer: usize, path: Pointer, value: []const u8 };
pub const Alternative = struct { schema: *const schema.Schema, conditions: []const Condition };
pub const Part = struct {
    id: PartId,
    paths: []const Pointer,
    requires: []const usize,
    alternatives: []const Alternative,
};
pub const PartValue = struct { part: usize, value: std.json.Value };

pub const Plan = opaque {
    pub fn bytes(self: *const Plan) []const u8 {
        return storage(self).bytes;
    }
    pub fn resultAlias(self: *const Plan) workflow.WorkflowResourceId {
        return storage(self).result_alias;
    }
    pub fn resultSchema(self: *const Plan) *const schema.Schema {
        return storage(self).canonical;
    }
    pub fn parts(self: *const Plan) []const Part {
        return storage(self).parts;
    }
    pub fn part(self: *const Plan, id: PartId) ?usize {
        for (self.parts(), 0..) |entry, index| if (std.mem.eql(u8, entry.id.bytes, id.bytes)) return index;
        return null;
    }
    pub fn dependsOn(self: *const Plan, index: usize, prerequisite: usize) bool {
        return index < self.parts().len and prerequisite < self.parts().len and depends(self.parts(), index, prerequisite);
    }
    pub fn selectSchema(self: *const Plan, index: usize, inputs: []const PartValue) SelectionError!*const schema.Schema {
        if (index >= self.parts().len) return error.InvalidCompositionSelection;
        const selected = self.parts()[index];
        for (inputs, 0..) |input, at| {
            if (input.part >= self.parts().len or !depends(self.parts(), index, input.part)) return error.InvalidCompositionSelection;
            for (inputs[0..at]) |prior| if (input.part == prior.part) return error.InvalidCompositionSelection;
        }
        for (selected.requires) |required| if (findInput(inputs, required) == null) return error.InvalidCompositionSelection;
        var result: ?*const schema.Schema = null;
        for (selected.alternatives) |alternative| {
            var matches = true;
            for (alternative.conditions) |condition| {
                const source = findInput(inputs, condition.producer) orelse return error.InvalidCompositionSelection;
                // Nested discriminators exist only in their active outer branch.
                // An absent path rules out this alternative, not the assignment.
                const value = lookup(source, condition.path) orelse {
                    matches = false;
                    break;
                };
                if (value != .string or !std.mem.eql(u8, value.string, condition.value)) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                if (result != null) return error.InvalidCompositionSelection;
                result = alternative.schema;
            }
        }
        return result orelse error.InvalidCompositionSelection;
    }
    /// Recompile projections against the registry's canonical destination owner.
    pub fn clone(self: *const Plan, allocator: std.mem.Allocator, canonical: *const schema.Schema) Error!*const Plan {
        if (!std.mem.eql(u8, self.resultSchema().bytes(), canonical.bytes()) or
            !std.mem.eql(u8, self.resultSchema().modelBytes(), canonical.modelBytes())) return invalid();
        const copied = try allocator.alloc(Part, self.parts().len);
        for (self.parts(), copied) |source, *destination| {
            const paths = try allocator.alloc(Pointer, source.paths.len);
            for (source.paths, paths) |path, *copy| {
                const segments = try allocator.alloc([]const u8, path.segments.len);
                for (path.segments, segments) |segment, *entry| entry.* = try allocator.dupe(u8, segment);
                copy.* = .{ .segments = segments };
            }
            destination.* = .{
                .id = .{ .bytes = try allocator.dupe(u8, source.id.bytes) },
                .paths = paths,
                .requires = try allocator.dupe(usize, source.requires),
                .alternatives = &.{},
            };
        }
        return derive(allocator, copied, self.resultAlias(), self.bytes(), canonical);
    }
};

const Storage = struct {
    bytes: []const u8,
    result_alias: workflow.WorkflowResourceId,
    canonical: *const schema.Schema,
    parts: []const Part,
};
fn storage(plan: *const Plan) *const Storage {
    return @ptrCast(@alignCast(plan));
}

pub fn resultAlias(raw: std.json.Value) Error!workflow.WorkflowResourceId {
    if (raw != .object or raw.object.count() != 3) return invalid();
    const tag = raw.object.get("schema") orelse return invalid();
    const result = raw.object.get("result") orelse return invalid();
    const parts = raw.object.get("parts") orelse return invalid();
    if (tag != .string or !std.mem.eql(u8, tag.string, version) or result != .string or parts != .object) return invalid();
    return workflow.WorkflowResourceId.parse(result.string) orelse invalid();
}

pub fn compile(allocator: std.mem.Allocator, raw: std.json.Value, bytes: []const u8, canonical: *const schema.Schema) Error!*const Plan {
    const alias = try resultAlias(raw);
    const entries = raw.object.get("parts").?.object;
    if (entries.count() == 0 or entries.count() > schema.max_properties) return invalid();
    const parts = try allocator.alloc(Part, entries.count());
    for (entries.keys(), entries.values(), parts) |name, value, *part| {
        if (value != .object or value.object.count() < 1 or value.object.count() > 2) return invalid();
        for (value.object.keys()) |key| if (!std.mem.eql(u8, key, "paths") and !std.mem.eql(u8, key, "requires")) return invalid();
        const id = PartId.parse(name) orelse return invalid();
        const paths_value = value.object.get("paths") orelse return invalid();
        if (paths_value != .array or paths_value.array.items.len == 0 or paths_value.array.items.len > schema.max_properties) return invalid();
        const paths = try allocator.alloc(Pointer, paths_value.array.items.len);
        for (paths_value.array.items, paths) |path, *destination| {
            if (path != .string) return invalid();
            destination.* = pointer.parse(allocator, path.string) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidJsonPointer => invalid(),
            };
            if (destination.segments.len == 0 or destination.segments.len > schema.max_depth) return invalid();
        }
        part.* = .{ .id = .{ .bytes = try allocator.dupe(u8, id.bytes) }, .paths = paths, .requires = &.{}, .alternatives = &.{} };
    }
    for (entries.values(), parts, 0..) |value, *part, index| {
        if (value.object.get("requires")) |required| {
            if (required != .array or required.array.items.len > parts.len) return invalid();
            const dependencies = try allocator.alloc(usize, required.array.items.len);
            for (required.array.items, dependencies, 0..) |name, *destination, offset| {
                if (name != .string) return invalid();
                destination.* = findPart(parts, name.string) orelse return invalid();
                if (destination.* == index) return invalid();
                for (dependencies[0..offset]) |prior| if (prior == destination.*) return invalid();
            }
            part.requires = dependencies;
        }
    }
    const visiting = try allocator.alloc(bool, parts.len);
    const visited = try allocator.alloc(bool, parts.len);
    @memset(visiting, false);
    @memset(visited, false);
    for (parts, 0..) |_, index| try visit(parts, index, visiting, visited);

    // Selectors are resolved against all variants, never compared as raw prefixes.
    for (parts, 0..) |part, index| for (part.paths, 0..) |path, path_index| {
        if (!try resolves(canonical.root(), path.segments)) return invalid();
        for (parts[0 .. index + 1], 0..) |prior_part, prior_index| {
            const prior_paths = if (prior_index == index) prior_part.paths[0..path_index] else prior_part.paths;
            for (prior_paths) |prior| if (prior.isPrefixOf(path) or path.isPrefixOf(prior)) return invalid();
        }
    };
    return derive(allocator, parts, alias, bytes, canonical);
}

fn derive(allocator: std.mem.Allocator, parts: []Part, alias: workflow.WorkflowResourceId, bytes: []const u8, canonical: *const schema.Schema) Error!*const Plan {
    var compiler: Compiler = .{ .allocator = allocator, .parts = parts };
    try compiler.cover(canonical.root(), .{ .segments = &.{} });
    for (parts, 0..) |*part, index| {
        const projections = try compiler.project(canonical.root(), .{ .segments = &.{} }, index);
        if (projections.len == 0) return invalid();
        const alternatives = try allocator.alloc(Alternative, projections.len);
        for (projections, alternatives) |projection, *alternative| {
            if (projection.node.* != .object and projection.node.* != .one_of) return invalid();
            alternative.* = .{ .schema = try schema.project(allocator, canonical, projection.node), .conditions = projection.conditions };
        }
        part.alternatives = alternatives;
    }
    const result = try allocator.create(Storage);
    result.* = .{ .bytes = try allocator.dupe(u8, bytes), .result_alias = .{ .bytes = try allocator.dupe(u8, alias.bytes) }, .canonical = canonical, .parts = parts };
    return @ptrCast(result);
}

const Projection = struct { node: *const schema.Node, conditions: []const Condition = &.{} };
const Compiler = struct {
    allocator: std.mem.Allocator,
    parts: []const Part,

    fn owner(self: Compiler, path: Pointer) ?usize {
        for (self.parts, 0..) |part, index| for (part.paths) |selected| if (selected.isPrefixOf(path)) return index;
        return null;
    }
    fn extend(self: Compiler, path: Pointer, name: []const u8) Error!Pointer {
        const result = try self.allocator.alloc([]const u8, path.segments.len + 1);
        @memcpy(result[0..path.segments.len], path.segments);
        result[path.segments.len] = name;
        return .{ .segments = result };
    }
    fn node(self: Compiler, value: schema.Node) Error!*const schema.Node {
        const result = try self.allocator.create(schema.Node);
        result.* = value;
        return result;
    }
    fn cover(self: Compiler, source: *const schema.Node, path: Pointer) Error!void {
        if (self.owner(path) != null) return;
        switch (source.*) {
            .object => |properties| {
                if (properties.len == 0) return invalid();
                for (properties) |property| {
                    const child = try self.extend(path, property.name);
                    if (!property.required and self.owner(child) == null) return invalid();
                    try self.cover(property.schema, child);
                }
            },
            .one_of => |variants| for (variants) |variant| try self.cover(variant, path),
            else => return invalid(),
        }
    }
    fn singleton(self: Compiler, source: *const schema.Node) Error![]const Projection {
        const result = try self.allocator.alloc(Projection, 1);
        result[0] = .{ .node = source };
        return result;
    }
    fn project(self: Compiler, source: *const schema.Node, path: Pointer, part: usize) Error![]const Projection {
        if (self.owner(path)) |producer| return if (producer == part) self.singleton(source) else &.{};
        return switch (source.*) {
            .object => |properties| self.projectObject(properties, path, part),
            .one_of => |variants| self.projectVariants(variants, path, part),
            else => invalid(),
        };
    }
    fn projectObject(self: Compiler, properties: []const schema.Property, path: Pointer, part: usize) Error![]const Projection {
        var result = try self.singleton(try self.node(.{ .object = &.{} }));
        for (properties) |property| {
            const choices = try self.project(property.schema, try self.extend(path, property.name), part);
            if (choices.len == 0) continue;
            if (result.len * choices.len > schema.max_variants) return invalid();
            var next: std.ArrayList(Projection) = .empty;
            for (result) |prior| for (choices) |choice| {
                const conditions = try self.combine(prior.conditions, choice.conditions) orelse continue;
                const fields = try self.allocator.alloc(schema.Property, prior.node.object.len + 1);
                @memcpy(fields[0..prior.node.object.len], prior.node.object);
                fields[prior.node.object.len] = .{ .name = property.name, .required = property.required, .schema = choice.node };
                try next.append(self.allocator, .{ .node = try self.node(.{ .object = fields }), .conditions = conditions });
            };
            result = try next.toOwnedSlice(self.allocator);
        }
        if (result.len == 0 or result[0].node.object.len == 0) return &.{};
        return result;
    }
    fn projectVariants(self: Compiler, variants: []const *const schema.Node, path: Pointer, part: usize) Error![]const Projection {
        const discriminator = try self.extend(path, "kind");
        const producer = self.owner(discriminator) orelse return invalid();
        const groups = try self.allocator.alloc([]const Projection, variants.len);
        for (variants, groups) |variant, *group| {
            group.* = try self.project(variant, path, part);
        }
        var empty: usize = 0;
        for (groups) |group| if (group.len == 0) {
            empty += 1;
        };
        if (empty == groups.len) return &.{};
        if (empty != 0) return invalid(); // No implicit absent-part transition.
        var identical = true;
        for (groups[1..]) |group| if (!try self.equalProjections(groups[0], group)) {
            identical = false;
            break;
        };
        if (identical) return groups[0];
        if (producer == part) {
            // Retain a tagged union when this response supplies its discriminator.
            const choices = try self.allocator.alloc(*const schema.Node, variants.len);
            for (groups, choices) |group, *choice| {
                if (group.len != 1 or group[0].conditions.len != 0) return invalid();
                choice.* = group[0].node;
            }
            return self.singleton(try self.node(.{ .one_of = choices }));
        }
        if (!depends(self.parts, part, producer)) return invalid();
        var result: std.ArrayList(Projection) = .empty;
        for (variants, groups) |variant, group| {
            const kind = schema.findProperty(variant.object, "kind").?.schema.constant.string;
            for (group) |projection| {
                if (result.items.len == schema.max_variants) return invalid();
                const conditions = try self.combine(projection.conditions, &.{.{ .producer = producer, .path = discriminator, .value = kind }}) orelse continue;
                try result.append(self.allocator, .{ .node = projection.node, .conditions = conditions });
            }
        }
        return result.toOwnedSlice(self.allocator);
    }
    fn equalProjections(self: Compiler, left: []const Projection, right: []const Projection) Error!bool {
        if (left.len != right.len) return false;
        for (left, right) |a, b| {
            if (a.conditions.len != b.conditions.len) return false;
            for (a.conditions, b.conditions) |x, y| if (!sameCondition(x, y)) return false;
            const x = try std.json.Stringify.valueAlloc(self.allocator, try @import("model_schema_projection.zig").value(self.allocator, a.node, .complete), .{});
            const y = try std.json.Stringify.valueAlloc(self.allocator, try @import("model_schema_projection.zig").value(self.allocator, b.node, .complete), .{});
            if (!std.mem.eql(u8, x, y)) return false;
        }
        return true;
    }
    fn combine(self: Compiler, left: []const Condition, right: []const Condition) Error!?[]const Condition {
        var result: std.ArrayList(Condition) = .empty;
        try result.appendSlice(self.allocator, left);
        for (right) |condition| {
            var exists = false;
            for (result.items) |prior| {
                if (prior.producer != condition.producer or !samePath(prior.path, condition.path)) continue;
                if (!std.mem.eql(u8, prior.value, condition.value)) return null;
                exists = true;
            }
            if (!exists) try result.append(self.allocator, condition);
        }
        return try result.toOwnedSlice(self.allocator);
    }
};

fn resolves(node: *const schema.Node, segments: []const []const u8) Error!bool {
    if (segments.len == 0) return true;
    return switch (node.*) {
        .object => |properties| blk: {
            const property = schema.findProperty(properties, segments[0]) orelse break :blk false;
            if (segments.len > 1 and !property.required) return invalid();
            break :blk try resolves(property.schema, segments[1..]);
        },
        .one_of => |variants| blk: {
            var present = false;
            for (variants) |variant| present = try resolves(variant, segments) or present;
            break :blk present;
        },
        else => invalid(),
    };
}
fn findPart(parts: []const Part, name: []const u8) ?usize {
    for (parts, 0..) |part, index| if (std.mem.eql(u8, name, part.id.bytes)) return index;
    return null;
}
fn visit(parts: []const Part, index: usize, visiting: []bool, visited: []bool) Error!void {
    if (visiting[index]) return invalid();
    if (visited[index]) return;
    visiting[index] = true;
    for (parts[index].requires) |required| try visit(parts, required, visiting, visited);
    visiting[index] = false;
    visited[index] = true;
}
fn depends(parts: []const Part, index: usize, required: usize) bool {
    var seen = [_]bool{false} ** schema.max_properties;
    var pending: [schema.max_properties]usize = undefined;
    var count: usize = 1;
    pending[0] = index;
    seen[index] = true;
    while (count != 0) {
        count -= 1;
        const current = pending[count];
        for (parts[current].requires) |dependency| {
            if (dependency == required) return true;
            if (seen[dependency]) continue;
            seen[dependency] = true;
            pending[count] = dependency;
            count += 1;
        }
    }
    return false;
}
fn findInput(inputs: []const PartValue, index: usize) ?std.json.Value {
    for (inputs) |input| if (input.part == index) return input.value;
    return null;
}
pub fn lookup(value: std.json.Value, path: Pointer) ?std.json.Value {
    return pointer.lookup(value, path);
}
fn samePath(left: Pointer, right: Pointer) bool {
    return left.segments.len == right.segments.len and left.isPrefixOf(right);
}
fn sameCondition(left: Condition, right: Condition) bool {
    return left.producer == right.producer and samePath(left.path, right.path) and std.mem.eql(u8, left.value, right.value);
}
fn invalid() error{InvalidJsonComposition} {
    return error.InvalidJsonComposition;
}
