const std = @import("std");
const packet_guidance = @import("test_fixtures/packet_guidance.zig");
const a = @import("domain/required_authority.zig");
const build: @import("actions/authority/build_required_authority_ledger.zig").Action = .{};
const reconcile: @import("actions/authority/reconcile_required_authorities.zig").Action = .{};
const validate: @import("actions/authority/validate_required_authority_reconciliation.zig").Action = .{};
const source: a.Authority = .{ .canonical = .{ .kind = .specification, .ordinal = 1, .revision = 1 } };
const sources = [_]a.Authority{source};
const candidate: a.CandidateId = .{ .ordinal = 1, .revision = 1 };
const kinds = [_]a.Kind{ .feature_intent, .entity_applicability, .design_decision, .executable_decomposition, .policy_predicate };

test {
    _ = @import("required_authority_workflow_test.zig");
    _ = @import("clarification_resolution_test.zig");
    _ = @import("answered_reconciliation_test.zig");
}

fn id(kind: a.Kind) a.Id {
    return .{ .kind = kind, .unit = switch (kind) {
        .feature_intent, .entity_applicability => .{ .feature = .singleton },
        else => .{ .decision = .{ .ordinal = 1 } },
    }, .slot = switch (kind) {
        .feature_intent => .description,
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
                0 => bad.requirement.contract_version = a.version + 1,
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

test "a gap found after its owner's stage or in recovery is upstream rework, and one found earlier or at it is a clarification" {
    const Tag = std.meta.Tag(a.Outcome);
    for ([_]struct { stage: a.DetectionStage, owner: a.Stage, rework: bool }{
        .{ .stage = .spec, .owner = .spec, .rework = false },
        .{ .stage = .spec, .owner = .plan, .rework = false },
        .{ .stage = .spec, .owner = .tasks, .rework = false },
        .{ .stage = .plan, .owner = .spec, .rework = true },
        .{ .stage = .plan, .owner = .plan, .rework = false },
        .{ .stage = .plan, .owner = .tasks, .rework = false },
        .{ .stage = .tasks, .owner = .spec, .rework = true },
        .{ .stage = .tasks, .owner = .plan, .rework = true },
        .{ .stage = .tasks, .owner = .tasks, .rework = false },
        .{ .stage = .implement, .owner = .spec, .rework = true },
        .{ .stage = .implement, .owner = .plan, .rework = true },
        .{ .stage = .implement, .owner = .tasks, .rework = true },
        .{ .stage = .recovery, .owner = .spec, .rework = true },
        .{ .stage = .recovery, .owner = .plan, .rework = true },
        .{ .stage = .recovery, .owner = .tasks, .rework = true },
    }) |case| {
        const expected: Tag = if (case.rework) .upstream_rework_required else .clarification_required;
        try std.testing.expectEqual(expected, std.meta.activeTag(a.route(case.stage, case.owner, .missing)));
    }
    // An unregistered owner never routes, whatever stage found it.
    try std.testing.expectEqual(@as(Tag, .administrative_block), std.meta.activeTag(a.route(.spec, .spec, .unregistered_ownership_or_policy)));
}

fn expectDeclaredOrder(comptime E: type, expected: []const []const u8) !void {
    const names = std.meta.fieldNames(E);
    try std.testing.expectEqual(expected.len, names.len);
    for (names, expected) |name, want| try std.testing.expectEqualStrings(want, name);
}

test "the ledger's order is the declaration order of its enums, so reordering one is a deliberate contract change" {
    // Requirements sort by kind, unit, slot and contract version, and the stronger of two gaps wins by
    // order. The ledger index becomes a requirement's ordinal in the model's packet, so these orders are
    // part of the contract that `a.version` names.
    try expectDeclaredOrder(a.Kind, &.{ "feature_intent", "reference_meaning", "entity_applicability", "preservation", "design_decision", "executable_decomposition", "policy_predicate" });
    try expectDeclaredOrder(a.Slot, &.{ "description", "primary_goal", "acceptance_criteria", "functional_requirements", "scenario_coverage", "text", "given", "when", "then", "name", "entities", "disposition", "value", "decision", "compliance" });
    try expectDeclaredOrder(std.meta.Tag(a.Unit), &.{ "feature", "record", "source", "signal", "conflict", "token", "decision" });
    try expectDeclaredOrder(a.GapReason, &.{ "missing", "ambiguous", "conflicting", "multiple_non_equivalent", "stale", "unsupported", "unregistered_ownership_or_policy" });
    try expectDeclaredOrder(@import("domain/specification.zig").Kind, &.{ "acceptance_criterion", "user_visible_outcome", "edge_case", "functional_requirement", "business_rule", "assumption", "non_goal", "prohibited_behavior", "entity" });
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
    const before = try project.execute(allocator, .{ .bytes = "hello-world" }, accounted);
    // Six mandatory slots, two signals, one exact value. The engine composes the
    // story and takes the title from the sources, so source readiness has neither
    // subject (ADRs 0047 and 0048).
    try std.testing.expectEqual(@as(usize, 9), before.seeds.len);
    try std.testing.expect(!@hasField(a.Slot, "primary_user_story"));
    try std.testing.expect(!@hasField(a.Slot, "display_name"));
    // A requirement of the previous contract version has no policy.
    var previous = before.seeds[0].id;
    previous.contract_version = a.version - 1;
    try std.testing.expect(a.policy(previous) == null);
    try std.testing.expect(a.policy(before.seeds[0].id) != null);
    try std.testing.expectEqual(.needs_user, (try run(allocator, before)).continuation);
    try std.testing.expectEqualStrings("Hello, World!", before.references.?.items.entries[1].claim.content.preserved_token.value.raw_value.bytes);
    // Specify projects only source readiness: no generated content binds review
    // requirements after generation starts.
    try std.testing.expectEqual(.source_readiness, before.projection);
    for (before.seeds) |seed| try std.testing.expect(seed.id.unit != .record);
    const ledger = try build.execute(allocator, before);
    try std.testing.expectEqual(before.seeds.len, ledger.requirements.len);
    for (ledger.requirements) |requirement| try std.testing.expectEqual(.spec, requirement.registered_policy.?.owner);
    var omitted = before;
    omitted.seeds = before.seeds[1..];
    try std.testing.expectError(error.InvalidRequiredAuthority, build.execute(allocator, omitted));
    var invented = before;
    const more = try allocator.alloc(a.Seed, before.seeds.len + 1);
    @memcpy(more[0..before.seeds.len], before.seeds);
    more[before.seeds.len] = more[0];
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
            const slot: a.Slot = @field(a.Slot, field.name);
            const purpose = try descriptions.recordField(g, kind, slot);
            try std.testing.expectEqualStrings(if (slot == .text) family else g.record_fields.get(keys.recordField(slot).?), purpose);
            if (slot != .text) try expected_record.print(allocator, " {s}: {s}", .{ field.name, purpose });
            const selected: a.Id = .{ .kind = .feature_intent, .unit = .{ .record = .{ .kind = kind, .ordinal = 3 } }, .slot = slot };
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
        try std.testing.expectError(error.InvalidRequiredAuthority, descriptions.recordField(g, kind, .description));
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
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "catalogue" }, accounted);
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
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, .{ .bytes = "library" }, accounted);
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
            5 => entries[0].requirement.contract_version = a.version + 1,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidRequiredAuthority, validate.execute(allocator, inputs, observations, wrong));
    }
}

test "authority projection and validation release every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const source_inputs = try fixture(arena.allocator(), .design_decision);
    const observed = try observe(arena.allocator(), source_inputs);
    const result = try reconcile.execute(arena.allocator(), try build.execute(arena.allocator(), source_inputs), observed);
    try std.testing.expect(try validate.execute(arena.allocator(), source_inputs, observed, result));
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
    inputs.detected_at = .spec;
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
    // The same gaps found by a later stage are earlier owners' rework, which no form carries.
    var later = inputs;
    later.detected_at = .tasks;
    const rework = try run(allocator, later);
    try std.testing.expect(rework.entries[0].outcome == .upstream_rework_required);
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.build(allocator, source_inputs, later, try observe(allocator, later), rework, &packet_guidance.marked));
}

test "an authority subject names the source text its unit concerns, never a generated ordinal or the contract version" {
    const c = @import("domain/clarification_inputs.zig");
    const clarifications = @import("domain/required_authority_clarifications.zig");
    const support = @import("domain/reference_support.zig");
    const r = @import("domain/reference_reconciliation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Display `Hello, World!`.\n", "Renew a library loan.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try f.global(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const read = reference.inputs;
    const signal = struct {
        fn id(ordinal: u32) a.Id {
            return .{ .kind = .reference_meaning, .unit = .{ .signal = .{ .ordinal = ordinal } }, .slot = .disposition };
        }
    };
    // A signal names the lines its claims cite, and the kind alone, with no contract version, names its requirement.
    const first = try clarifications.subjectFor(allocator, read, held, signal.id(held.signals[0].id.ordinal));
    try std.testing.expectEqualStrings("reference_meaning", first.requirement);
    try std.testing.expectEqualStrings("signal", first.unit);
    try std.testing.expectEqualStrings("disposition", first.slot);
    try std.testing.expect(first.sources.len != 0 and c.validSources(first.sources));
    for (first.sources) |span| {
        var held_path = false;
        for (read.corpus.sources) |origin| held_path = held_path or std.mem.eql(u8, origin.path.bytes, span.path);
        try std.testing.expect(held_path and span.lines != null);
    }
    // Another run numbers the same claims differently and names the same subject; other claims name another.
    const renumbered = try allocator.dupe(r.Signal, held.signals);
    renumbered[0].id = .{ .ordinal = 77 };
    var regenerated = held;
    regenerated.signals = renumbered;
    const again = try clarifications.subjectFor(allocator, read, regenerated, signal.id(77));
    try std.testing.expect(c.sameSubject(first, again));
    const other = try clarifications.subjectFor(allocator, read, held, signal.id(held.signals[2].id.ordinal));
    try std.testing.expect(!c.sameSubject(first, other));
    // The subject is the lines, so a claim quoted from inside a sentence's line is the same subject as the sentence: the
    // builder consolidates gaps over them into one need (§12.7, §14.14), as its own test checks.
    const inside = try clarifications.subjectFor(allocator, read, held, signal.id(held.signals[1].id.ordinal));
    try std.testing.expect(c.sameSubject(first, inside));
    // A unit the evidence does not hold, or evidence that is absent, is no subject.
    try std.testing.expectError(error.InvalidRequiredAuthority, clarifications.subjectFor(allocator, read, held, signal.id(999)));
    try std.testing.expectError(error.InvalidRequiredAuthority, clarifications.subjectFor(allocator, read, null, signal.id(held.signals[0].id.ordinal)));
    // A token names the lines of its claim.
    const token_id = for (held.items.entries) |item| {
        if (item.claim.content == .preserved_token) break item.claim.content.preserved_token.value.id;
    } else return error.ExpectedToken;
    const token = try clarifications.subjectFor(allocator, read, held, .{ .kind = .preservation, .unit = .{ .token = token_id }, .slot = .value });
    try std.testing.expectEqualStrings("preservation", token.requirement);
    try std.testing.expectEqualStrings("token", token.unit);
    try std.testing.expect(token.sources.len == 1 and token.sources[0].lines.?.first == 1);
    // A whole source is named by its path, and a source the corpus lacks is no subject.
    const whole = try clarifications.subjectFor(allocator, read, null, .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 1 } }, .slot = .disposition });
    try std.testing.expectEqualStrings("source", whole.unit);
    try std.testing.expect(whole.sources.len == 1 and whole.sources[0].lines == null);
    try std.testing.expectEqualStrings(read.corpus.sources[0].path.bytes, whole.sources[0].path);
    try std.testing.expectError(error.InvalidRequiredAuthority, clarifications.subjectFor(allocator, read, null, .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 99 } }, .slot = .disposition }));
    // The feature has no source text, and a decision, owned by a workflow that does not exist yet, keeps its ordinal.
    const feature = try clarifications.subjectFor(allocator, read, null, id(.feature_intent));
    try std.testing.expectEqualStrings("feature", feature.unit);
    try std.testing.expectEqual(@as(usize, 0), feature.sources.len);
    const decision = try clarifications.subjectFor(allocator, read, null, id(.design_decision));
    try std.testing.expectEqualStrings("decision.1", decision.unit);
    try std.testing.expectEqual(@as(usize, 0), decision.sources.len);
}

test "a conflict's subject names the lines its claims cite in every source, whatever number the run gave it" {
    const c = @import("domain/clarification_inputs.zig");
    const clarifications = @import("domain/required_authority_clarifications.zig");
    const support = @import("domain/reference_support.zig");
    const r = @import("domain/reference_reconciliation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try @import("reference_reconciliation_test.zig").conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const requirement = struct {
        fn id(ordinal: u32) a.Id {
            return .{ .kind = .reference_meaning, .unit = .{ .conflict = .{ .ordinal = ordinal } }, .slot = .disposition };
        }
    };
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, requirement.id(held.conflicts[0].id.ordinal));
    try std.testing.expectEqualStrings("conflict", subject.unit);
    // The conflict sets one source against another, so its subject names both.
    try std.testing.expectEqual(@as(usize, 2), subject.sources.len);
    try std.testing.expect(c.validSources(subject.sources));
    const renumbered = try allocator.dupe(r.Conflict, held.conflicts);
    renumbered[0].id = .{ .ordinal = 41 };
    var regenerated = held;
    regenerated.conflicts = renumbered;
    try std.testing.expect(c.sameSubject(subject, try clarifications.subjectFor(allocator, reference.inputs, regenerated, requirement.id(41))));
    try std.testing.expectError(error.InvalidRequiredAuthority, clarifications.subjectFor(allocator, reference.inputs, held, requirement.id(999)));
}

test "two gaps owned by one stage become two needs and two open forms with distinct subjects" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const refresh = @import("domain/clarification_refresh.zig");
    const c = @import("domain/clarification_inputs.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source_inputs = try clarificationSources(allocator);
    const one = try fixture(allocator, .feature_intent);
    var inputs = one;
    inputs.feature = source_inputs.corpus.feature_id;
    inputs.detected_at = .spec;
    // The second requirement has the same owner stage and another slot, so its subject differs.
    var other = one.seeds[0];
    other.id.slot = .primary_goal;
    inputs.seeds = try allocator.dupe(a.Seed, &.{ one.seeds[0], other });
    const proofs = try allocator.dupe(a.Evidence, &.{ one.evidence[0], one.evidence[0] });
    proofs[1].id.ordinal = 2;
    proofs[1].requirement = other.id;
    for (proofs) |*proof| {
        proof.finding = .ambiguous;
        proof.resolution = .{ .existing_authority = source };
        proof.review = .{ .question = "Which delivery deadline applies? Supply the date and timezone.", .detail = "The source provides no delivery deadline.", .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{} };
    }
    proofs[1].review.?.question = "Which delivery mechanism applies? Name the mechanism.";
    inputs.evidence = proofs;
    inputs.candidates = &.{};
    const needs = try conversion.build(allocator, source_inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    try std.testing.expectEqual(@as(usize, 2), needs.entries.len);
    try std.testing.expectEqual(.spec, needs.entries[0].stage);
    try std.testing.expectEqual(.spec, needs.entries[1].stage);
    try std.testing.expect(!std.mem.eql(u8, needs.entries[0].question, needs.entries[1].question));
    const opened = try refresh.refresh(allocator, .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} }, needs);
    const records = opened.state.value.?.records;
    try std.testing.expectEqual(@as(usize, 2), records.len);
    try std.testing.expect(!std.mem.eql(u8, records[0].id, records[1].id));
    try std.testing.expect(!c.sameSubject(records[0].subject, records[1].subject));
    // A rerun with the gaps in the other order keeps both subjects and their IDs.
    inputs.seeds = try allocator.dupe(a.Seed, &.{ other, one.seeds[0] });
    inputs.evidence = try allocator.dupe(a.Evidence, &.{ proofs[1], proofs[0] });
    const again = try conversion.build(allocator, source_inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    const reopened = try refresh.refresh(allocator, .{ .state = .{ .value = opened.state.value }, .submissions = &.{}, .protected_forms = &.{} }, again);
    try std.testing.expectEqual(@as(usize, 2), reopened.state.value.?.records.len);
    for (records) |before| {
        const kept = for (reopened.state.value.?.records) |after| {
            if (c.sameSubject(before.subject, after.subject)) break after;
        } else return error.SubjectLost;
        try std.testing.expectEqualStrings(before.id, kept.id);
    }
}

test "gaps over the same lines become one need and one form, and gaps over other lines stay their own" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const refresh = @import("domain/clarification_refresh.zig");
    const c = @import("domain/clarification_inputs.zig");
    const support = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    // The first source's sentence and its quoted token are on one line; the second source is another subject.
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Display `Hello, World!`.\n", "Renew a library loan.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try f.global(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, reference.inputs.corpus.feature_id, accounted);
    const evidence = try allocator.alloc(a.Evidence, inputs.seeds.len);
    for (inputs.seeds, evidence, 0..) |seed, *entry, index| entry.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .requirement = seed.id, .authorities = inputs.authorities, .resolution = .{ .existing_authority = inputs.authorities[0] }, .finding = .supported, .method = .model_assisted };
    var asked: usize = 0;
    for (evidence) |*entry| {
        if (entry.requirement.unit != .signal) continue;
        const signal = for (held.signals) |member| {
            if (member.id.ordinal == entry.requirement.unit.signal.ordinal) break member;
        } else return error.ExpectedSignal;
        entry.finding = .ambiguous;
        entry.review = .{
            .question = try std.fmt.allocPrint(allocator, "Which reading of requirement {d} applies?", .{asked}),
            .detail = try std.fmt.allocPrint(allocator, "The source leaves requirement {d} open.", .{asked}),
            .provenance = .{ .claim_ids = &.{}, .citation_ids = signal.value.citation_ids, .clarification_response_ids = &.{} },
            .source_ids = &.{},
        };
        asked += 1;
    }
    try std.testing.expect(asked >= 3);
    inputs.evidence = evidence;
    const needs = try conversion.build(allocator, reference.inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    // The signals over one line are one need that asks each question and gives each reason; the third has its own.
    try std.testing.expectEqual(@as(usize, 2), needs.entries.len);
    const first_path = reference.inputs.corpus.sources[0].path.bytes;
    const together = for (needs.entries) |need| {
        if (std.mem.eql(u8, need.subject.sources[0].path, first_path)) break need;
    } else return error.ExpectedSharedNeed;
    const alone = for (needs.entries) |need| {
        if (!std.mem.eql(u8, need.subject.sources[0].path, first_path)) break need;
    } else return error.ExpectedOwnNeed;
    const first_question = std.mem.indexOf(u8, together.question, "Which reading of requirement 0 applies?") orelse return error.QuestionLost;
    const second_question = std.mem.indexOf(u8, together.question, "Which reading of requirement 1 applies?") orelse return error.QuestionLost;
    try std.testing.expect(first_question < second_question);
    try std.testing.expect(std.mem.indexOf(u8, together.why_required, "requirement 0 open") != null and std.mem.indexOf(u8, together.why_required, "requirement 1 open") != null);
    try std.testing.expect(std.mem.indexOf(u8, alone.question, "requirement 2 applies") != null and std.mem.indexOf(u8, alone.question, "requirement 0") == null);
    // The authority every gap binds is bound once, not once per gap.
    try std.testing.expectEqual(inputs.authorities.len, together.authority.len);
    // The refresh opens one form for each need, and a rerun with the evidence in another order and another wording keeps both.
    const opened = try refresh.refresh(allocator, .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} }, needs);
    try std.testing.expectEqual(@as(usize, 2), opened.state.value.?.records.len);
    const reversed = try allocator.dupe(a.Evidence, evidence);
    std.mem.reverse(a.Evidence, reversed);
    for (reversed) |*entry| if (entry.review) |*review| {
        review.detail = "Another reviewer worded this differently.";
    };
    inputs.evidence = reversed;
    const again = try conversion.build(allocator, reference.inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    const reopened = try refresh.refresh(allocator, .{ .state = .{ .value = opened.state.value }, .submissions = &.{}, .protected_forms = &.{} }, again);
    try std.testing.expectEqual(@as(usize, 2), reopened.state.value.?.records.len);
    for (opened.state.value.?.records, reopened.state.value.?.records) |before, after| {
        try std.testing.expect(c.sameSubject(before.subject, after.subject));
        try std.testing.expectEqualStrings(before.id, after.id);
    }
}

test "a conflict's need offers its claims as options and every other need takes text" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const refresh = @import("domain/clarification_refresh.zig");
    const c = @import("domain/clarification_inputs.zig");
    const support = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try @import("reference_reconciliation_test.zig").conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    var inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, reference.inputs.corpus.feature_id, accounted);
    const evidence = try allocator.alloc(a.Evidence, inputs.seeds.len);
    for (inputs.seeds, evidence, 0..) |seed, *entry, index| entry.* = .{ .id = .{ .ordinal = @intCast(index + 1) }, .requirement = seed.id, .authorities = inputs.authorities, .resolution = .{ .existing_authority = inputs.authorities[0] }, .finding = .supported, .method = .model_assisted };
    for (evidence) |*entry| {
        if (entry.requirement.unit != .conflict) continue;
        entry.finding = .conflicting;
        entry.review = .{ .question = "Which behavior applies?", .detail = "The sources disagree.", .provenance = .{ .claim_ids = held.conflicts[0].value.claim_ids, .citation_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{} };
    }
    inputs.evidence = evidence;
    const needs = try conversion.build(allocator, reference.inputs, inputs, try observe(allocator, inputs), try run(allocator, inputs), &packet_guidance.marked);
    try std.testing.expectEqual(@as(usize, 1), needs.entries.len);
    const offered = needs.entries[0].answer_schema.select_one;
    try std.testing.expectEqual(@as(usize, 2), offered.len);
    try std.testing.expectEqualStrings("Confirm immediately.", offered[0].label);
    try std.testing.expectEqualStrings("Request approval first.", offered[1].label);
    // The refresh opens a selection form that holds the same options, and a rerun reuses it.
    const opened = try refresh.refresh(allocator, .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} }, needs);
    try std.testing.expectEqual(@as(usize, 1), opened.state.value.?.records.len);
    try std.testing.expectEqual(@as(usize, 2), opened.state.value.?.records[0].answer_schema.select_one.len);
    // A gap that is not a conflict is answered in text.
    const text = try conversion.consolidate(allocator, &.{}, &.{.{ .stage = .spec, .subject = needs.entries[0].subject, .authority = needs.entries[0].authority, .question = "Which applies?", .reason = "Open.", .citations = &.{}, .sources = &.{} }});
    try std.testing.expectEqual(c.max_text_bytes, text[0].answer_schema.bounded_business_text);
}

test "the parts of one subject share one way to answer, and a conflict's options are merged once each" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const c = @import("domain/clarification_inputs.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const first: []const c.Option = &.{ .{ .key = "a.md.1", .label = "One." }, .{ .key = "a.md.2", .label = "Two." } };
    const second: []const c.Option = &.{ .{ .key = "a.md.2", .label = "Two." }, .{ .key = "a.md.3", .label = "Three." } };
    const part = struct {
        fn make(answer: c.AnswerSchema) conversion.Part {
            return .{ .stage = .spec, .subject = .{ .requirement = "reference_meaning", .unit = "conflict", .slot = "disposition", .sources = &.{.{ .path = "a.md", .lines = .{ .first = 1, .last = 2 } }} }, .answer = answer, .authority = &.{.{ .canonical = .{ .kind = .specification, .ordinal = 1, .revision = 1 } }}, .question = "Which applies?", .reason = "Open.", .citations = &.{}, .sources = &.{} };
        }
    };
    // Overlapping options are offered once, in the order named.
    const merged = try conversion.consolidate(allocator, &.{}, &.{ part.make(.{ .select_one = first }), part.make(.{ .select_one = second }) });
    try std.testing.expectEqual(@as(usize, 1), merged.len);
    const options = merged[0].answer_schema.select_one;
    try std.testing.expectEqual(@as(usize, 3), options.len);
    for (options, [_][]const u8{ "a.md.1", "a.md.2", "a.md.3" }) |option, key| try std.testing.expectEqualStrings(key, option.key);
    // The same key under another label, a mixture of kinds, a selection of many and more options than a form offers fail.
    const relabelled: []const c.Option = &.{.{ .key = "a.md.1", .label = "Another." }};
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ part.make(.{ .select_one = first }), part.make(.{ .select_one = relabelled }) }));
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ part.make(.{ .select_one = first }), part.make(.{ .bounded_business_text = c.max_text_bytes }) }));
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ part.make(.{ .bounded_business_text = c.max_text_bytes }), part.make(.{ .bounded_business_text = 100 }) }));
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{part.make(.{ .select_many = .{ .minimum = 1, .maximum = 1, .options = first } })}));
    const many = try allocator.alloc(c.Option, c.max_options);
    for (many, 0..) |*option, index| option.* = .{ .key = try std.fmt.allocPrint(allocator, "k{d}", .{index}), .label = "Label." };
    _ = try conversion.consolidate(allocator, &.{}, &.{part.make(.{ .select_one = many })});
    const more: []const c.Option = &.{.{ .key = "extra", .label = "Extra." }};
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ part.make(.{ .select_one = many }), part.make(.{ .select_one = more }) }));
}

test "consolidation merges the parts of one stage and subject, never another subject or stage, and fails rather than truncates" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const c = @import("domain/clarification_inputs.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lines: []const c.SourceSpan = &.{ .{ .path = "a.md", .lines = .{ .first = 2, .last = 3 } }, .{ .path = "b.md", .lines = null } };
    const subject: c.Subject = .{ .requirement = "reference_meaning", .unit = "conflict", .slot = "disposition", .sources = lines };
    const specification = struct {
        fn authority(ordinal: u32, revision: u32) c.Authority {
            return .{ .canonical = .{ .kind = .specification, .ordinal = ordinal, .revision = revision } };
        }
    };
    const one: []const c.Authority = &.{ specification.authority(1, 1), specification.authority(2, 1) };
    const two: []const c.Authority = &.{ specification.authority(2, 1), specification.authority(3, 1) };
    const parts = [_]conversion.Part{
        .{ .stage = .spec, .subject = subject, .authority = one, .question = "Which applies?", .reason = "The sources disagree.", .citations = &.{}, .sources = &.{} },
        .{ .stage = .plan, .subject = subject, .authority = one, .question = "Which applies?", .reason = "The sources disagree.", .citations = &.{}, .sources = &.{} },
        .{ .stage = .spec, .subject = .{ .requirement = "reference_meaning", .unit = "conflict", .slot = "disposition", .sources = lines[1..] }, .authority = one, .question = "Which other applies?", .reason = "Another conflict.", .citations = &.{}, .sources = &.{} },
        .{ .stage = .spec, .subject = subject, .authority = two, .question = "Which applies?", .reason = "A second reviewer agrees.", .citations = &.{}, .sources = &.{} },
        .{ .stage = .spec, .subject = subject, .authority = two, .question = "Which takes precedence?", .reason = "The sources disagree.", .citations = &.{}, .sources = &.{} },
    };
    const needs = try conversion.consolidate(allocator, &.{}, &parts);
    // The stage and the lines name a need: a part of another stage and a part over other lines stay their own.
    try std.testing.expectEqual(@as(usize, 3), needs.len);
    try std.testing.expectEqual(.spec, needs[0].stage);
    try std.testing.expectEqual(.plan, needs[1].stage);
    try std.testing.expectEqualStrings("Which other applies?", needs[2].question);
    // The members of one subject are merged in the order named, each distinct question and reason once, each authority once.
    try std.testing.expectEqualStrings("Which applies?\nWhich takes precedence?", needs[0].question);
    try std.testing.expectEqualStrings("The sources disagree.\nA second reviewer agrees.", needs[0].why_required);
    try std.testing.expectEqual(@as(usize, 3), needs[0].authority.len);
    for ([_]u32{ 1, 2, 3 }, needs[0].authority) |ordinal, held| try std.testing.expectEqual(ordinal, held.canonical.ordinal);
    // A lone part passes through as it was named.
    try std.testing.expectEqualStrings("Which applies?", needs[1].question);
    try std.testing.expectEqual(@as(usize, 2), needs[1].authority.len);
    // No part is lost or doubled.
    var count: usize = 0;
    for (needs) |need| count += if (c.sameSubject(need.subject, subject)) 1 else 0;
    try std.testing.expectEqual(@as(usize, 2), count);
    // The one canonical record at two revisions is not one authority, and no merge hides it.
    var disputed = parts[0];
    disputed.authority = &.{specification.authority(1, 2)};
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ parts[0], disputed }));
    // A merged text beyond the form's bound fails, where either part alone is within it.
    const long = try allocator.alloc(u8, c.max_text_bytes / 2 + 1);
    @memset(long, 'q');
    var wordy = parts[0];
    wordy.question = long;
    var other = wordy;
    other.question = try std.fmt.allocPrint(allocator, "r{s}", .{long[1..]});
    _ = try conversion.consolidate(allocator, &.{}, &.{wordy});
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ wordy, other }));
    var explained = parts[0];
    explained.reason = long;
    var elsewhere = explained;
    elsewhere.reason = other.question;
    _ = try conversion.consolidate(allocator, &.{}, &.{explained});
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ explained, elsewhere }));
    // So do more authorities than a record names.
    const many = try allocator.alloc(c.Authority, c.max_record_authorities);
    for (many, 0..) |*held, index| held.* = specification.authority(@intCast(index + 1), 1);
    var wide = parts[0];
    wide.authority = many;
    var extra = parts[0];
    extra.authority = &.{specification.authority(c.max_record_authorities + 1, 1)};
    _ = try conversion.consolidate(allocator, &.{}, &.{wide});
    try std.testing.expectError(error.InvalidRequiredAuthority, conversion.consolidate(allocator, &.{}, &.{ wide, extra }));
}

test "a merged need keeps the evidence of a part that names only sources beside one that cites" {
    const conversion = @import("domain/required_authority_clarifications.zig");
    const c = @import("domain/clarification_inputs.zig");
    const support = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const f = @import("test_fixtures/reference_reconciliation.zig");
    const reference = try @import("reference_reconciliation_test.zig").prepare(allocator, &.{ "Display the catalogue.\n", "Renew a library loan.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try f.global(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const cited = held.items.entries[0];
    const named = held.items.entries[held.items.entries.len - 1];
    try std.testing.expect(!std.meta.eql(cited.source_id, named.source_id));
    const subject: c.Subject = .{ .requirement = "reference_meaning", .unit = "signal", .slot = "disposition", .sources = &.{} };
    const authority: []const c.Authority = &.{.{ .canonical = .{ .kind = .specification, .ordinal = 1, .revision = 1 } }};
    const citing: conversion.Part = .{ .stage = .spec, .subject = subject, .authority = authority, .question = "Which applies?", .reason = "Open.", .citations = &.{cited.citations[0].id}, .sources = &.{cited.source_id} };
    const naming: conversion.Part = .{ .stage = .spec, .subject = subject, .authority = authority, .question = "Which applies?", .reason = "Open.", .citations = &.{}, .sources = &.{named.source_id} };
    const alone = try conversion.consolidate(allocator, held.items.entries, &.{naming});
    const merged = try conversion.consolidate(allocator, held.items.entries, &.{ citing, naming });
    try std.testing.expectEqual(@as(usize, 1), merged.len);
    // The part that names only a source quotes it alone, as it would alone, and the merge keeps that quotation.
    const heading = try std.fmt.allocPrint(allocator, "Source {d}, line", .{named.source_id.ordinal});
    try std.testing.expect(std.mem.indexOf(u8, alone[0].question, heading) != null);
    try std.testing.expect(std.mem.indexOf(u8, merged[0].question, heading) != null);
    const kept = try std.fmt.allocPrint(allocator, "Source {d}, line", .{cited.source_id.ordinal});
    try std.testing.expect(std.mem.indexOf(u8, merged[0].question, kept) != null);
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
