//! One measured diagnostic dispatch through the existing replay service.
const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");
const replay = @import("../../../src/application/request_replay.zig");

pub const Trial = struct {
    ordinal: u32,
    request_id: []const u8,
    outcome: enum { completed, protocol_invalid, transport_failed, operation_failed },
    status: ?u16 = null,
    diagnostic: ?[]const u8 = null,
    elapsed_ns: i96 = 0,
    request_bytes: ?usize = null,
    response_bytes: ?usize = null,
    validation: debug.Validation = .{},

    pub fn canContinue(self: Trial) bool {
        return switch (self.outcome) {
            .completed, .protocol_invalid => true,
            .transport_failed, .operation_failed => false,
        };
    }
};

pub fn execute(a: std.mem.Allocator, io: std.Io, service: replay.Service, parent: debug.Call, identity: debug.ReplayIdentity) Trial {
    var trial: Trial = .{ .ordinal = @intCast(identity.sequence), .request_id = identity.id, .outcome = .operation_failed };
    const description = parent.description orelse {
        trial.diagnostic = "CaptureIncomplete";
        return trial;
    };
    const started: std.Io.Clock.Timestamp = .now(io, .awake);
    const result = service.replay(a, identity, parent, .{ .call = 0, .mode = .modified, .edit = .{ .content = description.content, .schema = description.schema } }) catch |err| {
        trial.elapsed_ns = started.durationTo(.now(io, .awake)).raw.toNanoseconds();
        trial.diagnostic = @errorName(err);
        return trial;
    };
    trial.elapsed_ns = started.durationTo(.now(io, .awake)).raw.toNanoseconds();
    trial.status = result.response.status;
    trial.request_bytes = result.request.body.len;
    trial.response_bytes = if (result.response.body) |bytes| bytes.len else null;
    trial.validation = result.validation;
    if (result.response.outcome != .received or result.response.status != 200) {
        trial.outcome = .transport_failed;
        trial.diagnostic = result.response.diagnostic orelse if (result.response.outcome == .received) "http_error" else @tagName(result.response.outcome);
    } else if (result.validation.extraction != .valid or result.validation.json != .valid or result.validation.schema != .valid) {
        trial.outcome = .protocol_invalid;
        trial.diagnostic = result.validation.reason;
    } else trial.outcome = .completed;
    return trial;
}
