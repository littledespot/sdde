const std = @import("std");
const capture = @import("application/model_exchange_capture.zig");
const prompt = @import("domain/sanitized_prompt_log.zig");
const stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");

const Sink = struct {
    allocator: std.mem.Allocator,
    fragments: std.ArrayList(prompt.SanitizedPromptFragment) = .empty,
    enabled: bool = true,
    failure_at: ?usize = null,
    failure_code: stream.FailureCode = .LOG_FLUSH_FAILURE,
    drop: bool = false,
    fn barrier(self: *Sink) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = event, .select_prompt_fn = select, .process_prompt_fn = process };
    }
    fn event(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) stream.Outcome {
        return .dropped;
    }
    fn select(context: *anyopaque, fragment: prompt.SanitizedPromptFragment) bool {
        const self: *Sink = @ptrCast(@alignCast(context));
        std.debug.assert(fragment.body_class == .complete_body);
        return self.enabled;
    }
    fn process(context: *anyopaque, fragment: prompt.SanitizedPromptFragment) stream.Outcome {
        const self: *Sink = @ptrCast(@alignCast(context));
        if (self.drop) return .dropped;
        if (self.failure_at == self.fragments.items.len) return .{ .blocked = self.failure_code };
        prompt.validate(fragment) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        var copy = fragment;
        copy.content = self.allocator.dupe(u8, fragment.content) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        copy.fragment_id.bytes = self.allocator.dupe(u8, fragment.fragment_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        copy.request_id.bytes = self.allocator.dupe(u8, fragment.request_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.fragments.append(self.allocator, copy) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = self.fragments.items.len, .segment_ordinal = 1, .bytes_written = fragment.content.len, .flushed = true } };
    }
};
const metadata: capture.Metadata = .{
    .workflow = telemetry.WorkflowShortcode.parse("SPEC") catch unreachable,
    .workflow_id = .{ .bytes = "spec" },
    .action = .{ .bytes = "invoke-model" },
    .node = .{ .bytes = "invoke-part" },
    .operation = .{ .bytes = "generate-part" },
    .model_slot = .{ .bytes = "generation" },
    .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 70000 } },
};

test "model capture preserves full sanitized bodies and existing request attempt identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    const prefix = try a.alloc(u8, 4997);
    @memset(prefix, 'a');
    const suffix = try a.alloc(u8, 170000);
    @memset(suffix, 'z');
    const body = try std.mem.concat(a, u8, &.{ prefix, "credential-秘密", suffix, "\ncomplete tail 🐈" });
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = body }, &.{"credential-秘密"}));
    try std.testing.expect(sink.fragments.items.len > 32);
    var restored: std.ArrayList(u8) = .empty;
    for (sink.fragments.items, 0..) |fragment, index| {
        try std.testing.expectEqual(@as(u32, 70000), fragment.attempt);
        try std.testing.expectEqualStrings("request-4", fragment.request_id.bytes);
        try std.testing.expectEqualStrings("generate-part", fragment.route_id.bytes);
        try std.testing.expectEqualStrings("generation", fragment.model_profile_id.bytes);
        try std.testing.expect(fragment.redacted and !fragment.truncated);
        try std.testing.expect(std.mem.startsWith(u8, fragment.fragment_id.bytes, "inference-request-provider_body-utf8-"));
        if (index > 0) try std.testing.expect(std.mem.order(u8, sink.fragments.items[index - 1].fragment_id.bytes, fragment.fragment_id.bytes) == .lt);
        try restored.appendSlice(a, fragment.content);
    }
    const expected = try std.mem.concat(a, u8, &.{ prefix, "[REDACTED_CREDENTIAL]", suffix, "\ncomplete tail 🐈" });
    try std.testing.expectEqualStrings(expected, restored.items);
    const before = sink.fragments.items.len;
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = "broken model JSON {" }, &.{}));
    try std.testing.expectEqualStrings("broken model JSON {", sink.fragments.items[before].content);
    try std.testing.expectEqual(.response, sink.fragments.items[before].direction);
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .transport_outcome = .{ .outcome = .cancelled } }, &.{}));
    try std.testing.expect(std.mem.startsWith(u8, sink.fragments.items[before + 1].fragment_id.bytes, "inference-response-transport_outcome-utf8-"));
    try std.testing.expect(!std.mem.eql(u8, sink.fragments.items[before].fragment_id.bytes, sink.fragments.items[before + 1].fragment_id.bytes));
    try std.testing.expect(logger.failure == null);
}

test "capture keeps binary provider responses reversible" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    try std.testing.expectEqual(.recorded, logger.port().capture(.response, .{ .provider_body = "\xff\x00" }, &.{}));
    try std.testing.expectEqualStrings("/wA=", sink.fragments.items[0].content);
    try std.testing.expect(std.mem.startsWith(u8, sink.fragments.items[0].fragment_id.bytes, "inference-response-provider_body-base64-"));
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "" }, &.{}));
    try std.testing.expectEqualStrings("", sink.fragments.items[1].content);
}

test "capture serialization failure records logging failure without a false body" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var sink: Sink = .{ .allocator = arena.allocator() };
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var logger: capture.Capture = .{ .allocator = failing.allocator(), .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    try std.testing.expectEqual(.blocked, logger.port().capture(.response, .{ .transport_outcome = .{ .outcome = .transport_failed } }, &.{}));
    try std.testing.expectEqual(.LOG_SERIALIZATION_FAILURE, logger.failure.?.code);
    try std.testing.expectEqual(.lineage, logger.failure.?.stage);
    try std.testing.expectEqual(.allocation, logger.failure.?.cause);
    try std.testing.expectEqualDeep(metadata.origin, logger.failure.?.origin.?);
    try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
}

test "capture honors disabled selection and makes persistence failures sticky" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a, .enabled = false };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    logger.begin(metadata);
    defer logger.end();
    try std.testing.expectEqual(.disabled, logger.port().capture(.request, .{ .provider_body = "private" }, &.{}));
    try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
    sink.enabled = true;
    sink.failure_at = 1;
    const body = try a.alloc(u8, 10001);
    @memset(body, 'x');
    try std.testing.expectEqual(.blocked, logger.port().capture(.request, .{ .provider_body = body }, &.{}));
    try std.testing.expectEqual(.LOG_FLUSH_FAILURE, logger.failure.?.code);
    try std.testing.expectEqual(.persistence, logger.failure.?.stage);
    try std.testing.expectEqual(.LOG_FLUSH_FAILURE, logger.failure.?.cause.sink);
    try std.testing.expectEqual(@as(usize, 1), sink.fragments.items.len);
    sink.failure_at = null;
    const retained_failure = logger.failure.?;
    try std.testing.expectEqual(.blocked, logger.port().capture(.response, .{ .provider_body = "must not continue" }, &.{}));
    try std.testing.expectEqual(@as(usize, 1), sink.fragments.items.len);
    try std.testing.expectEqualDeep(retained_failure, logger.failure.?);
    var drop_logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    sink.drop = true;
    drop_logger.begin(metadata);
    defer drop_logger.end();
    try std.testing.expectEqual(.blocked, drop_logger.port().capture(.response, .{ .provider_body = "unexpectedly dropped" }, &.{}));
    try std.testing.expectEqual(.LOG_SERIALIZATION_FAILURE, drop_logger.failure.?.code);
    try std.testing.expectEqual(.prompt_dropped, drop_logger.failure.?.cause);
}

test "request lineage distinguishes retry repair and unrelated requests" {
    const lineage = @import("domain/model_call_lineage.zig");
    var history: lineage.History = .{};
    defer history.deinit(std.testing.allocator);
    const first: lineage.Origin = .{ .request = .{ .value = 0 }, .attempt = .{ .value = 1 } };
    const retried: lineage.Origin = .{ .request = first.request, .attempt = .{ .value = 3 } };
    const repair: lineage.Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const repaired_again: lineage.Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const unrelated: lineage.Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    try std.testing.expectEqual(.initial, (try history.observe(std.testing.allocator, first, .initial, .none)).kind);
    _ = try history.observe(std.testing.allocator, unrelated, .initial, .none);
    const retry = try history.observe(std.testing.allocator, retried, .initial, .none);
    try std.testing.expectEqual(.retry, retry.kind);
    try std.testing.expectEqualDeep(first, retry.original);
    try std.testing.expectEqualDeep(first, retry.parent.?);
    const linked = try history.observe(std.testing.allocator, repair, .repair, .{ .response = retried });
    try std.testing.expectEqual(.repair, linked.kind);
    try std.testing.expectEqualDeep(first, linked.original);
    try std.testing.expectEqualDeep(retried, linked.parent.?);
    try std.testing.expectEqualDeep(first, (try history.observe(std.testing.allocator, repaired_again, .repair, .{ .response = repair })).original);
    try std.testing.expectError(error.DuplicateModelCall, history.observe(std.testing.allocator, repaired_again, .repair, .{ .response = repair }));
    try std.testing.expectError(error.MissingModelCallSource, history.observe(std.testing.allocator, .{ .request = .{ .value = 9 }, .attempt = .{ .value = 1 } }, .repair, .none));
    try std.testing.expectError(error.UnknownModelCallSource, history.observe(std.testing.allocator, .{ .request = .{ .value = 9 }, .attempt = .{ .value = 1 } }, .repair, .{ .response = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 1 } } }));
}

test "assembled candidate repair request capture does not invent a producing call" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: Sink = .{ .allocator = a };
    var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
    defer logger.deinit();
    // Grouped records retain each member's origin but have no single .unit
    // origin. The retained call-50 insertion selected that assembled unit.
    const origins: @import("domain/specification_candidate.zig").Origins = .{
        .fields = &.{
            .{ .target = .{ .record = 0 }, .origin = .{ .request = .{ .value = 11 }, .attempt = .{ .value = 1 } } },
            .{ .target = .{ .record = 1 }, .origin = .{ .request = .{ .value = 12 }, .attempt = .{ .value = 1 } } },
        },
    };
    var assembled = metadata;
    assembled.origin = .{ .request = .{ .value = 50 }, .attempt = .{ .value = 1 } };
    assembled.kind = .repair;
    try std.testing.expect(origins.at(.unit) == null);
    assembled.source = .assembled_candidate;
    logger.begin(assembled);
    defer logger.end();
    try std.testing.expectEqual(.recorded, logger.port().capture(.request, .{ .provider_body = "authorized assembled-candidate insertion" }, &.{}));
    try std.testing.expect(logger.failure == null);
    const links = sink.fragments.items[0].attribution.?.links;
    try std.testing.expectEqual(.repair, links.kind);
    try std.testing.expectEqual(.assembled_candidate, links.source);
    try std.testing.expect(links.parent == null);
    try std.testing.expectEqualDeep(assembled.origin, links.original);
}

test "explicit assembled repair lineage covers unrelated units and keeps retry parents" {
    const lineage = @import("domain/model_call_lineage.zig");
    var history: lineage.History = .{};
    defer history.deinit(std.testing.allocator);
    for ([_]u32{ 5, 70000, 99 }) |ordinal| {
        const first: lineage.Origin = .{ .request = .{ .value = ordinal }, .attempt = .{ .value = 1 } };
        const links = try history.observe(std.testing.allocator, first, .repair, .assembled_candidate);
        try std.testing.expect(lineage.valid(first, links));
        try std.testing.expectEqualDeep(first, links.original);
        try std.testing.expect(links.parent == null);
        const correction: lineage.Origin = .{ .request = first.request, .attempt = .{ .value = 2 } };
        const retried = try history.observe(std.testing.allocator, correction, .repair, .assembled_candidate);
        try std.testing.expect(lineage.valid(correction, retried));
        try std.testing.expectEqual(.retry, retried.kind);
        try std.testing.expectEqualDeep(first, retried.parent.?);
        try std.testing.expectEqualDeep(first, retried.original);
    }
}

test "lineage rejects missing foreign and inconsistent source provenance" {
    const lineage = @import("domain/model_call_lineage.zig");
    var history: lineage.History = .{};
    defer history.deinit(std.testing.allocator);
    const call: lineage.Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    try std.testing.expectError(error.MissingModelCallSource, history.observe(std.testing.allocator, call, .repair, .none));
    try std.testing.expectError(error.MissingModelCallSource, history.observe(std.testing.allocator, call, .context_followup, .none));
    try std.testing.expectError(error.UnexpectedModelCallSource, history.observe(std.testing.allocator, call, .initial, .assembled_candidate));
    try std.testing.expectError(error.UnexpectedModelCallSource, history.observe(std.testing.allocator, call, .context_followup, .assembled_candidate));
    try std.testing.expectError(error.UnknownModelCallSource, history.observe(std.testing.allocator, call, .repair, .{ .response = call }));
    const initial = try history.observe(std.testing.allocator, call, .initial, .none);
    const later: lineage.Origin = .{ .request = call.request, .attempt = .{ .value = 2 } };
    try std.testing.expectError(error.ExplicitRetryKind, history.observe(std.testing.allocator, later, .retry, .{ .response = call }));
    const retry = try history.observe(std.testing.allocator, later, .initial, .none);
    try std.testing.expectError(error.ZeroModelAttempt, history.observe(std.testing.allocator, .{ .request = call.request, .attempt = .{ .value = 0 } }, .initial, .none));
    const highest: lineage.Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 3 } };
    _ = try history.observe(std.testing.allocator, highest, .initial, .none);
    try std.testing.expectError(error.NonIncreasingModelAttempt, history.observe(std.testing.allocator, .{ .request = highest.request, .attempt = .{ .value = 2 } }, .initial, .none));
    var corrupt = initial;
    corrupt.kind = .repair;
    try std.testing.expect(!lineage.valid(call, corrupt));
    corrupt = retry;
    corrupt.source = .assembled_candidate;
    try std.testing.expect(!lineage.valid(later, corrupt));
    corrupt = initial;
    corrupt.source = .assembled_candidate;
    try std.testing.expect(!lineage.valid(call, corrupt));
}

test "capture lineage failures remain attributable and never persist secret bytes" {
    for ([_]@import("domain/model_call_lineage.zig").Source{ .none, .{ .response = metadata.origin } }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var sink: Sink = .{ .allocator = a };
        var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
        defer logger.deinit();
        var selected = metadata;
        selected.kind = .repair;
        selected.source = source;
        logger.begin(selected);
        defer logger.end();
        try std.testing.expectEqual(.blocked, logger.port().capture(.request, .{ .provider_body = "secret-value" }, &.{"secret-value"}));
        const detail = logger.failure.?;
        try std.testing.expectEqual(.lineage, detail.stage);
        const expected: @import("domain/model_call_lineage.zig").Rejection = if (source == .none) .missing_source else .unknown_source;
        try std.testing.expectEqual(expected, detail.cause.lineage);
        try std.testing.expectEqualDeep(selected.origin, detail.origin.?);
        try std.testing.expectEqual(.request, detail.direction);
        try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
        const encoded = try std.json.Stringify.valueAlloc(a, detail, .{});
        try std.testing.expect(std.mem.indexOf(u8, encoded, "secret-value") == null);
    }
}

test "capture allocation faults identify lineage serialization and redaction phases" {
    const diagnostics = @import("domain/model_capture_failure.zig");
    var observed: std.EnumSet(diagnostics.Stage) = .initEmpty();
    var provider_fixture: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
    try provider_fixture.init(std.testing.allocator);
    defer provider_fixture.deinit();
    for (0..64) |failure_index| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var sink: Sink = .{ .allocator = arena.allocator() };
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = failure_index });
        var logger: capture.Capture = .{ .allocator = failing.allocator(), .logs = sink.barrier() };
        defer logger.deinit();
        var selected = metadata;
        selected.description = @import("domain/model_request_description.zig").Description.from(&provider_fixture.request, &provider_fixture.provider_binding, .inference);
        logger.begin(selected);
        defer logger.end();
        const result = logger.port().capture(.response, .{ .transport_outcome = .{ .outcome = .transport_failed } }, &.{"secret-value"});
        if (result == .recorded) break;
        try std.testing.expectEqual(.blocked, result);
        const detail = logger.failure.?;
        try std.testing.expectEqual(.allocation, detail.cause);
        try std.testing.expectEqual(.LOG_SERIALIZATION_FAILURE, detail.code);
        observed.insert(detail.stage);
        const before = sink.fragments.items.len;
        try std.testing.expectEqual(.blocked, logger.port().capture(.response, .{ .provider_body = "discarded" }, &.{}));
        try std.testing.expectEqual(before, sink.fragments.items.len);
        try std.testing.expectEqualDeep(detail, logger.failure.?);
    }
    for ([_]diagnostics.Stage{ .lineage, .request_description_serialization, .transport_outcome_serialization, .redaction }) |stage| try std.testing.expect(observed.contains(stage));
}

test "request and returned-body persistence failures retain their exact code and association" {
    inline for (std.meta.tags(stream.FailureCode)) |failure_code| {
        for ([_]prompt.PromptDirection{ .request, .response }) |direction| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var sink: Sink = .{ .allocator = a, .failure_at = 0, .failure_code = failure_code };
            var logger: capture.Capture = .{ .allocator = a, .logs = sink.barrier() };
            defer logger.deinit();
            logger.begin(metadata);
            defer logger.end();
            try std.testing.expectEqual(.blocked, logger.port().capture(direction, .{ .provider_body = "unpersisted body" }, &.{}));
            const detail = logger.failure.?;
            try std.testing.expectEqual(failure_code, detail.code);
            try std.testing.expectEqual(failure_code, detail.cause.sink);
            try std.testing.expectEqual(.persistence, detail.stage);
            try std.testing.expectEqual(direction, detail.direction);
            try std.testing.expectEqualDeep(metadata.origin, detail.origin.?);
            try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
        }
    }
}
