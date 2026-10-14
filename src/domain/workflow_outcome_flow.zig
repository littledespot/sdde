//! Pure preservation proof for outcomes with no authorized native resolution.
//! Native recoverable subjects are checked against exact runtime evidence by the
//! same registered association contract; arbitrary data transforms grant none.
const std = @import("std");
const compilation = @import("workflow_compilation.zig");
const workflow = @import("workflow.zig");
const association = @import("workflow_outcome_association.zig");

pub const Error = error{WorkflowGraphCompileInvalid};

pub fn validate(_: std.mem.Allocator, authority: compilation.SemanticAuthority) Error!void {
    const maximum_steps = @import("workflow_definition.zig").max_steps;
    const maximum_edges = maximum_steps * @typeInfo(workflow.OutcomeTag).@"enum".fields.len;
    if (authority.steps.len == 0 or authority.steps.len > maximum_steps) return error.WorkflowGraphCompileInvalid;
    if (authority.transitions.len > maximum_edges) return error.WorkflowGraphCompileInvalid;
    // Resolve adjacency and targets once. Each preservation walk then visits
    // each edge at most once per carrier mode instead of rescanning the graph.
    var heads: [maximum_steps]?usize = @splat(null);
    var next: [maximum_edges]?usize = undefined;
    var targets: [maximum_edges]?usize = undefined;
    for (authority.transitions, 0..) |edge, index| {
        const from = stepIndex(authority.steps, edge.from.bytes) orelse return error.WorkflowGraphCompileInvalid;
        next[index] = heads[from];
        heads[from] = index;
        targets[index] = switch (edge.target) {
            .step => |id| stepIndex(authority.steps, id.bytes) orelse return error.WorkflowGraphCompileInvalid,
            .terminal => null,
        };
    }
    var visited_storage: [maximum_steps][2]bool = undefined;
    const visited = visited_storage[0..authority.steps.len];
    var pending: [maximum_steps * 2]Pending = undefined;
    var pending_count: usize = 0;
    for (authority.steps, 0..) |source, source_index| {
        // Opaque operation outcomes have no subject which a native resolver can
        // discharge. Logical request closure is irreversible in its own ledger.
        if (source.outcome_association != .independent and source.outcome_association != .request_closure) continue;
        for (source.outcomes) |outcome| {
            if (!association.prohibiting(outcome)) continue;
            @memset(visited, .{ false, false });
            pending_count = 0;
            var first_edge = heads[source_index];
            while (first_edge) |index| : (first_edge = next[index]) {
                const edge = authority.transitions[index];
                if (edge.outcome != outcome) continue;
                try follow(edge.target, targets[index], outcome, true, visited, &pending, &pending_count);
            }
            var cursor: usize = 0;
            while (cursor < pending_count) : (cursor += 1) {
                const item = pending[cursor];
                const step = authority.steps[item.index];
                switch (step.side_effect) {
                    .filesystem_read, .filesystem_write, .workflow_publication, .model_call => return error.WorkflowGraphCompileInvalid,
                    .none => {},
                }
                // A successor's admitted outcomes cannot erase the original
                // obligation, even when it changes unrelated data or succeeds.
                const binding = source.outcome_association.binding();
                const intact = item.intact and if (binding) |value| !changesCarrier(step, value) else false;
                const preserves = intact and source.outcome_association == .request_closure and
                    step.outcome_association == .preserve and sameCarrier(binding.?, step.outcome_association.preserve) and
                    std.mem.indexOfScalar(workflow.OutcomeTag, step.outcomes, outcome) != null;
                var outgoing = heads[item.index];
                while (outgoing) |index| : (outgoing = next[index]) {
                    const edge = authority.transitions[index];
                    if (preserves and edge.outcome != outcome) continue;
                    try follow(edge.target, targets[index], outcome, intact, visited, &pending, &pending_count);
                }
            }
        }
    }
}

const Pending = struct { index: usize, intact: bool };

fn follow(target: workflow.TransitionTarget, target_index: ?usize, outcome: workflow.OutcomeTag, intact: bool, visited: [][2]bool, pending: []Pending, pending_count: *usize) Error!void {
    switch (target) {
        .terminal => |terminal| if (terminal != outcome) return error.WorkflowGraphCompileInvalid,
        .step => {
            const index = target_index orelse return error.WorkflowGraphCompileInvalid;
            const mode: usize = @intFromBool(intact);
            if (!visited[index][mode]) {
                visited[index][mode] = true;
                if (pending_count.* >= pending.len) return error.WorkflowGraphCompileInvalid;
                pending[pending_count.*] = .{ .index = index, .intact = intact };
                pending_count.* += 1;
            }
        },
    }
}

fn stepIndex(steps: []const compilation.CompiledStep, id: []const u8) ?usize {
    for (steps, 0..) |step, index| if (std.mem.eql(u8, step.id.bytes, id)) return index;
    return null;
}

fn sameCarrier(left: association.Binding, right: association.Binding) bool {
    return left.kind == right.kind and left.subject == right.subject and left.evidence == right.evidence;
}

fn changesCarrier(step: compilation.CompiledStep, binding: association.Binding) bool {
    inline for (.{ step.produces, step.replaces, step.invalidates }) |keys| {
        for (keys) |key| if (key == binding.subject or key == binding.evidence) return true;
    }
    return false;
}

fn testStep(id: []const u8, outcomes: []const workflow.OutcomeTag) compilation.CompiledStep {
    return .{
        .id = .{ .bytes = id },
        .operation_id = .{ .bytes = id },
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = outcomes,
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    };
}

fn testAuthority(steps: []const compilation.CompiledStep, transitions: []const workflow.Transition) compilation.SemanticAuthority {
    return .{
        .workflow_id = .{ .bytes = "preservation" },
        .workflow_version = 1,
        .invocation_operation_id = .{ .bytes = "input" },
        .policy_profile_id = .{ .bytes = "policy" },
        .total_model_token_budget = .{ .value = 1 },
        .start_step_id = steps[0].id,
        .invocation_outputs = &.{},
        .resources = &.{},
        .steps = steps,
        .transitions = transitions,
        .maximum_step_executions = steps.len,
    };
}

test "opaque negative outcomes survive unrelated transformations and cleanup transitively" {
    for ([_]workflow.OutcomeTag{ .invalid, .failed, .blocked, .needs_user, .cancelled }) |outcome| {
        var steps = [_]compilation.CompiledStep{ testStep("source", &.{outcome}), testStep("transform", &.{.ok}), testStep("cleanup", &.{.ok}) };
        steps[1].produces = &.{.raw_engine_config};
        const edges = [_]workflow.Transition{
            .{ .from = steps[0].id, .outcome = outcome, .target = .{ .step = steps[1].id } },
            .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[2].id } },
            .{ .from = steps[2].id, .outcome = .ok, .target = .{ .terminal = .ok } },
        };
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&steps, &edges)));
    }
}

test "an irreversible request closure cannot enter effects or be admitted anew" {
    var steps = [_]compilation.CompiledStep{ testStep("closed", &.{.failed}), testStep("admit-other", &.{.ok}) };
    steps[0].outcome_association = .{ .request_closure = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } };
    steps[1].outcome_association = .{ .request_admission = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result } };
    const edges = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .step = steps[1].id } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .terminal = .ok } },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&steps, &edges)));
    steps[1].side_effect = .workflow_publication;
    const failed_edges = [_]workflow.Transition{
        edges[0], .{ .from = steps[1].id, .outcome = .ok, .target = .{ .terminal = .failed } },
    };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&steps, &failed_edges)));
}

test "matching negative terminal and native recoverable subjects remain admitted" {
    var steps = [_]compilation.CompiledStep{ testStep("source", &.{.invalid}), testStep("validate", &.{.ok}) };
    const edges = [_]workflow.Transition{.{ .from = steps[0].id, .outcome = .invalid, .target = .{ .terminal = .invalid } }};
    try validate(std.testing.allocator, testAuthority(steps[0..1], &edges));
    steps[0].outcome_association = .{ .observe = .{ .kind = .candidate, .subject = .parsed_reference_extraction, .evidence = .text_validated_reference_extraction } };
    steps[1].outcome_association = .{ .repair_validate = .{ .kind = .candidate, .subject = .parsed_reference_extraction, .evidence = .text_validated_reference_extraction } };
    const recoverable = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .invalid, .target = .{ .step = steps[1].id } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .terminal = .ok } },
    };
    // Exact same-subject admission is a runtime proof, not a compiler guess.
    try validate(std.testing.allocator, testAuthority(&steps, &recoverable));
}

test "a replaced carrier cannot borrow an intact reconvergent preservation path" {
    var steps = [_]compilation.CompiledStep{
        testStep("closed", &.{.failed}),         testStep("split", &.{ .ok, .more }),
        testStep("intact", &.{.ok}),             testStep("replaced", &.{.ok}),
        testStep("observe", &.{ .failed, .ok }),
    };
    const binding: association.Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .provider_authorization_result };
    steps[0].outcome_association = .{ .request_closure = binding };
    steps[4].outcome_association = .{ .preserve = binding };
    const edges = [_]workflow.Transition{
        .{ .from = steps[0].id, .outcome = .failed, .target = .{ .step = steps[1].id } },
        .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[2].id } },
        .{ .from = steps[1].id, .outcome = .more, .target = .{ .step = steps[3].id } },
        .{ .from = steps[2].id, .outcome = .ok, .target = .{ .step = steps[4].id } },
        .{ .from = steps[3].id, .outcome = .ok, .target = .{ .step = steps[4].id } },
        .{ .from = steps[4].id, .outcome = .failed, .target = .{ .terminal = .failed } },
        .{ .from = steps[4].id, .outcome = .ok, .target = .{ .terminal = .ok } },
    };
    try validate(std.testing.allocator, testAuthority(&steps, &edges));
    steps[3].invalidates = &.{.provider_authorization_result};
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&steps, &edges)));
}
