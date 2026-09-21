const std = @import("std");
const invocation = @import("provider_invocation_validation.zig");
const schema = @import("model_result_schema.zig");
const json = @import("strict_json.zig");

pub const Rejection = error{InvalidModelEnvelope};
pub const Error = Rejection || std.mem.Allocator.Error;
pub const Diagnostic = json.Diagnostic;

pub const Normalization = enum {
    none,
    removed_leading_brace_quote,
};

/// One model-response syntax boundary, also used by diagnostic inspection.
/// Content borrows the original response; the tree owns all decoded values.
pub const Document = struct {
    content: []const u8,
    parsed: std.json.Parsed(std.json.Value),
    normalization: Normalization = .none,

    pub fn deinit(self: *Document) void {
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub fn parseContent(allocator: std.mem.Allocator, content: []const u8, diagnostic: ?*?Diagnostic) Error!Document {
    if (diagnostic) |out| out.* = null;
    var original: ?Diagnostic = null;
    defer if (original) |failure| failure.deinit(allocator);
    var normalized: Normalization = .none;
    const parsed = json.parse(allocator, content, .{ .maximum_depth = schema.max_json_depth }, false, &original) catch |err| recovered: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // Approved §22.6 exception: only this exact prefix, after syntax failure,
        // and only once. Valid property names beginning with '{' remain intact.
        if (original.?.reason == .SyntaxError and std.mem.startsWith(u8, content, "{\"{")) {
            if (json.parse(allocator, content[2..], .{ .maximum_depth = schema.max_json_depth }, false, null)) |result| {
                normalized = .removed_leading_brace_quote;
                break :recovered result;
            } else |failure| if (failure == error.OutOfMemory) return error.OutOfMemory;
        }
        // Rejected evidence still refers to the original captured bytes.
        if (diagnostic) |out| {
            out.* = original;
            original = null;
        }
        return error.InvalidModelEnvelope;
    };
    if (parsed.value != .object) {
        parsed.deinit();
        if (diagnostic) |out| out.* = .{ .reason = .ExpectedObject };
        return error.InvalidModelEnvelope;
    }
    return .{ .content = if (normalized == .none) content else content[2..], .parsed = parsed, .normalization = normalized };
}

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

    /// Borrow the decoder-owned tree for deterministic structural composition.
    pub fn json(self: *const Candidate) *const std.json.Value {
        return &storage(self).parsed.value;
    }

    pub fn normalization(self: *const Candidate) Normalization {
        return storage(self).normalization;
    }

    /// Exact bytes consumed by this decoder. The association retains raw bytes.
    pub fn content(self: *const Candidate) []const u8 {
        return storage(self).content;
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
    normalization: Normalization,
    content: []const u8,
};

pub fn decode(allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate, diagnostic: ?*?Diagnostic) Error!Owned {
    const association = complete.association();
    var document = try parseContent(allocator, complete.content(), diagnostic);
    errdefer document.deinit();
    const state = try allocator.create(Storage);
    state.* = .{ .association = association, .parsed = document.parsed, .normalization = document.normalization, .content = document.content };
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

pub fn value(raw: *const std.json.Value) Value {
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
