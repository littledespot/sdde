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
    removed_repeated_field_prefix,
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
    var prefix: ?OpeningPrefix = null;
    const parsed = json.parse(allocator, content, .{ .maximum_depth = schema.max_json_depth }, false, &original) catch |err| recovered: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // Approved §22.6 exception: one opening artifact after syntax failure.
        // The complete remainder still passes the same strict JSON parser.
        if (original.?.reason == .SyntaxError) if (parseOpeningPrefix(content)) |opening| {
            if (json.parse(allocator, content[opening.length..], .{ .maximum_depth = schema.max_json_depth }, false, null)) |result| {
                prefix = opening;
                break :recovered result;
            } else |failure| if (failure == error.OutOfMemory) return error.OutOfMemory;
        };
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
    return .{ .content = if (prefix) |opening| content[opening.length..] else content, .parsed = parsed, .normalization = if (prefix) |opening| opening.normalization else .none };
}

const OpeningPrefix = struct { length: usize, normalization: Normalization };

/// Recognize an unfinished object/member opener, never search for JSON inside
/// arbitrary text. A nonempty member name must repeat the object's first key.
fn parseOpeningPrefix(content: []const u8) ?OpeningPrefix {
    if (!std.mem.startsWith(u8, content, "{\"")) return null;
    var end: usize = 2;
    while (end < content.len and content[end] != '{') : (end += 1) {
        if (content[end] < 0x20 or content[end] == '"' or content[end] == '\\') return null;
    }
    if (end == content.len) return null;
    if (end == 2) return .{ .length = end, .normalization = .removed_leading_brace_quote };
    const name = content[2..end];
    if (!std.unicode.utf8ValidateSlice(name)) return null;
    const first_key = std.mem.trimStart(u8, content[end + 1 ..], " \t\r\n");
    if (first_key.len == 0 or first_key[0] != '"' or !std.mem.startsWith(u8, first_key[1..], name)) return null;
    const after_name = first_key[1 + name.len ..];
    if (after_name.len == 0 or after_name[0] != '"') return null;
    const after_key = std.mem.trimStart(u8, after_name[1..], " \t\r\n");
    if (after_key.len == 0 or after_key[0] != ':') return null;
    return .{ .length = end, .normalization = .removed_repeated_field_prefix };
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
