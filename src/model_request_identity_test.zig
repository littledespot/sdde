const std = @import("std");

test "workflow-owned requests retain their origin without accepting SDD authority substitutes" {
    var runner = @import("model_request_identity_runner_test_fixture.zig").Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(@import("domain/model_request_identity.zig").RequestPurposeRegistry.all());
    const origin = modelOperation("origin");
    const owner: identity.ImmutableUnitOwnerId = .workflow_step;
    const request = try runner.assign(.initial, owner, origin, .initial_generation);
    const current = runner.ledger().?;
    _ = try runner.validate(current.revision(), request, owner, origin, .initial_generation);
    try std.testing.expectError(error.ModelRequestBindingInvalid, runner.validate(current.revision(), request, owner, modelOperation("another-step"), .initial_generation));
    try std.testing.expectError(error.InvalidRequestPurposeBinding, runner.assign(current.revision(), owner, origin, .{ .atomic_repair = .{ .bytes = "repair-1" } }));
    try std.testing.expectError(error.InvalidRequestPurposeBinding, runner.assign(current.revision(), owner, origin, .{ .semantic_review = .{ .bytes = "review-1" } }));
    try std.testing.expectError(error.InvalidImmutableUnitOwnerId, runner.assign(current.revision(), .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "" }, .obligation_cluster_id = .{ .bytes = "cluster" } } }, origin, .initial_generation));
    try std.testing.expectError(error.InvalidImmutableUnitOwnerId, runner.assign(current.revision(), .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = "reference" }, .chunk_id = .{ .bytes = "" } } }, origin, .initial_generation));
}
const advance_lifecycle = @import("actions/model/advance_model_request_lifecycle.zig");
const assign_request = @import("actions/model/assign_model_request_id.zig");
const build_ledger = @import("actions/model/build_initial_model_request_identity_ledger.zig");
const build_owner = @import("actions/model/build_immutable_unit_owner_id.zig");
const validate_binding = @import("actions/model/validate_model_request_binding.zig");
const runner_module = @import("model_request_identity_runner_test_fixture.zig");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const workflow = @import("domain/workflow.zig");

test "specification request ownership preserves validated feature directories for generation review and repair" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(identity.RequestPurposeRegistry.all());
    for ([_][]const u8{ "hello-world", "Loans/Café", "Library renewals/" ++ "a" ** 160 }) |directory| {
        const unit: identity.SpecificationUnitOwner = .{
            .reference_state_id = .{ .bytes = "reference-1" },
            .feature_id = @import("domain/feature_identity.zig").FeatureId.parse(directory).?,
            .unit_slot_id = .{ .bytes = "requirements" },
        };
        const owner: identity.ImmutableUnitOwnerId = .{ .specification_unit = unit };
        const operation = modelOperation("generate");
        const request = try runner.assign(runner.ledger().?.revision(), owner, operation, .initial_generation);
        _ = try runner.validate(runner.ledger().?.revision(), request, owner, operation, .initial_generation);
        try std.testing.expectEqualStrings(directory, request.immutable_unit_owner_id.specification_unit.feature_id.bytes);
        const repair = try runner.assign(runner.ledger().?.revision(), owner, operation, .{ .atomic_repair = .{ .bytes = "repair-1" } });
        try std.testing.expect(identity.unitOwnerEql(owner, repair.immutable_unit_owner_id));
        const review_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{
            .parent_unit_owner_id = .{ .specification_unit = unit },
            .review_slot_id = .{ .bytes = "support" },
        } };
        const review = try runner.assign(runner.ledger().?.revision(), review_owner, operation, .{ .semantic_review = .{ .bytes = "support" } });
        try std.testing.expect(identity.unitOwnerEql(review_owner, review.immutable_unit_owner_id));
    }
    for ([_][]const u8{ "", "/absolute", "../escape", "nested/../escape", "nested//empty", "nested/./dot" }) |directory| {
        const unit: identity.SpecificationUnitOwner = .{
            .reference_state_id = .{ .bytes = "reference-1" },
            .feature_id = .{ .bytes = directory },
            .unit_slot_id = .{ .bytes = "requirements" },
        };
        try std.testing.expectError(error.InvalidImmutableUnitOwnerId, identity.validateUnitOwner(.{ .specification_unit = unit }));
        try std.testing.expectError(error.InvalidImmutableUnitOwnerId, identity.validateUnitOwner(.{ .semantic_review = .{
            .parent_unit_owner_id = .{ .specification_unit = unit },
            .review_slot_id = .{ .bytes = "support" },
        } }));
    }
    try std.testing.expectError(error.InvalidImmutableUnitOwnerId, identity.validateUnitOwner(.{ .specification_unit = .{
        .reference_state_id = .{ .bytes = "référence" },
        .feature_id = .{ .bytes = "Loans/Café" },
        .unit_slot_id = .{ .bytes = "requirements" },
    } }));
}

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

test "ledger replacement validation binds one direct successor and one exact request transition" {
    const allocator = std.testing.allocator;
    const initial = try identity.createInitial(allocator, .all());
    defer identity.deinitOwner(initial);
    const first = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, modelOperation("first"), .initial_generation);
    defer identity.deinitOwner(first.owner);
    try identity.validateAssignmentSuccessor(identity.ledger(initial), identity.ledger(first.owner), first.model_request_id);
    const second = try identity.createSuccessor(identity.ledger(first.owner), identity.ledger(first.owner).revision(), .workflow_step, modelOperation("second"), .initial_generation);
    defer identity.deinitOwner(second.owner);
    const current = identity.ledger(second.owner);
    const invoked = try identity.createLifecycleSuccessor(current, current.revision(), first.model_request_id, .assigned, .invoked);
    defer identity.deinitOwner(invoked);
    const next = identity.ledger(invoked);
    try identity.validateLifecycleSuccessor(current, next, first.model_request_id, .assigned, .invoked);
    try std.testing.expectEqual(.assigned, next.record(second.model_request_id).?.status);
    try std.testing.expect(next.canonicalRequestId(first.model_request_id) == first.model_request_id);
    try std.testing.expectError(error.ModelRequestBindingInvalid, identity.validateLifecycleSuccessor(current, next, second.model_request_id, .assigned, .invoked));
    try std.testing.expectError(error.ModelRequestBindingInvalid, identity.validateAssignmentSuccessor(current, next, first.model_request_id));
    try std.testing.expectError(error.ModelRequestBindingInvalid, identity.validateLifecycleSuccessor(identity.ledger(first.owner), current, first.model_request_id, .assigned, .invoked));
    try std.testing.expectError(error.ModelRequestStatusConflict, identity.validateLifecycleSuccessor(current, next, first.model_request_id, .invoked, .invoked));
    try std.testing.expectError(error.ModelRequestRevisionConflict, identity.validateLifecycleSuccessor(current, current, first.model_request_id, .assigned, .invoked));
    try std.testing.expectError(error.ModelRequestRevisionConflict, identity.validateLifecycleSuccessor(identity.ledger(first.owner), next, first.model_request_id, .assigned, .invoked));
    const cancelled = try identity.createLifecycleSuccessor(current, current.revision(), first.model_request_id, .assigned, .{ .terminal = .cancelled });
    defer identity.deinitOwner(cancelled);
    try std.testing.expectError(error.InvalidModelRequestLifecycleTransition, identity.validateLifecycleSuccessor(current, identity.ledger(cancelled), first.model_request_id, .assigned, .invoked));
    const foreign = try identity.createInitial(allocator, .all());
    defer identity.deinitOwner(foreign);
    const foreign_request = try identity.createSuccessor(identity.ledger(foreign), .initial, .workflow_step, modelOperation("first"), .initial_generation);
    defer identity.deinitOwner(foreign_request.owner);
    try std.testing.expectError(error.ModelRequestRevisionConflict, identity.validateAssignmentSuccessor(identity.ledger(initial), identity.ledger(foreign_request.owner), foreign_request.model_request_id));
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
    try runner.initialize(identity.RequestPurposeRegistry.all());

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
    try runner.initialize(identity.RequestPurposeRegistry.all());
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
    try runner.initialize(identity.RequestPurposeRegistry.all());

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
    try runner.initialize(registry);
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
    try semantic_runner.initialize(identity.RequestPurposeRegistry.all());
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
        error.InvalidRequestPurposeRegistry,
        runner.initialize(.{}),
    );
    try std.testing.expect(runner.ledger() == null);
}

test "context followup requires an exact current-ledger parent and retains that parent" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(identity.RequestPurposeRegistry.all());
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
    try other.initialize(identity.RequestPurposeRegistry.all());
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
    try runner.initialize(identity.RequestPurposeRegistry.all());
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

test "runner advances one request through the closed lifecycle" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(identity.RequestPurposeRegistry.all());
    const request = try runner.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );

    try runner.advance(.{ .value = 1 }, request, .assigned, .invoked);
    const invoked = runner.ledger().?.record(request).?;
    try std.testing.expectEqual(identity.RequestStatus.invoked, invoked.status);
    try std.testing.expect(invoked.terminal_reason == null);
    try std.testing.expectEqual(@as(u64, 2), runner.ledger().?.revision().value);
    try std.testing.expectEqual(@as(usize, 1), runner.ledger().?.recordCount());

    try runner.advance(.{ .value = 2 }, request, .invoked, .{ .terminal = .accepted });
    const terminal = runner.ledger().?.record(request).?;
    try std.testing.expectEqual(identity.RequestStatus.terminal, terminal.status);
    try std.testing.expectEqual(identity.TerminalReason.accepted, terminal.terminal_reason.?);
    try std.testing.expectEqual(@as(u64, 3), runner.ledger().?.revision().value);
    try std.testing.expectEqual(@as(usize, 1), runner.ledger().?.recordCount());
}

test "terminal reason legality is exhaustive for assigned and invoked requests" {
    for (std.enums.values(identity.TerminalReason)) |reason| {
        {
            var runner = runner_module.Runner.init(std.testing.allocator);
            defer runner.deinit();
            try runner.initialize(identity.RequestPurposeRegistry.all());
            const request = try runner.assign(
                .initial,
                unitOwner("cluster-1"),
                modelOperation("generate"),
                .initial_generation,
            );
            if (isNotInvokedReason(reason) or reason == .cancelled) {
                try runner.advance(.{ .value = 1 }, request, .assigned, .{ .terminal = reason });
                try std.testing.expectEqual(reason, runner.ledger().?.record(request).?.terminal_reason.?);
            } else {
                try std.testing.expectError(
                    error.InvalidModelRequestLifecycleTransition,
                    runner.advance(.{ .value = 1 }, request, .assigned, .{ .terminal = reason }),
                );
            }
        }
        {
            var runner = runner_module.Runner.init(std.testing.allocator);
            defer runner.deinit();
            try runner.initialize(identity.RequestPurposeRegistry.all());
            const request = try runner.assign(
                .initial,
                unitOwner("cluster-1"),
                modelOperation("generate"),
                .initial_generation,
            );
            try runner.advance(.{ .value = 1 }, request, .assigned, .invoked);
            if (isNotInvokedReason(reason)) {
                try std.testing.expectError(
                    error.InvalidModelRequestLifecycleTransition,
                    runner.advance(.{ .value = 2 }, request, .invoked, .{ .terminal = reason }),
                );
            } else {
                try runner.advance(.{ .value = 2 }, request, .invoked, .{ .terminal = reason });
                try std.testing.expectEqual(reason, runner.ledger().?.record(request).?.terminal_reason.?);
            }
        }
    }
}

test "lifecycle CAS rejects stale illegal duplicate and foreign transitions atomically" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(identity.RequestPurposeRegistry.all());
    const request = try runner.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );

    try std.testing.expectError(
        error.ModelRequestRevisionConflict,
        runner.advance(.initial, request, .assigned, .invoked),
    );
    try std.testing.expectError(
        error.ModelRequestStatusConflict,
        runner.advance(.{ .value = 1 }, request, .invoked, .{ .terminal = .accepted }),
    );
    try std.testing.expectError(
        error.InvalidModelRequestLifecycleTransition,
        runner.advance(.{ .value = 1 }, request, .assigned, .{ .terminal = .accepted }),
    );
    try std.testing.expectEqual(@as(u64, 1), runner.ledger().?.revision().value);
    try std.testing.expectEqual(identity.RequestStatus.assigned, runner.ledger().?.record(request).?.status);

    try runner.advance(.{ .value = 1 }, request, .assigned, .invoked);
    try std.testing.expectError(
        error.InvalidModelRequestLifecycleTransition,
        runner.advance(.{ .value = 2 }, request, .invoked, .invoked),
    );
    try std.testing.expectError(
        error.InvalidModelRequestLifecycleTransition,
        runner.advance(
            .{ .value = 2 },
            request,
            .invoked,
            .{ .terminal = .not_invoked_authorization_failure },
        ),
    );
    try runner.advance(.{ .value = 2 }, request, .invoked, .{ .terminal = .failed });
    try std.testing.expectError(
        error.InvalidModelRequestLifecycleTransition,
        runner.advance(.{ .value = 3 }, request, .terminal, .invoked),
    );

    var foreign_runner = runner_module.Runner.init(std.testing.allocator);
    defer foreign_runner.deinit();
    try foreign_runner.initialize(identity.RequestPurposeRegistry.all());
    const foreign = try foreign_runner.assign(
        .initial,
        unitOwner("cluster-1"),
        modelOperation("generate"),
        .initial_generation,
    );
    try std.testing.expectError(
        error.ModelRequestNotFound,
        runner.advance(.{ .value = 3 }, foreign, .assigned, .invoked),
    );
    try std.testing.expectEqual(@as(u64, 3), runner.ledger().?.revision().value);
    try std.testing.expectEqual(identity.RequestStatus.terminal, runner.ledger().?.record(request).?.status);
}

test "lifecycle history cannot reuse a lower request ordinal" {
    var runner = runner_module.Runner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.initialize(identity.RequestPurposeRegistry.all());
    const owner = unitOwner("cluster-1");
    const model_operation = modelOperation("generate");
    const first = try runner.assign(.initial, owner, model_operation, .initial_generation);
    const second = try runner.assign(
        .{ .value = 1 },
        owner,
        model_operation,
        .initial_generation,
    );
    try std.testing.expectEqual(@as(u32, 2), second.request_ordinal.value);

    try runner.advance(.{ .value = 2 }, first, .assigned, .invoked);
    const third = try runner.assign(
        .{ .value = 3 },
        owner,
        model_operation,
        .initial_generation,
    );
    try std.testing.expectEqual(@as(u32, 3), third.request_ordinal.value);
    try std.testing.expectEqual(@as(usize, 3), runner.ledger().?.recordCount());
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
        advance_lifecycle.Action.contract.requires,
    );
    try std.testing.expectEqualSlices(
        pipeline.DataKey,
        &.{.model_request_identity_ledger},
        advance_lifecycle.Action.contract.replaces,
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

fn isNotInvokedReason(reason: identity.TerminalReason) bool {
    return switch (reason) {
        .not_invoked_authorization_failure => true,
        .accepted, .needs_user, .invalid_exhausted, .blocked, .failed, .cancelled => false,
    };
}
