//! Execution-local owner of complete provider-body capture. The common workflow
//! runner supplies attribution; the active feature-log lifecycle owns persistence.
const std = @import("std");
const capture_port = @import("../ports/model_exchange_capture.zig");
const barrier = @import("../ports/telemetry_barrier.zig");
const prompt = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const lineage = @import("../domain/model_call_lineage.zig");
const diagnostics = @import("../domain/model_capture_failure.zig");
pub const Metadata = struct {
    workflow: telemetry.WorkflowShortcode,
    workflow_id: telemetry.Identifier,
    node: telemetry.Identifier,
    action: telemetry.Identifier,
    operation: telemetry.Identifier,
    model_slot: telemetry.Identifier,
    origin: @import("../domain/model_candidate_origin.zig").Origin,
    kind: lineage.Kind = .initial,
    source: lineage.Source = .none,
    description: ?@import("../domain/model_request_description.zig").Description = null,
    source_context: ?@import("request_source_capture.zig").Context = null,
};
pub const Capture = struct {
    allocator: std.mem.Allocator,
    logs: barrier.Barrier,
    current: ?Metadata = null,
    failure: ?diagnostics.Failure = null,
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
        const metadata = self.current orelse return self.fail(direction, .metadata, .missing_metadata);
        var request_id: [64]u8 = undefined;
        const request = std.fmt.bufPrint(&request_id, "request-{d}", .{metadata.origin.request.value}) catch return self.fail(direction, .request_identity, .formatting);
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
        if (self.links == null) self.links = self.history.observe(self.allocator, metadata.origin, metadata.kind, metadata.source) catch |cause| return self.fail(direction, .lineage, if (lineage.rejection(cause)) |reason| .{ .lineage = reason } else .allocation);
        fragment.attribution = .{ .workflow_id = metadata.workflow_id, .action_id = metadata.action, .call = metadata.origin, .links = self.links.? };
        if (!self.description_recorded) {
            if (metadata.source_context) |source_context| {
                var arena = std.heap.ArenaAllocator.init(self.allocator);
                defer arena.deinit();
                const source_snapshot = @import("request_source_capture.zig").snapshot(arena.allocator(), source_context, metadata.node.bytes, credentials) catch |cause| return self.fail(.request, .source_snapshot, if (@import("request_source_capture.zig").rejection(cause)) |reason| .{ .source_snapshot = reason } else .allocation);
                if (source_snapshot) |value| {
                    const encoded = std.json.Stringify.valueAlloc(arena.allocator(), value, .{}) catch return self.fail(.request, .source_snapshot_serialization, .allocation);
                    var source_fragment = fragment;
                    source_fragment.direction = .request;
                    if (self.persist(source_fragment, "source_snapshot", encoded, credentials) == .blocked) return .blocked;
                }
            }
            if (metadata.description) |description| {
                const encoded = std.json.Stringify.valueAlloc(self.allocator, description, .{}) catch return self.fail(.request, .request_description_serialization, .allocation);
                defer self.allocator.free(encoded);
                var description_fragment = fragment;
                description_fragment.direction = .request;
                if (self.persist(description_fragment, "request_description", encoded, credentials) == .blocked) return .blocked;
            }
            self.description_recorded = true;
        }
        const bytes = switch (body) {
            .provider_body, .partial_provider_body => |bytes| bytes,
            .transport_outcome => |outcome| std.json.Stringify.valueAlloc(self.allocator, outcome, .{}) catch return self.fail(direction, .transport_outcome_serialization, .allocation),
        };
        defer if (body == .transport_outcome) self.allocator.free(bytes);
        return self.persist(fragment, @tagName(body), bytes, credentials);
    }

    fn persist(self: *Capture, initial: prompt.SanitizedPromptFragment, provenance: []const u8, bytes: []const u8, credentials: []const []const u8) capture_port.Outcome {
        var fragment = initial;
        const metadata = self.current.?;
        var sanitized = @import("../domain/model_log_redaction.zig").sanitize(self.allocator, bytes, credentials) catch return self.fail(initial.direction, .redaction, .allocation);
        defer sanitized.deinit(self.allocator);
        fragment.body_bytes = sanitized.bytes.len;
        var chunks = prompt.ContentChunks.init(sanitized.bytes) catch return self.fail(initial.direction, .chunking, .invalid_chunks);
        while (chunks.next()) |chunk| {
            var fragment_id: [128]u8 = undefined;
            fragment.fragment_id.bytes = std.fmt.bufPrint(&fragment_id, "{s}-{s}-{s}-{s}-{d:0>20}", .{ @tagName(metadata.origin.kind), @tagName(fragment.direction), provenance, @tagName(sanitized.encoding), chunk.byte_offset }) catch return self.fail(initial.direction, .fragment_identity, .formatting);
            fragment.content = chunk.content;
            fragment.retained_bytes = @intCast(chunk.content.len);
            fragment.redacted = sanitized.redacted;
            switch (self.logs.processPrompt(fragment)) {
                .persisted => {},
                .dropped => return self.fail(initial.direction, .persistence, .prompt_dropped),
                .blocked => |failure| {
                    // The logging orchestrator already emitted its emergency record.
                    self.failure = .{ .code = failure, .stage = .persistence, .cause = .{ .sink = failure }, .origin = metadata.origin, .direction = initial.direction };
                    return .blocked;
                },
            }
        }
        return .recorded;
    }
    fn fail(self: *Capture, direction: prompt.PromptDirection, stage: diagnostics.Stage, cause: diagnostics.Cause) capture_port.Outcome {
        if (self.current) |metadata| self.logs.reportFailure(metadata.workflow, .LOG_SERIALIZATION_FAILURE);
        self.failure = .{ .code = .LOG_SERIALIZATION_FAILURE, .stage = stage, .cause = cause, .origin = if (self.current) |metadata| metadata.origin else null, .direction = direction };
        return .blocked;
    }
};
