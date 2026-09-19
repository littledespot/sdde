//! Execution-local owner of complete provider-body capture. The common workflow
//! runner supplies attribution; the active feature-log lifecycle owns persistence.
const std = @import("std");
const capture_port = @import("../ports/model_exchange_capture.zig");
const barrier = @import("../ports/telemetry_barrier.zig");
const prompt = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const stream = @import("../domain/feature_log_stream.zig");
pub const Metadata = struct {
    workflow: telemetry.WorkflowShortcode,
    node: telemetry.Identifier,
    operation: telemetry.Identifier,
    model_slot: telemetry.Identifier,
    origin: @import("../domain/model_candidate_origin.zig").Origin,
};
pub const Capture = struct {
    allocator: std.mem.Allocator,
    logs: barrier.Barrier,
    current: ?Metadata = null,
    failure: ?stream.FailureCode = null,

    pub fn port(self: *Capture) capture_port.Port {
        return .{ .context = @ptrCast(self), .capture_fn = capture };
    }
    pub fn begin(self: *Capture, metadata: Metadata) void {
        std.debug.assert(self.current == null);
        self.current = metadata;
    }
    pub fn end(self: *Capture) void {
        self.current = null;
    }
    fn capture(context: *capture_port.Context, direction: prompt.PromptDirection, body: capture_port.Body, credentials: []const []const u8) capture_port.Outcome {
        const self: *Capture = @ptrCast(@alignCast(context));
        if (self.failure != null) return .blocked;
        const metadata = self.current orelse return self.fail(.LOG_SERIALIZATION_FAILURE);
        var request_id: [64]u8 = undefined;
        const request = std.fmt.bufPrint(&request_id, "request-{d}", .{metadata.origin.request.value}) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        var fragment: prompt.SanitizedPromptFragment = .{
            .workflow_shortcode = metadata.workflow,
            .node_id = metadata.node,
            .attempt = metadata.origin.attempt.value,
            .request_id = .{ .bytes = request },
            .route_id = metadata.operation,
            .model_profile_id = metadata.model_slot,
            .fragment_id = .{ .bytes = "capture-selection" },
            .direction = direction,
            .body_class = .complete_body,
            .content = "",
            .retained_bytes = 0,
            .truncated = false,
            .redacted = false,
        };
        if (!self.logs.selectPrompt(fragment)) return .disabled;
        const bytes = switch (body) {
            .provider_body, .partial_provider_body => |bytes| bytes,
            .transport_outcome => |outcome| std.json.Stringify.valueAlloc(self.allocator, outcome, .{}) catch return self.fail(.LOG_SERIALIZATION_FAILURE),
        };
        defer if (body == .transport_outcome) self.allocator.free(bytes);
        var sanitized = @import("../domain/model_log_redaction.zig").sanitize(self.allocator, bytes, credentials) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        defer sanitized.deinit(self.allocator);
        var chunks = prompt.ContentChunks.init(sanitized.bytes) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        while (chunks.next()) |chunk| {
            var fragment_id: [128]u8 = undefined;
            fragment.fragment_id.bytes = std.fmt.bufPrint(&fragment_id, "{s}-{s}-{s}-{s}-{d:0>20}", .{ @tagName(metadata.origin.kind), @tagName(direction), @tagName(body), @tagName(sanitized.encoding), chunk.byte_offset }) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
            fragment.content = chunk.content;
            fragment.retained_bytes = @intCast(chunk.content.len);
            fragment.redacted = sanitized.redacted;
            switch (self.logs.processPrompt(fragment)) {
                .persisted => {},
                .dropped => return self.fail(.LOG_SERIALIZATION_FAILURE),
                .blocked => |failure| {
                    // The logging orchestrator already emitted its emergency record.
                    self.failure = failure;
                    return .blocked;
                },
            }
        }
        return .recorded;
    }
    fn fail(self: *Capture, failure: stream.FailureCode) capture_port.Outcome {
        if (self.current) |metadata| self.logs.reportFailure(metadata.workflow, failure);
        self.failure = failure;
        return .blocked;
    }
};
