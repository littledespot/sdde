//! Anthropic Messages API endpoint projection (ADR 0028): fixed URL and API
//! version, key header and the response headers the shared exchange retains.
//! No connection, capture or beta header.
const std = @import("std");
const transport = @import("model_http_transport.zig");

pub const url = "https://api.anthropic.com/v1/messages";
pub const api_version = "2023-06-01";

/// The key is borrowed from the consumed capability for this one exchange.
pub fn project(allocator: std.mem.Allocator, api_key: []const u8) std.mem.Allocator.Error!transport.Projection {
    const headers = try allocator.alloc(std.http.Header, 2);
    headers[0] = .{ .name = "x-api-key", .value = api_key };
    headers[1] = .{ .name = "anthropic-version", .value = api_version };
    return .{ .url = url, .extra_headers = headers };
}

pub fn retained(name: []const u8) ?transport.RetainedHeader {
    if (std.ascii.eqlIgnoreCase(name, "request-id")) return .request_id;
    if (std.ascii.eqlIgnoreCase(name, "retry-after")) return .retry_after;
    return null;
}
