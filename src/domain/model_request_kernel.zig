//! The registered `request-model` operation's one contract (ADR 0030). The operation is the
//! kernel orchestrator over the fixed stages of `model_request_stage.zig`: the step declares
//! only what the workflow sees, and every stage's data and capabilities derive from the
//! stage bindings that composition registers beside it.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const operation = @import("workflow_operation.zig");
const compilation = @import("workflow_compilation.zig");
const stages = @import("model_request_stage.zig");
const workflow_retry = @import("workflow_retry.zig");

pub const Stage = stages.Stage;
pub const operation_id = "request-model";

/// What the workflow sees of one request (DE1 decision 2). These stay current on every outcome.
/// Every other request key is engine-internal: it exists between stages and ends with the step
/// (`design/contracts/model-request-operations.md`, "The `request-model` step's data contract").
pub const requires = [_]pipeline.DataKey{.model_request_identity_ledger};
pub const optional = [_]pipeline.DataKey{ .model_input_packet, .json_composition };
pub const produces = [_]pipeline.DataKey{ .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result };
pub const replaces = [_]pipeline.DataKey{.model_request_identity_ledger};
pub const outcomes = [_]workflow.OutcomeTag{ .ok, .invalid, .failed, .cancelled };

/// Request keys no step outside the kernel reads. The runner invalidates the ones present when
/// the step ends, in an engine-owned delta that is no part of the step's contract.
pub const internal_keys = [_]pipeline.DataKey{
    .assigned_model_request,
    .validated_model_request,
    .assigned_provider_operation,
    .invoked_provider_operation,
    .provider_authorization_result,
    .provider_invocation_result,
    .provider_invocation_validation_result,
    .model_envelope_result,
};

pub const transition_parameter = "transition";

/// The parameter a stage needs that no workflow declares: the two lifecycle advances.
pub fn fixedParameter(stage: Stage) ?struct { id: []const u8, value: []const u8 } {
    return switch (stage) {
        .advance_request, .advance_operation => .{ .id = transition_parameter, .value = "invoked" },
        else => null,
    };
}

/// The stage whose contract declares the step's `retry-limit` and whose retry authority bounds
/// the request's attempts.
pub const accounting_stage: Stage = .advance_attempt;

/// The operation contract's own shape. Its parameters derive from the stage contracts and are
/// checked with them (`ports/workflow_operation_registry.zig`).
pub fn validContract(contract: operation.Contract) bool {
    const limit = contract.retry_limit orelse return false;
    return std.mem.eql(u8, contract.id, operation_id) and contract.kind == .step and
        std.mem.eql(pipeline.DataKey, contract.requires, &requires) and
        std.mem.eql(pipeline.DataKey, contract.optional, &optional) and
        std.mem.eql(pipeline.DataKey, contract.produces, &produces) and
        std.mem.eql(pipeline.DataKey, contract.replaces, &replaces) and
        contract.invalidates.len == 0 and
        std.mem.eql(workflow.OutcomeTag, contract.outcomes, &outcomes) and
        contract.side_effect == .model_call and contract.runner_accounting == .none and
        contract.repair_role == .none and contract.outcome_association == .independent and
        contract.gates.len == 0 and contract.iteration == null and
        limit.scope == .model_request and limit.maximum == std.math.maxInt(u32);
}

/// Where a request goes after one stage ended with one outcome.
pub const Next = union(enum) {
    stage: Stage,
    finish: workflow.OutcomeTag,
};

/// The fixed transition table of one request (ADR 0030), the one statement of every stage's
/// outcome set. The orchestrator follows it; the registry checks each stage's registered
/// contract against it (`sameStageOutcomes`). A null result is an outcome the stage's contract
/// does not allow.
pub fn next(stage: Stage, outcome: workflow.OutcomeTag) ?Next {
    return switch (stage) {
        .prepare_request => okOrFailed(outcome, .advance_attempt),
        .advance_attempt => okOrFailed(outcome, .assign_operation),
        .assign_operation => okOrFailed(outcome, .prepare_authorization),
        .prepare_authorization => switch (outcome) {
            .ok => .{ .stage = .check_phase },
            .failed, .cancelled => .{ .stage = .terminate_operation },
            else => null,
        },
        .check_phase => switch (outcome) {
            .ok => .{ .stage = .advance_request },
            .more => .{ .stage = .advance_operation },
            .failed => .{ .finish = .failed },
            else => null,
        },
        .advance_request => okOrFailed(outcome, .advance_operation),
        .advance_operation => okOrFailed(outcome, .invoke_model),
        .invoke_model => anyResult(outcome, .validate_observation),
        .validate_observation => anyResult(outcome, .complete_operation),
        .complete_operation => anyResult(outcome, .admit_response),
        .admit_response => switch (outcome) {
            .ok, .failed, .cancelled => .{ .stage = .close_request },
            .invalid => .{ .stage = .check_runaway },
            else => null,
        },
        .check_runaway => switch (outcome) {
            .ok => .{ .stage = .build_protocol_retry },
            .more => .{ .stage = .build_runaway_resend },
            else => null,
        },
        .build_protocol_retry, .build_runaway_resend => okOrFailed(outcome, .advance_attempt),
        .close_request => switch (outcome) {
            .ok, .invalid, .failed, .cancelled => .{ .finish = outcome },
            else => null,
        },
        .terminate_operation => switch (outcome) {
            .failed, .cancelled => .{ .stage = .terminate_request },
            else => null,
        },
        .terminate_request => switch (outcome) {
            .failed, .cancelled => .{ .finish = outcome },
            else => null,
        },
    };
}

fn okOrFailed(outcome: workflow.OutcomeTag, following: Stage) ?Next {
    return switch (outcome) {
        .ok => .{ .stage = following },
        .failed => .{ .finish = .failed },
        else => null,
    };
}

fn anyResult(outcome: workflow.OutcomeTag, following: Stage) ?Next {
    return switch (outcome) {
        .ok, .failed, .cancelled => .{ .stage = following },
        else => null,
    };
}

/// Whether a stage's registered outcomes are exactly the ones the transition table follows. A
/// stage contract that gains or loses an outcome fails registry validation instead of ending a
/// request in an opaque rejection. `declared` holds no duplicate (checked with the contract).
pub fn sameStageOutcomes(stage: Stage, declared: []const workflow.OutcomeTag) bool {
    var followed: usize = 0;
    for (std.enums.values(workflow.OutcomeTag)) |tag| if (next(stage, tag) != null) {
        if (std.mem.indexOfScalar(workflow.OutcomeTag, declared, tag) == null) return false;
        followed += 1;
    };
    return followed == declared.len;
}

/// The generic compiled-step validators a kernel step does not take, stated once. Its stages take
/// all of them, each as the step it is; the kernel step itself declares only the effects the
/// workflow sees, so the validators that describe one operation's repair, runner accounting,
/// request lifecycle, provider operation, authorization and invocation do not apply to it: its net
/// contract produces `accounted_model_attempt` and `terminal_provider_operation`, which only a
/// runner-accounted stage may produce. `validProjection` fixes everything about it instead.
pub fn takesSingleOperationValidators(step: compilation.CompiledStep) bool {
    return !isKernel(step);
}

/// A compiled kernel step: the contract's effects, every stage exactly once in enum order, and
/// the retry authority only on the step itself and the accounting stage.
pub fn validProjection(step: compilation.CompiledStep) bool {
    if (!std.mem.eql(u8, step.operation_id.bytes, operation_id)) return false;
    if (step.request_stages.len != std.enums.values(Stage).len) return false;
    for (std.enums.values(Stage), step.request_stages) |expected, compiled| {
        if (compiled.stage != expected or compiled.step.request_stages.len != 0 or
            !std.mem.eql(u8, compiled.step.id.bytes, step.id.bytes)) return false;
        const authority = compiled.step.retry_authority;
        if ((expected == accounting_stage) != (authority != null)) return false;
        if (authority) |value| if (!value.eql(step.retry_authority orelse return false)) return false;
    }
    return step.side_effect == .model_call and step.runner_accounting == .none and step.repair_role == .none and
        step.outcome_association == .independent and step.gates.len == 0 and step.iteration == null and
        step.retry_authority != null and step.retry_authority.?.scope == .model_request and
        std.mem.eql(pipeline.DataKey, step.requires, &requires) and
        std.mem.eql(pipeline.DataKey, step.optional, &optional) and
        std.mem.eql(pipeline.DataKey, step.produces, &produces) and
        std.mem.eql(pipeline.DataKey, step.replaces, &replaces) and
        step.invalidates.len == 0 and
        std.mem.eql(workflow.OutcomeTag, step.outcomes, &outcomes);
}

/// Whether a model call's recorded action belongs to the step a caller chain ends at: that step's
/// own operation, or the inference stage of a `request-model` step, whose action ID records the
/// stage (ADR 0030, "Identity, retries and diagnostics").
pub fn callActionBelongsTo(caller_operation: []const u8, action: []const u8) bool {
    return std.mem.eql(u8, caller_operation, action) or
        (std.mem.eql(u8, caller_operation, operation_id) and std.mem.eql(u8, action, Stage.invoke_model.name()));
}

pub fn isKernel(step: compilation.CompiledStep) bool {
    return step.request_stages.len != 0;
}

/// A request's attempt allowance (DE1 decision 4): each attempt, correction or not, plus the one
/// runaway re-send each may take (ADR 0039).
pub fn attemptAllowance(limit: workflow_retry.Limit) u64 {
    return 2 * (1 + @as(u64, limit.value));
}

pub fn stageStep(step: compilation.CompiledStep, stage: Stage) ?*const compilation.CompiledStep {
    for (step.request_stages) |*compiled| if (compiled.stage == stage) return &compiled.step;
    return null;
}
