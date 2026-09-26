const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const values = @import("application/pipeline_values.zig");
const envelope_module = @import("application/pipeline_envelope.zig");

const Context = struct { text: []const u8, attempts: u32 };
const context_schema = values.schema(.workflow_invocation, Context, 1, 256);
const count_schema = values.schema(.canonical_log_level, u32, 1, 32);
const schemas = [_]data.Schema{ context_schema, count_schema };
const context_index = @intFromEnum(pipeline.DataKey.workflow_invocation);
const count_index = @intFromEnum(pipeline.DataKey.canonical_log_level);
const produce: pipeline.NodeContract = .{
    .id = "test.context",
    .kind = .action,
    .requires = &.{},
    .produces = &.{.workflow_invocation},
    .side_effect = .none,
};
const consume: pipeline.NodeContract = .{
    .id = "test.consume",
    .kind = .action,
    .requires = &.{.workflow_invocation},
    .produces = &.{},
    .side_effect = .none,
};

test "workflow information placement is idempotent isolated and cannot revive historical authority" {
    const recorded = context_schema.recorded();
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{recorded});
    defer envelope.deinit();
    var other = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{recorded});
    defer other.deinit();
    const occurrence = try envelope.beginOccurrence(produce.id);
    const foreign = try other.beginOccurrence(produce.id);
    try std.testing.expect(!occurrence.scope.eql(foreign.scope));
    try std.testing.expectEqual(occurrence.ordinal, foreign.ordinal);
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, recorded, Context, .{ .text = "source meaning", .attempts = 1 });
    try envelope.applyOccurrence(occurrence, produce, &delta, .ok);
    const original = envelope.records.items[0];
    const generation = envelope.generation;
    for (0..3) |_| {
        const placed = try envelope.place(occurrence, original.value, original.origin);
        try std.testing.expect(placed.already_present == original);
    }
    try std.testing.expectEqual(@as(usize, 1), envelope.records.items.len);
    try std.testing.expectEqual(generation, envelope.generation);
    try std.testing.expectError(error.InvalidInformationOccurrence, other.place(occurrence, original.value, original.origin));
    try std.testing.expectEqual(@as(usize, 0), other.records.items.len);
    var wrong_origin = original.origin;
    wrong_origin.outcome = .failed;
    try std.testing.expectError(error.InformationConflict, envelope.place(occurrence, original.value, wrong_origin));
    wrong_origin = original.origin;
    wrong_origin.lineage[context_index] = 99;
    try std.testing.expectError(error.InformationConflict, envelope.place(occurrence, original.value, wrong_origin));
    const conflicting = try values.create(std.testing.allocator, recorded, Context, .{ .text = "different", .attempts = 1 });
    defer values.destroy(conflicting);
    try std.testing.expectError(error.InformationConflict, envelope.place(occurrence, conflicting, original.origin));
    const wrong_schema = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "source meaning", .attempts = 1 });
    defer values.destroy(wrong_schema);
    try std.testing.expectError(error.DataSchemaMismatch, envelope.place(occurrence, wrong_schema, original.origin));

    var replace = produce;
    replace.produces = &.{};
    replace.replaces = &.{recorded.key};
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, recorded, Context, .{ .text = "source meaning", .attempts = 1 });
    try envelope.apply(replace, &delta, .ok);
    try std.testing.expectEqual(generation + 1, envelope.generation);
    try std.testing.expectEqual(@as(usize, 2), envelope.records.items.len);
    const current = envelope.slots[context_index];
    _ = try envelope.place(occurrence, original.value, original.origin);
    try std.testing.expect(envelope.slots[context_index] == current);
    const restricted = try envelope.view(.{ .id = "unrelated", .kind = .action, .requires = &.{}, .produces = &.{}, .side_effect = .none });
    try std.testing.expect(!restricted.contains(recorded.key));
    var invalidate: pipeline.NodeDelta = .{ .data_invalidations = .initOne(recorded.key) };
    try envelope.apply(.{ .id = "retire", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{recorded.key}, .side_effect = .none }, &invalidate, .ok);
    _ = try envelope.place(occurrence, original.value, original.origin);
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    delta.data_writes[context_index] = original.value;
    try std.testing.expectError(error.AliasedDataValue, envelope.apply(produce, &delta, .ok));
    envelope.discard(&delta);
    const history = envelope.latestInformation(recorded.key);
    try std.testing.expectEqualStrings("source meaning", (try values.read(&history, recorded, Context)).text);
}

test "information retention and current-value publication are atomic under allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, informationAllocationExercise, .{});
}

test "one application shares origin metadata across outputs and releases it after partial changes" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    const both: pipeline.NodeContract = .{ .id = "test.both", .kind = .action, .requires = &.{}, .produces = &.{ .workflow_invocation, .canonical_log_level }, .side_effect = .none };
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "first", .attempts = 1 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 7);
    try envelope.apply(both, &delta, .ok);
    const shared = envelope.origins[context_index].?;
    try std.testing.expect(shared == envelope.origins[count_index].?);

    var invalidate: pipeline.NodeDelta = .{ .data_invalidations = .initOne(.workflow_invocation) };
    try envelope.apply(.{ .id = "test.invalidate", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{.workflow_invocation}, .side_effect = .none }, &invalidate, .ok);
    try std.testing.expect(envelope.origins[context_index] == null);
    try std.testing.expect(envelope.origins[count_index].? == shared);
    try std.testing.expectEqual(@as(u64, 1), envelope.origins[count_index].?.generation);

    const replace: pipeline.NodeContract = .{ .id = "test.replace", .kind = .action, .requires = &.{.canonical_log_level}, .produces = &.{}, .replaces = &.{.canonical_log_level}, .side_effect = .none };
    delta.data_replacements[count_index] = try values.create(std.testing.allocator, count_schema, u32, 8);
    try envelope.apply(replace, &delta, .ok);
    try std.testing.expectEqual(@as(u64, 3), envelope.origins[count_index].?.generation);
}

test "multi-output application allocates one origin and abandons every failed preparation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, multiOutputAllocationCase, .{});
    var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var envelope = envelope_module.PipelineEnvelope.init(measured.allocator(), &schemas);
    defer envelope.deinit();
    const occurrence = try envelope.beginOccurrence("test.both");
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "first", .attempts = 1 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 7);
    const before = measured.alloc_index;
    try envelope.applyOccurrence(occurrence, multi_output, &delta, .ok);
    try std.testing.expectEqual(before + 1, measured.alloc_index);
}

const multi_output: pipeline.NodeContract = .{ .id = "test.both", .kind = .action, .requires = &.{}, .produces = &.{ .workflow_invocation, .canonical_log_level }, .side_effect = .none };

fn multiOutputAllocationCase(allocator: std.mem.Allocator) !void {
    var envelope = envelope_module.PipelineEnvelope.init(allocator, &schemas);
    defer envelope.deinit();
    const occurrence = try envelope.beginOccurrence(multi_output.id);
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(allocator, context_schema, Context, .{ .text = "first", .attempts = 1 });
    delta.data_writes[count_index] = try values.create(allocator, count_schema, u32, 7);
    try envelope.applyOccurrence(occurrence, multi_output, &delta, .ok);
}

test "retained information shares payload ownership and duplicate placement allocates nothing" {
    var live_bytes: [2]usize = undefined;
    for ([_]data.Schema{ context_schema, context_schema.recorded() }, 0..) |schema, index| {
        var measured = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        {
            var envelope = envelope_module.PipelineEnvelope.init(measured.allocator(), &.{schema});
            defer envelope.deinit();
            var delta: pipeline.NodeDelta = .{};
            defer envelope.discard(&delta);
            delta.data_writes[context_index] = try values.create(measured.allocator(), schema, Context, .{ .text = "retained source", .attempts = 1 });
            try envelope.apply(produce, &delta, .ok);
            live_bytes[index] = measured.allocated_bytes - measured.freed_bytes;
            if (schema.history == .execution) {
                const record = envelope.records.items[0];
                try std.testing.expect(record.value == envelope.slots[context_index]);
                const allocated = measured.allocated_bytes;
                measured.fail_index = measured.alloc_index;
                _ = try envelope.place(record.occurrence, record.value, record.origin);
                try std.testing.expectEqual(allocated, measured.allocated_bytes);
            }
        }
        try std.testing.expectEqual(measured.allocated_bytes, measured.freed_bytes);
    }
    try std.testing.expect(live_bytes[1] > live_bytes[0]);
    std.debug.print("information retention bytes: transient={d}, recorded={d}, incremental={d}; duplicate=0\n", .{ live_bytes[0], live_bytes[1], live_bytes[1] - live_bytes[0] });
}

fn informationAllocationExercise(allocator: std.mem.Allocator) !void {
    const recorded = context_schema.recorded();
    var envelope = envelope_module.PipelineEnvelope.init(allocator, &.{recorded});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(allocator, recorded, Context, .{ .text = "retained evidence", .attempts = 1 });
    envelope.apply(produce, &delta, .ok) catch |err| {
        try std.testing.expectEqual(@as(u64, 0), envelope.generation);
        try std.testing.expectEqual(@as(usize, 0), envelope.records.items.len);
        try std.testing.expect(envelope.slots[context_index] == null);
        return err;
    };
    const first = envelope.records.items[0];
    try std.testing.expect((try envelope.place(first.occurrence, first.value, first.origin)).already_present == first);
}

test "shared gate checks source lineage and renewal after source and projection replacements" {
    const retained_context = context_schema.recorded();
    const gate = @import("domain/workflow_gate.zig");
    const proof = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
    const contract: gate.Contract = .{ .id = .{ .bytes = "test.projection@1" }, .issuer = .{ .bytes = "test.validate-projection" }, .evidence = proof.key, .authority = &.{count_schema.key} };
    const project: pipeline.NodeContract = .{ .id = "test.project", .kind = .action, .requires = &.{retained_context.key}, .produces = &.{count_schema.key}, .side_effect = .none };
    const validate: pipeline.NodeContract = .{ .id = contract.issuer.bytes, .kind = .action, .requires = &.{count_schema.key}, .produces = &.{proof.key}, .side_effect = .none };
    for ([_][]const u8{ "Business source", "Repository capability" }) |text| {
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ retained_context, count_schema, proof });
        defer envelope.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&delta);
        delta.data_writes[context_index] = try values.create(std.testing.allocator, retained_context, Context, .{ .text = text, .attempts = 1 });
        try envelope.apply(produce, &delta, .ok);
        delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
        try envelope.apply(project, &delta, .ok);
        delta.data_writes[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(validate, &delta, .ok);
        try std.testing.expect(envelope.checkGate(contract) == null);
        var refresh = produce;
        refresh.requires = produce.produces;
        refresh.replaces = produce.produces;
        refresh.produces = &.{};
        delta.data_replacements[context_index] = try values.create(std.testing.allocator, retained_context, Context, .{ .text = text, .attempts = 1 });
        try envelope.apply(refresh, &delta, .ok);
        try std.testing.expectEqual(.stale_authority, envelope.checkGate(contract).?);
        var rebuild = project;
        rebuild.requires = &.{ retained_context.key, count_schema.key };
        rebuild.replaces = project.produces;
        rebuild.produces = &.{};
        delta.data_replacements[count_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
        try envelope.apply(rebuild, &delta, .ok);
        try std.testing.expectEqual(.stale_authority, envelope.checkGate(contract).?);
        var renew = validate;
        renew.replaces = validate.produces;
        renew.produces = &.{};
        delta.data_replacements[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(renew, &delta, .ok);
        try std.testing.expect(envelope.checkGate(contract) == null);
        const remove: pipeline.NodeContract = .{ .id = "test.remove-source", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{retained_context.key}, .side_effect = .none };
        delta.data_invalidations.insert(retained_context.key);
        try envelope.apply(remove, &delta, .ok);
        try std.testing.expectEqual(.missing_authority, envelope.checkGate(contract).?);
    }
}

test "captured evidence survives transport retirement but keeps every current source dependency" {
    const gate = @import("domain/workflow_gate.zig");
    const packet = values.schema(.model_input_packet, u32, 1, 32).captured();
    const evidence = values.schema(.model_payload_schema_result, u32, 1, 32).captured();
    const proof = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
    const contract: gate.Contract = .{ .id = .{ .bytes = "test.capture@1" }, .issuer = .{ .bytes = "test.validate-capture" }, .evidence = proof.key, .authority = &.{count_schema.key} };
    const validate: pipeline.NodeContract = .{ .id = contract.issuer.bytes, .kind = .action, .requires = contract.authority, .produces = &.{proof.key}, .side_effect = .none };
    for ([_][]const u8{ "Reference business meaning", "Executable decomposition evidence" }) |text| {
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ context_schema, count_schema, packet, evidence, proof });
        defer envelope.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&delta);
        delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = text, .attempts = 1 });
        try envelope.apply(produce, &delta, .ok);
        for ([_]struct { schema: data.Schema, input: pipeline.DataKey }{
            .{ .schema = packet, .input = context_schema.key },
            .{ .schema = evidence, .input = packet.key },
            .{ .schema = count_schema, .input = evidence.key },
        }) |stage| {
            delta.data_writes[@intFromEnum(stage.schema.key)] = try values.create(std.testing.allocator, stage.schema, u32, 1);
            try envelope.apply(.{ .id = "test.capture", .kind = .action, .requires = &.{stage.input}, .produces = &.{stage.schema.key}, .side_effect = .none }, &delta, .ok);
        }
        delta.data_writes[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(validate, &delta, .ok);
        try std.testing.expect(envelope.checkGate(contract) == null);
        delta.data_invalidations = .initMany(&.{ packet.key, evidence.key });
        try envelope.apply(.{ .id = "test.retire", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{ packet.key, evidence.key }, .side_effect = .none }, &delta, .ok);
        delta = .{};
        try std.testing.expect(envelope.checkGate(contract) == null);
        delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = text, .attempts = 1 });
        try envelope.apply(.{ .id = "test.refresh", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{context_schema.key}, .side_effect = .none }, &delta, .ok);
        try std.testing.expectEqual(.stale_authority, envelope.checkGate(contract).?);
        delta.data_invalidations = .initOne(context_schema.key);
        try envelope.apply(.{ .id = "test.remove", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{context_schema.key}, .side_effect = .none }, &delta, .ok);
        try std.testing.expectEqual(.missing_authority, envelope.checkGate(contract).?);
    }
}

test "mixed-generation captured evidence cannot refresh a gate and execution control is not evidence" {
    const gate = @import("domain/workflow_gate.zig");
    const proof = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
    const contract: gate.Contract = .{ .id = .{ .bytes = "test.join@1" }, .issuer = .{ .bytes = "test.validate-join" }, .evidence = proof.key, .authority = &.{count_schema.key} };
    for ([_]bool{ false, true }) |control| {
        const base = values.schema(.model_input_packet, u32, 1, 32);
        const packet = if (control) base.executionControl() else base.captured();
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ context_schema, count_schema, packet, proof });
        defer envelope.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&delta);
        delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "Current business evidence", .attempts = 1 });
        try envelope.apply(produce, &delta, .ok);
        delta.data_writes[@intFromEnum(packet.key)] = try values.create(std.testing.allocator, packet, u32, 1);
        try envelope.apply(.{ .id = "test.capture", .kind = .action, .requires = &.{context_schema.key}, .produces = &.{packet.key}, .side_effect = .none }, &delta, .ok);
        delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "New business evidence", .attempts = 1 });
        try envelope.apply(.{ .id = "test.refresh", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{context_schema.key}, .side_effect = .none }, &delta, .ok);
        delta.data_writes[@intFromEnum(count_schema.key)] = try values.create(std.testing.allocator, count_schema, u32, 1);
        try envelope.apply(.{ .id = "test.join", .kind = .action, .requires = &.{ packet.key, context_schema.key }, .produces = &.{count_schema.key}, .side_effect = .none }, &delta, .ok);
        delta.data_writes[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(.{ .id = contract.issuer.bytes, .kind = .action, .requires = contract.authority, .produces = &.{proof.key}, .side_effect = .none }, &delta, .ok);
        if (control) try std.testing.expect(envelope.checkGate(contract) == null) else try std.testing.expectEqual(.stale_authority, envelope.checkGate(contract).?);
    }
}

test "native repair renews declared dependencies atomically while preserving source freshness and history" {
    const gate = @import("domain/workflow_gate.zig");
    const candidate = values.schema(.model_input_packet, u32, 1, 32).captured().recorded();
    const review = values.schema(.model_payload_schema_result, u32, 1, 32).captured().recorded();
    const proof = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
    const gate_contract: gate.Contract = .{ .id = .{ .bytes = "test.repair@1" }, .issuer = .{ .bytes = "test.validate" }, .evidence = proof.key, .authority = &.{count_schema.key} };
    const project: pipeline.NodeContract = .{ .id = "test.project", .kind = .action, .requires = &.{candidate.key}, .produces = &.{count_schema.key}, .side_effect = .none };
    const validate: pipeline.NodeContract = .{ .id = gate_contract.issuer.bytes, .kind = .action, .requires = &.{count_schema.key}, .produces = &.{proof.key}, .side_effect = .none };
    for (0..7) |scenario| {
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ context_schema, candidate, count_schema, review, proof });
        defer envelope.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&delta);
        delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "Current source or policy", .attempts = 1 });
        try envelope.apply(produce, &delta, .ok);
        delta.data_writes[@intFromEnum(candidate.key)] = try values.create(std.testing.allocator, candidate, u32, 1);
        try envelope.apply(.{ .id = "test.candidate", .kind = .action, .requires = &.{context_schema.key}, .produces = &.{candidate.key}, .side_effect = .none }, &delta, .ok);
        delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
        try envelope.apply(project, &delta, .ok);
        if (scenario == 5) {
            delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "Changed before review", .attempts = 2 });
            try envelope.apply(.{ .id = "test.change-source", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{context_schema.key}, .side_effect = .none }, &delta, .ok);
        }
        delta.data_writes[@intFromEnum(review.key)] = try values.create(std.testing.allocator, review, u32, 1);
        try envelope.apply(.{ .id = "test.review", .kind = .action, .requires = &.{ context_schema.key, candidate.key, count_schema.key }, .produces = &.{review.key}, .side_effect = .none }, &delta, .ok);
        delta.data_writes[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(validate, &delta, .ok);
        if (scenario == 5) try std.testing.expectEqual(.stale_authority, envelope.checkGate(gate_contract).?) else try std.testing.expect(envelope.checkGate(gate_contract) == null);
        const historical = envelope.records.items[1];
        const original_frontier = historical.origin;
        if (scenario == 1) {
            delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "Changed source or policy", .attempts = 2 });
            try envelope.apply(.{ .id = "test.change-source", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{context_schema.key}, .side_effect = .none }, &delta, .ok);
        }
        if (scenario == 6) {
            delta.data_replacements[count_index] = try values.create(std.testing.allocator, count_schema, u32, 2);
            try envelope.apply(.{ .id = "test.rebuild-projection", .kind = .action, .requires = &.{candidate.key}, .produces = &.{}, .replaces = &.{count_schema.key}, .side_effect = .none }, &delta, .ok);
        }
        const generation = envelope.generation;
        const invalidates: []const pipeline.DataKey = if (scenario == 2) &.{ review.key, proof.key } else &.{ count_schema.key, review.key, proof.key };
        const merge: pipeline.NodeContract = .{ .id = "test.merge", .kind = .action, .requires = &.{ context_schema.key, candidate.key, review.key, count_schema.key }, .produces = &.{}, .replaces = &.{candidate.key}, .invalidates = invalidates, .side_effect = .none, .repair_role = if (scenario == 3) .none else .merge };
        delta.data_replacements[@intFromEnum(candidate.key)] = try values.create(std.testing.allocator, candidate, u32, 2);
        delta.data_invalidations = .initMany(invalidates);
        const permit: @import("domain/workflow_retry.zig").Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
        if (scenario != 4) delta.repair_transition = .{ .merged = .{ .permit = permit, .revision_after = 2, .validation = .dependent_review } };
        if ((scenario >= 1 and scenario <= 3) or scenario == 5) {
            try std.testing.expectError(if (scenario == 3) error.UndeclaredRepairTransition else error.InvalidRepairRenewal, envelope.apply(merge, &delta, .ok));
            try std.testing.expectEqual(generation, envelope.generation);
            try std.testing.expect(envelope.slots[count_index] != null);
            continue;
        }
        try envelope.apply(merge, &delta, .ok);
        delta = .{};
        try std.testing.expectEqualDeep(original_frontier, historical.origin);
        try std.testing.expect(envelope.checkGate(gate_contract) != null);
        delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 2);
        try envelope.apply(project, &delta, .ok);
        try std.testing.expectEqual(.missing_evidence, envelope.checkGate(gate_contract).?);
        delta.data_writes[@intFromEnum(proof.key)] = try values.create(std.testing.allocator, proof, gate.Decision, .accepted);
        try envelope.apply(validate, &delta, .ok);
        if (scenario == 4) try std.testing.expect(envelope.checkGate(gate_contract) != null) else try std.testing.expect(envelope.checkGate(gate_contract) == null);
    }
}

test "lineage allocation failure leaves all output slots and generations unpublished" {
    for (0..2) |index| {
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = index });
        var envelope = envelope_module.PipelineEnvelope.init(failing.allocator(), &.{ context_schema, count_schema });
        defer envelope.deinit();
        var delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&delta);
        delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "Original", .attempts = 1 });
        delta.data_writes[@intFromEnum(count_schema.key)] = try values.create(std.testing.allocator, count_schema, u32, 1);
        try std.testing.expectError(error.OutOfMemory, envelope.apply(.{ .id = "test.publish", .kind = .action, .requires = &.{}, .produces = &.{ context_schema.key, count_schema.key }, .side_effect = .none }, &delta, .ok));
        try std.testing.expectEqual(@as(u64, 0), envelope.generation);
        for (envelope.slots) |slot| try std.testing.expect(slot == null);
        for (envelope.origins) |origin| try std.testing.expect(origin == null);
        try std.testing.expect(delta.data_writes[context_index] != null);
    }
}

test "envelope owns copied input and exposes only declared keys" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    var bytes = "hello".*;
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = &bytes, .attempts = 2 });
    try envelope.apply(produce, &delta, .ok);
    try std.testing.expect(delta.data_writes[context_index] == null);
    bytes[0] = 'x';
    const view = try envelope.view(consume);
    const context = try values.read(&view, context_schema, Context);
    try std.testing.expectEqualStrings("hello", context.text);
    try std.testing.expectEqual(@as(u32, 2), context.attempts);
    const hidden = try envelope.view(.{ .id = "test.hidden", .kind = .action, .requires = &.{}, .produces = &.{}, .side_effect = .none });
    try std.testing.expect(!hidden.contains(.workflow_invocation));
    try std.testing.expectError(error.MissingRequiredData, values.read(&hidden, context_schema, Context));
    try std.testing.expectError(error.DataSchemaMismatch, values.read(&view, context_schema, u32));
}

test "optional inputs expose present values without making absent values required" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    const optional: pipeline.NodeContract = .{
        .id = "test.optional",
        .kind = .action,
        .requires = &.{},
        .optional = &.{.workflow_invocation},
        .produces = &.{},
        .side_effect = .none,
    };
    const absent = try envelope.view(optional);
    try std.testing.expect(!absent.contains(.workflow_invocation));
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "optional", .attempts = 1 });
    try envelope.apply(produce, &delta, .ok);
    const present = try envelope.view(optional);
    try std.testing.expectEqualStrings("optional", (try values.read(&present, context_schema, Context)).text);
}

test "retaining immutable pipeline data preserves its owner after invalidation" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "retained once", .attempts = 2 });
    try envelope.apply(produce, &delta, .ok);
    const before = try envelope.view(consume);
    const original = try values.read(&before, context_schema, Context);
    const retained = try values.retain(before.slots[context_index].?);
    defer values.destroy(retained);
    var invalidation: pipeline.NodeDelta = .{ .data_invalidations = .initOne(.workflow_invocation) };
    const invalidate: pipeline.NodeContract = .{ .id = "test.invalidate", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{.workflow_invocation}, .side_effect = .none };
    try envelope.apply(invalidate, &invalidation, .ok);
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    var retained_view: data.View = .{};
    retained_view.slots[context_index] = retained;
    const after = try values.read(&retained_view, context_schema, Context);
    try std.testing.expect(after == original);
    try std.testing.expectEqualStrings("retained once", after.text);
}

test "rejected replacements and schema mismatches preserve the complete old envelope" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    var initial: pipeline.NodeDelta = .{};
    defer envelope.discard(&initial);
    initial.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "old", .attempts = 1 });
    try envelope.apply(produce, &initial, .ok);
    const replace_and_write: pipeline.NodeContract = .{
        .id = "test.replace",
        .kind = .action,
        .requires = &.{.workflow_invocation},
        .produces = &.{.canonical_log_level},
        .replaces = &.{.workflow_invocation},
        .side_effect = .none,
    };
    var bad_version = count_schema;
    bad_version.version = 2;
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "new", .attempts = 2 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, bad_version, u32, 9);
    try std.testing.expectError(error.DataSchemaMismatch, envelope.apply(replace_and_write, &delta, .ok));
    const old = try envelope.view(consume);
    try std.testing.expectEqualStrings("old", (try values.read(&old, context_schema, Context)).text);
    const require_count: pipeline.NodeContract = .{ .id = "test.count", .kind = .action, .requires = &.{.canonical_log_level}, .produces = &.{}, .side_effect = .none };
    try std.testing.expectError(error.MissingRequiredData, envelope.view(require_count));
    envelope.discard(&delta);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "new", .attempts = 2 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 9);
    try envelope.apply(replace_and_write, &delta, .ok);
    const next = try envelope.view(consume);
    try std.testing.expectEqualStrings("new", (try values.read(&next, context_schema, Context)).text);
    const counts = try envelope.view(require_count);
    try std.testing.expectEqual(@as(u32, 9), (try values.read(&counts, count_schema, u32)).*);

    var invalidation: pipeline.NodeDelta = .{ .data_invalidations = .initOne(.workflow_invocation) };
    const invalidate: pipeline.NodeContract = .{ .id = "test.invalidate", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{.workflow_invocation}, .side_effect = .none };
    try envelope.apply(invalidate, &invalidation, .ok);
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    try std.testing.expectError(error.InvalidationTargetMissing, envelope.apply(invalidate, &invalidation, .ok));
}

test "missing extra wrong-key and aliased values cannot satisfy a data contract" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &schemas);
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    try std.testing.expectError(error.MissingDeclaredWrite, envelope.apply(produce, &delta, .ok));
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
    try std.testing.expectError(error.UndeclaredWrite, envelope.apply(produce, &delta, .ok));
    delta.data_writes[context_index] = delta.data_writes[count_index];
    const both: pipeline.NodeContract = .{ .id = "test.both", .kind = .action, .requires = &.{}, .produces = &.{ .canonical_log_level, .workflow_invocation }, .side_effect = .none };
    try std.testing.expectError(error.AliasedDataValue, envelope.apply(both, &delta, .ok));
    envelope.discard(&delta); // Duplicate handle is destroyed once.
    delta.data_writes[context_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
    try std.testing.expectError(error.DataSchemaMismatch, envelope.apply(produce, &delta, .ok));
    envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "retained", .attempts = 1 });
    try envelope.apply(produce, &delta, .ok);
    const view = try envelope.view(consume);
    delta.data_replacements[context_index] = view.slots[context_index];
    const replace: pipeline.NodeContract = .{ .id = "test.replace", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{.workflow_invocation}, .side_effect = .none };
    try std.testing.expectError(error.AliasedDataValue, envelope.apply(replace, &delta, .ok));
    envelope.discard(&delta); // A borrowed input remains owned by the envelope.
    try std.testing.expectEqualStrings("retained", (try values.read(&view, context_schema, Context)).text);
}

test "value construction enforces native type version and allocation bounds" {
    try std.testing.expectError(error.DataSchemaMismatch, values.create(std.testing.allocator, count_schema, Context, .{ .text = "wrong type", .attempts = 1 }));
    var invalid = context_schema;
    invalid.version = 0;
    try std.testing.expectError(error.InvalidDataSchema, values.create(std.testing.allocator, invalid, Context, .{ .text = "", .attempts = 1 }));
    var small = context_schema;
    small.maximum_bytes = @sizeOf(Context) + 1;
    try std.testing.expectError(error.DataValueLimitExceeded, values.create(std.testing.allocator, small, Context, .{ .text = "oversized", .attempts = 1 }));
}

test "unregistered schemas invalid telemetry and conflicting effects leave values unchanged" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "retained", .attempts = 1 });
    try std.testing.expectError(error.UnregisteredDataSchema, envelope.apply(produce, &delta, .ok));
    envelope.schemas = &schemas;
    delta.telemetry_fact_count = 255;
    try std.testing.expectError(error.InvalidTelemetryCount, envelope.apply(produce, &delta, .ok));
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    delta.telemetry_fact_count = 0;
    try envelope.apply(produce, &delta, .ok);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "rejected", .attempts = 2 });
    delta.data_invalidations.insert(.workflow_invocation);
    const conflicting: pipeline.NodeContract = .{
        .id = "test.conflict",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{.workflow_invocation},
        .invalidates = &.{.workflow_invocation},
        .side_effect = .none,
    };
    try std.testing.expectError(error.ConflictingDataEffects, envelope.apply(conflicting, &delta, .ok));
    const retained = try envelope.view(consume);
    try std.testing.expectEqualStrings("retained", (try values.read(&retained, context_schema, Context)).text);
}

test "value and envelope ownership survives every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    const Nested = struct { tags: []const []const u8, choice: union(enum) { text: []const u8, count: u32 }, context: ?*const Context };
    const nested_schema = values.schema(.workflow_invocation, Nested, 1, 1024);
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{nested_schema});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(allocator, nested_schema, Nested, .{
        .tags = &.{ "one", "two" },
        .choice = .{ .text = "three" },
        .context = &.{ .text = "four", .attempts = 4 },
    });
    try envelope.apply(produce, &delta, .ok);
    const view = try envelope.view(consume);
    const result = try values.read(&view, nested_schema, Nested);
    try std.testing.expectEqualStrings("two", result.tags[1]);
    try std.testing.expectEqualStrings("three", result.choice.text);
    try std.testing.expectEqualStrings("four", result.context.?.text);
}
