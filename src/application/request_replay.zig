//! One diagnostic request, at most one send, immutable parent. No workflow binding.
const std = @import("std");
const debug = @import("../domain/request_debugger.zig");
const port = @import("../ports/request_replay.zig");
pub const Result = struct { request: debug.RequestRecord, response: debug.ResponseRecord, validation: debug.Validation };
pub const Service = struct {
    provider: port.Provider,
    store: port.Store,

    pub fn replay(self: Service, allocator: std.mem.Allocator, identity: debug.ReplayIdentity, parent: debug.Call, input: debug.ReplayInput) port.Error!Result {
        if (identity.sequence == 0 or @import("../domain/telemetry.zig").Identifier.validate(identity.run.bytes) == null) return error.InvalidReplay;
        const id = identity.id;
        var description = parent.description orelse return error.InvalidReplay;
        if (description.operation_kind != .inference or !parent.request_complete) return error.InvalidReplay;
        if ((input.mode == .modified) != (input.edit != null)) return error.InvalidReplay;
        if (input.edit) |edit| {
            description.content = edit.content;
            description.schema = edit.schema;
        }
        const body = try self.provider.prepare(allocator, description);
        if (input.mode == .exact and (parent.redacted or !std.mem.eql(u8, body, parent.request orelse return error.InvalidReplay))) return error.InvalidReplay;
        const request: debug.RequestRecord = .{ .id = id, .run = identity.run.bytes, .sequence = identity.sequence, .parent_run = parent.run, .parent_call = parent.id, .original_run = parent.original_run orelse parent.run, .original_call = parent.original, .node = parent.node, .mode = input.mode, .description = description, .source_snapshot = parent.source_snapshot, .source_overrides = parent.source_overrides or input.mode == .modified, .body = if (input.mode == .exact) parent.request.? else body };
        try self.store.request(allocator, request);
        const response = self.provider.send(allocator, request) catch |err| {
            // Even an operational provider error leaves an explicit diagnostic result.
            try self.store.response(allocator, .{ .id = id, .outcome = .transport_failed, .diagnostic = @errorName(err) });
            return err;
        };
        try self.store.response(allocator, response);
        const validation = if (response.outcome == .received and response.status == 200 and response.body != null and response.encoding == .utf8)
            try self.provider.inspect(allocator, description, response.body.?)
        else
            debug.Validation{};
        return .{ .request = request, .response = response, .validation = validation };
    }
};
