//! Scripted candidate data injected at the fake provider; the real compiler,
//! engine, runner, model lifecycle and domain validators still execute.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("../application/pipeline_values.zig");
const workflow = @import("../domain/workflow.zig");
const r = @import("../domain/reference_reconciliation.zig");
const g = @import("../domain/specification_generation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const a = @import("../domain/required_authority.zig");
pub const Driver = struct {
    runner: *@import("../application/workflow_pipeline_runner.zig").Runner,
    fake: *@import("../adapters/provider/fake_llm_provider.zig").FakeLLMProvider,
    malformed: bool = false,
    uncertain: bool = false,
    pub fn run(self: *Driver) @import("../domain/run_outcome.zig").Outcome {
        return @import("../application/workflow_engine_orchestrator.zig").run(.{ .context = self, .vtable = &.{ .validate_operation_registry = selected, .parse_invocation = selected, .select_workflow = selected, .prepare_workflow = ready, .selected_graph = graph, .invoke_invocation = invocation, .invoke_step = step } });
    }
    fn selected(_: *anyopaque) @import("../application/workflow_engine_child_bindings.zig").SelectionStepOutcome { return .ok; }
    fn ready(_: *anyopaque) @import("../application/workflow_engine_child_bindings.zig").PreparationOutcome { return .ok; }
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
            const body = response(arena.allocator(), view, self.uncertain) catch |err| std.debug.panic("invalid scripted candidate: {s}", .{@errorName(err)});
            self.fake.invocation_plan.complete.content = if (self.malformed) "{" else body;
        };
        const result = self.runner.bindings().invokeStep(id);
        if (result != .outcome or (result.outcome != .ok and result.outcome != .more)) std.debug.print("spec generation step {s}: {any}\n", .{ id.bytes, result });
        return result;
    }
};

fn response(allocator: std.mem.Allocator, view: data.View, uncertain: bool) ![]const u8 {
    const request = try requests.readCurrent(&view, requests.prepared_schema);
    switch (request.id().immutable_unit_owner_id) {
        .reference_chunk => |scope| {
            const inputs = (try values.read(&view, @import("../application/reference_evidence_workflow.zig").inputs_schema, r.evidence.Inputs)).*;
            const selected_chunk = try r.evidence.resolve(inputs, .{ .state_id = .{ .bytes = scope.reference_state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } });
            const chunk = selected_chunk.chunk;
            const candidates = (try values.read(&view, @import("../application/structured_token_workflow.zig").candidates_schema, r.extraction.tokens.Candidates)).*;
            const body = try std.json.Stringify.valueAlloc(allocator, .{ .kind = "claims", .claims = .{.{ .content = .{ .kind = "business", .text = r.text.BusinessText{ .segments = &.{.{ .literal = .{ .value = "The requested outcome is observable." } }} } }, .citations = .{r.evidence.CitationProposal{ .source_id = chunk.source_id, .block_id = chunk.block_id, .location = chunk.span, .verbatim = selected_chunk.bytes }} }}, .token_classifications = .{} }, .{});
            return @import("reference_tokens.zig").wire(allocator, body, try @import("reference_tokens.zig").classifications(allocator, candidates, chunk));
        },
        .reference_global => {
            const input = (try native.read(&view, @import("../application/reference_reconciliation_workflow.zig").input_schema, .reconciliation_input)).payload().reconciliation_input;
            if (input.purpose == .summary) return std.json.Stringify.valueAlloc(allocator, .{ .summary = try @import("reference_reconciliation.zig").summary(allocator, input) }, .{});
            return std.json.Stringify.valueAlloc(allocator, .{ .global = try @import("reference_reconciliation.zig").global(allocator, input) }, .{});
        },
        .specification_unit => {
            const current = try @import("../application/specification_workflow.zig").readSession(&view);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const value = try attributed(allocator, all, &.{all.entries[0].claim.id});
            const unit = try @import("../domain/specification_session.zig").unit(current.completed);
            const proposed: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                .records => |kind| result: {
                    if (kind != .functional_requirement and kind != .user_visible_outcome) break :result .{ .records = &.{} };
                    var records: std.ArrayList(g.spec.RecordProposal) = .empty;
                    for (all.entries) |item| {
                        const selected = try attributed(allocator, all, &.{item.claim.id});
                        if (kind == .functional_requirement and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .functional_requirement = .{ .text = selected.value } }, .provenance = selected.provenance });
                        if (kind == .user_visible_outcome and item.claim.content == .preserved_token) try records.append(allocator, .{ .content = .{ .user_visible_outcome = .{ .text = .{ .exact_copy = .{ .token_id = item.claim.content.preserved_token.value.id, .citation_id = item.claim.content.preserved_token.citation_id } } } }, .provenance = selected.provenance });
                    }
                    break :result .{ .records = records.items };
                },
            } };
            return std.json.Stringify.valueAlloc(allocator, proposed, .{});
        },
        .semantic_review => {
            const inputs = try @import("../application/required_authority_values.zig").read(&view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs);
            const ledger = try a.build(allocator, inputs);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const findings = try allocator.alloc(@import("../domain/specification_support.zig").Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
                var selected = (try attributed(allocator, all, &.{all.entries[0].claim.id})).provenance;
                switch (requirement.seed.id.unit) {
                    .token => |token| for (all.entries) |item| {
                        if (item.claim.content == .preserved_token and item.claim.content.preserved_token.value.id.ordinal == token.ordinal) selected = (try attributed(allocator, all, &.{item.claim.id})).provenance;
                    },
                    .signal => |id| for (context.references.records.signals) |signal| {
                        if (signal.id.ordinal == id.ordinal) selected = (try attributed(allocator, all, signal.value.claim_ids)).provenance;
                    },
                    .record => |id| if (inputs.specification) |content| {
                        for (content.records) |record| if (std.meta.eql(record.id, id)) { selected = record.proposal.provenance; };
                    },
                    .feature => if (inputs.specification) |content| {
                        selected = switch (requirement.seed.id.slot) { .display_name => content.display_name.provenance, .primary_user_story => content.primary_user_story.provenance, .entities => content.entities.basis.provenance, else => selected };
                    },
                    else => {},
                }
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .finding = if (uncertain) .ambiguous else .supported, .disposition = if (requirement.seed.id.kind == .entity_applicability and inputs.specification != null and inputs.specification.?.entities.disposition == .not_applicable) .not_applicable else .supported, .provenance = selected };
            }
            return std.json.Stringify.valueAlloc(allocator, @import("../domain/specification_support.zig").Review{ .entries = findings }, .{});
        },
        else => return error.InvalidFixture,
    }
}
fn attributed(allocator: std.mem.Allocator, all: r.Items, ids: []const r.ClaimId) !g.spec.AttributedValue {
    var citations: std.ArrayList(r.CitationId) = .empty;
    for (ids) |id| for ((try r.item(all, id)).claim.citation_ids) |citation| {
        if (!r.contains(r.CitationId, citations.items, citation)) try citations.append(allocator, citation);
    };
    const segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = try std.fmt.allocPrint(allocator, "Requested business behavior {d}.", .{ids[0].ordinal}) } }});
    return .{ .value = .{ .normalized = .{ .segments = segments } }, .provenance = .{ .claim_ids = try allocator.dupe(r.ClaimId, ids), .citation_ids = citations.items, .clarification_response_ids = &.{} } };
}
