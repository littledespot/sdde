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
        if (source.outcome_association == .advisory_request_closure and
            (source.outcomes.len != 1 or !association.advisoryClosureRoute(source.outcome_association.advisory_request_closure, source.outcomes[0]) or
                !association.validDescriptor(source.outcome_association, source.requires, source.optional, source.produces, source.replaces, source.repair_role))) return error.WorkflowGraphCompileInvalid;
        // Ordinary closure remains irreversible. The distinct native advisory
        // descriptor carries a failed request across its internal routing tag.
        if (source.outcome_association != .independent and source.outcome_association != .request_closure and
            source.outcome_association != .advisory_request_closure) continue;
        for (source.outcomes) |outcome| {
            const deferred_advice = source.outcome_association == .advisory_request_closure and
                association.advisoryClosureRoute(source.outcome_association.advisory_request_closure, outcome);
            if (!association.prohibiting(outcome) and !deferred_advice) continue;
            const obligation: workflow.OutcomeTag = if (deferred_advice) .failed else outcome;
            @memset(visited, .{ false, false });
            pending_count = 0;
            var first_edge = heads[source_index];
            while (first_edge) |index| : (first_edge = next[index]) {
                const edge = authority.transitions[index];
                if (edge.outcome != outcome) continue;
                try follow(edge.target, targets[index], obligation, true, visited, &pending, &pending_count);
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
                    std.mem.indexOfScalar(workflow.OutcomeTag, step.outcomes, obligation) != null;
                const completes_advice = deferred_advice and intact and nativeAdvisoryCompletion(step);
                var outgoing = heads[item.index];
                while (outgoing) |index| : (outgoing = next[index]) {
                    const edge = authority.transitions[index];
                    if (preserves and edge.outcome != obligation) continue;
                    // Only native completion can discharge this particular
                    // request. Its failure edge retains the original failure.
                    if (completes_advice and (edge.outcome == .ok or edge.outcome == .more)) continue;
                    try follow(edge.target, targets[index], obligation, intact, visited, &pending, &pending_count);
                }
            }
        }
    }
}

fn nativeAdvisoryCompletion(step: compilation.CompiledStep) bool {
    if (step.outcome_association != .advisory_completion or step.side_effect != .none or
        step.runner_accounting != .none or step.capabilities.len != 0 or step.retry_authority != null or step.model != null or
        !association.validDescriptor(step.outcome_association, step.requires, step.optional, step.produces, step.replaces, step.repair_role)) return false;
    var failed = false;
    for (step.outcomes) |outcome| switch (outcome) {
        .ok, .more => {},
        .failed => failed = true,
        .invalid, .blocked, .needs_user, .cancelled => return false,
    };
    return failed;
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

fn testAdviceCompletion() compilation.CompiledStep {
    var step = testStep("finish-advice", &.{ .ok, .more, .failed });
    step.requires = &.{ .specification_support_review, .prepared_model_request, .model_request_identity_ledger, .accounted_model_attempt };
    step.replaces = &.{.specification_support_review};
    step.repair_role = .abandon_advice;
    step.outcome_association = .{ .advisory_completion = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    return step;
}

test "only native advisory completion discharges its exact deferred failed request before publication" {
    for ([_]struct { witness: @import("pipeline.zig").DataKey, route: workflow.OutcomeTag }{
        .{ .witness = .model_payload_schema_result, .route = .more },
        .{ .witness = .accounted_model_attempt, .route = .blocked },
    }) |mode| {
        var steps = [_]compilation.CompiledStep{
            testStep("close-advice", &.{mode.route}),
            testStep("read-only-cleanup", &.{.ok}),
            testAdviceCompletion(),
            testStep("retire-protocol", &.{.ok}),
            testStep("publish", &.{.ok}),
        };
        const binding: association.Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = mode.witness };
        steps[0].outcome_association = .{ .advisory_request_closure = binding };
        steps[0].requires = &.{ .prepared_model_request, .model_request_identity_ledger, mode.witness };
        steps[0].replaces = &.{.model_request_identity_ledger};
        steps[4].side_effect = .workflow_publication;
        const edges = [_]workflow.Transition{
            .{ .from = steps[0].id, .outcome = mode.route, .target = .{ .step = steps[1].id } },
            .{ .from = steps[1].id, .outcome = .ok, .target = .{ .step = steps[2].id } },
            .{ .from = steps[2].id, .outcome = .ok, .target = .{ .step = steps[4].id } },
            .{ .from = steps[2].id, .outcome = .more, .target = .{ .step = steps[3].id } },
            .{ .from = steps[2].id, .outcome = .failed, .target = .{ .terminal = .failed } },
            .{ .from = steps[3].id, .outcome = .ok, .target = .{ .step = steps[4].id } },
            .{ .from = steps[4].id, .outcome = .ok, .target = .{ .terminal = .ok } },
        };
        try validate(std.testing.allocator, testAuthority(&steps, &edges));
        for (std.enums.values(workflow.OutcomeTag)) |wrong_route| if (wrong_route != mode.route) {
            var wrong_source = steps;
            wrong_source[0].outcomes = &.{wrong_route};
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&wrong_source, &edges)));
        };
        var wrong_source = steps;
        wrong_source[0].outcomes = &.{ mode.route, .failed };
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&wrong_source, &edges)));
        wrong_source = steps;
        wrong_source[0].replaces = &.{};
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&wrong_source, &edges)));
        var wrong_edges = edges;
        wrong_edges[4].target = .{ .step = steps[4].id };
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&steps, &wrong_edges)));
        for ([_]@import("pipeline.zig").DataKey{ .prepared_model_request, mode.witness }) |carrier| {
            var changed = steps;
            changed[1].invalidates = &.{carrier};
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&changed, &edges)));
        }
        var nonnative = steps;
        nonnative[2].repair_role = .none;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&nonnative, &edges)));
        nonnative = steps;
        nonnative[2].outcome_association = .{ .preserve = steps[2].outcome_association.advisory_completion };
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&nonnative, &edges)));
        for ([_]@import("pipeline.zig").SideEffect{ .filesystem_read, .filesystem_write, .model_call, .workflow_publication }) |effect| {
            var effects = steps;
            effects[2].side_effect = effect;
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&effects, &edges)));
        }
        var unrelated = steps;
        unrelated[1].outcomes = &.{ .ok, .failed };
        const unrelated_edges = edges ++ [_]workflow.Transition{.{ .from = steps[1].id, .outcome = .failed, .target = .{ .step = steps[2].id } }};
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&unrelated, &unrelated_edges)));
        for ([_]workflow.OutcomeTag{ .failed, .invalid, .cancelled, .blocked, .needs_user }) |ordinary_outcome| {
            var ordinary = steps;
            ordinary[0].outcomes = &.{ordinary_outcome};
            var ordinary_edges = edges;
            ordinary_edges[0].outcome = ordinary_outcome;
            ordinary[0].outcome_association = .{ .request_closure = binding };
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&ordinary, &ordinary_edges)));
            ordinary[0].outcome_association = .independent;
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, validate(std.testing.allocator, testAuthority(&ordinary, &ordinary_edges)));
        }
    }
}
