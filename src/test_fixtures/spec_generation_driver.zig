//! Scripted candidate data injected at the fake provider; the real compiler,
//! engine, runner, model lifecycle and domain validators still execute.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const workflow = @import("../domain/workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
pub const Fault = struct {
    stage: enum { extraction, reconciliation, generation, repair, support },
    shape: enum { empty, nested_empty, mixed_variant, alternating_protocol },
    repetition: union(enum) { once, every_request: u32, persistent } = .once,
};
pub const Driver = struct {
    runner: *@import("../application/workflow_pipeline_runner.zig").Runner,
    fake: *@import("../adapters/provider/fake_llm_provider.zig").FakeLLMProvider,
    support_fault: ?@import("spec_generation_responses.zig").SupportFault = null,
    support_post: bool = false,
    source_gaps: bool = false,
    evidence_fault: @FieldType(@import("spec_generation_responses.zig").Options, "evidence_fault") = null,
    candidate_omission: bool = false,
    extraction_omission: bool = false,
    support_repair_calls: usize = 0,
    support_merges: usize = 0,
    omission_repair_calls: usize = 0,
    text_fault: bool = false,
    failed_text_repair: bool = false,
    text_repair_calls: usize = 0,
    text_failure_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_original_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_text_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_failure_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    reconciliation_repair_fault: @FieldType(@import("spec_generation_responses.zig").Options, "reconciliation_repair_fault") = null,
    reconciliation_fault: ?@import("spec_generation_responses.zig").ReconciliationFault = null,
    reconciliation_protocol_fault: ?enum { envelope_once, envelope_then_json, token_once, token_always } = null,
    reconciliation_repair_calls: usize = 0,
    reconciliation_merges: usize = 0,
    unchanged_reconciliation_merges: usize = 0,
    malformed: bool = false,
    uncertain: bool = false,
    malformed_once: bool = false,
    repair: bool = false,
    failed_repair: bool = false,
    omit_exact: bool = false,
    citation_fault: @FieldType(@import("spec_generation_responses.zig").Options, "citation_fault") = null,
    failed_citation_repair: bool = false,
    citation_repair_calls: usize = 0,
    missing_classifications: bool = false,
    failed_classification_repair: bool = false,
    malformed_classification_repair_once: bool = false,
    classification_repair_calls: usize = 0,
    brief_uncertain: bool = false,
    entities_required: bool = false,
    generation_gap: bool = false,
    calls: usize = 0,
    fault: ?Fault = null,
    fault_calls: usize = 0,
    fault_requests: usize = 0,
    fault_request: ?*const @import("../domain/model_request_identity.zig").ModelRequestId = null,
    pub fn run(self: *Driver) @import("../domain/run_outcome.zig").Outcome {
        return @import("../application/workflow_engine_orchestrator.zig").run(.{ .context = self, .vtable = &.{ .validate_operation_registry = selected, .parse_invocation = selected, .select_workflow = selected, .prepare_workflow = ready, .selected_graph = graph, .invoke_invocation = invocation, .invoke_step = step } });
    }
    fn selected(_: *anyopaque) @import("../application/workflow_engine_child_bindings.zig").SelectionStepOutcome {
        return .ok;
    }
    fn ready(_: *anyopaque) @import("../application/workflow_engine_child_bindings.zig").PreparationOutcome {
        return .ok;
    }
    fn graph(context: *const anyopaque) *const @import("../domain/workflow_compilation.zig").CompiledWorkflow {
        const self: *const Driver = @ptrCast(@alignCast(context));
        return self.runner.selected.graph;
    }
    fn invocation(context: *anyopaque) @import("../domain/workflow_execution.zig").Applied {
        const self: *Driver = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) @import("../domain/workflow_execution.zig").Applied {
        const self: *Driver = @ptrCast(@alignCast(context));
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes) and std.mem.eql(u8, entry.operation_id.bytes, "invoke-model")) {
            const view: data.View = .{ .slots = self.runner.envelope.slots };
            const body = @import("spec_generation_responses.zig").build(arena.allocator(), view, .{ .evidence_fault = self.evidence_fault, .source_gaps = self.source_gaps, .support_fault = self.support_fault, .support_post = self.support_post, .candidate_omission = self.candidate_omission, .extraction_omission = self.extraction_omission, .text_fault = self.text_fault, .failed_text_repair = self.failed_text_repair, .reconciliation_repair_fault = self.reconciliation_repair_fault, .reconciliation_fault = self.reconciliation_fault, .uncertain = self.uncertain, .brief_uncertain = self.brief_uncertain, .repair = self.repair, .failed_repair = self.failed_repair, .omit_exact = self.omit_exact, .entities_required = self.entities_required, .generation_gap = self.generation_gap, .citation_fault = self.citation_fault, .failed_citation_repair = self.failed_citation_repair, .missing_classifications = self.missing_classifications, .failed_classification_repair = self.failed_classification_repair }) catch |err| std.debug.panic("invalid scripted candidate: {s}", .{@errorName(err)});
            self.fake.invocation_plan.complete.content = if (self.malformed or (self.malformed_once and self.calls == 0)) "{" else body;
            const current_request = requests.readCurrent(&view, requests.prepared_schema) catch unreachable;
            const attempt = @import("../domain/model_attempt_accounting.zig").latestAttempt(self.runner.model_accounting.?.attempts).ordinal().value;
            const validated = requests.readCurrent(&view, requests.validated_schema) catch unreachable;
            var base_buffer: [2]@import("../domain/llm_provider_operation.zig").ModelVisibleContent = undefined;
            const base = validated.content(&base_buffer);
            const content = current_request.prepared().?.content;
            std.testing.expectEqual(base.len + @as(usize, if (attempt > 1) 3 else 0), content.len) catch unreachable;
            std.testing.expectEqualDeep(base, content[0..base.len]) catch unreachable;
            if (current_request.id().purpose == .semantic_review) {
                const packet = @import("../application/pipeline_values.zig").read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch unreachable;
                const input = std.json.parseFromSlice(std.json.Value, arena.allocator(), packet.body(), .{}) catch unreachable;
                var permits_applicability = false;
                for (input.value.object.get("requirements").?.array.items) |requirement| {
                    permits_applicability = permits_applicability or requirement.object.contains("permitted_not_applicable");
                    std.testing.expect(requirement.object.contains("task") and requirement.object.contains("evidence")) catch unreachable;
                    std.testing.expect(!requirement.object.contains("kind") and !requirement.object.contains("slot") and !requirement.object.contains("unit")) catch unreachable;
                }
                const schema = std.json.parseFromSlice(std.json.Value, arena.allocator(), current_request.prepared().?.response_schema.modelBytes(), .{}) catch unreachable;
                const value = schema.value.object.get("properties").?.object.get("entries").?.object.get("items").?.object.get("properties").?.object.get("value").?;
                assertReviewShape(value, permits_applicability) catch unreachable;
            }
            if (current_request.id().purpose == .atomic_repair) {
                if (current_request.id().immutable_unit_owner_id == .semantic_review) self.support_repair_calls += 1;
                if (view.contains(@import("../application/specification_omission_repair_workflow.zig").schema.key)) self.omission_repair_calls += 1;
                const packet = @import("../application/pipeline_values.zig").read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch unreachable;
                assertRepairRequest(arena.allocator(), current_request.prepared().?, packet) catch unreachable;
            }
            if (current_request.id().immutable_unit_owner_id == .reference_global and current_request.id().purpose == .atomic_repair) {
                const packet = @import("../application/pipeline_values.zig").read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch unreachable;
                if (self.reconciliation_protocol_fault) |fault| {
                    if (fault == .token_once or fault == .token_always) {
                        if (self.reconciliation_repair_calls == 0 or fault == .token_always) self.fake.invocation_plan.complete.content = "{\"kind\":\"preserved_token\",\"token_id\":{\"ordinal\":1}}";
                    } else if (self.reconciliation_repair_calls == 0 or fault == .envelope_then_json) {
                        const input = std.json.parseFromSlice(std.json.Value, arena.allocator(), packet.body(), .{}) catch unreachable;
                        const echoed = std.json.Stringify.valueAlloc(arena.allocator(), input.value.object.get("repair").?, .{}) catch unreachable;
                        self.fake.invocation_plan.complete.content = if (self.reconciliation_repair_calls == 0) echoed else echoed[0 .. echoed.len - 1];
                    }
                }
                self.reconciliation_repair_calls += 1;
            }
            if (current_request.id().immutable_unit_owner_id == .reference_chunk and current_request.id().purpose == .atomic_repair) {
                if (self.malformed_classification_repair_once and self.classification_repair_calls == 0) self.fake.invocation_plan.complete.content = "{}";
                const packet = @import("../application/pipeline_values.zig").read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch unreachable;
                if (std.mem.eql(u8, packet.resultDefinition().?.bytes, "business_text_replacement")) self.text_repair_calls += 1 else if (self.citation_fault != null) self.citation_repair_calls += 1 else self.classification_repair_calls += 1;
            }
            if (self.fault) |fault| {
                const request = requests.readCurrent(&view, requests.prepared_schema) catch unreachable;
                const stage: @FieldType(Fault, "stage") = switch (request.id().immutable_unit_owner_id) {
                    .reference_chunk => .extraction,
                    .reference_global => .reconciliation,
                    .specification_unit => if (request.id().purpose == .atomic_repair) .repair else .generation,
                    .semantic_review => .support,
                    else => unreachable,
                };
                if (stage == fault.stage and fault.shape == .alternating_protocol and attempt > 1) {
                    const evidence = std.json.parseFromSlice(struct { rejected_response: []const u8 }, arena.allocator(), content[content.len - 1].evidence, .{}) catch unreachable;
                    std.testing.expectEqualStrings(if (attempt % 2 == 0) "{" else "{}", evidence.value.rejected_response) catch unreachable;
                }
                const reject = switch (fault.repetition) {
                    .once => self.fault_calls == 0,
                    .every_request => |count| attempt <= count,
                    .persistent => true,
                };
                if (stage == fault.stage and reject) {
                    if (self.fault_request != request.id()) {
                        std.debug.assert(self.fault_request == null or fault.repetition == .every_request);
                        self.fault_request = request.id();
                        self.fault_requests += 1;
                    }
                    self.fake.invocation_plan.complete.content = if (fault.shape == .alternating_protocol) (if (attempt % 2 == 1) "{" else "{}") else corrupt(arena.allocator(), body, fault.shape) catch unreachable;
                    self.fault_calls += 1;
                }
            }
            self.calls += 1;
        };
        const result = self.runner.bindings().invokeStep(id);
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes) and std.mem.eql(u8, entry.operation_id.bytes, @import("../actions/reference/merge_reference_reconciliation_repair.zig").Action.contract.id) and result.status() == .ok) {
            const view: data.View = .{ .slots = self.runner.envelope.slots };
            const parsed = @import("../application/reference_extraction_workflow.zig").read(&view, @import("../application/reference_reconciliation_workflow.zig").parsed_schema, .reconciliation_parsed) catch unreachable;
            const merged = parsed.payload().reconciliation_parsed.source.last_repair.?;
            const observed = @import("../application/candidate_repair_observations.zig").read(arena.allocator(), &view) catch unreachable;
            var matches: usize = 0;
            for (observed) |item| if (std.mem.eql(u8, item.authorization.bytes, merged.authorization.bytes)) {
                std.testing.expectEqualDeep(merged, item) catch unreachable;
                matches += 1;
            };
            std.testing.expectEqual(@as(usize, 1), matches) catch unreachable;
            self.reconciliation_merges += 1;
            if (!merged.changed) self.unchanged_reconciliation_merges += 1;
        };
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes) and std.mem.eql(u8, entry.operation_id.bytes, "merge-specification-support-repair") and (result.status() == .ok or result.status() == .invalid)) {
            const view: data.View = .{ .slots = self.runner.envelope.slots };
            const support = @import("../application/required_authority_values.zig").read(&view, @import("../application/specification_support_workflow.zig").schema, .support) catch unreachable;
            const merge = switch (support) {
                .accepted => |accepted| accepted.candidate.last_repair.?,
                .rejected => |rejected| rejected.candidate.?.last_repair.?,
            };
            const observations = @import("../application/candidate_repair_observations.zig").read(arena.allocator(), &view) catch unreachable;
            var matches: usize = 0;
            for (observations) |observation| if (std.mem.eql(u8, observation.authorization.bytes, merge.authorization.bytes)) {
                std.testing.expectEqualDeep(merge, observation) catch unreachable;
                matches += 1;
            };
            std.testing.expectEqual(@as(usize, 1), matches) catch unreachable;
            self.support_merges += 1;
        };
        const diagnostic = @import("../application/candidate_validation_diagnostics.zig").read(&.{ .slots = self.runner.envelope.slots }) catch unreachable;
        if (diagnostic) |value| switch (value) {
            .extraction_text => |rejection| if (self.text_failure_origin == null) {
                self.text_failure_origin = rejection.origin;
            },
            .token_classifications => |rejection| if (self.classification_failure_origin == null) {
                self.classification_failure_origin = rejection.origin;
                const extraction = @import("../application/reference_extraction_workflow.zig");
                const parsed = extraction.read(&.{ .slots = self.runner.envelope.slots }, extraction.parsed_schema, .parsed) catch unreachable;
                for (parsed.payload().parsed.entries) |entry| if (entry.scope.chunk_id.eql(rejection.scope.chunk_id)) {
                    self.classification_original_origin = entry.origin;
                    if (entry.text_origins.len != 0) self.classification_text_origin = entry.text_origins[0].origin;
                };
            },
            else => {},
        };
        return result;
    }
};

fn assertRepairRequest(a: std.mem.Allocator, request: *const @import("../domain/llm_provider_operation.zig").IdentifiedProviderNeutralModelRequest, packet: *const @import("../domain/model_input_packet.zig").Packet) !void {
    // Exercise the real provider serializer, without making a network call.
    const wire = try @import("../adapters/provider/bedrock_request.zig").encode(a, request, .inference);
    const decoded = try std.json.parseFromSlice(std.json.Value, a, wire, .{});
    const user = decoded.value.object.get("messages").?.array.items[0].object.get("content").?.array.items[0].object.get("text").?.string;
    try std.testing.expectEqualStrings(packet.body(), user);
    const input = try std.json.parseFromSlice(std.json.Value, a, user, .{});
    const repair = input.value.object.get("repair").?.object;
    try std.testing.expect(!repair.contains("expected"));
    try std.testing.expectEqual(std.mem.eql(u8, repair.get("operation").?.string, "replace"), repair.contains("current_value"));
    if (request.model_request_id.immutable_unit_owner_id == .semantic_review) {
        const rule = repair.get("rule").?.object;
        if (std.mem.eql(u8, rule.get("issue").?.string, "invalid_evidence")) {
            const current = rule.get("finding").?.object.get("decision").?.string;
            const minimum = rule.get("evidence_rule").?.object.get("minimum").?.string;
            if (std.mem.eql(u8, current, "supported") or std.mem.eql(u8, current, "not_applicable")) try std.testing.expectEqualStrings("claim_required", minimum);
            try std.testing.expect(rule.contains("evidence_issue"));
        }
    }
    if (packet.resultDefinition()) |definition| {
        if (std.mem.eql(u8, definition.bytes, "finding") or std.mem.eql(u8, definition.bytes, "applicability_finding")) {
            const schema = try std.json.parseFromSlice(std.json.Value, a, request.response_schema.modelBytes(), .{});
            try assertReviewShape(schema.value, std.mem.eql(u8, definition.bytes, "applicability_finding"));
        }
        const payload: ?[]const u8 = if (std.mem.eql(u8, definition.bytes, "business_text")) "segments" else if (std.mem.eql(u8, definition.bytes, "reference_text")) "nodes" else if (std.mem.eql(u8, definition.bytes, "token_reference")) "token_id" else null;
        if (payload) |field| {
            const schema = try std.json.parseFromSlice(std.json.Value, a, request.response_schema.modelBytes(), .{});
            const properties = schema.value.object.get("properties").?.object;
            try std.testing.expectEqual(@as(usize, 1), properties.count());
            try std.testing.expect(properties.contains(field));
        }
    }
    var schema_found = false;
    var instruction_found = false;
    for (decoded.value.object.get("system").?.array.items) |part| {
        const value = part.object.get("text").?.string;
        schema_found = schema_found or std.mem.eql(u8, value, request.response_schema.modelBytes());
        instruction_found = instruction_found or std.mem.indexOf(u8, value, "Return only the selected replacement, matching the supplied schema and evidence.") != null;
    }
    try std.testing.expect(schema_found and instruction_found);
}

fn assertReviewShape(schema: std.json.Value, permits_applicability: bool) !void {
    const properties = schema.object.get("properties").?.object;
    try std.testing.expectEqual(@as(usize, 4), properties.count());
    try std.testing.expect(!properties.contains("finding") and !properties.contains("disposition"));
    const decisions = properties.get("decision").?.object.get("enum").?.array.items;
    try std.testing.expectEqual(@as(usize, if (permits_applicability) 6 else 5), decisions.len);
    var has_not_applicable = false;
    for (decisions) |decision| has_not_applicable = has_not_applicable or std.mem.eql(u8, decision.string, "not_applicable");
    try std.testing.expectEqual(permits_applicability, has_not_applicable);
}

fn corrupt(allocator: std.mem.Allocator, body: []const u8, shape: @FieldType(Fault, "shape")) ![]const u8 {
    if (shape == .empty) return "{}";
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    if (shape == .mixed_variant) {
        try parsed.value.object.put(allocator, "foreign_variant", .{ .object = .{} });
    } else {
        std.debug.assert(emptyNested(&parsed.value, true));
    }
    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
}
fn emptyNested(value: *std.json.Value, root: bool) bool {
    switch (value.*) {
        .object => |*object| {
            if (!root and (object.contains("kind") or object.contains("ordinal"))) {
                // The caller uses an arena; the complete parsed owner is kept.
                object.clearRetainingCapacity();
                return true;
            }
            for (object.values()) |*child| if (emptyNested(child, false)) return true;
        },
        .array => |*array| for (array.items) |*child| {
            if (emptyNested(child, false)) return true;
        },
        else => {},
    }
    return false;
}
