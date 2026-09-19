//! Scripted candidate data injected at the fake provider; the real compiler,
//! engine, runner, model lifecycle and domain validators still execute.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const workflow = @import("../domain/workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
pub const Fault = struct {
    stage: enum { extraction, reconciliation, generation, repair, support, candidate_review },
    shape: enum { empty, nested_empty, mixed_variant, alternating_protocol },
    repetition: union(enum) { once, every_request: u32, persistent } = .once,
};
pub const Driver = struct {
    runner: *@import("../application/workflow_pipeline_runner.zig").Runner,
    fake: *@import("../adapters/provider/fake_llm_provider.zig").FakeLLMProvider,
    support_fault: ?@import("spec_generation_responses.zig").SupportFault = null,
    support_post: bool = false,
    principle_conflict: bool = false,
    principle_calls: usize = 0,
    measurement_prefix: ?[]const u8 = null,
    source_gaps: bool = false,
    source_loss: ?@import("spec_generation_responses.zig").SourceLoss = null,
    source_repair_calls: usize = 0,
    evidence_fault: @FieldType(@import("spec_generation_responses.zig").Options, "evidence_fault") = null,
    candidate_omissions: @FieldType(@import("spec_generation_responses.zig").Options, "candidate_omissions") = null,
    extraction_omission: bool = false,
    support_repair_calls: usize = 0,
    support_merges: usize = 0,
    omission_repair_calls: usize = 0,
    omission_merges: usize = 0,
    omission_resolutions: usize = 0,
    omission_keys: [2]?@import("../domain/workflow_retry.zig").Key = @splat(null),
    text_fault: bool = false,
    failed_text_repair: bool = false,
    text_repair_calls: usize = 0,
    text_failure_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_original_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_text_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    classification_failure_origin: ?@import("../domain/model_candidate_origin.zig").Origin = null,
    reconciliation_repair_fault: @FieldType(@import("spec_generation_responses.zig").Options, "reconciliation_repair_fault") = null,
    reconciliation_fault: ?@import("spec_generation_responses.zig").ReconciliationFault = null,
    disposition_sequence: @FieldType(@import("spec_generation_responses.zig").Options, "disposition_sequence") = null,
    summary_sequence: ?@import("summary_protocol_sequence.zig").Mode = null,
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
    pub fn verifyDispositionSequence(self: *Driver, result: @import("../domain/run_outcome.zig").Outcome) !void {
        const exhausted = self.disposition_sequence == .exhaust;
        try std.testing.expectEqual(@as(usize, 2), self.reconciliation_repair_calls);
        try std.testing.expectEqual(@as(usize, if (exhausted) 2 else 3), self.reconciliation_merges);
        try std.testing.expectEqual(@as(usize, 0), self.unchanged_reconciliation_merges);
        const ledger = self.runner.tokenLedger();
        try std.testing.expectEqual(self.calls, ledger.accounted_operations.items.len);
        try std.testing.expectEqual(@as(u128, self.calls) * (self.fake.invocation_plan.complete.input_tokens + self.fake.invocation_plan.complete.output_tokens), ledger.committed());
        const view: data.View = .{ .slots = self.runner.envelope.slots };
        const identities = try @import("../application/pipeline_values.zig").read(&view, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const observations = try @import("../application/candidate_repair_observations.zig").read(arena.allocator(), &view);
        try std.testing.expectEqual(@as(usize, 1), observations.len);
        try std.testing.expectEqual(@as(u64, if (exhausted) 3 else 4), observations[0].revision_after);
        if (exhausted) {
            var matches: usize = 0;
            for (ledger.accounted_operations.items) |operation| if (observations[0].origin.?.matches(identities, operation.id)) {
                try std.testing.expect(operation.id.model_request_id.purpose == .atomic_repair);
                matches += 1;
            };
            try std.testing.expectEqual(@as(usize, 1), matches);
        } else try std.testing.expect(observations[0].origin == null);
        if (exhausted) {
            try std.testing.expectEqual(@as(usize, 8), self.calls);
            try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
            try std.testing.expectEqual(@as(u32, 1), result.execution_rejected.retry_limit.limit.value);
            try std.testing.expectEqual(@as(u64, 2), result.execution_rejected.retry_limit.completed_executions);
            const rejected = (try @import("../application/candidate_validation_diagnostics.zig").read(&view)).?.reconciliation;
            try std.testing.expectEqual(.same_content_kind, rejected.issue.expected.constraint);
            try std.testing.expectEqual(@as(u64, 3), rejected.revision);
            try std.testing.expectEqualDeep(observations[0].origin, rejected.origin);
            try std.testing.expect(!view.contains(.clarification_needs) and !view.contains(.published_workflow_output));
        }
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
            const attempt = @import("../domain/model_attempt_accounting.zig").latestAttempt(self.runner.model_accounting.?.attempts).ordinal().value;
            const body = @import("spec_generation_responses.zig").build(arena.allocator(), view, .{ .summary_sequence = self.summary_sequence, .disposition_sequence = self.disposition_sequence, .attempt = attempt, .source_loss = self.source_loss, .evidence_fault = self.evidence_fault, .source_gaps = self.source_gaps, .support_fault = self.support_fault, .support_merges = self.support_merges, .support_post = self.support_post, .principle_conflict = self.principle_conflict, .candidate_omissions = self.candidate_omissions, .extraction_omission = self.extraction_omission, .text_fault = self.text_fault, .failed_text_repair = self.failed_text_repair, .reconciliation_repair_fault = self.reconciliation_repair_fault, .reconciliation_fault = self.reconciliation_fault, .uncertain = self.uncertain, .brief_uncertain = self.brief_uncertain, .repair = self.repair, .failed_repair = self.failed_repair, .omit_exact = self.omit_exact, .entities_required = self.entities_required, .generation_gap = self.generation_gap, .citation_fault = self.citation_fault, .failed_citation_repair = self.failed_citation_repair, .missing_classifications = self.missing_classifications, .failed_classification_repair = self.failed_classification_repair }) catch |err| std.debug.panic("invalid scripted candidate: {s}", .{@errorName(err)});
            self.fake.invocation_plan.complete.content = if (self.malformed or (self.malformed_once and self.calls == 0)) "{" else body;
            const current_request = requests.readCurrent(&view, requests.prepared_schema) catch unreachable;
            if (self.measurement_prefix) |prefix| if (self.summary_sequence != null or current_request.part() != null or current_request.id().immutable_unit_owner_id == .semantic_review) {
                const Part = struct { kind: []const u8, text: []const u8 };
                const parts = arena.allocator().alloc(Part, current_request.prepared().?.content.len) catch unreachable;
                for (parts, current_request.prepared().?.content) |*part, content_part| part.* = .{ .kind = @tagName(content_part), .text = content_part.bytes() };
                const measured = std.json.Stringify.valueAlloc(arena.allocator(), .{
                    .purpose = @tagName(current_request.id().purpose),
                    .content = parts,
                    .schema = current_request.prepared().?.response_schema.modelBytes(),
                    .composition = if (current_request.part()) |part| .{
                        .part = part.plan.parts()[part.part].id.bytes,
                        .canonical_schema = part.plan.resultSchema().modelBytes(),
                        .base_input = part.base.body(),
                    } else null,
                }, .{}) catch unreachable;
                const path = std.fmt.allocPrint(arena.allocator(), "{s}-{d}-{d}.json", .{ prefix, self.calls, attempt }) catch unreachable;
                std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = measured }) catch unreachable;
            };
            const validated = requests.readCurrent(&view, requests.validated_schema) catch unreachable;
            var base_buffer: [2]@import("../domain/llm_provider_operation.zig").ModelVisibleContent = undefined;
            const base = validated.content(&base_buffer);
            const content = current_request.prepared().?.content;
            std.testing.expectEqual(base.len + @as(usize, if (attempt > 1) 3 else 0), content.len) catch unreachable;
            std.testing.expectEqualDeep(base, content[0..base.len]) catch unreachable;
            if (attempt > 1) std.testing.expectEqualStrings(current_request.protocolPrompt().?, content[base.len].guidance) catch unreachable;
            if (current_request.id().purpose == .semantic_review) {
                const packet = @import("../application/pipeline_values.zig").read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch unreachable;
                const input = std.json.parseFromSlice(std.json.Value, arena.allocator(), packet.body(), .{}) catch unreachable;
                const policy = input.value.object.get("subject").? == .string;
                if (policy) {
                    self.principle_calls += 1;
                    std.testing.expectEqualStrings("principle_consistency", input.value.object.get("subject").?.string) catch unreachable;
                    std.testing.expect(input.value.object.get("principles").?.array.items.len != 0) catch unreachable;
                    const schema = std.json.parseFromSlice(std.json.Value, arena.allocator(), current_request.prepared().?.response_schema.modelBytes(), .{}) catch unreachable;
                    const properties = schema.value.object.get("properties").?.object.get("entries").?.object.get("items").?.object.get("properties").?.object.get("value").?.object.get("properties").?.object;
                    std.testing.expectEqual(@as(usize, 3), properties.count()) catch unreachable;
                    std.testing.expect(properties.contains("decision") and properties.contains("citations") and properties.contains("detail")) catch unreachable;
                } else {
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
            }
            if (current_request.id().purpose == .atomic_repair) {
                if (view.contains(.source_omission_repair)) self.source_repair_calls += 1;
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
                const matches_stage = stage == fault.stage or (stage == .support and fault.stage == .candidate_review and (authorityInputs(&view)).specification != null);
                if (matches_stage and fault.shape == .alternating_protocol and attempt > 1) {
                    const evidence = std.json.parseFromSlice(struct { rejected_response: []const u8 }, arena.allocator(), content[content.len - 1].evidence, .{}) catch unreachable;
                    std.testing.expectEqualStrings(if (attempt % 2 == 0) "{" else "{}", evidence.value.rejected_response) catch unreachable;
                }
                const reject = switch (fault.repetition) {
                    .once => self.fault_calls == 0,
                    .every_request => |count| attempt <= count,
                    .persistent => true,
                };
                if (matches_stage and reject) {
                    if (fault.stage == .candidate_review) {
                        std.testing.expect(authorityInputs(&view).specification != null) catch unreachable;
                        std.testing.expect(self.runner.repair_retry.currentPermit() == null) catch unreachable;
                        std.testing.expectEqual(@as(u32, 1), attempt) catch unreachable;
                    }
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
        // Retain pre-merge evidence so the shared fixture can check siblings
        // after the runner invalidates repair state and replaces the review.
        const values = @import("../application/pipeline_values.zig");
        var before_merge: data.View = .{};
        defer for (before_merge.slots) |value| if (value) |retained| values.destroy(retained);
        var semantic_parent: ?@import("../domain/workflow_retry.zig").Permit = null;
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes)) {
            if (self.candidate_omissions != null and std.mem.eql(u8, entry.operation_id.bytes, "apply-specification-support")) semantic_parent = self.runner.repair_retry.currentPermit();
            const keys: []const @import("../domain/pipeline.zig").DataKey = if (std.mem.eql(u8, entry.operation_id.bytes, "merge-specification-support-repair")) &.{ .specification_support_review, .specification_support_repair } else if (std.mem.eql(u8, entry.operation_id.bytes, "merge-specification-omission-repair")) &.{.specification_omission_repair} else if (self.summary_sequence != null and std.mem.eql(u8, entry.operation_id.bytes, "merge-reference-reconciliation-repair")) &.{.parsed_reference_reconciliation} else &.{};
            for (keys) |key| {
                const index = @intFromEnum(key);
                before_merge.slots[index] = values.retain(self.runner.envelope.slots[index].?) catch unreachable;
            }
        };
        const result = self.runner.bindings().invokeStep(id);
        if (semantic_parent) |parent| {
            std.testing.expectEqual(.ok, result.status()) catch unreachable;
            std.testing.expect(self.runner.repair_retry.currentPermit() == null) catch unreachable;
            std.testing.expectEqualDeep(self.omission_keys[self.omission_resolutions].?, parent.key) catch unreachable;
            self.omission_resolutions += 1;
        }
        if (before_merge.contains(.specification_omission_repair) and result.status() == .ok) {
            const permit = assertOmissionMerge(arena.allocator(), &before_merge, &.{ .slots = self.runner.envelope.slots }) catch unreachable;
            for (self.omission_keys[0..self.omission_merges]) |key| std.testing.expect(!std.meta.eql(key.?, permit.key)) catch unreachable;
            self.omission_keys[self.omission_merges] = permit.key;
            self.omission_merges += 1;
        }
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
            if (self.disposition_sequence != null) {
                std.testing.expectEqual(@as(u64, self.reconciliation_merges + 1), merged.revision_before) catch unreachable;
                std.testing.expectEqual(@as(u64, self.reconciliation_merges + 2), merged.revision_after) catch unreachable;
                std.testing.expect(merged.changed) catch unreachable;
                if (self.reconciliation_merges < 2) {
                    const identities = @import("../application/pipeline_values.zig").read(&view, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger) catch unreachable;
                    const accounted = self.runner.tokenLedger().accounted_operations.items;
                    std.testing.expect(merged.origin.?.matches(identities, accounted[accounted.len - 1].id)) catch unreachable;
                } else std.testing.expect(merged.origin == null) catch unreachable;
            }
            if (self.summary_sequence != null) @import("summary_protocol_sequence.zig").assertMerge(&before_merge, &view, self.reconciliation_merges) catch unreachable;
            self.reconciliation_merges += 1;
            if (!merged.changed) self.unchanged_reconciliation_merges += 1;
        };
        for (self.runner.selected.graph.authority.steps) |entry| if (std.mem.eql(u8, entry.id.bytes, id.bytes) and std.mem.eql(u8, entry.operation_id.bytes, "merge-specification-support-repair") and (result.status() == .ok or result.status() == .invalid)) {
            const view: data.View = .{ .slots = self.runner.envelope.slots };
            assertSupportMerge(arena.allocator(), &before_merge, &view) catch unreachable;
            const review_workflow = @import("../application/specification_support_workflow.zig");
            const current = review_workflow.progress(&view) catch unreachable;
            const merge = blk: {
                inline for (.{ @import("../domain/specification_support.zig").Purpose.source, .principles }) |review_purpose| if (review_workflow.purpose(current) == review_purpose) {
                    const review = review_workflow.collection(review_purpose, current) catch unreachable;
                    break :blk switch (review) {
                        .accepted => |accepted| accepted.candidate.last_repair.?,
                        .rejected => |rejected| rejected.candidate.?.last_repair.?,
                    };
                };
                unreachable;
            };
            const observations = @import("../application/candidate_repair_observations.zig").read(arena.allocator(), &view) catch unreachable;
            if (self.support_fault == .foreign_sources) {
                std.testing.expectEqual(self.support_merges != 0, merge.changed) catch unreachable;
                std.testing.expectEqual(@as(u64, self.support_merges + 2), merge.revision_after) catch unreachable;
            }
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
                    self.classification_original_origin = if (entry.producers) |producers| producers.classifications else entry.origin;
                    if (entry.text_origins.len != 0) self.classification_text_origin = entry.text_origins[0].origin;
                };
            },
            else => {},
        };
        return result;
    }
};

fn assertSupportMerge(allocator: std.mem.Allocator, before: *const data.View, after: *const data.View) !void {
    const workflow_review = @import("../application/specification_support_workflow.zig");
    const support = @import("../domain/specification_support.zig");
    const previous = try workflow_review.progress(before);
    const current = try workflow_review.progress(after);
    try std.testing.expectEqual(workflow_review.purpose(previous), workflow_review.purpose(current));
    inline for (.{ support.Purpose.source, .principles }) |purpose| if (workflow_review.purpose(current) == purpose) {
        const old = (try workflow_review.collection(purpose, previous)).rejected.candidate.?;
        const result = try workflow_review.collection(purpose, current);
        const candidate = switch (result) {
            .accepted => |accepted| accepted.candidate,
            .rejected => |rejected| rejected.candidate.?,
        };
        const state = try @import("../application/required_authority_values.zig").read(before, @import("../application/specification_support_repair_workflow.zig").schema, if (purpose == .source) .support_repair else .principle_support_repair);
        const authorization = state.authorization;
        try std.testing.expectEqualDeep(old.origin, candidate.origin);
        try std.testing.expectEqual(old.revision + 1, candidate.revision);
        for (old.review.entries, 0..) |entry, index| {
            if (index == authorization.target.index) {
                if (authorization.operation == .replace and authorization.operation.replace != .finding)
                    try std.testing.expectEqual(entry.value.decision, candidate.review.entries[index].value.decision);
                continue;
            }
            const retained_index = if (authorization.operation == .delete and index > authorization.target.index) index - 1 else index;
            try std.testing.expectEqualDeep(entry, candidate.review.entries[retained_index]);
            try std.testing.expectEqualDeep(old.origins[index], candidate.origins[retained_index]);
        }
        const checked = try support.Contract(purpose).validate(allocator, authorization.dependencies.inputs, authorization.dependencies.sources, candidate);
        try std.testing.expectEqual(std.meta.activeTag(result), std.meta.activeTag(checked));
        if (checked == .rejected) try std.testing.expectEqualDeep(result.rejected.rejection, checked.rejected.rejection);
    };
}

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
        if (std.mem.eql(u8, rule.get("issue").?.string, "invalid_evidence") and rule.get("evidence_rule").?.object.contains("minimum")) {
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
    const fields = @typeInfo(@import("../domain/specification_support.zig").Source.Value).@"struct".fields;
    try std.testing.expectEqual(fields.len, properties.count());
    inline for (fields) |field| try std.testing.expect(properties.contains(field.name));
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

fn authorityInputs(view: *const data.View) @import("../domain/required_authority.zig").Inputs {
    return @import("../application/required_authority_values.zig").read(view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs) catch unreachable;
}

fn assertOmissionMerge(allocator: std.mem.Allocator, before: *const data.View, after: *const data.View) !@import("../domain/workflow_retry.zig").Permit {
    const spec_workflow = @import("../application/specification_workflow.zig");
    const state = try @import("../application/specification_values.zig").storage.read(before, @import("../application/specification_omission_repair_workflow.zig").schema, .omission_repair);
    const authorization = state.authorization;
    const prior = authorization.dependencies.session;
    const current = try spec_workflow.readSession(after);
    try std.testing.expectEqual(prior.revision + 1, current.revision);
    for (prior.units, current.units, 0..) |old, next, index| {
        if (index != authorization.target.unit) {
            try std.testing.expectEqualDeep(old, next);
        } else {
            try std.testing.expectEqual(old.?.response.content.records.len + 1, next.?.response.content.records.len);
            try std.testing.expectEqualDeep(old.?.response.content.records, next.?.response.content.records[0..old.?.response.content.records.len]);
            try std.testing.expectEqualDeep(authorization.retry.?, next.?.last_repair.?.retry.?);
        }
    }
    const context = try spec_workflow.readContext(after);
    const full = try @import("../domain/specification_session.zig").assemble(allocator, @import("reference_text.zig").validator, context, current);
    _ = try @import("../domain/specification_coverage.zig").validate(allocator, context.references, current.units[0].?.response.content.brief, full.content);
    return authorization.retry.?;
}
