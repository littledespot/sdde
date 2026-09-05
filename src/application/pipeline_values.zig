const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution_reference = @import("../domain/execution_reference.zig");

pub const Error = std.mem.Allocator.Error || error{
    InvalidDataSchema,
    DataSchemaMismatch,
    DataValueLimitExceeded,
    MissingRequiredData,
};

const Owned = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    schema: data.Schema,
    payload: *const anyopaque,
    retained_refs: ?*RetainedReference = null,
    native_owner: ?NativeOwner = null,
};

const NativeOwner = struct {
    context: *anyopaque,
    destroy_fn: *const fn (*anyopaque) void,
};

const RetainedReference = struct {
    reference: execution_reference.Ref,
    next: ?*RetainedReference,
};

pub fn schema(comptime key: pipeline.DataKey, comptime T: type, version: u32, maximum_bytes: u32) data.Schema {
    return .{ .key = key, .version = version, .maximum_bytes = maximum_bytes, .type_name = @typeName(T) };
}

/// Copies an immutable native value into an independently owned allocation.
/// Borrowed input slices can never escape into the accumulated workflow data.
/// Execution-reference identities are retained, never dereferenced or cloned.
pub fn create(allocator: std.mem.Allocator, descriptor: data.Schema, comptime T: type, value: T) Error!*data.Value {
    if (!descriptor.valid()) return error.InvalidDataSchema;
    if (!std.mem.eql(u8, descriptor.type_name, @typeName(T))) return error.DataSchemaMismatch;
    var budget: Budget = .{ .remaining = descriptor.maximum_bytes };
    try budget.consume(@sizeOf(T));
    const owner = try allocator.create(Owned);
    errdefer allocator.destroy(owner);
    var canonical_schema = descriptor;
    canonical_schema.type_name = @typeName(T);
    owner.* = .{ .allocator = allocator, .arena = .init(allocator), .schema = canonical_schema, .payload = undefined };
    errdefer owner.arena.deinit();
    errdefer releaseReferences(owner);
    const payload = try owner.arena.allocator().create(T);
    payload.* = try clone(T, value, owner, &budget);
    owner.payload = @ptrCast(payload);
    return @ptrCast(owner);
}

pub fn valueSchema(value: *const data.Value) data.Schema {
    return owned(value).schema;
}

/// Transfers an independently owned, sealed immutable native result on success.
/// Native bindings supply its typed owner, accessor, destructor and retained
/// byte count. Neither workflow data nor model output can supply these hooks.
pub fn adopt(
    allocator: std.mem.Allocator,
    descriptor: data.Schema,
    comptime T: type,
    comptime Owner: type,
    owner: *Owner,
    comptime get: *const fn (*const Owner) *const T,
    comptime destroy_owner: *const fn (*Owner) void,
    retained_bytes: usize,
) Error!*data.Value {
    if (@typeInfo(T) != .@"opaque") @compileError("ordinary pipeline data must use the immutable copying constructor");
    if (!descriptor.valid()) return error.InvalidDataSchema;
    if (!std.mem.eql(u8, descriptor.type_name, @typeName(T))) return error.DataSchemaMismatch;
    if (retained_bytes == 0 or retained_bytes > descriptor.maximum_bytes) return error.DataValueLimitExceeded;
    const finalizer = struct {
        fn destroy(context: *anyopaque) void {
            destroy_owner(@ptrCast(@alignCast(context)));
        }
    };
    const storage = try allocator.create(Owned);
    var canonical_schema = descriptor;
    canonical_schema.type_name = @typeName(T);
    storage.* = .{
        .allocator = allocator,
        .arena = .init(allocator),
        .schema = canonical_schema,
        .payload = get(owner),
        .native_owner = .{ .context = @ptrCast(owner), .destroy_fn = finalizer.destroy },
    };
    return @ptrCast(storage);
}

pub fn read(view: *const data.View, expected: data.Schema, comptime T: type) Error!*const T {
    if (!expected.valid()) return error.InvalidDataSchema;
    const value = view.slots[@intFromEnum(expected.key)] orelse return error.MissingRequiredData;
    const owner = owned(value);
    if (!owner.schema.eql(expected) or !std.mem.eql(u8, owner.schema.type_name, @typeName(T))) {
        return error.DataSchemaMismatch;
    }
    return @ptrCast(@alignCast(owner.payload));
}

pub fn destroy(value: *data.Value) void {
    const owner: *Owned = @ptrCast(@alignCast(value));
    const allocator = owner.allocator;
    releaseReferences(owner);
    if (owner.native_owner) |native| native.destroy_fn(native.context);
    owner.arena.deinit();
    allocator.destroy(owner);
}

fn owned(value: *const data.Value) *const Owned {
    return @ptrCast(@alignCast(value));
}

const Budget = struct {
    remaining: usize,

    fn consume(self: *Budget, bytes: usize) Error!void {
        if (bytes > self.remaining) return error.DataValueLimitExceeded;
        self.remaining -= bytes;
    }
};

fn releaseReferences(owner: *Owned) void {
    var next = owner.retained_refs;
    while (next) |entry| : (next = entry.next) entry.reference.release();
    owner.retained_refs = null;
}

fn clone(comptime T: type, source: T, owner: *Owned, budget: *Budget) Error!T {
    const allocator = owner.arena.allocator();
    if (T == execution_reference.Ref) {
        try budget.consume(@sizeOf(RetainedReference));
        const retained = try allocator.create(RetainedReference);
        retained.* = .{ .reference = source.retain(), .next = owner.retained_refs };
        owner.retained_refs = retained;
        return retained.reference;
    }
    return switch (@typeInfo(T)) {
        .void, .bool, .int, .float, .@"enum" => source,
        .optional => |info| if (source) |value| try clone(info.child, value, owner, budget) else null,
        .array => |info| result: {
            var result: T = undefined;
            for (source, 0..) |value, index| result[index] = try clone(info.child, value, owner, budget);
            break :result result;
        },
        .@"struct" => |info| result: {
            var result: T = undefined;
            inline for (info.fields) |field| {
                if (!field.is_comptime) @field(result, field.name) = try clone(field.type, @field(source, field.name), owner, budget);
            }
            break :result result;
        },
        .@"union" => |info| result: {
            if (info.tag_type == null) @compileError("pipeline values require tagged unions");
            switch (source) {
                inline else => |value, tag| break :result @unionInit(T, @tagName(tag), try clone(@TypeOf(value), value, owner, budget)),
            }
        },
        .pointer => |info| result: {
            if (!info.is_const or info.is_volatile or info.is_allowzero or info.sentinel_ptr != null) {
                @compileError("pipeline values permit only immutable nonsentinel pointers and slices");
            }
            switch (info.size) {
                .slice => {
                    const bytes = std.math.mul(usize, @max(1, @sizeOf(info.child)), source.len) catch return error.DataValueLimitExceeded;
                    try budget.consume(bytes);
                    const result = try allocator.alloc(info.child, source.len);
                    for (source, 0..) |value, index| result[index] = try clone(info.child, value, owner, budget);
                    break :result result;
                },
                .one => {
                    try budget.consume(@max(1, @sizeOf(info.child)));
                    const result = try allocator.create(info.child);
                    result.* = try clone(info.child, source.*, owner, budget);
                    break :result result;
                },
                else => @compileError("pipeline values cannot contain unbounded pointers"),
            }
        },
        else => @compileError("pipeline values must be closed immutable native data, without capabilities or erased pointers"),
    };
}
