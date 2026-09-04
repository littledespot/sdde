const std = @import("std");
const advance_lifecycle = @import("../actions/model/advance_model_request_lifecycle.zig");
const assign_request = @import("../actions/model/assign_model_request_id.zig");
const build_ledger = @import("../actions/model/build_initial_model_request_identity_ledger.zig");
const validate_binding = @import("../actions/model/validate_model_request_binding.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const identity = @import("../domain/model_request_identity.zig");
const pipeline = @import("../domain/pipeline.zig");
const provider_lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const provider_runner = @import("provider_operation_lifecycle_runner.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    envelope: pipeline.PipelineEnvelope = pipeline.PipelineEnvelope.init(&.{}),
    current_owner: ?*identity.Owner = null,
    provider_operations: ?provider_runner.Runner = null,
    build_action: build_ledger.Action = .{},
    assign_action: assign_request.Action = .{},
    advance_action: advance_lifecycle.Action = .{},
    validate_action: validate_binding.Action = .{},

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
        stage_run_epoch_id: identity.StageRunEpochId,
        purpose_registry: identity.RequestPurposeRegistry,
    ) (identity.Error || provider_lifecycle.Error)!void {
        self.envelope.validateInvocation(build_ledger.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const owner = try self.build_action.execute(
            self.allocator,
            stage_run_epoch_id,
            purpose_registry,
        );
        errdefer identity.deinitOwner(owner);
        var operations = try provider_runner.Runner.init(self.allocator, stage_run_epoch_id);
        errdefer operations.deinit();
        self.envelope = self.envelope.apply(
            build_ledger.Action.contract,
            pipeline.NodeDelta.successful(build_ledger.Action.contract),
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
        self.envelope.validateInvocation(assign_request.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const assignment = try self.assign_action.execute(
            identity.ledger(current_owner),
            expected_revision,
            unit_owner_id,
            model_operation_id,
            purpose,
        );
        errdefer identity.deinitOwner(assignment.owner);
        self.envelope = self.envelope.apply(
            assign_request.Action.contract,
            pipeline.NodeDelta.successful(assign_request.Action.contract),
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
        self.envelope.validateInvocation(validate_binding.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        return self.validate_action.execute(
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
            pipeline.NodeDelta.successful(advance_lifecycle.Action.contract),
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
