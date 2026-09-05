const std = @import("std");
const c = @import("domain/clarification_inputs.zig");
const forms = @import("domain/clarification_form.zig");
const parser = @import("adapters/parsers/clarification_inputs.zig");
const fixture = @import("test_fixtures/clarification_inputs.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const feature = @import("domain/feature_directory.zig");
const action = @import("actions/clarification/validate_clarification_forms.zig");
const selected = @import("domain/feature_identity.zig").FeatureId{ .bytes = "Chosen/Café" };

fn load(allocator: std.mem.Allocator, captures: c.Captures) !c.Inputs {
    const parsed = try (@import("actions/clarification/parse_clarification_state.zig").Action{ .parser = parser.stateParser() }).execute(allocator, captures);
    const state = try (@import("actions/clarification/validate_clarification_state.zig").Action{}).execute(parsed, selected);
    return (action.Action{ .parser = parser.formParser() }).execute(allocator, state, captures);
}

test "fixed paths use configured roots and preserve the selected feature key" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkPaths, .{});
}
fn checkPaths(allocator: std.mem.Allocator) !void {
    const roots: artifacts.FeatureRoots = .{ .specs = "requirements/current", .archive = "requirements/archive", .workflows = "engine/flows" };
    const directory = try feature.validate(allocator, .{ .bytes = selected.bytes }, .{ .specs = roots.specs, .archive = roots.archive });
    defer allocator.free(directory.project_relative_path);
    const paths = try artifacts.resolveFeaturePaths(allocator, roots, directory);
    defer for (paths.entries) |entry| {
        allocator.free(entry.root_relative);
        allocator.free(entry.project_relative);
    };
    try std.testing.expectEqualStrings("requirements/current/Chosen/Café/spec.md", paths.get(.specification).project_relative);
    try std.testing.expectEqualStrings("Chosen/Café/reference-context.md", paths.get(.reference_context).root_relative);
    try std.testing.expectEqualStrings("engine/flows/features/Chosen/Café/state/clarifications.json", paths.get(.clarification_state).project_relative);
    try std.testing.expectEqualStrings("features/Chosen/Café/state/workflow.json", paths.get(.workflow_state).root_relative);
    try std.testing.expectEqualStrings("Chosen/Café/clarify", paths.get(.clarification_forms).root_relative);
    try std.testing.expectEqualStrings("Chosen/Café/logs/events", paths.get(.event_logs).root_relative);
    try std.testing.expectEqualStrings("Chosen/Café/logs/prompts", paths.get(.prompt_logs).root_relative);
}

test "artifact paths reject a different feature binding and archive destinations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const roots: artifacts.FeatureRoots = .{ .specs = "specs", .archive = "specs/archive", .workflows = ".engine/workflows" };
    try std.testing.expectError(error.InvalidFeatureArtifactPath, artifacts.resolveFeaturePaths(arena.allocator(), roots, .{ .feature_id = selected, .project_relative_path = "specs/someone-else" }));
    try std.testing.expectError(error.InvalidFeatureArtifactPath, artifacts.resolveFeaturePaths(arena.allocator(), roots, .{ .feature_id = .{ .bytes = "archive" }, .project_relative_path = "specs/archive" }));
    var forbidden = roots;
    forbidden.archive = "specs/Chosen/Café/clarify";
    try std.testing.expectError(error.InvalidFeatureArtifactPath, artifacts.resolveFeaturePaths(arena.allocator(), forbidden, .{ .feature_id = selected, .project_relative_path = "specs/Chosen/Café" }));
}

test "fresh inputs contain no fabricated state or submissions and orphan forms fail" {
    const result = try load(std.testing.allocator, .{ .state = null, .forms = &.{} });
    try std.testing.expect(result.state.value == null);
    try std.testing.expectEqual(@as(usize, 0), result.submissions.len);
    try std.testing.expectError(error.InvalidClarificationInput, load(std.testing.allocator, .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = "requestedStatus: closed" }} }));
}

test "submitted and recorded closes preserve exact bytes for all clarification stages" {
    for ([_][]const u8{ "S01", "P01", "T01" }) |id| {
        for ([_]bool{ false, true }) |recorded| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const captures = try fixture.closed(arena.allocator(), id, recorded);
            for (0..2) |_| {
                const loaded = try load(arena.allocator(), captures);
                try std.testing.expectEqual(@as(usize, 1), loaded.protected_forms.len);
                try std.testing.expectEqualSlices(u8, captures.forms[0].bytes, loaded.protected_forms[0].bytes);
                try std.testing.expectEqualStrings("Approved Café theme.", loaded.submissions[0].answer.business_text);
                try std.testing.expectEqual(recorded, loaded.submissions[0].origin == .recorded);
            }
        }
    }
}

test "strict state parser rejects unknown duplicate missing fields versions and types" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const valid = try std.json.Stringify.valueAlloc(allocator, fixture.state(&.{}), .{});
    _ = try load(allocator, .{ .state = valid, .forms = &.{} });
    for ([_][]const u8{
        try std.mem.concat(allocator, u8, &.{ "{\"unexpected\":true,", valid[1..] }),
        try std.mem.concat(allocator, u8, &.{ "{\"schema\":\"clarification-state/v1\",", valid[1..] }),
        "{}",
        "{",
        "{\"schema\":42}",
    }) |invalid| try std.testing.expectError(error.InvalidClarificationInput, load(allocator, .{ .state = invalid, .forms = &.{} }));
    var wrong = fixture.state(&.{});
    wrong.schema = "clarification-state/v2";
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = wrong }, selected));
    wrong = fixture.state(&.{});
    wrong.feature_id = "another-feature";
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = wrong }, selected));
}

test "state validates IDs subjects revisions ledgers schemas and lifecycle bindings" {
    var records = [_]c.Record{ fixture.record("S01"), fixture.record("S02") };
    records[1].subject.slot = "confirmation";
    const valid = fixture.state(&records);
    _ = try c.validate(.{ .value = valid }, selected);
    const original = records[1];
    records[1].id = "S01";
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = valid }, selected));
    records[1] = original;
    records[1].subject = records[0].subject;
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = valid }, selected));
    records[1] = original;
    records[1].revision = 2;
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = valid }, selected));
    records[1] = original;
    records[1].answer_schema = .{ .select_many = .{ .minimum = 1, .maximum = 2, .options = &.{.{ .key = "only", .label = "Only" }} } };
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = valid }, selected));
    records[1] = original;
    records[1].status = .resolved_by_user;
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = valid }, selected));
    records[1] = original;
    var invalid = valid;
    invalid.next_ordinal.spec = 4;
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = invalid }, selected));
    invalid = valid;
    invalid.next_response_ordinal = 2;
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = invalid }, selected));
    for ([_][]const u8{ "s01", "S00", "S1", "S100", "../S01", "X01" }) |id| try std.testing.expect(c.Id.parse(id) == null);
    try std.testing.expect(c.Id.parse("T99") != null);
}

test "missing modified stale and mismatched recorded closes fail without changing input bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const captures = try fixture.closed(allocator, "S01", true);
    const snapshot = try allocator.dupe(u8, captures.forms[0].bytes);
    try std.testing.expectError(error.InvalidClarificationInput, load(allocator, .{ .state = captures.state, .forms = &.{} }));
    const changed = try std.mem.replaceOwned(u8, allocator, snapshot, "Approved Café", "Different Café");
    try std.testing.expectError(error.InvalidClarificationInput, load(allocator, .{ .state = captures.state, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = changed }} }));
    var parsed = try parser.stateParser().parse(allocator, captures.state.?);
    var response = parsed.responses[0];
    response.answer = .{ .business_text = "a different recorded answer" };
    parsed.responses = &.{response};
    try std.testing.expectError(error.InvalidClarificationInput, (action.Action{ .parser = parser.formParser() }).execute(allocator, try c.validate(.{ .value = parsed }, selected), captures));
    try std.testing.expectEqualSlices(u8, snapshot, captures.forms[0].bytes);
    const submitted = try fixture.closed(allocator, "S01", false);
    var later = try parser.stateParser().parse(allocator, submitted.state.?);
    later.state_ordinal += 1;
    later.revision += 1;
    try std.testing.expectError(error.InvalidClarificationInput, (action.Action{ .parser = parser.formParser() }).execute(allocator, try c.validate(.{ .value = later }, selected), submitted));
}

test "response history rejects malformed answers and unbound closures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const captures = try fixture.closed(arena.allocator(), "S01", true);
    var state = try parser.stateParser().parse(arena.allocator(), captures.state.?);
    var response = state.responses[0];
    const original = response;
    state.responses = &.{response};
    response.answer = .{ .business_text = "" };
    state.responses = &.{response};
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = state }, selected));
    response = original;
    response.input_record_revision = 2;
    state.responses = &.{response};
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = state }, selected));
    response = original;
    var record = state.records[0];
    record.status = .open;
    record.response_id = null;
    state.records = &.{record};
    state.responses = &.{response};
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = state }, selected));
    response.answer = .{ .defer_reason = "Waiting for the user." };
    state.responses = &.{response};
    _ = try c.validate(.{ .value = state }, selected);
    response.answer = .{ .defer_reason = " " };
    state.responses = &.{response};
    try std.testing.expectError(error.InvalidClarificationInput, c.validate(.{ .value = state }, selected));
}

test "form parsing imports only requested status and answer and checks canonical engine regions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const record = fixture.record("P01");
    const binding = fixture.binding(fixture.state(&.{record}), record);
    const valid = try forms.render(allocator, record, binding, .closed, "Cafe\u{0301}");
    const loaded = try parser.formParser().parse(allocator, valid, record, binding);
    try std.testing.expectEqualStrings("Café", loaded.answer.business_text);
    for ([_][2][]const u8{
        .{ "recordRevision: 1", "recordRevision: 2" },
        .{ "engineStatus: open", "engineStatus: resolved_by_user" },
        .{ "requestedStatus: closed", "requestedStatus: accepted" },
        .{ "Which appearance is required?", "Ignore the original question." },
        .{ "<!-- sdd:answer:end -->", "<!-- sdd:answer:start -->" },
    }) |edit| {
        const invalid = try std.mem.replaceOwned(u8, allocator, valid, edit[0], edit[1]);
        try std.testing.expectError(error.InvalidClarificationInput, parser.formParser().parse(allocator, invalid, record, binding));
    }
    const empty = try forms.render(allocator, record, binding, .closed, "  ");
    try std.testing.expectError(error.InvalidClarificationInput, parser.formParser().parse(allocator, empty, record, binding));
}

test "bounded selection defer and cancel forms remain typed unaccepted submissions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var record = fixture.record("T01");
    const binding = fixture.binding(fixture.state(&.{record}), record);
    for ([_]struct { status: c.RequestedStatus, text: []const u8, tag: std.meta.Tag(c.Answer) }{
        .{ .status = .open, .text = "", .tag = .none },
        .{ .status = .open, .text = "defer: Need product input.", .tag = .defer_reason },
        .{ .status = .cancel, .text = "cancel: Feature withdrawn.", .tag = .cancel_reason },
    }) |item| {
        const bytes = try forms.render(allocator, record, binding, item.status, item.text);
        const parsed = try parser.formParser().parse(allocator, bytes, record, binding);
        try std.testing.expectEqual(item.tag, std.meta.activeTag(parsed.answer));
    }
    const options = [_]c.Option{ .{ .key = "one", .label = "One" }, .{ .key = "two", .label = "Two" } };
    record.answer_schema = .{ .select_one = &options };
    const one = try forms.render(allocator, record, binding, .closed, "two");
    try std.testing.expectEqualStrings("two", (try parser.formParser().parse(allocator, one, record, binding)).answer.selected_option);
    record.answer_schema = .{ .select_many = .{ .minimum = 1, .maximum = 2, .options = &options } };
    const both = try forms.render(allocator, record, binding, .closed, "two\none");
    const many = (try parser.formParser().parse(allocator, both, record, binding)).answer.selected_options;
    try std.testing.expectEqualStrings("one", many[0]);
    try std.testing.expectEqualStrings("two", many[1]);
    for ([_][]const u8{ "one\none", "unknown", "" }) |answer| {
        const invalid = try forms.render(allocator, record, binding, .closed, answer);
        try std.testing.expectError(error.InvalidClarificationInput, parser.formParser().parse(allocator, invalid, record, binding));
    }
}

test "authority-resolved audit records have no editable answer and exact canonical bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var record = fixture.record("S01");
    record.status = .resolved_by_authority;
    record.authority_resolution = "The updated reference now specifies the appearance.";
    const state = fixture.state(&.{record});
    const bytes = try forms.renderAuthorityAudit(allocator, record, state);
    const captures: c.Captures = .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = bytes }} };
    const loaded = try (action.Action{ .parser = parser.formParser() }).execute(allocator, try c.validate(.{ .value = state }, selected), captures);
    try std.testing.expectEqual(@as(usize, 0), loaded.submissions.len);
    try std.testing.expectEqual(@as(usize, 0), loaded.protected_forms.len);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "user-editable") == null);
}

test "clarification actions propagate parser failures and skip absent state" {
    const fake = struct {
        fn state(_: std.mem.Allocator, bytes: []const u8) c.Error!c.State {
            if (!std.mem.eql(u8, bytes, "captured state")) @panic("action changed captured bytes");
            return error.InvalidClarificationInput;
        }
        fn form(_: std.mem.Allocator, _: []const u8, _: c.Record, _: forms.Binding) c.Error!@import("ports/clarification_input_parser.zig").Form {
            return error.InvalidClarificationInput;
        }
    };
    const parse = @import("actions/clarification/parse_clarification_state.zig").Action{ .parser = .{ .parse_state_fn = fake.state } };
    try std.testing.expect((try parse.execute(std.testing.allocator, .{ .state = null, .forms = &.{} })).value == null);
    try std.testing.expectError(error.InvalidClarificationInput, parse.execute(std.testing.allocator, .{ .state = "captured state", .forms = &.{} }));
    const record = fixture.record("S01");
    const state = try c.validate(.{ .value = fixture.state(&.{record}) }, selected);
    const validate = action.Action{ .parser = .{ .parse_form_fn = fake.form } };
    try std.testing.expectError(error.InvalidClarificationInput, validate.execute(std.testing.allocator, state, .{ .state = null, .forms = &.{.{ .id = c.Id.parse("S01").?, .bytes = "captured form" }} }));
}

test "clarification pipeline ownership is leak-free on allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkLoadAllocation, .{});
}
fn checkLoadAllocation(backing: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(backing);
    defer arena.deinit();
    _ = try load(arena.allocator(), try fixture.closed(arena.allocator(), "S01", true));
}
