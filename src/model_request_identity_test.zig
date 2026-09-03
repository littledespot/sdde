const std = @import("std");
const assign_request = @import("actions/model/assign_model_request_id.zig");
const build_ledger = @import("actions/model/build_initial_model_request_identity_ledger.zig");
const build_owner = @import("actions/model/build_immutable_unit_owner_id.zig");
const validate_binding = @import("actions/model/validate_model_request_binding.zig");
const runner_module = @import("application/model_request_identity_runner.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");

test "request purpose registry is closed and duplicate free" {
    const registry = try identity.RequestPurposeRegistry.init(&.{
        .initial_generation,
        .context_followup,
    });
    try std.testing.expect(registry.allows(.initial_generation));
    try std.testing.expect(!registry.allows(.atomic_repair));
    try std.testing.expectError(
        error.InvalidRequestPurposeRegistry,
        identity.RequestPurposeRegistry.init(&.{}),
    );
    try std.testing.expectError(
        error.InvalidRequestPurposeRegistry,
        identity.RequestPurposeRegistry.init(&.{ .initial_generation, .initial_generation }),
    );
}

test "immutable unit owner builder validates the complete typed descriptor" {
    const valid = unitOwner("cluster-1");
    const built = try (build_owner.Action{}).execute(valid);
    try std.testing.expect(identity.unitOwnerEql(valid, built));

    try std.testing.expectError(
        error.InvalidImmutableUnitOwnerId,
        (build_owner.Action{}).execute(.{ .task_cluster = .{
            .plan_state_id = .{ .bytes = "" },
            .obligation_cluster_id = .{ .bytes = "cluster-1" },
        } }),
    );
}

test "runner assigns monotonic request identities by unit operation and purpose" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(.{ .bytes = "epoch-42" }, identity.RequestPurposeRegistry.all());

    const owner = unitOwner("cluster-1");
    const operation = modelOperation("generate");
    const first = try runner.assign(.initial, owner, operation, .initial_generation);
    try std.testing.expectEqual(@as(u32, 1), first.request_ordinal.value);
    try std.testing.expectEqual(identity.RequestStatus.assigned, runner.ledger().?.latestRecord().?.status);
    try std.testing.expect(runner.ledger().?.latestRecord().?.terminal_reason == null);

    const second = try runner.assign(.{ .value = 1 }, owner, operation, .initial_generation);
    try std.testing.expectEqual(@as(u32, 2), second.request_ordinal.value);

    const repair = try runner.assign(
        .{ .value = 2 },
        owner,
        operation,
        .{ .atomic_repair = .{ .bytes = "repair-1" } },
    );
    try std.testing.expectEqual(@as(u32, 1), repair.request_ordinal.value);
    const other_unit = try runner.assign(
        .{ .value = 3 },
        unitOwner("cluster-2"),
        operation,
        .initial_generation,
    );
    try std.testing.expectEqual(@as(u32, 1), other_unit.request_ordinal.value);
    try std.testing.expectEqual(@as(usize, 4), runner.ledger().?.recordCount());
    try std.testing.expectEqual(@as(u64, 4), runner.ledger().?.revision().value);

    const evidence = try runner.validate(
        .{ .value = 4 },
        first,
        owner,
        operation,
        .initial_generation,
    );
    try std.testing.expect(evidence.modelRequestId() == first);
}

test "every closed request purpose binds its required authority" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const parent: identity.ContentUnitOwnerId = .{ .task_cluster = .{
        .plan_state_id = .{ .bytes = "plan-state-1" },
        .obligation_cluster_id = .{ .bytes = "cluster-1" },
    } };
    const semantic_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{
        .parent_unit_owner_id = parent,
        .review_slot_id = .{ .bytes = "review-1" },
    } };
    const semantic = try runner.assign(
        .initial,
        semantic_owner,
        modelOperation("review"),
        .{ .semantic_review = .{ .bytes = "review-1" } },
    );
    try std.testing.expectEqual(identity.RequestPurposeKind.semantic_review, std.meta.activeTag(semantic.purpose));

    const clarification = try runner.assign(
        .{ .value = 1 },
        unitOwner("cluster-1"),
        modelOperation("resolve"),
        .{ .clarification_resolution = .{
            .clarification_state_id = .{ .bytes = "clarification-state-1" },
            .clarification_state_revision = 2,
            .clarification_id = .{ .bytes = "question-1" },
        } },
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        clarification.purpose.clarification_resolution.clarification_state_revision,
    );
}

test "request assignment owns copied identity bytes for the run lifetime" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());

    var cluster = [_]u8{ 'c', 'l', 'u', 's', 't', 'e', 'r', '-', '1' };
    const first = try runner.assign(
        .initial,
        unitOwner(&cluster),
        modelOperation("generate"),
        .initial_generation,
    );
    @memset(&cluster, 'x');
    _ = try runner.assign(
        .{ .value = 1 },
        unitOwner("cluster-2"),
        modelOperation("generate"),
        .initial_generation,
    );
    try std.testing.expectEqualStrings(
        "cluster-1",
        first.immutable_unit_owner_id.task_cluster.obligation_cluster_id.bytes,
    );
    try std.testing.expect(runner.ledger().?.containsRequest(first));
}

test "stale revisions and unregistered or mismatched purpose bindings are rejected atomically" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    const registry = try identity.RequestPurposeRegistry.init(&.{.initial_generation});
    try runner.initialize(.{ .bytes = "epoch-1" }, registry);
    const owner = unitOwner("cluster-1");
    const operation = modelOperation("generate");
    _ = try runner.assign(.initial, owner, operation, .initial_generation);

    try std.testing.expectError(
        error.ModelRequestRevisionConflict,
        runner.assign(.initial, owner, operation, .initial_generation),
    );
    try std.testing.expectError(
        error.RequestPurposeNotRegistered,
        runner.assign(
            .{ .value = 1 },
            owner,
            operation,
            .{ .atomic_repair = .{ .bytes = "repair-1" } },
        ),
    );
    var invalid_operation = operation;
    invalid_operation.workflow_version = 0;
    try std.testing.expectError(
        error.InvalidWorkflowModelOperationId,
        runner.assign(.{ .value = 1 }, owner, invalid_operation, .initial_generation),
    );
    try std.testing.expectEqual(@as(usize, 1), runner.ledger().?.recordCount());
    try std.testing.expectEqual(@as(u64, 1), runner.ledger().?.revision().value);

    var semantic_runner = runner_module.Runner.init(std.testing.allocator);
    defer semantic_runner.deinit();
    try semantic_runner.initialize(.{ .bytes = "epoch-2" }, identity.RequestPurposeRegistry.all());
    try std.testing.expectError(
        error.InvalidRequestPurposeBinding,
        semantic_runner.assign(
            .initial,
            owner,
            operation,
            .{ .semantic_review = .{ .bytes = "review-1" } },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), semantic_runner.ledger().?.recordCount());
}

test "ledger initialization rejects malformed epoch authority" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try std.testing.expectError(
        error.InvalidStageRunEpochId,
        runner.initialize(.{ .bytes = "epoch with spaces" }, identity.RequestPurposeRegistry.all()),
    );
    try std.testing.expect(runner.ledger() == null);
}

test "context followup requires an exact current-ledger parent and retains that parent" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const owner = unitOwner("cluster-1");
    const first = try runner.assign(.initial, owner, modelOperation("generate"), .initial_generation);
    const followup = try runner.assign(
        .{ .value = 1 },
        owner,
        modelOperation("resolve-context"),
        .{ .context_followup = .{
            .parent_model_request_id = first,
            .validated_context_request_ordinal = identity.PositiveOrdinal.init(1).?,
        } },
    );
    try std.testing.expect(followup.purpose.context_followup.parent_model_request_id == first);

    var other = runner_module.Runner.init(std.testing.allocator);
    defer other.deinit();
    try other.initialize(.{ .bytes = "epoch-2" }, identity.RequestPurposeRegistry.all());
    const foreign = try other.assign(.initial, owner, modelOperation("generate"), .initial_generation);
    try std.testing.expectError(
        error.InvalidRequestPurposeBinding,
        runner.assign(
            .{ .value = 2 },
            owner,
            modelOperation("resolve-context"),
            .{ .context_followup = .{
                .parent_model_request_id = foreign,
                .validated_context_request_ordinal = identity.PositiveOrdinal.init(1).?,
            } },
        ),
    );
}

test "binding validation requires exact ledger membership and every bound field" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
    const owner = unitOwner("cluster-1");
    const operation = modelOperation("generate");
    const request = try runner.assign(.initial, owner, operation, .initial_generation);
    _ = try runner.validate(.{ .value = 1 }, request, owner, operation, .initial_generation);

    try std.testing.expectError(
        error.ModelRequestBindingInvalid,
        runner.validate(.initial, request, owner, operation, .initial_generation),
    );
    try std.testing.expectError(
        error.ModelRequestBindingInvalid,
        runner.validate(
            .{ .value = 1 },
            request,
            unitOwner("cluster-2"),
            operation,
            .initial_generation,
        ),
    );
    var copied = request.*;
    const copied_evidence = try runner.validate(
        .{ .value = 1 },
        &copied,
        owner,
        operation,
        .initial_generation,
    );
    try std.testing.expect(copied_evidence.modelRequestId() == request);
    copied.request_ordinal.value = 2;
    try std.testing.expectError(
        error.ModelRequestBindingInvalid,
        runner.validate(.{ .value = 1 }, &copied, owner, operation, .initial_generation),
    );
}

test "request identity actions declare the sole ledger production and replacement" {
    try std.testing.expectEqualSlices(
        pipeline.DataKey,
        &.{.model_request_identity_ledger},
        build_ledger.Action.contract.produces,
    );
    try std.testing.expectEqualSlices(
        pipeline.DataKey,
        &.{.model_request_identity_ledger},
        assign_request.Action.contract.requires,
    );
    try std.testing.expectEqualSlices(
        pipeline.DataKey,
        &.{.model_request_identity_ledger},
        assign_request.Action.contract.replaces,
    );
    try std.testing.expectEqualSlices(
        pipeline.DataKey,
        &.{.model_request_identity_ledger},
        validate_binding.Action.contract.requires,
    );
}

fn unitOwner(cluster_id: []const u8) identity.ImmutableUnitOwnerId {
    return .{ .task_cluster = .{
        .plan_state_id = .{ .bytes = "plan-state-1" },
        .obligation_cluster_id = .{ .bytes = cluster_id },
    } };
}

fn modelOperation(step_id: []const u8) binding.WorkflowModelOperationId {
    return .{
        .workflow_id = workflow.WorkflowId.parse("arbitrary-flow").?,
        .workflow_version = 1,
        .workflow_step_id = workflow.WorkflowStepId.parse(step_id).?,
    };
}
