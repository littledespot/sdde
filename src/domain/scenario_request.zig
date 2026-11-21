//! Claim-bound scenarios, the request half (ADR 0038 Decisions 2 and 3). The model gets a group's
//! numbered slots (`scenario_slots.zig`) and answers each with the Given, When and Then of one
//! acceptance criterion. The answer carries no claim, kind or group: the engine binds each number
//! to its slot's claim and takes the group from the batch, as it fixes a record's evidence at
//! authoring (`specification_generation.zig`). The answer is a wire contract of its own, not a
//! records response, and its schema admits exactly one scenario for each slot number.
const std = @import("std");
const spec = @import("specification.zig");
const r = @import("reference_reconciliation.zig");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const slots = @import("scenario_slots.zig");
const session = @import("specification_session.zig");
const binding = @import("specification_source_binding.zig");
const packets = @import("model_input_packet.zig");
const json = @import("model_candidate_json.zig");
const schema = @import("model_result_schema.zig");
const evidence = @import("model_evidence.zig");

/// The result definition of `generation.schema.json`.
pub const definition = @import("specification_result_definitions.zig").Generation.scenarios;

pub const Error = session.Error || slots.Error || r.Error;

// The records the step writes are the scenario family's, which the fields and the record below spell.
comptime {
    std.debug.assert(spec.scenario_family == .acceptance_criterion);
}

/// One slot's scenario as the model writes it. Its text fields are the acceptance criterion's own.
pub const Scenario = struct {
    pub const model_fields = .{
        .given = spec.textField(spec.scenario_family, "given"),
        .when = spec.textField(spec.scenario_family, "when"),
        .then = spec.textField(spec.scenario_family, "then"),
    };
    number: slots.SlotNumber,
    /// Omitted where the sources state no starting situation for the requirement.
    given: ?spec.BusinessValue = null,
    when: spec.BusinessValue,
    then: spec.BusinessValue,
};

/// The answer: one scenario for each slot, in any order.
pub const Response = struct { scenarios: []const Scenario };

/// The properties that make a scenario one acceptance criterion. Scenarios of one answer that repeat all
/// of them are one criterion written twice (ADR 0038 Decision 3).
const criterion_properties: []const []const u8 = &.{ "given", "when", "then" };

// The list is the criterion's own fields: the content the later duplicate rule compares is every field
// of the acceptance criterion, so a field added there must be compared here too.
comptime {
    const content = @typeInfo(@FieldType(spec.Content(spec.BusinessValue), "acceptance_criterion")).@"struct".fields;
    std.debug.assert(content.len == criterion_properties.len);
    for (criterion_properties) |name| {
        std.debug.assert(@hasField(Scenario, name) and @hasField(@FieldType(spec.Content(spec.BusinessValue), "acceptance_criterion"), name));
    }
}

/// The one native restriction of the answer: it names every slot's number once and no other, and no two
/// scenarios repeat the same criterion.
pub fn numberChoice(allocator: std.mem.Allocator, group_plan: slots.Plan) std.mem.Allocator.Error!schema.IntegerChoice {
    return .{
        .target = .{ .path = &.{ .{ .property = "scenarios" }, .items, .{ .property = "number" } } },
        .definition = definition.id(),
        .allowed = try group_plan.numbers(allocator),
        .collection = .exact_members,
        .distinct = criterion_properties,
    };
}

/// The acceptance criteria of an answer, one for each slot of `group_plan` in slot order, whatever
/// order the answer has. The engine fixes each criterion's kind, its one claim and its group
/// (`g.batchRecord`); the answer's numbers must be the plan's, each once. The answer passed the
/// request's payload-schema admission before this runs, so a failure here is not the model's to
/// correct. The caller owns an arena: the result lives until it is released.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, group_plan: slots.Plan, bound: binding.RecordBound) Error![]const spec.Values(.model).RecordProposal {
    const response = json.decode(Response, allocator, bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    return bind(allocator, group_plan, bound, response);
}

fn bind(allocator: std.mem.Allocator, group_plan: slots.Plan, bound: binding.RecordBound, response: Response) Error![]const spec.Values(.model).RecordProposal {
    if (bound.signal.ordinal != group_plan.group.ordinal or response.scenarios.len != group_plan.count()) return error.InvalidSpecificationUnit;
    const criteria = try allocator.alloc(spec.Values(.model).RecordProposal, group_plan.count());
    const written = try allocator.alloc(bool, group_plan.count());
    @memset(written, false);
    // As many answers as slots, each naming a slot once, leave no slot unanswered.
    for (response.scenarios) |scenario| {
        const index = group_plan.indexOf(scenario.number) orelse return error.InvalidSpecificationUnit;
        if (written[index]) return error.InvalidSpecificationUnit;
        written[index] = true;
        criteria[index] = try g.batchRecord(allocator, bound, .{ .acceptance_criterion = .{ .given = scenario.given, .when = scenario.when, .then = scenario.then } }, try allocator.dupe(r.ClaimId, &.{group_plan.slot(index).claim}));
    }
    return criteria;
}

/// The request for the group whose scenarios are written next (`session.scenarioPlan`): each slot
/// offered as a numbered requirement (`requirements`, apart from the answer's `scenarios`) with its
/// claim's meaning and source, the corpus's sources, and the exact values and display references the
/// slots' claims allow. It offers no statement, entity, story or other batch's record, so a criterion
/// cannot copy a statement's wording. The caller releases the packet.
pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, guidance: *const @import("packet_guidance.zig").Guidance) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const group_plan = try session.scenarioPlan(a, current);
    // The catalogue of every claim; the selection below narrows its display values to the slots' own claims.
    const display = try session.displayCatalogue(a, context, null);
    const Offered = struct { number: slots.SlotNumber, meaning: []const u8, source_id: r.extraction.identity.SourceId };
    const offered = try a.alloc(Offered, group_plan.count());
    for (offered, 0..) |*entry, index| {
        const slot = group_plan.slot(index);
        const requirement = for (display.requirements) |candidate| {
            if (candidate.claim_id.ordinal == slot.claim.ordinal) break candidate;
        } else return error.InvalidSpecificationUnit;
        entry.* = .{ .number = slot.number, .meaning = requirement.meaning, .source_id = requirement.source_id };
    }
    const purpose = @import("required_authority_description.zig").record(a, guidance, spec.scenario_family) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    const payload = .{
        .purpose = purpose,
        .requirements = @as([]const Offered, offered),
        .exact_texts = display.exact_choices,
        .sources = try evidence.sources(a, context.inputs),
        .passive_literals = try @import("reference_model_input.zig").passiveChoices(a, context.registry, context.inputs, display.scopes),
    };
    const body = try json.encodeEvidence(@TypeOf(payload), a, payload);
    var result = try packets.create(allocator, body, try session.owner(a, current), .initial_generation, definition.id());
    defer packets.release(result);
    const witnessed = try packets.withOriginalSources(allocator, result, context.inputs);
    packets.release(result);
    result = witnessed;
    const model_fields = json.fieldBindings(Response, a, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    const policies = try packets.withFieldPolicies(allocator, result, model_fields);
    packets.release(result);
    result = policies;
    const presentation = @import("model_field_presentation.zig");
    const omitted = try packets.withPresentationOmissions(allocator, result, &[_]presentation.Omission{.{ .requires = .exact_copy, .path = &.{.{ .property = "exact_texts" }} }});
    packets.release(result);
    result = omitted;
    const operation = try packets.withContext(enum { write }, allocator, result, "operation", .write);
    packets.release(result);
    result = operation;
    const claims = try a.alloc(r.ClaimId, group_plan.count());
    for (claims, 0..) |*claim, index| claim.* = group_plan.slot(index).claim;
    const narrowed = try session.withSelectionChoices(allocator, result, context, .{ .claim_ids = claims, .clarification_response_ids = &.{} });
    packets.release(result);
    result = narrowed;
    return packets.withIntegerChoices(allocator, result, &.{try numberChoice(a, group_plan)});
}
