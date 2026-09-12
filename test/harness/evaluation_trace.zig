//! Capture real evaluator exchanges before validation can discard their payload.
const std = @import("std");
const provider = @import("provider.zig");
const evidence = @import("evidence.zig");

pub const Trace = struct {
    store: evidence.Store,
    inner: provider.Port,
    calls: usize = 0,
    failure: ?anyerror = null,

    pub fn port(self: *Trace) provider.Port {
        return .{ .context = @ptrCast(self), .invoke_fn = invoke };
    }
    fn invoke(context: *provider.Context, a: std.mem.Allocator, body: []const u8, timeout_ms: u32) provider.Error!provider.Observation {
        const self: *Trace = @ptrCast(@alignCast(context));
        if (self.failure != null) return error.Cancelled;
        self.calls += 1;
        self.store.write(.evaluation, self.calls, .request, body) catch |err| {
            self.failure = err;
            return error.Cancelled;
        };
        const result = self.inner.invoke(a, body, timeout_ms) catch |err| {
            self.saveError(err) catch |failure| {
                self.failure = failure;
            };
            return err;
        };
        self.save(result) catch |err| {
            self.failure = err;
        };
        return result;
    }
    fn saveError(self: *Trace, failure: provider.Error) !void {
        const bytes = try std.json.Stringify.valueAlloc(self.store.allocator, .{ .error_name = @errorName(failure) }, .{});
        defer self.store.allocator.free(bytes);
        try self.store.write(.evaluation, self.calls, .outcome, bytes);
    }
    fn save(self: *Trace, result: provider.Observation) !void {
        if (result.response_body) |bytes| try self.store.write(.evaluation, self.calls, .response, bytes);
        if (result.payload) |bytes| try self.store.write(.evaluation, self.calls, .model_output, bytes);
        const bytes = try std.json.Stringify.valueAlloc(self.store.allocator, .{
            .identity = result.identity,
            .request_id = result.request_id,
            .usage = result.usage,
            .failure = result.failure,
        }, .{});
        defer self.store.allocator.free(bytes);
        try self.store.write(.evaluation, self.calls, .outcome, bytes);
    }
};
