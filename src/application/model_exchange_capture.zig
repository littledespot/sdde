//! Execution-local owner of complete provider-body capture. The common workflow
//! runner supplies attribution; the active feature-log lifecycle owns persistence.
const std = @import("std");
const capture_port = @import("../ports/model_exchange_capture.zig");
const barrier = @import("../ports/telemetry_barrier.zig");
const prompt = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const stream = @import("../domain/feature_log_stream.zig");
const lineage = @import("../domain/model_call_lineage.zig");
pub const Metadata = struct {
    workflow: telemetry.WorkflowShortcode,
    workflow_id: telemetry.Identifier,
    node: telemetry.Identifier,
    action: telemetry.Identifier,
    operation: telemetry.Identifier,
    model_slot: telemetry.Identifier,
    origin: @import("../domain/model_candidate_origin.zig").Origin,
    kind: lineage.Kind = .initial,
    source: ?lineage.Origin = null,
    description: ?@import("../domain/model_request_description.zig").Description = null,
    source_context: ?@import("request_source_capture.zig").Context = null,
};
pub const Capture = struct {
    allocator: std.mem.Allocator,
    logs: barrier.Barrier,
    current: ?Metadata = null,
    failure: ?stream.FailureCode = null,
    history: lineage.History = .{},
    links: ?lineage.Links = null,
    description_recorded: bool = false,

    pub fn deinit(self: *Capture) void {
        self.history.deinit(self.allocator);
    }

    pub fn port(self: *Capture) capture_port.Port {
        return .{ .context = @ptrCast(self), .capture_fn = capture };
    }
    pub fn begin(self: *Capture, metadata: Metadata) void {
        std.debug.assert(self.current == null);
        self.current = metadata;
        self.links = null;
        self.description_recorded = false;
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
        if (self.links == null) self.links = self.history.observe(self.allocator, metadata.origin, metadata.kind, metadata.source) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        fragment.attribution = .{ .workflow_id = metadata.workflow_id, .action_id = metadata.action, .call = metadata.origin, .links = self.links.? };
        if (!self.description_recorded) {
            if (metadata.source_context) |source_context| {
                var arena = std.heap.ArenaAllocator.init(self.allocator);
                defer arena.deinit();
                const source_snapshot = @import("request_source_capture.zig").snapshot(arena.allocator(), source_context, metadata.node.bytes, credentials) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
                if (source_snapshot) |value| {
                    const encoded = std.json.Stringify.valueAlloc(arena.allocator(), value, .{}) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
                    var source_fragment = fragment;
                    source_fragment.direction = .request;
                    if (self.persist(source_fragment, "source_snapshot", encoded, credentials) == .blocked) return .blocked;
                }
            }
            if (metadata.description) |description| {
                const encoded = std.json.Stringify.valueAlloc(self.allocator, description, .{}) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
                defer self.allocator.free(encoded);
                var description_fragment = fragment;
                description_fragment.direction = .request;
                if (self.persist(description_fragment, "request_description", encoded, credentials) == .blocked) return .blocked;
            }
            self.description_recorded = true;
        }
        const bytes = switch (body) {
            .provider_body, .partial_provider_body => |bytes| bytes,
            .transport_outcome => |outcome| std.json.Stringify.valueAlloc(self.allocator, outcome, .{}) catch return self.fail(.LOG_SERIALIZATION_FAILURE),
        };
        defer if (body == .transport_outcome) self.allocator.free(bytes);
        return self.persist(fragment, @tagName(body), bytes, credentials);
    }

    fn persist(self: *Capture, initial: prompt.SanitizedPromptFragment, provenance: []const u8, bytes: []const u8, credentials: []const []const u8) capture_port.Outcome {
        var fragment = initial;
        const metadata = self.current.?;
        var sanitized = @import("../domain/model_log_redaction.zig").sanitize(self.allocator, bytes, credentials) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        defer sanitized.deinit(self.allocator);
        fragment.body_bytes = sanitized.bytes.len;
        var chunks = prompt.ContentChunks.init(sanitized.bytes) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
        while (chunks.next()) |chunk| {
            var fragment_id: [128]u8 = undefined;
            fragment.fragment_id.bytes = std.fmt.bufPrint(&fragment_id, "{s}-{s}-{s}-{s}-{d:0>20}", .{ @tagName(metadata.origin.kind), @tagName(fragment.direction), provenance, @tagName(sanitized.encoding), chunk.byte_offset }) catch return self.fail(.LOG_SERIALIZATION_FAILURE);
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
