//! Credential-free capture diagnostics. These observations grant no authority.
const std = @import("std");
pub const Stage = enum {
    metadata,
    request_identity,
    lineage,
    source_snapshot,
    source_snapshot_serialization,
    request_description_serialization,
    transport_outcome_serialization,
    redaction,
    chunking,
    fragment_identity,
    persistence,
};
pub const Cause = union(enum) {
    missing_metadata,
    allocation,
    formatting,
    lineage: @import("model_call_lineage.zig").Rejection,
    source_snapshot: @import("request_source_snapshot.zig").CaptureRejection,
    invalid_chunks,
    prompt_dropped,
    sink: @import("feature_log_stream.zig").FailureCode,
};
pub const Failure = struct {
    code: @import("feature_log_stream.zig").FailureCode,
    stage: Stage,
    cause: Cause,
    origin: ?@import("model_candidate_origin.zig").Origin,
    direction: @import("sanitized_prompt_log.zig").PromptDirection,
    subsequent_logging_failure: ?@import("feature_log_stream.zig").FailureCode = null,

    pub fn diagnostic(self: Failure) []const u8 {
        return switch (self.stage) {
            .metadata => "MODEL_CAPTURE_METADATA_FAILURE",
            .request_identity => "MODEL_CAPTURE_REQUEST_IDENTITY_FAILURE",
            .lineage => "MODEL_CAPTURE_LINEAGE_FAILURE",
            .source_snapshot => "MODEL_CAPTURE_SOURCE_SNAPSHOT_FAILURE",
            .source_snapshot_serialization => "MODEL_CAPTURE_SOURCE_SERIALIZATION_FAILURE",
            .request_description_serialization => "MODEL_CAPTURE_DESCRIPTION_SERIALIZATION_FAILURE",
            .transport_outcome_serialization => "MODEL_CAPTURE_TRANSPORT_SERIALIZATION_FAILURE",
            .redaction => "MODEL_CAPTURE_REDACTION_FAILURE",
            .chunking => "MODEL_CAPTURE_CHUNKING_FAILURE",
            .fragment_identity => "MODEL_CAPTURE_FRAGMENT_IDENTITY_FAILURE",
            .persistence => "MODEL_CAPTURE_PERSISTENCE_FAILURE",
        };
    }

    pub fn diagnosticWithCause(self: Failure, buffer: []u8) error{NoSpaceLeft}![]const u8 {
        const cause = switch (self.cause) {
            .lineage => |value| @tagName(value),
            .source_snapshot => |value| @tagName(value),
            .sink => |value| @tagName(value),
            inline else => @tagName(self.cause),
        };
        const result = try std.fmt.bufPrint(buffer, "{s}_{s}", .{ self.diagnostic(), cause });
        for (result) |*byte| byte.* = std.ascii.toUpper(byte.*);
        return result;
    }
};

test "capture diagnostics retain stage and closed cause within the telemetry code bound" {
    for (std.enums.values(Stage)) |stage| {
        var buffer: [96]u8 = undefined;
        const failure: Failure = .{ .code = .LOG_SERIALIZATION_FAILURE, .stage = stage, .cause = .{ .source_snapshot = .missing_source_chain }, .origin = null, .direction = .request };
        const code = try failure.diagnosticWithCause(&buffer);
        try std.testing.expect(std.mem.startsWith(u8, code, failure.diagnostic()));
        try std.testing.expect(std.mem.endsWith(u8, code, "_MISSING_SOURCE_CHAIN"));
        try std.testing.expect(@import("telemetry.zig").DiagnosticCode.validate(code) != null);
    }
}
