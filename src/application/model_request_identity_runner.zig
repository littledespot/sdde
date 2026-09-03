const std = @import("std");
const assign_request = @import("../actions/model/assign_model_request_id.zig");
const build_ledger = @import("../actions/model/build_initial_model_request_identity_ledger.zig");
const validate_binding = @import("../actions/model/validate_model_request_binding.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const identity = @import("../domain/model_request_identity.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    envelope: pipeline.PipelineEnvelope = pipeline.PipelineEnvelope.init(&.{}),
    current_owner: ?*identity.Owner = null,
    build_action: build_ledger.Action = .{},
    assign_action: assign_request.Action = .{},
    validate_action: validate_binding.Action = .{},

    pub fn init(allocator: std.mem.Allocator) Runner {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Runner) void {
        if (self.current_owner) |owner| identity.deinitOwner(owner);
        self.* = undefined;
    }

    pub fn initialize(
        self: *Runner,
        stage_run_epoch_id: identity.StageRunEpochId,
        purpose_registry: identity.RequestPurposeRegistry,
    ) identity.Error!void {
        self.envelope.validateInvocation(build_ledger.Action.contract) catch {
            return error.ModelRequestBindingInvalid;
        };
        const owner = try self.build_action.execute(
            self.allocator,
            stage_run_epoch_id,
            purpose_registry,
        );
        errdefer identity.deinitOwner(owner);
        self.envelope = self.envelope.apply(
            build_ledger.Action.contract,
            pipeline.NodeDelta.successful(build_ledger.Action.contract),
        ) catch return error.ModelRequestBindingInvalid;
        self.current_owner = owner;
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

    pub fn ledger(self: *const Runner) ?*const identity.ModelRequestIdentityLedger {
        const owner = self.current_owner orelse return null;
        return identity.ledger(owner);
    }
};
