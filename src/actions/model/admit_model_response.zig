const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const invocation = @import("../../domain/provider_invocation_validation.zig");
const envelope = @import("../../domain/model_envelope.zig");
const validation = @import("../../domain/model_payload_schema.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "admit-model-response",
        .kind = .action,
        .requires = &@import("../../domain/workflow_model_invocation.zig").decode_requires,
        .produces = &@import("../../domain/workflow_model_invocation.zig").admission_produces,
        .side_effect = .none,
    };

    /// The caller owns the decoded tree; validation borrows that exact tree.
    pub const Result = struct { decoded: envelope.Owned, validated: validation.Result };

    pub fn execute(_: Action, allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate, diagnostic: ?*?envelope.Diagnostic) envelope.Error!Result {
        const decoded = try envelope.decode(allocator, complete, diagnostic);
        return .{ .decoded = decoded, .validated = validation.validate(decoded.candidate) };
    }
};
