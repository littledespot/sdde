const std = @import("std");
const debug = @import("../domain/request_debugger.zig");
pub const Error = std.mem.Allocator.Error || error{ InvalidReplay, ReplayUnauthorized, ReplayStorageFailure, ReplayProviderFailure };
pub const Context = opaque {};
pub const Provider = struct {
    context: *Context,
    prepare_fn: *const fn (*Context, std.mem.Allocator, debug.Description) Error![]const u8,
    send_fn: *const fn (*Context, std.mem.Allocator, debug.RequestRecord) Error!debug.ResponseRecord,
    inspect_fn: *const fn (*Context, std.mem.Allocator, debug.Description, []const u8) Error!debug.Validation,

    pub fn prepare(self: Provider, a: std.mem.Allocator, description: debug.Description) Error![]const u8 {
        return self.prepare_fn(self.context, a, description);
    }
    pub fn send(self: Provider, a: std.mem.Allocator, request: debug.RequestRecord) Error!debug.ResponseRecord {
        return self.send_fn(self.context, a, request);
    }
    pub fn inspect(self: Provider, a: std.mem.Allocator, description: debug.Description, body: []const u8) Error!debug.Validation {
        return self.inspect_fn(self.context, a, description, body);
    }
};
pub const Store = struct {
    context: *Context,
    request_fn: *const fn (*Context, std.mem.Allocator, debug.RequestRecord) Error!void,
    response_fn: *const fn (*Context, std.mem.Allocator, debug.ResponseRecord) Error!void,
    pub fn request(self: Store, a: std.mem.Allocator, value: debug.RequestRecord) Error!void {
        return self.request_fn(self.context, a, value);
    }
    pub fn response(self: Store, a: std.mem.Allocator, value: debug.ResponseRecord) Error!void {
        return self.response_fn(self.context, a, value);
    }
};
