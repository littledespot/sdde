//! Closed-field and scalar readers with path diagnostics, shared by every
//! provider decoder. Each decoder still decides which fields its API allows,
//! requires or permits as null.
const std = @import("std");
const json_pointer = @import("../../domain/json_pointer.zig");

pub const Invalid = error{InvalidResponse};

/// Diagnostic paths are owned; release before reusing the output slot.
pub const DecodeDiagnostic = struct {
    reason: enum { invalid_response, expected_object, unknown_field },
    path: []const u8,

    pub fn deinit(self: DecodeDiagnostic, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }

    pub fn explanation(self: DecodeDiagnostic) []const u8 {
        return switch (self.reason) {
            .invalid_response => "Invalid provider response",
            .expected_object => "Expected provider response object",
            .unknown_field => "Unknown provider response field",
        };
    }

    /// Record a generic rejection when the decoder found no precise path.
    pub fn fallback(allocator: std.mem.Allocator, diagnostic: ?*?DecodeDiagnostic) std.mem.Allocator.Error!void {
        if (diagnostic) |out| {
            if (out.* == null) out.* = .{ .reason = .invalid_response, .path = try allocator.dupe(u8, "") };
        }
    }
};

const FieldRejection = union(enum) { expected_object, unknown_field: []const u8 };

pub fn fields(raw: std.json.Value, allowed: []const []const u8) Invalid!void {
    return checkFields(raw, allowed, null);
}

fn checkFields(raw: std.json.Value, allowed: []const []const u8, diagnostic: ?*?FieldRejection) Invalid!void {
    if (diagnostic) |out| out.* = null;
    if (raw != .object) {
        if (diagnostic) |out| out.* = .expected_object;
        return error.InvalidResponse;
    }
    for (raw.object.keys()) |key| {
        for (allowed) |name| if (std.mem.eql(u8, key, name)) break else {} else {
            if (diagnostic) |out| out.* = .{ .unknown_field = key };
            return error.InvalidResponse;
        }
    }
}

pub fn diagnosedFields(allocator: std.mem.Allocator, raw: std.json.Value, allowed: []const []const u8, path: []const json_pointer.Segment, diagnostic: ?*?DecodeDiagnostic) (Invalid || std.mem.Allocator.Error)!void {
    var rejection: ?FieldRejection = null;
    checkFields(raw, allowed, &rejection) catch {
        if (diagnostic) |out| {
            var segments: std.ArrayList(json_pointer.Segment) = .empty;
            defer segments.deinit(allocator);
            try segments.appendSlice(allocator, path);
            switch (rejection.?) {
                .expected_object => {},
                .unknown_field => |key| try segments.append(allocator, .{ .property = key }),
            }
            out.* = .{
                .reason = switch (rejection.?) {
                    .expected_object => .expected_object,
                    .unknown_field => .unknown_field,
                },
                .path = try json_pointer.render(allocator, segments.items),
            };
        }
        return error.InvalidResponse;
    };
}

/// Every listed field must be present, even when its value may be null.
pub fn required(raw: std.json.Value, names: []const []const u8) Invalid!void {
    for (names) |name| _ = try field(raw, name);
}

pub fn field(raw: std.json.Value, name: []const u8) Invalid!std.json.Value {
    if (raw != .object) return error.InvalidResponse;
    return raw.object.get(name) orelse error.InvalidResponse;
}

pub fn string(raw: std.json.Value) Invalid![]const u8 {
    return if (raw == .string) raw.string else error.InvalidResponse;
}

pub fn integer(raw: std.json.Value) Invalid!u64 {
    if (raw != .number_string or raw.number_string.len == 0) return error.InvalidResponse;
    for (raw.number_string) |byte| if (byte < '0' or byte > '9') return error.InvalidResponse;
    return std.fmt.parseInt(u64, raw.number_string, 10) catch error.InvalidResponse;
}

/// A non-negative integer or null; null counts as zero.
pub fn optionalInteger(raw: std.json.Value) Invalid!u64 {
    return if (raw == .null) 0 else integer(raw);
}

pub fn enumeration(raw: std.json.Value, allowed: []const []const u8) Invalid!void {
    const value = try string(raw);
    for (allowed) |name| if (std.mem.eql(u8, value, name)) return;
    return error.InvalidResponse;
}

/// Strict syntax, UTF-8 and duplicate-key rejection for a provider body.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) @import("../../domain/strict_json.zig").Error!std.json.Parsed(std.json.Value) {
    return @import("../../domain/strict_json.zig").parse(allocator, bytes, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
}
