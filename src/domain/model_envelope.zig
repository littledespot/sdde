const std = @import("std");
const invocation = @import("provider_invocation_validation.zig");
const schema = @import("model_result_schema.zig");
const json = @import("strict_json.zig");

pub const Error = error{InvalidModelEnvelope} || std.mem.Allocator.Error;

/// Read-only views of the one parsed tree. Numbers retain their exact JSON
/// lexemes: decoding neither rounds them nor decides schema type/range validity.
pub const Value = union(enum) {
    null_value,
    boolean: bool,
    number: []const u8,
    string: []const u8,
    array: *const Array,
    object: *const Object,
};

pub const Member = struct { name: []const u8, value: Value };

pub const Object = opaque {
    pub fn count(self: *const Object) usize {
        return object(self).count();
    }

    pub fn get(self: *const Object, name: []const u8) ?Value {
        const map = object(self);
        const index = map.getIndex(name) orelse return null;
        return value(&map.values()[index]);
    }

    pub fn at(self: *const Object, index: usize) ?Member {
        const map = object(self);
        if (index >= map.count()) return null;
        return .{ .name = map.keys()[index], .value = value(&map.values()[index]) };
    }
};

pub const Array = opaque {
    pub fn count(self: *const Array) usize {
        return array(self).items.len;
    }

    pub fn at(self: *const Array, index: usize) ?Value {
        const items = array(self).items;
        if (index >= items.len) return null;
        return value(&items[index]);
    }
};

/// Decoder-produced syntax evidence only, never schema validity or authority
/// to execute, repair or commit. Correlation stays in the original evidence.
pub const Candidate = opaque {
    pub fn association(self: *const Candidate) *const invocation.Evidence {
        return storage(self).association;
    }

    pub fn root(self: *const Candidate) *const Object {
        return @ptrCast(&storage(self).parsed.value.object);
    }
};

/// Owns the parsed tree, not the invocation evidence/request/graph. Those
/// immutable authorities and their owners must outlive this candidate.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    candidate: *const Candidate,

    pub fn deinit(self: *Owned) void {
        const state = storage(self.candidate);
        state.parsed.deinit();
        self.allocator.destroy(state);
        self.* = undefined;
    }
};

const Storage = struct {
    association: *const invocation.Evidence,
    parsed: std.json.Parsed(std.json.Value),
};

pub fn decode(allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate) Error!Owned {
    const association = complete.association();
    var parsed = json.parse(allocator, complete.content(), .{
        .maximum_depth = schema.max_json_depth,
    }, false) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidModelEnvelope,
    };
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelEnvelope;
    const state = try allocator.create(Storage);
    state.* = .{ .association = association, .parsed = parsed };
    return .{ .allocator = allocator, .candidate = @ptrCast(state) };
}

fn storage(candidate: *const Candidate) *const Storage {
    return @ptrCast(@alignCast(candidate));
}

fn object(view: *const Object) *const std.json.ObjectMap {
    return @ptrCast(@alignCast(view));
}

fn array(view: *const Array) *const std.json.Array {
    return @ptrCast(@alignCast(view));
}

fn value(raw: *const std.json.Value) Value {
    return switch (raw.*) {
        .null => .null_value,
        .bool => |boolean| .{ .boolean = boolean },
        .number_string => |number| .{ .number = number },
        .string => |string| .{ .string = string },
        .array => .{ .array = @ptrCast(&raw.array) },
        .object => .{ .object = @ptrCast(&raw.object) },
        // The sole producer parses with parse_numbers=false.
        .integer, .float => unreachable,
    };
}
