const std = @import("std");
const evidence = @import("domain/actor_evidence.zig");
const acceptance = @import("domain/clarification_acceptance.zig");
const c = @import("domain/clarification_inputs.zig");
const feature = @import("domain/feature_identity.zig");
const feature_directory = @import("domain/feature_directory.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const authenticating = @import("domain/clarification_authentication.zig");
const pipeline = @import("domain/pipeline.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const strict_json = @import("domain/strict_json.zig");
const source_port = @import("ports/workflow_state_source.zig");
const evidence_parser = @import("adapters/parsers/actor_evidence.zig");
const prepare_stage = @import("actions/specify/prepare_actor_evidence.zig");
const accept_stage = @import("actions/clarification/accept_clarification_responses.zig");
const fixture = @import("test_fixtures/clarification_inputs.zig");

const feature_id = "Chosen/Café";

fn selected() feature.FeatureId {
    return feature.FeatureId.parse(feature_id).?;
}

fn observation(actor: []const u8) evidence.Observation {
    var time: [20]u8 = undefined;
    @memcpy(&time, "2026-11-23T08:15:00Z");
    return .{ .provider = .os_account, .actor_id = actor, .assurance = .invoking_account, .run_id = "RUN-1", .occurred_at = time };
}

fn authentication(actor: []const u8) evidence.Observation {
    return observation(actor);
}

fn openState(a: std.mem.Allocator, count: usize) !c.State {
    const records = try a.alloc(c.Record, count);
    for (records, 0..) |*record, index| {
        record.* = fixture.record(try std.fmt.allocPrint(a, "S{d:0>2}", .{index + 1}));
        record.subject = .{ .requirement = try std.fmt.allocPrint(a, "FR-{d:0>3}", .{index + 1}), .unit = "primary", .slot = "appearance", .sources = &.{} };
    }
    return fixture.state(records);
}

fn submission(record: c.Record, status: c.RequestedStatus, answer: c.Answer) c.Submission {
    return .{ .id = c.Id.parse(record.id).?, .subject = record.subject, .authority = record.authority, .requested_status = status, .answer = answer, .origin = .submitted };
}

fn closed(record: c.Record) c.Submission {
    return submission(record, .closed, .{ .business_text = "Approved Café theme." });
}

fn inputsOf(state: c.State, submissions: []const c.Submission) c.Inputs {
    return .{ .state = .{ .value = state }, .submissions = submissions, .protected_forms = &.{} };
}

const limits: strict_json.Limits = .{ .maximum_bytes = evidence.max_bytes, .maximum_depth = evidence.max_depth };

test "a run's authentications append in one revision with consecutive ordinals" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prior = evidence.empty(selected());
    try evidence.validate(prior, selected());
    const first = try evidence.record(a, prior, &.{ authentication("ada"), authentication("ada") });
    try std.testing.expectEqual(@as(u64, 1), first.registry.revision);
    try std.testing.expectEqual(@as(u64, 3), first.registry.next_ordinal);
    try std.testing.expectEqual(@as(usize, 2), first.appended.len);
    try std.testing.expectEqual(@as(u64, 1), first.appended[0].ordinal);
    try std.testing.expectEqual(@as(u64, 2), first.appended[1].ordinal);
    try evidence.validateAppend(prior, first.registry);
    var later_run = observation("ada");
    later_run.run_id = "RUN-2";
    const second = try evidence.record(a, first.registry, &.{later_run});
    try std.testing.expectEqual(@as(u64, 2), second.registry.revision);
    try std.testing.expectEqual(@as(u64, 3), second.appended[0].ordinal);
    try evidence.validateAppend(first.registry, second.registry);
    const none = try evidence.record(a, second.registry, &.{});
    try std.testing.expectEqual(second.registry.revision, none.registry.revision);
    try std.testing.expectEqual(@as(usize, 0), none.appended.len);
}

test "an account name outside the token syntax is rejected and nothing is recorded" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "ada lovelace", "Zoë", "", "a" ** 129 }) |name| {
        try std.testing.expectError(error.UnsupportedActorName, evidence.record(a, evidence.empty(selected()), &.{authentication(name)}));
    }
    for ([_][]const u8{ "ada", "ada.lovelace", "ada_l-1@host", "a" ** 128 }) |name| {
        _ = try evidence.record(a, evidence.empty(selected()), &.{authentication(name)});
    }
}

test "the registry round-trips through its closed JSON and rejects unknown members" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{ authentication("ada"), authentication("ada") });
    const bytes = try evidence.encode(a, recorded.registry);
    const decoded = try strict_json.decode(evidence.Registry, a, bytes, limits);
    try evidence.validate(decoded, selected());
    try std.testing.expectEqualStrings(bytes, try evidence.encode(a, decoded));
    const empty_bytes = try evidence.encode(a, evidence.empty(selected()));
    _ = try strict_json.decode(evidence.Registry, a, empty_bytes, limits);
    for ([_][]const u8{
        "{\"entries\":[],\"extra\":1,\"feature_id\":\"Chosen/Café\",\"next_ordinal\":1,\"revision\":0,\"schema\":\"actor-evidence-registry/v1\"}",
        "{\"entries\":[{\"actor_id\":\"ada\",\"assurance\":\"invoking_account\",\"event_kind\":\"clarification_response\",\"occurred_at\":\"2026-11-23T08:15:00Z\",\"ordinal\":1,\"provider\":\"keychain\",\"run_id\":\"RUN-1\"}],\"feature_id\":\"Chosen/Café\",\"next_ordinal\":2,\"revision\":1,\"schema\":\"actor-evidence-registry/v1\"}",
        "{\"entries\":[{\"actor_id\":\"ada\",\"assurance\":\"invoking_account\",\"credential\":\"secret\",\"event_kind\":\"clarification_response\",\"occurred_at\":\"2026-11-23T08:15:00Z\",\"ordinal\":1,\"provider\":\"os_account\",\"run_id\":\"RUN-1\"}],\"feature_id\":\"Chosen/Café\",\"next_ordinal\":2,\"revision\":1,\"schema\":\"actor-evidence-registry/v1\"}",
    }) |rejected| try std.testing.expectError(error.InvalidJsonDocument, strict_json.decode(evidence.Registry, a, rejected, limits));
}

test "validation rejects a registry that is not the feature's append-only sequence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const good = (try evidence.record(a, evidence.empty(selected()), &.{authentication("ada")})).registry;
    try evidence.validate(good, selected());
    for (0..10) |scenario| {
        var bad = good;
        const entries = try a.dupe(evidence.Evidence, good.entries);
        switch (scenario) {
            9 => entries[0].occurred_at = "2026-99-99T99:99:99Z",
            0 => bad.schema = "actor-evidence-registry/v2",
            1 => bad.feature_id = "Another/Feature",
            2 => bad.next_ordinal = 3,
            3 => entries[0].ordinal = 2,
            4 => bad.revision = 0,
            5 => bad.revision = 2,
            6 => entries[0].actor_id = "ada lovelace",
            7 => entries[0].run_id = "",
            8 => entries[0].occurred_at = "2026-11-23 08:15:00Z",
            else => unreachable,
        }
        bad.entries = entries;
        try std.testing.expectError(error.InvalidActorEvidence, evidence.validate(bad, selected()));
    }
    try std.testing.expectError(error.InvalidActorEvidence, evidence.validate(evidence.empty(selected()), feature.FeatureId.parse("Another/Feature").?));
}

test "an append that rewrites history or skips a revision is rejected" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prior = (try evidence.record(a, evidence.empty(selected()), &.{authentication("ada")})).registry;
    const next = (try evidence.record(a, prior, &.{authentication("ada")})).registry;
    try evidence.validateAppend(prior, next);
    try evidence.validateAppend(prior, prior);
    for (0..5) |scenario| {
        var bad = next;
        const entries = try a.dupe(evidence.Evidence, next.entries);
        switch (scenario) {
            0 => entries[0].actor_id = "eve",
            1 => bad.revision = next.revision + 1,
            2 => bad.revision = prior.revision,
            3 => bad.entries = entries[0..0],
            4 => bad.feature_id = "Another/Feature",
            else => unreachable,
        }
        if (scenario != 3) bad.entries = entries;
        try std.testing.expectError(error.InvalidActorEvidence, evidence.validateAppend(prior, bad));
    }
    var advanced = prior;
    advanced.revision += 1;
    try std.testing.expectError(error.InvalidActorEvidence, evidence.validateAppend(prior, advanced));
}

test "an evidence ID parses only as AE and a positive ordinal without leading zeros" {
    var buffer: [24]u8 = undefined;
    try std.testing.expectEqualStrings("AE-12", evidence.idText(&buffer, 12));
    try std.testing.expectEqual(@as(?u64, 12), evidence.parseId("AE-12"));
    for ([_][]const u8{ "", "AE-", "AE-0", "AE-012", "ae-1", "AE-1x", "AE--1", "fixture-auth-1", "AE-4097" }) |bad| {
        try std.testing.expectEqual(@as(?u64, null), evidence.parseId(bad));
    }
}

test "a form that needs authentication is a closed answered form of this run's" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const state = try openState(a, 1);
    const record = state.records[0];
    try std.testing.expect(acceptance.needsAuthentication(closed(record)));
    try std.testing.expect(acceptance.needsAuthentication(submission(record, .closed, .{ .selected_option = "light" })));
    try std.testing.expect(!acceptance.needsAuthentication(submission(record, .open, .{ .defer_reason = "later" })));
    // A cancel with its reason is a form of this run's too, and a cancel or a closed form without its own kind of answer is not.
    try std.testing.expect(acceptance.needsAuthentication(submission(record, .cancel, .{ .cancel_reason = "stop" })));
    try std.testing.expect(!acceptance.needsAuthentication(submission(record, .cancel, .none)));
    try std.testing.expect(!acceptance.needsAuthentication(submission(record, .cancel, .{ .business_text = "stop" })));
    try std.testing.expect(!acceptance.needsAuthentication(submission(record, .closed, .{ .cancel_reason = "stop" })));
    try std.testing.expect(!acceptance.needsAuthentication(submission(record, .closed, .none)));
    var recorded = closed(record);
    recorded.origin = .recorded;
    try std.testing.expect(!acceptance.needsAuthentication(recorded));
    const submissions = [_]c.Submission{ closed(record), submission(record, .open, .{ .defer_reason = "later" }) };
    const ids = try acceptance.pending(a, inputsOf(state, &submissions));
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqual(@as(usize, 0), (try acceptance.pending(a, inputsOf(state, &.{}))).len);
}

test "acceptance resolves each authenticated form in one later state" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const state = try openState(a, 3);
    const submissions = [_]c.Submission{ closed(state.records[0]), closed(state.records[1]), submission(state.records[2], .open, .{ .defer_reason = "later" }) };
    const inputs = inputsOf(state, &submissions);
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{ authentication("ada"), authentication("ada") });
    const accepted = try acceptance.accept(a, inputs, &.{
        .{ .id = c.Id.parse("S01").?, .form_bytes = "first form", .evidence = recorded.appended[0] },
        .{ .id = c.Id.parse("S02").?, .form_bytes = "second form", .evidence = recorded.appended[1] },
    });
    const next = accepted.state.value.?;
    try std.testing.expectEqual(@as(u64, 2), next.state_ordinal);
    try std.testing.expectEqual(@as(u64, 2), next.revision);
    try std.testing.expectEqual(@as(u64, 3), next.next_response_ordinal);
    try std.testing.expectEqual(@as(usize, 2), next.responses.len);
    for (next.responses, 0..) |response, index| {
        try std.testing.expectEqual(@as(u64, index + 1), response.id);
        try std.testing.expectEqual(@as(u64, 1), response.input_state_ordinal);
        try std.testing.expectEqual(@as(u64, 1), response.input_state_revision);
        try std.testing.expectEqual(@as(u64, 1), response.input_record_revision);
        try std.testing.expectEqualStrings("ada", response.actor_id);
        try std.testing.expectEqualStrings("2026-11-23T08:15:00Z", response.answered_at);
        try std.testing.expectEqualStrings(if (index == 0) "AE-1" else "AE-2", response.authentication_evidence_id);
        try std.testing.expectEqual(@as(u64, index + 1), next.records[index].response_id.?);
        try std.testing.expectEqual(c.EngineStatus.resolved_by_user, next.records[index].status);
        try std.testing.expectEqual(@as(u64, 2), next.records[index].revision);
        try std.testing.expect(accepted.submissions[index].origin == .recorded);
    }
    try std.testing.expectEqualStrings("first form", next.responses[0].submitted_form_bytes);
    try std.testing.expectEqual(c.EngineStatus.open, next.records[2].status);
    try std.testing.expectEqual(@as(u64, 1), next.records[2].revision);
    try std.testing.expectEqual(@as(usize, 0), (try acceptance.pending(a, accepted)).len);
    try evidence.validateJoin(recorded.registry, next);
    // A later run continues the response ordinals and the registry's.
    const later = try evidence.record(a, recorded.registry, &.{authentication("ada")});
    const third = [_]c.Submission{closed(next.records[2])};
    const continued = try acceptance.accept(a, inputsOf(next, &third), &.{.{ .id = c.Id.parse("S03").?, .form_bytes = "third form", .evidence = later.appended[0] }});
    const final = continued.state.value.?;
    try std.testing.expectEqual(@as(u64, 3), final.state_ordinal);
    try std.testing.expectEqual(@as(usize, 3), final.responses.len);
    try std.testing.expectEqual(@as(u64, 3), final.responses[2].id);
    try std.testing.expectEqualStrings("AE-3", final.responses[2].authentication_evidence_id);
    try evidence.validateJoin(later.registry, final);
}

test "a cancel is accepted with the other valid forms, cancels its record and ends the run" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const state = try openState(a, 3);
    const submissions = [_]c.Submission{ closed(state.records[0]), submission(state.records[1], .cancel, .{ .cancel_reason = "No longer needed." }), submission(state.records[2], .open, .{ .defer_reason = "later" }) };
    const inputs = inputsOf(state, &submissions);
    const planned = try acceptance.pending(a, inputs);
    try std.testing.expectEqual(@as(usize, 2), planned.len);
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{ authentication("ada"), authentication("ada") });
    const accepted = try acceptance.accept(a, inputs, &.{
        .{ .id = c.Id.parse("S01").?, .form_bytes = "first form", .evidence = recorded.appended[0] },
        .{ .id = c.Id.parse("S02").?, .form_bytes = "cancel form", .evidence = recorded.appended[1] },
    });
    const next = accepted.state.value.?;
    try std.testing.expectEqual(c.EngineStatus.resolved_by_user, next.records[0].status);
    try std.testing.expectEqual(c.EngineStatus.cancelled_by_user, next.records[1].status);
    try std.testing.expectEqual(c.EngineStatus.open, next.records[2].status);
    try std.testing.expectEqualStrings("No longer needed.", next.responses[1].answer.cancel_reason);
    try std.testing.expectEqualStrings("cancel form", next.responses[1].submitted_form_bytes);
    try evidence.validateJoin(recorded.registry, next);
    // The run is cancelled by a cancel it accepted, and by no other: not by closed forms alone, and not by a cancel an earlier
    // run accepted, which no longer awaits an account.
    try std.testing.expect(acceptance.cancels(accepted, planned));
    try std.testing.expect(!acceptance.cancels(accepted, planned[0..1]));
    // The check action routes that one typed fact: the run ends `cancelled` for it and continues otherwise.
    const check: @import("actions/clarification/check_clarification_cancellation.zig").Action = .{};
    try std.testing.expectEqual(@as(@import("domain/workflow.zig").OutcomeTag, .cancelled), check.execute(accepted, .{ .pending = planned, .observations = &.{} }));
    try std.testing.expectEqual(@as(@import("domain/workflow.zig").OutcomeTag, .ok), check.execute(accepted, .{ .pending = planned[0..1], .observations = &.{} }));
    try std.testing.expectEqual(@as(@import("domain/workflow.zig").OutcomeTag, .ok), check.execute(inputs, .{ .pending = planned, .observations = &.{} }));
    try std.testing.expect(!acceptance.cancels(accepted, &.{}));
    try std.testing.expect(!acceptance.cancels(inputs, planned));
    try std.testing.expectEqual(@as(usize, 0), (try acceptance.pending(a, accepted)).len);
    const only_closed = try acceptance.accept(a, inputsOf(state, submissions[0..1]), &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "first form", .evidence = recorded.appended[0] }});
    try std.testing.expect(!acceptance.cancels(only_closed, planned[0..1]));
    // A cancel whose reason is no cancel reason is not accepted.
    const bad = [_]c.Submission{submission(state.records[0], .cancel, .{ .business_text = "stop" })};
    try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, inputsOf(state, &bad), &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = recorded.appended[0] }}));
}

test "acceptance rejects a form that was not authenticated for this run" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const state = try openState(a, 3);
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{authentication("ada")});
    const proof = recorded.appended[0];
    var withdrawn = submission(state.records[2], .cancel, .{ .cancel_reason = "stop" });
    withdrawn.origin = .recorded;
    const submissions = [_]c.Submission{ closed(state.records[0]), submission(state.records[1], .open, .{ .defer_reason = "later" }), withdrawn };
    const inputs = inputsOf(state, &submissions);
    const unchanged = try acceptance.accept(a, inputs, &.{});
    try std.testing.expectEqual(inputs.submissions.ptr, unchanged.submissions.ptr);
    // A defer stays open, a form already recorded takes no second authentication, an unknown form was never submitted.
    for ([_][]const u8{ "S02", "S03", "S09" }) |id| {
        try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, inputs, &.{.{ .id = c.Id.parse(id).?, .form_bytes = "form", .evidence = proof }}));
    }
    // One form is accepted once.
    try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, inputs, &.{
        .{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof },
        .{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof },
    }));
    // No prior state, so no record to resolve.
    try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, .{ .state = .{ .value = null }, .submissions = &submissions, .protected_forms = &.{} }, &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof }}));
    // A record that is already resolved takes no second response.
    const accepted = try acceptance.accept(a, inputs, &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof }});
    var again = closed(accepted.state.value.?.records[0]);
    try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, inputsOf(accepted.state.value.?, &.{again}), &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof }}));
    again.origin = .recorded;
    try std.testing.expectError(error.InvalidClarificationInput, acceptance.accept(a, inputsOf(accepted.state.value.?, &.{again}), &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = proof }}));
}

test "a response joins its evidence by identity, account and time and no entry is joined twice" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const state = try openState(a, 2);
    const submissions = [_]c.Submission{ closed(state.records[0]), closed(state.records[1]) };
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{ authentication("ada"), authentication("ada") });
    const accepted = try acceptance.accept(a, inputsOf(state, &submissions), &.{
        .{ .id = c.Id.parse("S01").?, .form_bytes = "first", .evidence = recorded.appended[0] },
        .{ .id = c.Id.parse("S02").?, .form_bytes = "second", .evidence = recorded.appended[1] },
    });
    const next = accepted.state.value.?;
    try evidence.validateJoin(recorded.registry, next);
    try evidence.validateJoin(evidence.empty(selected()), try openState(a, 1));
    // An entry no response names is tolerated.
    const extra = try evidence.record(a, recorded.registry, &.{authentication("ada")});
    try evidence.validateJoin(extra.registry, next);
    for (0..5) |scenario| {
        var registry = recorded.registry;
        const entries = try a.dupe(evidence.Evidence, registry.entries);
        const responses = try a.dupe(c.Response, next.responses);
        var state_copy = next;
        switch (scenario) {
            0 => registry = evidence.empty(selected()),
            1 => entries[1].actor_id = "eve",
            2 => entries[0].occurred_at = "2026-11-23T08:16:00Z",
            3 => responses[1].authentication_evidence_id = "AE-1",
            4 => responses[0].authentication_evidence_id = "fixture-auth-1",
            else => unreachable,
        }
        if (scenario != 0) registry.entries = entries;
        state_copy.responses = responses;
        try std.testing.expectError(error.InvalidActorEvidence, evidence.validateJoin(registry, state_copy));
    }
}

/// Reports cancelled from its `cancel_at`-th status check on.
const Countdown = struct {
    checks: usize = 0,
    cancel_at: usize = std.math.maxInt(usize),
    fn runtime(self: *Countdown) pipeline.NodeRuntime {
        return .{ .context = self, .status_fn = status };
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Countdown = @ptrCast(@alignCast(context.?));
        self.checks += 1;
        return if (self.checks >= self.cancel_at) .cancelled else .active;
    }
};

var capability_storage: u8 = 0;
fn inputCapability() *const roots.FeatureInputReadCapability {
    return @ptrCast(&capability_storage);
}

/// The registry file's source: its bytes, or none published, or an unreadable one.
const FakeSource = struct {
    bytes: ?[]const u8 = null,
    fail: bool = false,
    reads: usize = 0,

    fn capturer(self: *FakeSource) source_port.Capturer {
        return .{ .context = self, .capability = inputCapability(), .capture_fn = capture };
    }
    fn capture(context: *anyopaque, _: *const roots.FeatureInputReadCapability, allocator: std.mem.Allocator, _: feature_directory.Directory, _: artifacts.FeaturePaths) source_port.Error!?[]const u8 {
        const self: *FakeSource = @ptrCast(@alignCast(context));
        self.reads += 1;
        if (self.fail) return error.FeatureInputUnavailable;
        return try allocator.dupe(u8, self.bytes orelse return null);
    }
};

const feature_roots: artifacts.FeatureRoots = .{ .specs = "requirements/current", .archive = "requirements/current/archive", .workflows = "engine/flows" };

fn observedDirectory() feature_directory.Directory {
    return .{ .selector = .{ .feature_id = selected(), .project_relative_path = "requirements/current/Chosen/Café" }, .root_observation = .absent, .observation = .absent };
}

/// One resolved form and the registry that holds its evidence: the state a feature holds after a run accepted the answer.
const Held = struct { inputs: c.Inputs, registry: evidence.Registry };

fn heldAfterAcceptance(a: std.mem.Allocator) !Held {
    const open = try openState(a, 1);
    const recorded = try evidence.record(a, evidence.empty(selected()), &.{authentication("ada")});
    const inputs = try acceptance.accept(a, inputsOf(open, &.{closed(open.records[0])}), &.{.{ .id = c.Id.parse("S01").?, .form_bytes = "form", .evidence = recorded.appended[0] }});
    return .{ .inputs = inputs, .registry = recorded.registry };
}

fn expectPrepareStops(action: prepare_stage.Action, inputs: c.Inputs, step: prepare_stage.Step, expected: prepare_stage.Error) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const observed = observedDirectory();
    const paths = try artifacts.resolveFeaturePaths(arena.allocator(), feature_roots, observed.selector);
    var diagnostic: prepare_stage.Diagnostic = .{};
    try std.testing.expectError(expected, action.execute(arena.allocator(), .{}, &diagnostic, observed, paths, inputs));
    try std.testing.expectEqual(@as(?prepare_stage.Step, step), diagnostic.step);
}

test "the prepare stage reads the feature's registry, or the empty one, and joins it to the clarification state" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const observed = observedDirectory();
    const paths = try artifacts.resolveFeaturePaths(a, feature_roots, observed.selector);
    var diagnostic: prepare_stage.Diagnostic = .{};
    // A feature that published no registry has the empty one at revision 0, and no bytes were captured.
    var nothing: FakeSource = .{};
    const first = try (prepare_stage.Action{ .source = nothing.capturer(), .parser = evidence_parser.parser() }).execute(a, .{}, &diagnostic, observed, paths, inputsOf(try openState(a, 1), &.{}));
    try std.testing.expectEqual(@as(?[]const u8, null), first.capture);
    try std.testing.expectEqual(@as(u64, 0), first.registry.revision);
    try std.testing.expectEqual(@as(usize, 1), nothing.reads);
    try std.testing.expectEqual(@as(?prepare_stage.Step, null), diagnostic.step);
    // A published registry comes back as captured and joins the responses the state holds.
    const held = try heldAfterAcceptance(a);
    const published = try evidence.encode(a, held.registry);
    var present: FakeSource = .{ .bytes = published };
    const second = try (prepare_stage.Action{ .source = present.capturer(), .parser = evidence_parser.parser() }).execute(a, .{}, &diagnostic, observed, paths, held.inputs);
    try std.testing.expectEqualStrings(published, second.capture.?);
    try std.testing.expectEqual(@as(u64, 1), second.registry.revision);
    try std.testing.expectEqual(@as(usize, 1), second.registry.entries.len);
}

test "a failure in each prepare step names that step and propagates the step's own error" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try heldAfterAcceptance(a);
    const parser = evidence_parser.parser();
    var unreadable: FakeSource = .{ .fail = true };
    try expectPrepareStops(.{ .source = unreadable.capturer(), .parser = parser }, held.inputs, .capture_registry, error.FeatureInputUnavailable);
    try expectPrepareStops(.{ .source = null, .parser = parser }, held.inputs, .capture_registry, error.FeatureInputUnavailable);
    var malformed: FakeSource = .{ .bytes = "not a registry" };
    try expectPrepareStops(.{ .source = malformed.capturer(), .parser = parser }, held.inputs, .parse_registry, error.InvalidActorEvidence);
    // Another feature's registry, and a registry that holds none of the evidence a response names, fail validation.
    var foreign: FakeSource = .{ .bytes = try evidence.encode(a, evidence.empty(feature.FeatureId.parse("Another/Feature").?)) };
    try expectPrepareStops(.{ .source = foreign.capturer(), .parser = parser }, held.inputs, .validate_registry, error.InvalidActorEvidence);
    var missing: FakeSource = .{ .bytes = try evidence.encode(a, evidence.empty(selected())) };
    try expectPrepareStops(.{ .source = missing.capturer(), .parser = parser }, held.inputs, .validate_registry, error.InvalidActorEvidence);
    // The same registry joins a state that holds no response: an unjoined entry is tolerated, an unjoined response is not.
    var present: FakeSource = .{ .bytes = try evidence.encode(a, held.registry) };
    var diagnostic: prepare_stage.Diagnostic = .{};
    const observed = observedDirectory();
    const paths = try artifacts.resolveFeaturePaths(a, feature_roots, observed.selector);
    _ = try (prepare_stage.Action{ .source = present.capturer(), .parser = parser }).execute(a, .{}, &diagnostic, observed, paths, inputsOf(try openState(a, 1), &.{}));
}

test "cancellation is checked before every prepare step and stops before the next" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const observed = observedDirectory();
    const paths = try artifacts.resolveFeaturePaths(a, feature_roots, observed.selector);
    const steps_count = @typeInfo(prepare_stage.Step).@"enum".fields.len;
    for (1..steps_count + 1) |cancel_at| {
        var source: FakeSource = .{ .bytes = try evidence.encode(a, evidence.empty(selected())) };
        var countdown: Countdown = .{ .cancel_at = cancel_at };
        var diagnostic: prepare_stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, (prepare_stage.Action{ .source = source.capturer(), .parser = evidence_parser.parser() }).execute(a, countdown.runtime(), &diagnostic, observed, paths, inputsOf(try openState(a, 1), &.{})));
        try std.testing.expectEqual(@as(?prepare_stage.Step, @enumFromInt(cancel_at - 1)), diagnostic.step);
        // Only the capture reads the file, and it ran only when the stage was not cancelled before it.
        try std.testing.expectEqual(@as(usize, if (cancel_at > 1) 1 else 0), source.reads);
    }
}

/// Two closed forms and one deferred form, with the observations the loop made for the two closed ones.
fn authenticatedForms(a: std.mem.Allocator) !struct { inputs: c.Inputs, captures: c.Captures, progress: authenticating.Progress } {
    const state = try openState(a, 3);
    const submissions = try a.dupe(c.Submission, &.{ closed(state.records[0]), closed(state.records[1]), submission(state.records[2], .open, .{ .defer_reason = "later" }) });
    const inputs = inputsOf(state, submissions);
    const forms = try a.dupe(c.FormCapture, &.{ .{ .id = c.Id.parse("S01").?, .bytes = "first form" }, .{ .id = c.Id.parse("S02").?, .bytes = "second form" } });
    var progress = try authenticating.plan(a, inputs);
    progress = try authenticating.advance(a, progress, observation("ada"));
    progress = try authenticating.advance(a, progress, observation("ada"));
    return .{ .inputs = inputs, .captures = .{ .state = null, .forms = forms }, .progress = progress };
}

test "the accept stage pairs each authenticated form with its bytes, records the evidence and accepts the responses" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try authenticatedForms(a);
    var diagnostic: accept_stage.Diagnostic = .{};
    const outputs = try (accept_stage.Action{}).execute(a, .{}, &diagnostic, held.inputs, held.captures, evidence.empty(selected()), held.progress);
    try std.testing.expectEqual(@as(?accept_stage.Step, null), diagnostic.step);
    const next = outputs.inputs.state.value.?;
    try std.testing.expectEqual(@as(usize, 2), next.responses.len);
    try std.testing.expectEqualStrings("first form", next.responses[0].submitted_form_bytes);
    try std.testing.expectEqualStrings("second form", next.responses[1].submitted_form_bytes);
    try std.testing.expectEqual(@as(u64, 1), outputs.registry.revision);
    try std.testing.expectEqual(@as(usize, 2), outputs.registry.entries.len);
    try evidence.validateJoin(outputs.registry, next);
    // The deferred form stays open and unanswered.
    try std.testing.expectEqual(c.EngineStatus.open, next.records[2].status);
    // A run with no form to authenticate returns its inputs and registry as they were.
    const none = try authenticating.plan(a, inputsOf(held.inputs.state.value.?, &.{}));
    const unchanged = try (accept_stage.Action{}).execute(a, .{}, &diagnostic, inputsOf(held.inputs.state.value.?, &.{}), held.captures, evidence.empty(selected()), none);
    try std.testing.expectEqual(@as(u64, 0), unchanged.registry.revision);
    try std.testing.expectEqual(@as(usize, 0), unchanged.registry.entries.len);
    try std.testing.expectEqual(held.inputs.state.value.?.revision, unchanged.inputs.state.value.?.revision);
}

fn expectAcceptStops(inputs: c.Inputs, captures: c.Captures, progress: authenticating.Progress, step: accept_stage.Step, expected: accept_stage.Error) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diagnostic: accept_stage.Diagnostic = .{};
    try std.testing.expectError(expected, (accept_stage.Action{}).execute(arena.allocator(), .{}, &diagnostic, inputs, captures, evidence.empty(selected()), progress));
    try std.testing.expectEqual(@as(?accept_stage.Step, step), diagnostic.step);
}

test "a failure in each accept step names that step and accepts nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try authenticatedForms(a);
    const pending = held.progress.pending;
    const observations = held.progress.observations;
    // The loop must have authenticated exactly the pending forms, each once, in their order.
    try expectAcceptStops(held.inputs, held.captures, .{ .pending = pending, .observations = observations[0..1] }, .bind_forms, error.InvalidClarificationInput);
    try expectAcceptStops(held.inputs, held.captures, .{ .pending = pending[0..1], .observations = observations[0..1] }, .bind_forms, error.InvalidClarificationInput);
    try expectAcceptStops(held.inputs, held.captures, .{ .pending = &.{ pending[1], pending[0] }, .observations = observations }, .bind_forms, error.InvalidClarificationInput);
    // Every authenticated form needs the bytes that were captured for it.
    try expectAcceptStops(held.inputs, .{ .state = null, .forms = held.captures.forms[0..1] }, held.progress, .bind_forms, error.InvalidClarificationInput);
    // An account the registry cannot name is not recorded, so no form is accepted.
    const nameless = try a.dupe(evidence.Observation, observations);
    nameless[1].actor_id = "ada lovelace";
    try expectAcceptStops(held.inputs, held.captures, .{ .pending = pending, .observations = nameless }, .record_evidence, error.UnsupportedActorName);
    // A form that is already resolved is no longer pending, so an observation for it is stopped at the binding, however
    // the loop came by it.
    const resolved = try heldAfterAcceptance(a);
    const open = try openState(a, 1);
    var again = try authenticating.plan(a, inputsOf(open, &.{closed(open.records[0])}));
    again = try authenticating.advance(a, again, observation("ada"));
    try expectAcceptStops(resolved.inputs, .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = "form" }} }, again, .bind_forms, error.InvalidClarificationInput);
    // A submission whose record is no longer open is not accepted, whatever its state says it is.
    var settled = try openState(a, 1);
    const settled_records = try a.dupe(c.Record, settled.records);
    settled_records[0].status = .resolved_by_user;
    settled_records[0].response_id = 1;
    settled.records = settled_records;
    var settled_progress = try authenticating.plan(a, inputsOf(settled, &.{closed(settled_records[0])}));
    settled_progress = try authenticating.advance(a, settled_progress, observation("ada"));
    try expectAcceptStops(inputsOf(settled, &.{closed(settled_records[0])}), .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = "form" }} }, settled_progress, .accept_responses, error.InvalidClarificationInput);
    // Responses that do not join the registry stop the stage after acceptance: an earlier response names evidence by another
    // account, and the new entry takes that evidence's ordinal.
    const joined = try openState(a, 2);
    const joined_records = try a.dupe(c.Record, joined.records);
    joined_records[0].status = .resolved_by_user;
    joined_records[0].response_id = 1;
    joined_records[0].revision = 2;
    var with_response = joined;
    with_response.records = joined_records;
    with_response.state_ordinal = 2;
    with_response.revision = 2;
    with_response.next_response_ordinal = 2;
    with_response.responses = &.{.{
        .id = 1,
        .clarification_id = "S01",
        .input_state_ordinal = 1,
        .input_state_revision = 1,
        .input_record_revision = 1,
        .submitted_form_bytes = "earlier form",
        .answer = .{ .business_text = "Earlier answer." },
        .actor_id = "eve",
        .authentication_evidence_id = "AE-1",
        .answered_at = "2026-11-23T08:15:00Z",
    }};
    const next_submissions = [_]c.Submission{closed(joined_records[1])};
    var unjoined = try authenticating.plan(a, inputsOf(with_response, &next_submissions));
    unjoined = try authenticating.advance(a, unjoined, observation("ada"));
    try expectAcceptStops(inputsOf(with_response, &next_submissions), .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S02").?, .bytes = "form" }} }, unjoined, .validate_responses, error.InvalidActorEvidence);
}

fn prepareStageUnderFailure(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try heldAfterAcceptance(a);
    var source: FakeSource = .{ .bytes = try evidence.encode(a, held.registry) };
    const observed = observedDirectory();
    const paths = try artifacts.resolveFeaturePaths(a, feature_roots, observed.selector);
    var diagnostic: prepare_stage.Diagnostic = .{};
    // An allocation failure in a step is that step's own, and propagates as the same error.
    _ = (prepare_stage.Action{ .source = source.capturer(), .parser = evidence_parser.parser() }).execute(a, .{}, &diagnostic, observed, paths, held.inputs) catch |err| {
        try std.testing.expectEqual(error.OutOfMemory, err);
        try std.testing.expect(diagnostic.step != null);
        return err;
    };
}

fn acceptStageUnderFailure(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try authenticatedForms(a);
    var diagnostic: accept_stage.Diagnostic = .{};
    _ = (accept_stage.Action{}).execute(a, .{}, &diagnostic, held.inputs, held.captures, evidence.empty(selected()), held.progress) catch |err| {
        try std.testing.expectEqual(error.OutOfMemory, err);
        try std.testing.expect(diagnostic.step != null);
        return err;
    };
}

test "an allocation failure in either stage propagates as itself, names its step and leaks nothing" {
    const untraced = @import("test_fixtures/untraced_allocator.zig");
    try untraced.checkAllAllocationFailures(prepareStageUnderFailure, .{});
    try untraced.checkAllAllocationFailures(acceptStageUnderFailure, .{});
}

test "the accepted responses must join the registry that holds their evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try authenticatedForms(a);
    const bound = try accept_stage.steps.bindForms(a, held.inputs, held.captures, held.progress);
    try std.testing.expectEqual(@as(usize, 2), bound.forms.len);
    try std.testing.expectEqualStrings("second form", bound.forms[1]);
    const recorded = try accept_stage.steps.recordEvidence(a, evidence.empty(selected()), held.progress);
    const accepted = try accept_stage.steps.acceptResponses(a, held.inputs, held.progress, bound, recorded);
    try accept_stage.steps.validateResponses(recorded.registry, accepted);
    try std.testing.expectError(error.InvalidActorEvidence, accept_stage.steps.validateResponses(evidence.empty(selected()), accepted));
    // Nothing accepted, nothing to join.
    try accept_stage.steps.validateResponses(evidence.empty(selected()), .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} });
}

test "cancellation is checked before every accept step and stops before the next" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const held = try authenticatedForms(a);
    const steps_count = @typeInfo(accept_stage.Step).@"enum".fields.len;
    for (1..steps_count + 1) |cancel_at| {
        var countdown: Countdown = .{ .cancel_at = cancel_at };
        var diagnostic: accept_stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, (accept_stage.Action{}).execute(a, countdown.runtime(), &diagnostic, held.inputs, held.captures, evidence.empty(selected()), held.progress));
        try std.testing.expectEqual(@as(?accept_stage.Step, @enumFromInt(cancel_at - 1)), diagnostic.step);
        try std.testing.expectEqual(cancel_at, countdown.checks);
    }
}
