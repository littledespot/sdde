const std = @import("std");
const runtime = @import("domain/json_composition_runtime.zig");
const schema_adapter = @import("adapters/parsers/model_result_schemas.zig");
const packets = @import("domain/model_input_packet.zig");
const identity = @import("domain/model_request_identity.zig");
const origin = @import("domain/model_candidate_origin.zig").Origin;
const invocation = @import("domain/provider_invocation_validation.zig");
const envelope = @import("domain/model_envelope.zig");
const payload = @import("domain/model_payload_schema.zig");
const Fixture = @import("provider_invocation_test_fixture.zig").Fixture;

const contract =
    \\{"type":"object","properties":{"value":{"type":"integer","minimum":0,"maximum":10}},"required":["value"],"additionalProperties":false}
;
const config =
    \\{"schema":"json-composition/v1","result":"result","parts":{"value":{"paths":["/value"]}}}
;

test "composition retains only accepted schema-associated requests and placement is idempotent" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter: schema_adapter.Adapter = .{};
    const canonical = try adapter.compiler().compile(a, contract);
    const plan = try adapter.compiler().compileComposition(a, config, canonical);
    var fixture: Fixture = undefined;
    const restricted = try @import("domain/model_result_schema.zig").restrict(std.testing.allocator, try plan.selectSchema(0, &.{}), &.{.{ .kind = "unavailable" }}, &.{});
    defer restricted.release();
    try fixture.initWithCompiledSchema(restricted.selected());
    defer fixture.deinit();
    const id = fixture.base.model_request_id;
    const packet = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, id.purpose, null);
    defer packets.release(packet);
    const initial = try runtime.State.init(a, plan, packet, id.stage_run_epoch_id);
    const binding = try initial.select(a, 0);
    try std.testing.expect(binding.valid());
    try std.testing.expectError(error.IncompleteComposition, initial.assemble(a));
    fixture.fake.invocation_plan = .{ .complete = .{ .content = "{\"value\":1e0}", .input_tokens = 10, .output_tokens = 2 } };
    var response = try fixture.response();
    defer response.deinit();
    var admitted = try invocation.validate(std.testing.allocator, fixture.call, &response);
    defer admitted.deinit();
    var decoded = try envelope.decode(std.testing.allocator, admitted.evidence.result().complete, null);
    defer decoded.deinit();
    const proof = payload.validate(decoded.candidate).valid;
    const ledger = fixture.base.requests.ledger().?;
    const producer = origin.from(ledger, fixture.authorized.invoked.id).?;
    try std.testing.expect(origin.fromAccepted(ledger, proof) == null);
    try std.testing.expectError(error.InvalidCompositionBinding, initial.retain(a, binding, proof, producer, ledger));
    const record = ledger.record(id).?;
    const invoked_owner = if (record.status == .assigned) try identity.createLifecycleSuccessor(ledger, ledger.revision(), id, .assigned, .invoked) else null;
    defer if (invoked_owner) |owner| identity.deinitOwner(owner);
    const invoked = if (invoked_owner) |owner| identity.ledger(owner) else ledger;
    const accepted_owner = try identity.createLifecycleSuccessor(invoked, invoked.revision(), id, .invoked, .{ .terminal = .accepted });
    defer identity.deinitOwner(accepted_owner);
    const accepted = identity.ledger(accepted_owner);
    const retained = try initial.retain(a, binding, proof, producer, accepted);
    const repeated = try retained.retain(a, binding, proof, producer, accepted);
    try std.testing.expect(repeated.entries.ptr == retained.entries.ptr);
    try std.testing.expect(initial.entries[0] == null);
    try std.testing.expectError(error.InvalidCompositionBinding, retained.select(a, 0));
    const assembled = try retained.assemble(a);
    try std.testing.expect(assembled.validate() == null);
    try std.testing.expectEqualStrings("{\"value\":1e0}", assembled.body);
    try std.testing.expectEqualDeep(producer, assembled.producer(&.{"value"}).?);
    try std.testing.expect(assembled.producer(&.{"missing"}) == null);
    try std.testing.expectEqual(@as(u64, 12), admitted.evidence.usage().?.total_tokens);
    try std.testing.expectEqualDeep(producer, assembled.origin);

    var conflict = response;
    conflict.completed.raw_result.complete.content = try @import("domain/llm_provider_operation.zig").CompleteOwnedUtf8.init(std.testing.allocator, "{\"value\":2}");
    defer conflict.deinit();
    var conflicting_admission = try invocation.validate(std.testing.allocator, fixture.call, &conflict);
    defer conflicting_admission.deinit();
    var conflicting_decoded = try envelope.decode(std.testing.allocator, conflicting_admission.evidence.result().complete, null);
    defer conflicting_decoded.deinit();
    const conflicting_proof = payload.validate(conflicting_decoded.candidate).valid;
    try std.testing.expectError(error.ConflictingCompositionPart, retained.retain(a, binding, conflicting_proof, producer, accepted));
    try std.testing.expectEqualStrings("{\"value\":1e0}", (try retained.assemble(a)).body);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationLifecycle, .{ plan, packet, proof, producer, accepted });

    const failed_owner = try identity.createLifecycleSuccessor(invoked, invoked.revision(), id, .invoked, .{ .terminal = .failed });
    defer identity.deinitOwner(failed_owner);
    try std.testing.expectError(error.InvalidCompositionBinding, initial.retain(a, binding, proof, producer, identity.ledger(failed_owner)));
    const cancelled_owner = try identity.createLifecycleSuccessor(invoked, invoked.revision(), id, .invoked, .{ .terminal = .cancelled });
    defer identity.deinitOwner(cancelled_owner);
    try std.testing.expectError(error.InvalidCompositionBinding, initial.retain(a, binding, proof, producer, identity.ledger(cancelled_owner)));
    const foreign = try identity.createInitial(std.testing.allocator, identity.RequestPurposeRegistry.all());
    defer identity.deinitOwner(foreign);
    try std.testing.expectError(error.InvalidCompositionBinding, initial.retain(a, binding, proof, producer, identity.ledger(foreign)));
    const other_packet = try packets.create(std.testing.allocator, "{\"source\":\"different\"}", id.immutable_unit_owner_id, id.purpose, null);
    defer packets.release(other_packet);
    const other = try runtime.State.init(a, plan, other_packet, id.stage_run_epoch_id);
    try std.testing.expectError(error.InvalidCompositionBinding, other.retain(a, binding, proof, producer, accepted));
    const other_plan = try adapter.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","parts":{"other":{"paths":["/value"]}}}
    , canonical);
    const other_part = try runtime.State.init(a, other_plan, packet, id.stage_run_epoch_id);
    const other_binding = try other_part.select(a, 0);
    try std.testing.expectEqualStrings(binding.schema.modelBytes(), other_binding.schema.modelBytes());
    try std.testing.expect(binding.schema != other_binding.schema);
    try std.testing.expectError(error.InvalidCompositionBinding, other_part.retain(a, other_binding, proof, producer, accepted));
    var different_schema = binding;
    different_schema.schema = canonical;
    try std.testing.expect(!different_schema.valid());
    try std.testing.expectError(error.InvalidCompositionBinding, initial.retain(a, different_schema, proof, producer, accepted));
}

fn allocationLifecycle(allocator: std.mem.Allocator, plan: *const @import("domain/json_composition.zig").Plan, packet: *const packets.Packet, proof: *const payload.Evidence, producer: origin, ledger: *const identity.ModelRequestIdentityLedger) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const initial = try runtime.State.init(a, plan, packet, ledger.stageRunEpochId());
    const binding = try initial.select(a, 0);
    _ = try initial.inputs(a, binding);
    const retained = try initial.retain(a, binding, proof, producer, ledger);
    const candidate = try retained.assemble(a);
    try std.testing.expect(candidate.validate() == null);
}

test "assembly retains required containers with absent optional leaves without inventing optional containers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter: schema_adapter.Adapter = .{};
    const canonical = try adapter.compiler().compile(a,
        \\{"type":"object","properties":{"header":{"type":"object","properties":{"title":{"type":"string","maxLength":16},"enabled":{"type":"boolean"}},"required":[],"additionalProperties":false},"details":{"type":"object","properties":{"note":{"type":"string","maxLength":16}},"required":["note"],"additionalProperties":false}},"required":["header"],"additionalProperties":false}
    );
    const plan = try adapter.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","parts":{"text":{"paths":["/header/title","/details"]},"flag":{"paths":["/header/enabled"]}}}
    , canonical);
    const scenarios = [_]struct { text: []const u8, flag: []const u8, expected: []const u8 }{
        .{ .text = "{\"header\":{}}", .flag = "{\"header\":{}}", .expected = "{\"header\":{}}" },
        .{ .text = "{\"header\":{\"title\":\"Report\"}}", .flag = "{\"header\":{}}", .expected = "{\"header\":{\"title\":\"Report\"}}" },
        .{ .text = "{\"header\":{},\"details\":{\"note\":\"Review\"}}", .flag = "{\"header\":{\"enabled\":false}}", .expected = "{\"header\":{\"enabled\":false},\"details\":{\"note\":\"Review\"}}" },
        .{ .text = "{\"header\":{\"title\":\"Report\"}}", .flag = "{\"header\":{\"enabled\":false}}", .expected = "{\"header\":{\"title\":\"Report\",\"enabled\":false}}" },
        .{ .text = "{\"header\":{\"title\":\"Report\"},\"details\":{\"note\":\"Review\"}}", .flag = "{\"header\":{}}", .expected = "{\"header\":{\"title\":\"Report\"},\"details\":{\"note\":\"Review\"}}" },
    };
    for (scenarios) |scenario| {
        var fixture: Fixture = undefined;
        try fixture.initWithCompiledSchema(try plan.selectSchema(0, &.{}));
        defer fixture.deinit();
        const id = fixture.base.model_request_id;
        const packet = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, id.purpose, null);
        defer packets.release(packet);
        const initial = try runtime.State.init(a, plan, packet, id.stage_run_epoch_id);
        const first_binding = try initial.select(a, 0);
        const second_binding = try initial.select(a, 1);
        var text = try Attempt.accept(&fixture, scenario.text);
        defer text.deinit();
        const first = try initial.retain(a, first_binding, text.proof(), text.producer, fixture.base.requests.ledger().?);
        var prior = try nextRequest(&fixture, second_binding.schema, "flags");
        defer prior.deinit();
        var flag = try Attempt.accept(&fixture, scenario.flag);
        defer flag.deinit();
        const complete = try first.retain(a, second_binding, flag.proof(), flag.producer, fixture.base.requests.ledger().?);
        const assembled = try complete.assemble(a);
        try std.testing.expect(assembled.validate() == null);
        try std.testing.expectEqualStrings(scenario.expected, assembled.body);
        try std.testing.expectEqualDeep(text.producer, assembled.origin);
        if (std.mem.indexOf(u8, scenario.text, "title") != null and std.mem.indexOf(u8, scenario.text, "details") != null)
            try std.testing.expectEqualDeep(text.producer, assembled.producer(&.{}).?);
        if (std.mem.indexOf(u8, scenario.text, "title") != null)
            try std.testing.expectEqualDeep(text.producer, assembled.producer(&.{ "header", "title" }).?)
        else
            try std.testing.expect(assembled.producer(&.{ "header", "title" }) == null);
        if (std.mem.indexOf(u8, scenario.text, "title") != null and std.mem.indexOf(u8, scenario.flag, "enabled") != null)
            try std.testing.expect(assembled.producer(&.{"header"}) == null)
        else if (std.mem.indexOf(u8, scenario.text, "title") != null)
            try std.testing.expectEqualDeep(text.producer, assembled.producer(&.{"header"}).?)
        else if (std.mem.indexOf(u8, scenario.flag, "enabled") != null)
            try std.testing.expectEqualDeep(flag.producer, assembled.producer(&.{"header"}).?)
        else
            try std.testing.expect(assembled.producer(&.{"header"}) == null);
        if (std.mem.indexOf(u8, scenario.text, "details") != null)
            try std.testing.expectEqualDeep(text.producer, assembled.producer(&.{ "details", "note" }).?)
        else
            try std.testing.expect(assembled.producer(&.{"details"}) == null);
    }
}

test "named schema assembly preserves sibling placement and rejects stale prerequisite bindings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter: schema_adapter.Adapter = .{};
    const canonical = try adapter.compiler().compile(a,
        \\{"$ref":"#/$defs/other","$defs":{"other":{"type":"object","properties":{"ignored":{"type":"boolean"}},"required":["ignored"],"additionalProperties":false},"record":{"type":"object","properties":{"left":{"type":"string","maxLength":16},"middle":{"type":"boolean"},"right":{"type":"array","items":{"type":"integer","minimum":0,"maximum":9},"maxItems":3}},"required":["left","middle","right"],"additionalProperties":false}}}
    );
    const plan = try adapter.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","definition":"record","parts":{"first":{"paths":["/left"]},"sibling":{"paths":["/middle"]},"dependent":{"paths":["/right"],"requires":["first"]}}}
    , canonical);
    var fixture: Fixture = undefined;
    try fixture.initWithCompiledSchema(try plan.selectSchema(0, &.{}));
    defer fixture.deinit();
    const id = fixture.base.model_request_id;
    const packet = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, id.purpose, null);
    defer packets.release(packet);
    const initial = try runtime.State.init(a, plan, packet, id.stage_run_epoch_id);
    try std.testing.expectError(error.IncompleteComposition, initial.select(a, 2));
    const first_binding = try initial.select(a, 0);
    const sibling_binding = try initial.select(a, 1);
    var first = try Attempt.accept(&fixture, "{\"left\":\"original\"}");
    defer first.deinit();
    const first_state = try initial.retain(a, first_binding, first.proof(), first.producer, fixture.base.requests.ledger().?);
    const dependent_binding = try first_state.select(a, 2);
    var first_request = try nextRequest(&fixture, sibling_binding.schema, "sibling");
    defer first_request.deinit();
    var sibling = try Attempt.accept(&fixture, "{\"middle\":true}");
    defer sibling.deinit();
    const second_state = try first_state.retain(a, sibling_binding, sibling.proof(), sibling.producer, fixture.base.requests.ledger().?);
    const repeated = try second_state.retain(a, first_binding, first.proof(), first.producer, fixture.base.requests.ledger().?);
    try std.testing.expect(repeated.entries.ptr == second_state.entries.ptr);
    const before = try std.json.Stringify.valueAlloc(a, try first_state.inputs(a, dependent_binding), .{});
    const after = try std.json.Stringify.valueAlloc(a, try repeated.inputs(a, dependent_binding), .{});
    try std.testing.expectEqualStrings(before, after);
    try std.testing.expectEqualStrings("{\"first\":{\"left\":\"original\"}}", after);
    try std.testing.expect(second_state.entries[0].?.proof == first_state.entries[0].?.proof);
    var stale = dependent_binding;
    const stale_prerequisites = try a.dupe(runtime.Prerequisite, stale.prerequisites);
    stale_prerequisites[0].origin.attempt.value += 1;
    stale.prerequisites = stale_prerequisites;
    try std.testing.expectError(error.InvalidCompositionBinding, second_state.inputs(a, stale));
    var sibling_request = try nextRequest(&fixture, dependent_binding.schema, "dependent");
    defer sibling_request.deinit();
    var dependent = try Attempt.accept(&fixture, "{\"right\":[3,1,2]}");
    defer dependent.deinit();
    try std.testing.expectError(error.InvalidCompositionBinding, repeated.retain(a, stale, dependent.proof(), dependent.producer, fixture.base.requests.ledger().?));
    const final = try repeated.retain(a, dependent_binding, dependent.proof(), dependent.producer, fixture.base.requests.ledger().?);
    const candidate = try final.assemble(a);
    try std.testing.expect(candidate.validate() == null);
    try std.testing.expect(payload.validateValue(envelope.value(&candidate.value), canonical.root()) != null);
    var incomplete = candidate;
    incomplete.value = (try std.json.parseFromSlice(std.json.Value, a, "{\"left\":\"original\"}", .{})).value;
    try std.testing.expect(incomplete.validate() != null);
    try std.testing.expectEqualStrings("{\"left\":\"original\",\"middle\":true,\"right\":[3,1,2]}", candidate.body);
    try std.testing.expectEqualDeep(first.producer, candidate.origin);
    try std.testing.expectEqualDeep(first.producer, candidate.producer(&.{"left"}).?);
    try std.testing.expectEqualDeep(sibling.producer, candidate.producer(&.{"middle"}).?);
    try std.testing.expectEqualDeep(dependent.producer, candidate.producer(&.{ "right", "1" }).?);
    try std.testing.expect(candidate.producer(&.{ "right", "3" }) == null);
    try std.testing.expectEqual(@as(usize, 3), fixture.base.requests.ledger().?.recordCount());
    for ([_]*const identity.ModelRequestId{ first_request.request.model_request_id, sibling_request.request.model_request_id, fixture.prepared.request.model_request_id }) |request|
        try std.testing.expectEqual(@as(u32, 1), fixture.base.attempts.current().attemptsReserved(request));
    try std.testing.expectEqual(@as(u64, 36), first.admission.evidence.usage().?.total_tokens + sibling.admission.evidence.usage().?.total_tokens + dependent.admission.evidence.usage().?.total_tokens);
}

test "nested tagged assembly preserves escaped keys and exact integer spellings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter: schema_adapter.Adapter = .{};
    const canonical = try adapter.compiler().compile(a,
        \\{"type":"object","properties":{"mode":{"oneOf":[{"type":"object","properties":{"kind":{"const":"values"},"value":{"type":"array","items":{"type":"integer","minimum":-9223372036854775808,"maximum":9223372036854775807},"maxItems":4}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"empty"},"value":{"type":"null"}},"required":["kind","value"],"additionalProperties":false}]},"a/b":{"type":"string","maxLength":16}},"required":["mode","a/b"],"additionalProperties":false}
    );
    const plan = try adapter.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","parts":{"tag":{"paths":["/mode/kind","/a~1b"]},"value":{"paths":["/mode/value"],"requires":["tag"]}}}
    , canonical);
    const cases = [_]struct { tag: []const u8, value: []const u8, expected: []const u8 }{
        .{
            .tag = "{\"mode\":{\"kind\":\"values\"},\"a/b\":\"kept\"}",
            .value = "{\"mode\":{\"value\":[9.223372036854775807e18,-9223372036854775808,9007199254740993.0,-0.0e999]}}",
            .expected = "{\"mode\":{\"kind\":\"values\",\"value\":[9.223372036854775807e18,-9223372036854775808,9007199254740993.0,-0.0e999]},\"a/b\":\"kept\"}",
        },
        .{
            .tag = "{\"mode\":{\"kind\":\"empty\"},\"a/b\":\"kept\"}",
            .value = "{\"mode\":{\"value\":null}}",
            .expected = "{\"mode\":{\"kind\":\"empty\",\"value\":null},\"a/b\":\"kept\"}",
        },
    };
    for (cases) |case| {
        var fixture: Fixture = undefined;
        try fixture.initWithCompiledSchema(try plan.selectSchema(0, &.{}));
        defer fixture.deinit();
        const id = fixture.base.model_request_id;
        const packet = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, id.purpose, null);
        defer packets.release(packet);
        const initial = try runtime.State.init(a, plan, packet, id.stage_run_epoch_id);
        const tag_binding = try initial.select(a, 0);
        var tag = try Attempt.accept(&fixture, case.tag);
        defer tag.deinit();
        const tagged = try initial.retain(a, tag_binding, tag.proof(), tag.producer, fixture.base.requests.ledger().?);
        const value_binding = try tagged.select(a, 1);
        var prior = try nextRequest(&fixture, value_binding.schema, "nested-value");
        defer prior.deinit();
        var value = try Attempt.accept(&fixture, case.value);
        defer value.deinit();
        const complete = try tagged.retain(a, value_binding, value.proof(), value.producer, fixture.base.requests.ledger().?);
        const assembled = try complete.assemble(a);
        try std.testing.expect(assembled.validate() == null);
        try std.testing.expectEqualStrings(case.expected, assembled.body);
        try std.testing.expectEqualDeep(tag.producer, assembled.producer(&.{"a/b"}).?);
        try std.testing.expectEqualDeep(tag.producer, assembled.producer(&.{ "mode", "kind" }).?);
        try std.testing.expectEqualDeep(value.producer, assembled.producer(&.{ "mode", "value" }).?);
        try std.testing.expect(assembled.producer(&.{"mode"}) == null);
        try std.testing.expectEqualDeep(tag.producer, assembled.origin);
    }
}

const Attempt = struct {
    response: @import("domain/llm_provider_operation.zig").ProviderInvocationObservation,
    admission: invocation.Owned,
    decoded: envelope.Owned,
    producer: origin,

    fn accept(fixture: *Fixture, body: []const u8) !Attempt {
        fixture.fake.invocation_plan = .{ .complete = .{ .content = body, .input_tokens = 10, .output_tokens = 2 } };
        var response = try fixture.response();
        errdefer response.deinit();
        var admission = try invocation.validate(std.testing.allocator, fixture.call, &response);
        errdefer admission.deinit();
        var decoded = try envelope.decode(std.testing.allocator, admission.evidence.result().complete, null);
        errdefer decoded.deinit();
        const selected_proof = payload.validate(decoded.candidate).valid;
        try fixture.base.change(.inference, .{ .terminate = .completed });
        const ledger = fixture.base.requests.ledger().?;
        try fixture.base.requests.advance(ledger.revision(), fixture.base.model_request_id, .invoked, .{ .terminal = .accepted });
        return .{ .response = response, .admission = admission, .decoded = decoded, .producer = origin.fromAccepted(fixture.base.requests.ledger().?, selected_proof).? };
    }
    fn proof(self: *const Attempt) *const payload.Evidence {
        return payload.validate(self.decoded.candidate).valid;
    }
    fn deinit(self: *Attempt) void {
        self.decoded.deinit();
        self.admission.deinit();
        self.response.deinit();
    }
};

fn nextRequest(fixture: *Fixture, selected: *const @import("domain/model_result_schema.zig").Schema, step: []const u8) !@import("domain/model_request_preparation.zig").Owned {
    const previous = fixture.prepared;
    var operation = fixture.base.model_request_id.model_operation_id;
    operation.workflow_step_id = .{ .bytes = step };
    const current = fixture.base.requests.ledger().?;
    fixture.base.model_request_id = try fixture.base.requests.assign(current.revision(), fixture.base.model_request_id.immutable_unit_owner_id, operation, .initial_generation);
    fixture.base.provider_binding.operation_id = operation;
    fixture.base.request_invoked = false;
    fixture.base.request.model_request_id = fixture.base.model_request_id;
    fixture.base.request.model_operation_id = operation;
    fixture.base.request.binding_id = fixture.base.provider_binding.bindingId();
    _ = try fixture.base.attempts.reserve(fixture.base.attempts.current().revision(), fixture.base.requests.ledger().?, fixture.base.ledger(), fixture.base.requests.ledger().?.revision(), fixture.base.model_request_id, .initial);
    fixture.resource.content = .{ .result_schema = selected };
    fixture.prepared = try @import("domain/model_request_preparation.zig").build(std.testing.allocator, try fixture.requestSource(), fixture.base.request.content);
    fixture.base.request = fixture.prepared.request.*;
    fixture.authorized = try fixture.base.startInference();
    fixture.call = .{ .request = fixture.prepared.request, .provider_binding = &fixture.base.provider_binding, .operations = fixture.base.ledger(), .operation_id = fixture.authorized.invoked.id };
    return previous;
}
