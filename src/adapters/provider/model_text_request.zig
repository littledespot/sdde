//! The one model-visible text layout every provider encoder and replay use
//! (ADR 0028): system and guidance parts in order, then the response-format
//! guidance and the schema guidance exactly once, then the user and evidence
//! parts in order. Encoders own only their wire shapes.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const controls = @import("../../domain/model_controls.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidRequest};

pub const ReasoningEffort = enum { low, medium, high, xhigh, max };

pub fn reasoningEffort(value: ?[]const u8) error{InvalidRequest}!?ReasoningEffort {
    const selected = value orelse return null;
    return std.meta.stringToEnum(ReasoningEffort, selected) orelse error.InvalidRequest;
}

pub const TextSchema = union(enum) {
    prompt_only: []const u8,
    native: struct { guidance: []const u8, structure: []const u8 },

    pub fn guidance(self: TextSchema) []const u8 {
        return switch (self) {
            .prompt_only => |bytes| bytes,
            .native => |native| native.guidance,
        };
    }
};

/// The request's schema guidance, with the shared native grammar projection
/// in native mode. Release with `freeSchema`.
pub fn schemaFor(allocator: std.mem.Allocator, request: *const operation.IdentifiedProviderNeutralModelRequest) std.mem.Allocator.Error!TextSchema {
    return switch (request.response_guidance_mode) {
        .prompt_only => .{ .prompt_only = request.response_schema.modelBytes() },
        .native_schema => .{ .native = .{
            .guidance = request.response_schema.modelBytes(),
            .structure = try @import("../../domain/model_schema_projection.zig").render(allocator, request.response_schema, .native),
        } },
    };
}

pub fn freeSchema(allocator: std.mem.Allocator, schema: TextSchema) void {
    if (schema == .native) allocator.free(schema.native.structure);
}

/// A native structure must be one JSON object, whichever provider sends it.
pub fn validateStructure(allocator: std.mem.Allocator, schema: TextSchema) Error!void {
    if (schema != .native) return;
    var projected = @import("../../domain/strict_json.zig").parse(allocator, schema.native.structure, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequest;
    defer projected.deinit();
    if (projected.value != .object) return error.InvalidRequest;
}

/// Borrowed, ordered text. The engine never invents, trims, merges or reorders
/// a part; a request with no user or evidence part is invalid.
pub const Layout = struct {
    system: []const []const u8,
    user: []const []const u8,

    pub fn deinit(self: Layout, allocator: std.mem.Allocator) void {
        allocator.free(self.system);
        allocator.free(self.user);
    }
};

pub fn layout(allocator: std.mem.Allocator, content: []const operation.ModelVisibleContent, schema: TextSchema) Error!Layout {
    var system: std.ArrayList([]const u8) = .empty;
    defer system.deinit(allocator);
    var user: std.ArrayList([]const u8) = .empty;
    defer user.deinit(allocator);
    for (content) |part| switch (part) {
        .system, .guidance => |text| try system.append(allocator, text),
        .user, .evidence => |text| try user.append(allocator, text),
    };
    if (user.items.len == 0) return error.InvalidRequest;
    try system.append(allocator, controls.response_format_guidance);
    try system.append(allocator, schema.guidance());
    const system_parts = try system.toOwnedSlice(allocator);
    errdefer allocator.free(system_parts);
    return .{ .system = system_parts, .user = try user.toOwnedSlice(allocator) };
}

test "layout keeps relative order and appends guidance exactly once" {
    const a = std.testing.allocator;
    const content = [_]operation.ModelVisibleContent{ .{ .user = "u1" }, .{ .system = "s1" }, .{ .evidence = "e1" }, .{ .guidance = "g1" } };
    const value = try layout(a, &content, .{ .prompt_only = "schema" });
    defer value.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), value.system.len);
    try std.testing.expectEqualStrings("s1", value.system[0]);
    try std.testing.expectEqualStrings("g1", value.system[1]);
    try std.testing.expectEqualStrings(controls.response_format_guidance, value.system[2]);
    try std.testing.expectEqualStrings("schema", value.system[3]);
    try std.testing.expectEqual(@as(usize, 2), value.user.len);
    try std.testing.expectEqualStrings("u1", value.user[0]);
    try std.testing.expectEqualStrings("e1", value.user[1]);
    try std.testing.expectError(error.InvalidRequest, layout(a, &.{.{ .system = "only system" }}, .{ .prompt_only = "schema" }));
}

test "native structure must be one JSON object" {
    try validateStructure(std.testing.allocator, .{ .native = .{ .guidance = "{}", .structure = "{\"type\":\"object\"}" } });
    try std.testing.expectError(error.InvalidRequest, validateStructure(std.testing.allocator, .{ .native = .{ .guidance = "{}", .structure = "[]" } }));
    try std.testing.expectError(error.InvalidRequest, validateStructure(std.testing.allocator, .{ .native = .{ .guidance = "{}", .structure = "{" } }));
    try validateStructure(std.testing.allocator, .{ .prompt_only = "not checked" });
}
