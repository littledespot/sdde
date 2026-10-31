const std = @import("std");
const packet_guidance = @import("test_fixtures/packet_guidance.zig");
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

fn clarificationSources(allocator: std.mem.Allocator) !@import("domain/reference_evidence.zig").Inputs {
    var identities: @import("reference_evidence_test.zig").IdSource = .{};
    const captured = try @import("reference_ingestion_test.zig").read(allocator, "delivery.md", "Deliver a confirmation; its deadline and delivery mechanism are undecided.\n");
    return @import("reference_evidence_test.zig").prepare(allocator, &identities, captured);
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
    const accounted = (try f.finish(allocator, final, try f.global(allocator, final), reference.context())).valid;
    const project: @import("actions/authority/build_specification_authority_requirements.zig").Action = .{};
    const before = try project.execute(allocator, .{ .bytes = "hello-world" }, accounted, null, null);
    try std.testing.expectEqual(@as(usize, 11), before.seeds.len); // Eight mandatory slots, two signals, one exact value.
    try std.testing.expectEqual(.needs_user, (try run(allocator, before)).continuation);
    try std.testing.expectEqualStrings("Hello, World!", before.references.?.items.entries[1].claim.content.preserved_token.value.raw_value.bytes);
    const spec = @import("domain/specification.zig");
    const value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Supported business value" } }} };
    const provenance: spec.Provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} };
    const attributed: spec.AttributedValue = .{ .value = value, .source_group_ids = &.{accounted.records.signals[0].id}, .provenance = provenance };
    const brief: spec.Brief = .{ .title = attributed, .description = attributed, .primary_goal = attributed };
    var content: spec.IdentifiedContent = .{ .display_name = attributed, .primary_user_story = attributed, .entities = .{ .disposition = .not_applicable, .basis = attributed }, .records = &.{} };
    try std.testing.expectEqual(.source_readiness, before.projection);
    try std.testing.expectError(error.InvalidRequiredAuthority, project.execute(allocator, before.feature, accounted, content, null));
    const empty = try project.execute(allocator, before.feature, accounted, content, brief);
    try std.testing.expectEqual(.specification, empty.projection);
    try std.testing.expectEqual(before.seeds.len, empty.seeds.len);
    const records = try allocator.alloc(spec.IdentifiedRecord, @typeInfo(spec.Kind).@"enum".fields.len);
    inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
        var fields: @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) = undefined;
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(fields, field.name) = if (field.type == spec.BusinessValue) value else &.{ value, value };
        }
        records[index] = .{ .id = .{ .kind = kind, .ordinal = 1 }, .proposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .source_group_ids = attributed.source_group_ids, .provenance = provenance } };
    }
    content.records = records;
    const after = try project.execute(allocator, before.feature, accounted, content, brief);
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

test "record purposes place workflow guidance in native record frames" {
    const spec = @import("domain/specification.zig");
    const descriptions = @import("domain/required_authority_description.zig");
    const keys = @import("domain/packet_guidance.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const g = &packet_guidance.marked;
    const catalogue = try descriptions.records(allocator, g);
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        const family = descriptions.recordFamily(g, kind);
        try std.testing.expectEqualStrings(g.record_families.get(kind), family);
        var expected_record: std.ArrayList(u8) = .empty;
        try expected_record.print(allocator, "{s}: {s}", .{ @tagName(kind), family });
        inline for (std.meta.fields(@FieldType(spec.Content(spec.BusinessValue), @tagName(kind)))) |field| {
            const slot: a.Slot = @field(a.Slot, if (std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name);
            const purpose = try descriptions.recordField(g, kind, slot);
            try std.testing.expectEqualStrings(if (slot == .text) family else g.record_fields.get(keys.recordField(slot).?), purpose);
            if (slot != .text) try expected_record.print(allocator, " {s}: {s}", .{ field.name, purpose });
            const selected: a.Id = .{ .kind = .feature_intent, .unit = .{ .record = .{ .kind = kind, .ordinal = 3 } }, .slot = slot, .member = if (slot == .relationship) 2 else 0 };
            const task = try descriptions.task(allocator, g, selected);
            try std.testing.expectEqualStrings(if (slot == .text)
                try std.fmt.allocPrint(allocator, "{s}.text: {s}", .{ @tagName(kind), family })
            else
                try std.fmt.allocPrint(allocator, "{s}: {s} {s}: {s}", .{ @tagName(kind), family, @tagName(slot), purpose }), task);
            try std.testing.expectEqualStrings(try descriptions.recordTask(allocator, g, kind, slot), task);
            try std.testing.expectEqual(.spec, a.policy(selected).?.owner);
        }
        const record = try descriptions.record(allocator, g, kind);
        try std.testing.expectEqualStrings(expected_record.items, record);
        try std.testing.expect(std.mem.indexOf(u8, catalogue, record) != null);
        try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.recordField(g, kind, .display_name));
    }
    try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.recordField(g, .functional_requirement, .given));
    try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.recordField(g, .entity, .text));
    try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.task(allocator, g, .{ .kind = .feature_intent, .unit = .{ .record = .{ .kind = .assumption, .ordinal = 1 } }, .slot = .when }));
    // Distinct text-only families keep distinct shipped definitions.
    const shipped = &(try packet_guidance.shipped(allocator)).guidance;
    const text_kinds = [_]spec.Kind{ .user_visible_outcome, .functional_requirement, .business_rule, .assumption, .non_goal, .prohibited_behavior };
    for (text_kinds, 0..) |kind, index| {
        for (text_kinds[0..index]) |prior| try std.testing.expect(!std.mem.eql(u8, try descriptions.recordField(shipped, kind, .text), try descriptions.recordField(shipped, prior, .text)));
    }
}

test "feature and reference tasks place workflow guidance at native frames" {
    const descriptions = @import("domain/required_authority_description.zig");
    const keys = @import("domain/packet_guidance.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const g = &packet_guidance.marked;
    for (std.enums.values(a.Slot)) |slot| {
        const kind: a.Kind = if (slot == .entities) .entity_applicability else .feature_intent;
        const feature: a.Id = .{ .kind = kind, .unit = .{ .feature = .singleton }, .slot = slot };
        if (keys.featurePurpose(slot)) |purpose| {
            try std.testing.expectEqualStrings(g.feature_purposes.get(purpose), try descriptions.task(allocator, g, feature));
        } else if (@import("domain/specification_authority.zig").collectionFamily(slot)) |family| {
            try std.testing.expectEqualStrings(g.record_families.get(family), try descriptions.task(allocator, g, feature));
        } else try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.task(allocator, g, feature));
    }
    const references = [_]a.Id{
        .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 7 } }, .slot = .disposition },
        .{ .kind = .reference_meaning, .unit = .{ .signal = .{ .ordinal = 7 } }, .slot = .disposition },
        .{ .kind = .reference_meaning, .unit = .{ .conflict = .{ .ordinal = 7 } }, .slot = .disposition },
        .{ .kind = .preservation, .unit = .{ .token = .{ .ordinal = 7 } }, .slot = .value },
    };
    for (references) |reference| {
        const fragments = g.reference_tasks.get(std.meta.stringToEnum(keys.ReferenceUnit, @tagName(reference.unit)).?);
        const task = try descriptions.task(allocator, g, reference);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(allocator, "{s}7{s}", .{ fragments.before, fragments.after }), task);
        // A non-feature clarification question embeds exactly that task.
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, try descriptions.question(allocator, g, reference), task));
    }
    // Decision identities remain a native frame with no guidance entry.
    try std.testing.expectEqualStrings("design_decision decision 2.", try descriptions.task(allocator, g, .{ .kind = .design_decision, .unit = .{ .decision = .{ .ordinal = 2 } }, .slot = .decision }));
}

test "reference support must name current accounted signals with no foreign or duplicate members" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{"Display the catalogue.\n"});
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try f.global(allocator, final), reference.context())).valid;
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "catalogue" }, accounted, null, null);
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
    const accounted = (try f.finish(allocator, final, try @import("reference_reconciliation_test.zig").conflicting(allocator, final), reference.context())).valid;
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "library" }, accounted, null, null);
    try std.testing.expectEqual(@as(usize, 1), inputs.forced_gaps.len);
    const evidence = try allocator.alloc(a.Evidence, inputs.seeds.len);
    for (inputs.seeds, evidence, 0..) |seed, *entry, index| entry.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .requirement = seed.id, .authorities = inputs.authorities, .resolution = .{ .existing_authority = inputs.authorities[0] }, .finding = .supported, .method = .model_assisted };
    inputs.evidence = evidence;
    const result = try run(allocator, inputs);
    try std.testing.expectEqual(.invalid, result.continuation);
    const conflict = for (result.entries) |entry| {
        if (entry.requirement.unit == .conflict) break entry;
    } else return error.ExpectedConflict;
    try std.testing.expect(conflict.candidate_defect != null);
    try std.testing.expectEqual(.resolved_exactly_one, std.meta.activeTag(conflict.outcome));
    try std.testing.expectEqualDeep(accounted.records.conflicts[0].value.citation_ids, inputs.references.?.conflicts[0].value.citation_ids);
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
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
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

test "source-backed omissions stay invalid across registered owners and source gaps never authorize repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for ([_]a.Kind{ .feature_intent, .design_decision, .executable_decomposition }) |kind| {
        var inputs = try fixture(allocator, kind);
        const proofs = try allocator.dupe(a.Evidence, inputs.evidence);
        proofs[0].finding = .candidate_omission;
        proofs[0].resolution = .{ .existing_authority = source };
        inputs.evidence = proofs;
        inputs.forced_gaps = &.{.{ .requirement = id(kind), .reason = .missing, .subject = .candidate }};
        const observations = try observe(allocator, inputs);
        const result = try run(allocator, inputs);
        try std.testing.expectEqual(.invalid, result.continuation);
        try std.testing.expect(result.entries[0].outcome == .resolved_exactly_one);
        try std.testing.expect((try a.supportedOmission(allocator, inputs, observations, result, id(kind))) != null);
        try std.testing.expect(!try a.validate(allocator, inputs, observations, result));
        // Positive review cannot fill missing mandatory content or authorize a
        // speculative repair without an independently identified omission.
        proofs[0].finding = .supported;
        const empty = try run(allocator, inputs);
        try std.testing.expectEqual(.invalid, empty.continuation);
        try std.testing.expect((try a.supportedOmission(allocator, inputs, observations, empty, id(kind))) == null);
        for ([_]a.Finding{ .unsupported, .ambiguous, .conflicting }) |finding| {
            proofs[0].finding = finding;
            const gap = try run(allocator, inputs);
            try std.testing.expectEqual(.invalid, gap.continuation);
            try std.testing.expect((try a.supportedOmission(allocator, inputs, observations, gap, id(kind))) == null);
        }
        proofs[0].finding = .candidate_omission;
        inputs.authorities = &.{};
        const stale = try run(allocator, inputs);
        try std.testing.expectEqual(.invalid, stale.continuation);
        try std.testing.expect((try a.supportedOmission(allocator, inputs, observations, stale, id(kind))) == null);
    }
}

test "invalid candidate content retains genuine authority gaps without authorizing omission repair or clarification" {
    const needs = @import("domain/required_authority_clarifications.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source_inputs = try clarificationSources(allocator);
    for ([_]a.Kind{ .feature_intent, .entity_applicability }) |kind| {
        var inputs = try fixture(allocator, kind);
        inputs.feature = source_inputs.corpus.feature_id;
        var proof = inputs.evidence[0];
        proof.finding = .candidate_invalid;
        proof.resolution = .{ .existing_authority = source };
        proof.review = .{
            .detail = "MOCK candidate invents an additional approval requirement.",
            .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} },
            .source_ids = &.{.{ .ordinal = 1 }},
        };
        for ([_]?a.AuthorityGap.GapKind{ null, .unsupported, .ambiguous, .conflicting }) |gap_kind| {
            proof.review.?.authority_gap = if (gap_kind) |selected| .{
                .kind = selected,
                .source_ids = &.{},
                .detail = "MOCK source leaves the delivery deadline unresolved.",
                .question = "MOCK which delivery deadline applies? Supply the date and timezone.",
            } else null;
            inputs.evidence = &.{proof};
            const observations = try observe(allocator, inputs);
            const result = try run(allocator, inputs);
            try std.testing.expectEqual(.invalid, result.continuation);
            const entry = result.entries[0];
            try std.testing.expectEqual(.invalid_content, entry.candidate_defect.?.reason);
            try std.testing.expect(entry.candidate_defect.?.support == null);
            if (gap_kind) |selected| {
                try std.testing.expectEqual(@as(a.GapReason, switch (selected) {
                    .unsupported => .unsupported,
                    .ambiguous => .ambiguous,
                    .conflicting => .conflicting,
                }), entry.outcome.clarification_required.reason);
                try std.testing.expectEqualStrings("MOCK which delivery deadline applies? Supply the date and timezone.", inputs.evidence[0].review.?.authority_gap.?.question);
            } else try std.testing.expectEqual(.resolved_exactly_one, std.meta.activeTag(entry.outcome));
            try std.testing.expect(!try a.validate(allocator, inputs, observations, result));
            try std.testing.expect((try a.supportedOmission(allocator, inputs, observations, result, id(kind))) == null);
            try std.testing.expectError(error.InvalidRequiredAuthority, needs.build(allocator, source_inputs, inputs, observations, result, &packet_guidance.marked));
            // Persisting a separately supported omission cannot turn the invalid
            // assertion into authorized omission recovery.
            var omission = proof;
            omission.id.ordinal = 2;
            omission.finding = .candidate_omission;
            omission.review.?.authority_gap = null;
            for ([_]bool{ false, true }) |reverse| {
                inputs.evidence = if (reverse) &.{ omission, proof } else &.{ proof, omission };
                const both = try run(allocator, inputs);
                try std.testing.expectEqual(.invalid_content, both.entries[0].candidate_defect.?.reason);
                try std.testing.expect((try a.supportedOmission(allocator, inputs, try observe(allocator, inputs), both, id(kind))) == null);
            }
        }
    }
}

test "authority clarification subjects preserve earliest owner and remain stable across finding order and wording" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const refresh = @import("domain/clarification_refresh.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source_inputs = try clarificationSources(allocator);
    const one = try fixture(allocator, .feature_intent);
    const two = try fixture(allocator, .design_decision);
    var inputs = one;
    inputs.feature = source_inputs.corpus.feature_id;
    inputs.detected_at = .tasks;
    inputs.seeds = try allocator.dupe(a.Seed, &.{ one.seeds[0], two.seeds[0] });
    const proofs = try allocator.dupe(a.Evidence, &.{ one.evidence[0], two.evidence[0] });
    proofs[1].id.ordinal = 2;
    for (proofs) |*proof| {
        proof.finding = .ambiguous;
        proof.resolution = .{ .existing_authority = source };
        proof.review = .{ .question = "Which delivery deadline applies? Supply the date and timezone.", .detail = "The source provides no delivery deadline.", .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{} };
    }
    proofs[1].review.?.question = "Which delivery mechanism should implement the deadline? Name the mechanism.";
    inputs.evidence = proofs;
    inputs.candidates = &.{};
    const needs = try conversion.build(allocator, source_inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    try std.testing.expectEqual(@as(usize, 2), needs.entries.len);
    try std.testing.expectEqual(.spec, needs.entries[0].stage);
    try std.testing.expectEqual(.plan, needs.entries[1].stage);
    try std.testing.expect(!std.mem.eql(u8, needs.entries[0].question, needs.entries[1].question));
    for (needs.entries) |need| {
        try std.testing.expectEqualStrings("The source provides no delivery deadline.", need.why_required);
        try std.testing.expect(!std.mem.eql(u8, need.question, need.why_required));
    }
    const c = @import("domain/clarification_inputs.zig");
    const first = try refresh.refresh(allocator, .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} }, needs);
    const changed = try allocator.dupe(a.Evidence, &.{ proofs[1], proofs[0] });
    changed[0].review.?.detail = "Specify the applicable delivery deadline.";
    inputs.evidence = changed;
    const again = try conversion.build(allocator, source_inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    const second = try refresh.refresh(allocator, .{ .state = .{ .value = first.state.value }, .submissions = &.{}, .protected_forms = &.{} }, again);
    for (first.state.value.?.records, second.state.value.?.records) |before, after| {
        try std.testing.expect(c.sameSubject(before.subject, after.subject));
        try std.testing.expectEqualStrings(before.id, after.id);
    }
    try std.testing.expectError(error.ProtectedClarification, refresh.refresh(allocator, .{ .state = .{ .value = first.state.value }, .submissions = &.{}, .protected_forms = &.{.{ .id = c.Id.parse(first.state.value.?.records[0].id).?, .bytes = "protected" }} }, again));
}

test "current contradictory assessments fail while genuine missing decisions retain their questions" {
    const needs = @import("domain/required_authority_clarifications.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source_inputs = try clarificationSources(allocator);
    for ([_]a.Kind{ .feature_intent, .design_decision, .executable_decomposition }) |kind| {
        var inputs = try fixture(allocator, kind);
        inputs.feature = source_inputs.corpus.feature_id;
        var negative = inputs.evidence[0];
        negative.finding = .unsupported;
        negative.resolution = .{ .existing_authority = source };
        negative.method = .model_assisted;
        negative.review = .{ .detail = "The action is supported but its deadline is absent.", .question = "When is the deadline? Supply a date and timezone.", .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{} };
        inputs.evidence = &.{negative};
        const gap = try run(allocator, inputs);
        try std.testing.expectEqual(.needs_user, gap.continuation);
        _ = try needs.build(allocator, source_inputs, inputs, try observe(allocator, inputs), gap, &packet_guidance.marked);
        var positive = negative;
        positive.id.ordinal = 2;
        positive.finding = .supported;
        positive.review.?.question = null;
        positive.review.?.detail = "The same current source already supplies the deadline.";
        for ([_]bool{ false, true }) |reverse| {
            inputs.evidence = if (reverse) &.{ positive, negative } else &.{ negative, positive };
            const inconclusive = try run(allocator, inputs);
            try std.testing.expectEqual(.invalid, inconclusive.continuation);
            try std.testing.expectEqual(.inconclusive_review, inconclusive.entries[0].candidate_defect.?.reason);
            try std.testing.expectError(error.InvalidRequiredAuthority, needs.build(allocator, source_inputs, inputs, try observe(allocator, inputs), inconclusive, &packet_guidance.marked));
        }
        // A vague negative with no question cannot gain one from a descriptor.
        negative.review = null;
        inputs.evidence = &.{negative};
        try std.testing.expectError(error.InvalidRequiredAuthority, needs.build(allocator, source_inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked));
    }
}
