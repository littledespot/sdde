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
            const body = @import("spec_generation_responses.zig").build(arena.allocator(), view, .{ .uncertain = self.uncertain, .brief_uncertain = self.brief_uncertain, .repair = self.repair, .failed_repair = self.failed_repair, .omit_exact = self.omit_exact, .entities_required = self.entities_required, .generation_gap = self.generation_gap, .citation_fault = self.citation_fault, .failed_citation_repair = self.failed_citation_repair, .missing_classifications = self.missing_classifications, .failed_classification_repair = self.failed_classification_repair }) catch |err| std.debug.panic("invalid scripted candidate: {s}", .{@errorName(err)});
            self.fake.invocation_plan.complete.content = if (self.malformed or (self.malformed_once and self.calls == 0)) "{" else body;
            const current_request = requests.readCurrent(&view, requests.prepared_schema) catch unreachable;
            const attempt = @import("../domain/model_attempt_accounting.zig").latestAttempt(self.runner.model_accounting.?.attempts).ordinal().value;
            const validated = requests.readCurrent(&view, requests.validated_schema) catch unreachable;
            var base_buffer: [2]@import("../domain/llm_provider_operation.zig").ModelVisibleContent = undefined;
            const base = validated.content(&base_buffer);
            const content = current_request.prepared().?.content;
            std.testing.expectEqual(base.len + @as(usize, if (attempt > 1) 3 else 0), content.len) catch unreachable;
            std.testing.expectEqualDeep(base, content[0..base.len]) catch unreachable;
            if (current_request.id().immutable_unit_owner_id == .reference_chunk and current_request.id().purpose == .atomic_repair) {
                if (self.malformed_classification_repair_once and self.classification_repair_calls == 0) self.fake.invocation_plan.complete.content = "{}";
                if (self.citation_fault != null) self.citation_repair_calls += 1 else self.classification_repair_calls += 1;
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
        return self.runner.bindings().invokeStep(id);
    }
};

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
            if (!root and object.contains("kind")) {
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
