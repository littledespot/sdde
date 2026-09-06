const std = @import("std");
const a = @import("domain/required_authority.zig");
const build: @import("actions/authority/build_required_authority_ledger.zig").Action = .{};
const reconcile: @import("actions/authority/reconcile_required_authorities.zig").Action = .{};
const validate: @import("actions/authority/validate_required_authority_reconciliation.zig").Action = .{};
const parse: @import("actions/authority/parse_required_authority_observations.zig").Action = .{};
const source: a.Authority = .{ .canonical = .{ .kind = .specification, .ordinal = 1, .revision = 1 } };
const sources = [_]a.Authority{source};
const candidate: a.CandidateId = .{ .ordinal = 1, .revision = 1 };
const kinds = [_]a.Kind{ .feature_intent, .entity_applicability, .design_decision, .executable_decomposition, .policy_predicate };

test {
    _ = @import("required_authority_workflow_test.zig");
}

fn id(kind: a.Kind) a.Id {
    return .{ .kind = kind, .unit = switch (kind) {
        .feature_intent, .entity_applicability => .{ .feature = .singleton },
        else => .{ .decision = .{ .ordinal = 1 } },
    }, .slot = switch (kind) {
        .feature_intent => .display_name,
        .entity_applicability => .entities,
        .policy_predicate => .compliance,
        else => .decision,
    } };
}
pub fn fixture(allocator: std.mem.Allocator, kind: a.Kind) !a.Inputs {
    const seeds = try allocator.alloc(a.Seed, 1);
    seeds[0] = .{ .id = id(kind), .input_authorities = &sources, .requiredness = switch (kind) {
        .feature_intent, .entity_applicability => .{ .schema = .specification },
        .design_decision => .{ .policy = .design },
        .executable_decomposition => .{ .policy = .decomposition },
        .policy_predicate => .{ .policy = .compliance },
        else => unreachable,
    } };
    const evidence = try allocator.alloc(a.Evidence, 1);
    evidence[0] = .{ .id = .{ .ordinal = 1 }, .requirement = seeds[0].id, .authorities = &sources, .resolution = .{ .supported_candidate = candidate }, .finding = .supported, .method = .model_assisted };
    const candidates = try allocator.alloc(a.Candidate, 1);
    candidates[0] = .{ .id = candidate, .requirement = seeds[0].id };
    return .{ .feature = .{ .bytes = "hello-world" }, .detected_at = .spec, .authorities = &sources, .seeds = seeds, .evidence = evidence, .candidates = candidates };
}
pub fn observe(allocator: std.mem.Allocator, inputs: a.Inputs) !a.Observations {
    const entries = try allocator.alloc(a.Observation, inputs.seeds.len);
    for (inputs.seeds, entries) |seed, *entry| {
        var evidence: std.ArrayList(a.EvidenceId) = .empty;
        for (inputs.evidence) |item| if (std.meta.eql(item.requirement, seed.id)) {
            try evidence.append(allocator, item.id);
        };
        entry.* = .{ .requirement = seed.id, .inspected_authorities = seed.input_authorities, .evidence_ids = try evidence.toOwnedSlice(allocator) };
    }
    return .{ .entries = entries };
}
fn run(allocator: std.mem.Allocator, inputs: a.Inputs) !a.Result {
    return reconcile.execute(allocator, try build.execute(allocator, inputs), try observe(allocator, inputs));
}

test "required authority uses one policy across unrelated kinds and cannot infer support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (kinds) |kind| {
        var inputs = try fixture(allocator, kind);
        const result = try run(allocator, inputs);
        try std.testing.expectEqual(.all_resolved, result.continuation);
        try std.testing.expect(try validate.execute(allocator, inputs, try observe(allocator, inputs), result));
        inputs.evidence = &.{};
        try std.testing.expectEqual(.needs_user, (try run(allocator, inputs)).continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, validate.execute(allocator, inputs, try observe(allocator, inputs), result));
    }
}

test "complete one-to-one observations reject missing duplicate foreign and omitted authority or evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (kinds) |kind| {
        const inputs = try fixture(allocator, kind);
        const ledger = try build.execute(allocator, inputs);
        const good = (try observe(allocator, inputs)).entries[0];
        try std.testing.expectError(error.InvalidRequiredAuthority, reconcile.execute(allocator, ledger, .{ .entries = &.{} }));
        try std.testing.expectError(error.InvalidRequiredAuthority, reconcile.execute(allocator, ledger, .{ .entries = &.{ good, good } }));
        for (0..5) |scenario| {
            var bad = good;
            switch (scenario) {
                0 => bad.requirement.member = 999,
                1 => bad.inspected_authorities = &.{},
                2 => bad.evidence_ids = &.{},
                3 => bad.evidence_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 1 } },
                4 => bad.evidence_ids = &.{.{ .ordinal = 99 }},
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidRequiredAuthority, reconcile.execute(allocator, ledger, .{ .entries = &.{bad} }));
        }
    }
}

test "uncertainty stale unsupported and non-equivalent evidence never becomes success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (kinds) |kind| for (0..8) |scenario| {
        var inputs = try fixture(allocator, kind);
        const evidence = try allocator.dupe(a.Evidence, inputs.evidence);
        inputs.evidence = evidence;
        switch (scenario) {
            0 => evidence[0].finding = .ambiguous,
            1 => evidence[0].finding = .conflicting,
            2 => evidence[0].finding = .unsupported,
            3 => evidence[0].authorities = &.{},
            4 => inputs.authorities = &.{.{ .canonical = .{ .kind = .specification, .ordinal = 1, .revision = 2 } }},
            5 => {
                const changed = try allocator.dupe(a.Candidate, inputs.candidates);
                changed[0].id.revision = 2;
                inputs.candidates = changed;
            },
            6 => evidence[0].authorities = &.{.{ .canonical = .{ .kind = .plan, .ordinal = 999, .revision = 1 } }},
            7 => {
                const both = try allocator.alloc(a.Evidence, 2);
                both[0] = evidence[0];
                both[1] = evidence[0];
                both[1].id.ordinal = 2;
                both[1].resolution = .{ .existing_authority = source };
                inputs.evidence = both;
            },
            else => unreachable,
        }
        try std.testing.expectEqual(.needs_user, (try run(allocator, inputs)).continuation);
    };
}

test "directly equivalent candidates retain every member and cannot hide alternatives" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var inputs = try fixture(allocator, .feature_intent);
    const both = try allocator.alloc(a.Evidence, 2);
    both[0] = inputs.evidence[0];
    both[1] = inputs.evidence[0];
    both[1].id.ordinal = 2;
    inputs.evidence = both;
    const result = try run(allocator, inputs);
    try std.testing.expectEqual(.all_resolved, result.continuation);
    try std.testing.expectEqual(@as(usize, 2), result.entries[0].evidence_ids.len);
    var observation = (try observe(allocator, inputs)).entries[0];
    observation.evidence_ids = observation.evidence_ids[0..1];
    try std.testing.expectError(error.InvalidRequiredAuthority, reconcile.execute(allocator, try build.execute(allocator, inputs), .{ .entries = &.{observation} }));
}

test "registry owns allowed non-applicability and exact authenticated exception scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (kinds) |kind| {
        var inputs = try fixture(allocator, kind);
        const evidence = try allocator.dupe(a.Evidence, inputs.evidence);
        inputs.evidence = evidence;
        evidence[0].resolution = .{ .not_applicable = .no_business_data };
        try std.testing.expectEqual(@as(@FieldType(a.Result, "continuation"), if (kind == .entity_applicability) .all_resolved else .needs_user), (try run(allocator, inputs)).continuation);
        evidence[0].resolution = .{ .exception = .{ .ordinal = 1 } };
        const exceptions = try allocator.alloc(a.Exception, 1);
        exceptions[0] = .{ .id = .{ .ordinal = 1 }, .requirement = id(kind), .authority = source, .authenticated_actor_ordinal = 1 };
        inputs.exceptions = exceptions;
        try std.testing.expectEqual(@as(@FieldType(a.Result, "continuation"), if (kind == .policy_predicate) .all_resolved else .blocked), (try run(allocator, inputs)).continuation);
        exceptions[0].authenticated_actor_ordinal = 0;
        try std.testing.expectEqual(.blocked, (try run(allocator, inputs)).continuation);
    }
}

test "earliest owner is immutable at downstream discovery and unknown combinations block" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for (kinds) |kind| {
        var inputs = try fixture(allocator, kind);
        inputs.evidence = &.{};
        inputs.detected_at = .implement;
        const result = try run(allocator, inputs);
        try std.testing.expectEqual(.blocked, result.continuation);
        try std.testing.expectEqual(a.policy(id(kind)).?.owner, result.entries[0].outcome.upstream_rework_required.owner);
    }
    var inputs = try fixture(allocator, .feature_intent);
    const seeds = try allocator.dupe(a.Seed, inputs.seeds);
    seeds[0].id.slot = .compliance;
    inputs.seeds = seeds;
    inputs.evidence = &.{};
    inputs.candidates = &.{};
    try std.testing.expectEqual(.administrative_block, std.meta.activeTag((try run(allocator, inputs)).entries[0].outcome));
}

test "closed observation parser rejects scores ownership and resolution assertions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = try parse.execute(allocator, "{\"entries\":[]}");
    for ([_][]const u8{ "{}", "{\"entries\":[],\"score\":100}", "{\"entries\":[],\"passed\":true}", "{\"entries\":[],\"owner\":\"plan\"}", "{\"entries\":[],\"entries\":[]}", "{\"entries\":[],\"resolution\":\"supported\"}" }) |bytes| try std.testing.expectError(error.InvalidRequiredAuthority, parse.execute(allocator, bytes));
}

test "Specify projects registered native fields and complete reference obligations without invented counts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{"Display `Hello, World!`.\n"});
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = try f.finish(allocator, final, try f.global(allocator, final), reference.context());
    const project: @import("actions/authority/build_specification_authority_requirements.zig").Action = .{};
    const before = try project.execute(allocator, .{ .bytes = "hello-world" }, accounted, null);
    try std.testing.expectEqual(@as(usize, 6), before.seeds.len); // Three mandatory slots, two signals, one exact value.
    try std.testing.expectEqual(.needs_user, (try run(allocator, before)).continuation);
    try std.testing.expectEqualStrings("Hello, World!", before.references.?.records.assignments.checked.prior.prior.input.progress.plan.layout.items.entries[1].claim.content.preserved_token.value.raw_value.bytes);
    const spec = @import("domain/specification.zig");
    const value: spec.BusinessValue = .{ .normalized = .{ .segments = &.{.{ .literal = .{ .value = "Supported business value" } }} } };
    const provenance: spec.Provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} };
    const attributed: spec.AttributedValue = .{ .value = value, .provenance = provenance };
    var content: spec.IdentifiedContent = .{ .display_name = attributed, .primary_user_story = attributed, .entities = .{ .disposition = .not_applicable, .basis = attributed }, .records = &.{} };
    const empty = try project.execute(allocator, before.feature, accounted, content);
    try std.testing.expectEqual(before.seeds.len, empty.seeds.len);
    const records = try allocator.alloc(spec.IdentifiedRecord, @typeInfo(spec.Kind).@"enum".fields.len);
    inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
        var fields: @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) = undefined;
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(fields, field.name) = if (field.type == spec.BusinessValue) value else &.{ value, value };
        }
        records[index] = .{ .id = .{ .kind = kind, .ordinal = 1 }, .proposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .provenance = provenance } };
    }
    content.records = records;
    const after = try project.execute(allocator, before.feature, accounted, content);
    try std.testing.expectEqual(before.seeds.len + 15, after.seeds.len);
    const ledger = try build.execute(allocator, after);
    try std.testing.expectEqual(after.seeds.len, ledger.requirements.len);
    for (ledger.requirements) |requirement| try std.testing.expectEqual(.spec, requirement.registered_policy.?.owner);
    var omitted = after;
    omitted.seeds = after.seeds[1..];
    try std.testing.expectError(error.InvalidRequiredAuthority, build.execute(allocator, omitted));
    var invented = after;
    const more = try allocator.alloc(a.Seed, after.seeds.len + 1);
    @memcpy(more[0..after.seeds.len], after.seeds);
    more[after.seeds.len] = more[0];
    invented.seeds = more;
    try std.testing.expectError(error.InvalidRequiredAuthority, build.execute(allocator, invented));
}

test "reference support must name current accounted signals with no foreign or duplicate members" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{"Display the catalogue.\n"});
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = try f.finish(allocator, final, try f.global(allocator, final), reference.context());
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "catalogue" }, accounted, null);
    const evidence = try allocator.alloc(a.Evidence, inputs.seeds.len);
    for (inputs.seeds, evidence, 0..) |seed, *entry, index| entry.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .requirement = seed.id, .authorities = inputs.authorities, .resolution = .{ .existing_authority = inputs.authorities[0] }, .finding = .supported, .method = .model_assisted };
    inputs.evidence = evidence;
    const support: std.meta.Elem(@FieldType(a.Evidence, "reference_support")) = .{ .signal = accounted.records.signals[0].id };
    evidence[0].reference_support = &.{support};
    try std.testing.expectEqual(.all_resolved, (try run(allocator, inputs)).continuation);
    evidence[0].reference_support = &.{ support, support };
    try std.testing.expectError(error.InvalidRequiredAuthority, run(allocator, inputs));
    evidence[0].reference_support = &.{.{ .signal = .{ .ordinal = 999 } }};
    try std.testing.expectError(error.InvalidRequiredAuthority, run(allocator, inputs));
    evidence[0].reference_support = &.{.{ .conflict = .{ .ordinal = 999 } }};
    try std.testing.expectError(error.InvalidRequiredAuthority, run(allocator, inputs));
    evidence[0].reference_support = &.{support};
    evidence[0].authorities = &.{};
    try std.testing.expectEqual(.needs_user, (try run(allocator, inputs)).continuation);
}

test "reference conflicts cannot be dropped or resolved by supplied evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = try f.finish(allocator, final, try @import("reference_reconciliation_test.zig").conflicting(allocator, final), reference.context());
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "library" }, accounted, null);
    try std.testing.expectEqual(@as(usize, 1), inputs.forced_gaps.len);
    const evidence = try allocator.alloc(a.Evidence, inputs.seeds.len);
    for (inputs.seeds, evidence, 0..) |seed, *entry, index| entry.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .requirement = seed.id, .authorities = inputs.authorities, .resolution = .{ .existing_authority = inputs.authorities[0] }, .finding = .supported, .method = .model_assisted };
    inputs.evidence = evidence;
    const result = try run(allocator, inputs);
    try std.testing.expectEqual(.needs_user, result.continuation);
    const conflict = for (result.entries) |entry| {
        if (entry.requirement.unit == .conflict) break entry;
    } else return error.ExpectedConflict;
    try std.testing.expectEqual(.conflicting, conflict.outcome.clarification_required.reason);
    try std.testing.expectEqualDeep(accounted.records.conflicts[0].value.citation_ids, inputs.references.?.records.conflicts[0].value.citation_ids);
    evidence[0].reference_support = &.{.{ .conflict = accounted.records.conflicts[0].id }};
    const with_conflicting_support = try run(allocator, inputs);
    try std.testing.expectEqual(evidence[0].requirement, with_conflicting_support.entries[0].requirement);
    try std.testing.expectEqual(.conflicting, with_conflicting_support.entries[0].outcome.clarification_required.reason);
    inputs.detected_at = .plan;
    try std.testing.expectEqual(.blocked, (try run(allocator, inputs)).continuation);
    inputs.forced_gaps = &.{};
    try std.testing.expectError(error.InvalidRequiredAuthority, build.execute(allocator, inputs));
}

test "result identity scope cardinality and equivalent membership are rechecked against current inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try fixture(allocator, .feature_intent);
    const observations = try observe(allocator, inputs);
    const result = try run(allocator, inputs);
    for (0..6) |scenario| {
        var wrong = result;
        const entries = try allocator.dupe(a.Entry, result.entries);
        wrong.entries = entries;
        switch (scenario) {
            0 => wrong.entries = &.{},
            1 => wrong.entries = &.{ entries[0], entries[0] },
            2 => wrong.feature.bytes = "another-feature",
            3 => entries[0].evidence_ids = &.{},
            4 => entries[0].outcome = .{ .resolved_explicit_not_applicable = .no_business_data },
            5 => entries[0].requirement.contract_version = 2,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidRequiredAuthority, validate.execute(allocator, inputs, observations, wrong));
    }
}

test "authority projection parsing and validation release every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const source_inputs = try fixture(arena.allocator(), .design_decision);
    const observed = try observe(arena.allocator(), source_inputs);
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), observed, .{});
    const parsed = try parse.execute(arena.allocator(), bytes);
    const result = try reconcile.execute(arena.allocator(), try build.execute(arena.allocator(), source_inputs), parsed);
    try std.testing.expect(try validate.execute(arena.allocator(), source_inputs, parsed, result));
}
