const std = @import("std");
const advance_lifecycle = @import("actions/model/advance_model_request_lifecycle.zig");
const build_ledger = @import("actions/model/build_initial_model_request_identity_ledger.zig");
const provider_binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const provider_lifecycle = @import("domain/provider_operation_lifecycle.zig");
const provider_runner = @import("provider_operation_lifecycle_runner_test_fixture.zig");

/// The ledger successor the prepare stage publishes together with its request and binding evidence,
/// applied on its own so this harness can exercise each identity transition (ADR 0030: no workflow
/// step selects either transition).
const assign_contract: pipeline.NodeContract = .{
    .id = "test.assign-model-request-id",
    .kind = .action,
    .requires = &.{.model_request_identity_ledger},
    .produces = &.{},
    .replaces = &.{.model_request_identity_ledger},
    .side_effect = .none,
};

/// Binding validation reads the ledger and writes nothing.
const validate_contract: pipeline.NodeContract = .{
    .id = "test.validate-model-request-binding",
    .kind = .action,
    .requires = &.{.model_request_identity_ledger},
    .produces = &.{},
    .side_effect = .none,
};

/// Isolated action-test harness; production request transitions run in the `request-model` kernel.
pub const Runner = struct {
    allocator: std.mem.Allocator,
    envelope: pipeline.DataShape = pipeline.DataShape.init(&.{}),
    current_owner: ?*identity.Owner = null,
    provider_operations: ?provider_runner.Runner = null,
    build_action: build_ledger.Action = .{},
    advance_action: advance_lifecycle.Action = .{},

    pub fn init(allocator: std.mem.Allocator) Runner {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Runner) void {
        if (self.provider_operations) |*operations| operations.deinit();
        if (self.current_owner) |owner| identity.deinitOwner(owner);
        self.* = undefined;
    }

    pub fn initialize(
        self: *Runner,
        purpose_registry: identity.RequestPurposeRegistry,
    ) (identity.Error || provider_lifecycle.Error)!void {
        self.envelope.validateInvocation(build_ledger.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const owner = try self.build_action.execute(
            self.allocator,
            purpose_registry,
        );
        errdefer identity.deinitOwner(owner);
        var operations = try provider_runner.Runner.init(self.allocator, identity.ledger(owner).stageRunEpochId());
        errdefer operations.deinit();
        self.envelope = self.envelope.apply(
            build_ledger.Action.contract,
            pipeline.DataEffects.fromContract(build_ledger.Action.contract),
        ) catch return error.ModelRequestBindingInvalid;
        self.current_owner = owner;
        self.provider_operations = operations;
    }

    pub fn assign(
        self: *Runner,
        expected_revision: identity.LedgerRevision,
        unit_owner_id: identity.ImmutableUnitOwnerId,
        model_operation_id: provider_binding.WorkflowModelOperationId,
        purpose: identity.RequestPurposeBinding,
    ) identity.Error!*const identity.ModelRequestId {
        const current_owner = self.current_owner orelse return error.ModelRequestBindingInvalid;
        self.envelope.validateInvocation(assign_contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const assignment = try identity.createSuccessor(
            identity.ledger(current_owner),
            expected_revision,
            unit_owner_id,
            model_operation_id,
            purpose,
        );
        errdefer identity.deinitOwner(assignment.owner);
        self.envelope = self.envelope.apply(
            assign_contract,
            pipeline.DataEffects.fromContract(assign_contract),
        ) catch return error.ModelRequestBindingInvalid;
        self.current_owner = assignment.owner;
        identity.deinitOwner(current_owner);
        return assignment.model_request_id;
    }

    pub fn validate(
        self: *Runner,
        expected_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        unit_owner_id: identity.ImmutableUnitOwnerId,
        model_operation_id: provider_binding.WorkflowModelOperationId,
        purpose: identity.RequestPurposeBinding,
    ) identity.ValidationError!*const identity.ModelRequestBindingEvidence {
        const owner = self.current_owner orelse return error.ModelRequestBindingInvalid;
        self.envelope.validateInvocation(validate_contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        return identity.validateBinding(
            identity.ledger(owner),
            expected_revision,
            request_id,
            unit_owner_id,
            model_operation_id,
            purpose,
        );
    }

    pub fn advance(
        self: *Runner,
        expected_revision: identity.LedgerRevision,
        request_id: *const identity.ModelRequestId,
        expected_status: identity.RequestStatus,
        transition: identity.LifecycleTransition,
    ) (identity.Error || provider_lifecycle.ValidationError)!void {
        const current_owner = self.current_owner orelse return error.ModelRequestBindingInvalid;
        self.envelope.validateInvocation(advance_lifecycle.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const successor = try self.advance_action.execute(
            identity.ledger(current_owner),
            self.providerOperations().current(),
            expected_revision,
            request_id,
            expected_status,
            transition,
        );
        errdefer identity.deinitOwner(successor);
        self.envelope = self.envelope.apply(
            advance_lifecycle.Action.contract,
            pipeline.DataEffects.fromContract(advance_lifecycle.Action.contract),
        ) catch return error.ModelRequestBindingInvalid;
        self.current_owner = successor;
        identity.deinitOwner(current_owner);
    }

    pub fn ledger(self: *const Runner) ?*const identity.ModelRequestIdentityLedger {
        const owner = self.current_owner orelse return null;
        return identity.ledger(owner);
    }

    pub fn providerOperations(self: *Runner) *provider_runner.Runner {
        return &self.provider_operations.?;
    }
};
