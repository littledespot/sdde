const std = @import("std");

// Engine-selected profile; never an additional model-visible envelope field.
pub const profile = "model-result-schema/v1";
pub const max_bytes = @import("workflow_definition.zig").max_resource_bytes;
pub const max_json_depth = 64;
pub const max_depth = 16;
pub const max_nodes = 4096;
pub const max_properties = 256;
pub const max_choices = 256;
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

pub const Node = union(enum) {
    object: []const Property,
    string: struct { minimum: u32, maximum: u32 },
    integer: struct { minimum: i64, maximum: i64 },
    boolean,
    null_value,
    constant: Scalar,
    enumeration: []const []const u8,
    array: struct { minimum: u32, maximum: u32, items: *const Node },
    one_of: []const *const Node,
};

// Syntax/semantic compilation is the only producer. Consumers cannot construct
// a result-schema resource from a raw byte slice or a nominal schema ID.
pub const Schema = opaque {
    pub fn root(self: *const Schema) *const Node {
        return &storage(self).root;
    }

    pub fn bytes(self: *const Schema) []const u8 {
        return storage(self).bytes;
    }

    pub fn modelBytes(self: *const Schema) []const u8 {
        return storage(self).model_bytes;
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
const Storage = struct { bytes: []const u8, model_bytes: []const u8, root: Node, definitions: []const Definition = &.{} };

fn cloneSchema(allocator: std.mem.Allocator, source: *const Schema, bytes: []const u8) std.mem.Allocator.Error!*const Schema {
    const copy = try allocator.create(Storage);
    const definitions = try allocator.alloc(Definition, storage(source).definitions.len);
    for (storage(source).definitions, definitions) |entry, *destination| {
        destination.* = .{
            .id = .{ .bytes = try allocator.dupe(u8, entry.id.bytes) },
            .result = if (entry.result) |value| try cloneSchema(allocator, value, bytes) else null,
        };
    }
    copy.* = .{ .bytes = bytes, .model_bytes = try allocator.dupe(u8, source.modelBytes()), .root = try cloneNode(allocator, source.root().*), .definitions = definitions };
    return @ptrCast(copy);
}

fn storage(value: *const Schema) *const Storage {
    return @ptrCast(@alignCast(value));
}

// The narrow syntax adapter supplies the complete decoded document and its
// exact source bytes. All output allocations belong to the caller's arena;
// that arena must be discarded on rejection/allocation failure.
pub fn compile(allocator: std.mem.Allocator, raw: std.json.Value, bytes: []const u8) Error!*const Schema {
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
    var iterator = compiler.definitions.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        const id = DefinitionId.parse(entry.key_ptr.*) orelse return invalid();
        compiler.node_count = 0;
        const node = try compiler.reference(id, 1);
        definitions[index] = .{
            .id = .{ .bytes = try allocator.dupe(u8, id.bytes) },
            .result = if (isResult(node)) try createSchema(allocator, node, captured, &.{}) else null,
        };
    }
    // The existing expansion bound applies independently to the selected root.
    compiler.node_count = 0;
    const root = try compiler.node(root_value, 1);
    if (!isResult(root)) return invalid();
    return createSchema(allocator, root, captured, definitions);
}

fn isResult(root: *const Node) bool {
    return switch (root.*) {
        .object => |properties| {
            if (findProperty(properties, "kind")) |property| switch (property.schema.*) {
                .constant => return false,
                .enumeration => |values| if (values.len == 1) return false,
                else => {},
            };
            return true;
        },
        .one_of => true,
        else => false,
    };
}

fn createSchema(allocator: std.mem.Allocator, root: *const Node, bytes: []const u8, definitions: []const Definition) Error!*const Schema {
    const result = try allocator.create(Storage);
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const model_bytes = try std.json.Stringify.valueAlloc(allocator, try @import("model_schema_projection.zig").value(scratch.allocator(), root, .complete), .{});
    result.* = .{ .bytes = bytes, .model_bytes = model_bytes, .root = root.*, .definitions = definitions };
    return @ptrCast(result);
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
                const kind = try variantKind(choice.*);
                for (choices[0..index]) |prior| if (std.mem.eql(u8, kind, try variantKind(prior))) return invalid();
            }
            result.* = .{ .one_of = choices };
        } else if (object.get("const")) |value| {
            try fields(object, &.{"const"});
            result.* = .{ .constant = try self.scalar(value) };
        } else if (object.get("enum")) |values| {
            try fields(object, &.{"enum"});
            if (values != .array or values.array.items.len == 0 or values.array.items.len > max_choices) return invalid();
            const choices = try self.allocator.alloc([]const u8, values.array.items.len);
            for (values.array.items, choices, 0..) |value, *choice, index| {
                if (value != .string) return invalid();
                for (choices[0..index]) |prior| if (std.mem.eql(u8, prior, value.string)) return invalid();
                choice.* = try self.copyString(value.string);
            }
            result.* = .{ .enumeration = choices };
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

fn variantKind(node: *const Node) Error![]const u8 {
    if (node.* != .object) return invalid();
    const property = findProperty(node.object, "kind") orelse return invalid();
    if (!property.required or property.schema.* != .constant or property.schema.constant != .string or
        property.schema.constant.string.len == 0) return invalid();
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
        .array => |array| .{ .array = .{ .minimum = array.minimum, .maximum = array.maximum, .items = try cloneChild(allocator, array.items) } },
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
