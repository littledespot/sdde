const std = @import("std");
const provider_binding = @import("llm_provider_binding.zig");

pub const StageRunEpochId = struct {
    bytes: []const u8,

    pub fn isValid(self: StageRunEpochId) bool {
        validateAuthorityId(self.bytes, error.InvalidStageRunEpochId) catch return false;
        return true;
    }

    pub fn eql(left: StageRunEpochId, right: StageRunEpochId) bool {
        return authorityIdEql(left.bytes, right.bytes);
    }
};
pub const ReferenceStateId = struct { bytes: []const u8 };
pub const ReferenceChunkId = struct { bytes: []const u8 };
pub const UnitSlotId = struct { bytes: []const u8 };
pub const FeatureRequestId = struct { bytes: []const u8 };
pub const PlanInputAuthorityStateId = struct { bytes: []const u8 };
pub const PlanStateId = struct { bytes: []const u8 };
pub const ObligationClusterId = struct { bytes: []const u8 };
pub const TaskDefinitionStateId = struct { bytes: []const u8 };
pub const TaskId = struct { bytes: []const u8 };
pub const OperationIntentId = struct { bytes: []const u8 };
pub const ReviewSlotId = struct { bytes: []const u8 };
pub const RepairAuthorizationId = struct { bytes: []const u8 };
pub const SemanticReviewSlotId = struct { bytes: []const u8 };
pub const ClarificationStateId = struct { bytes: []const u8 };
pub const ClarificationId = struct { bytes: []const u8 };

pub const PositiveOrdinal = struct {
    value: u32,

    pub fn init(value: u32) ?PositiveOrdinal {
        return if (value == 0) null else .{ .value = value };
    }
};

pub const LedgerRevision = struct {
    value: u64,

    pub const initial: LedgerRevision = .{ .value = 0 };

    pub fn eql(left: LedgerRevision, right: LedgerRevision) bool {
        return left.value == right.value;
    }
};

pub const ReferenceChunkOwner = struct {
    reference_state_id: ReferenceStateId,
    chunk_id: ReferenceChunkId,
};
pub const ReferenceGlobalOwner = struct {
    reference_state_id: ReferenceStateId,
    unit_slot_id: UnitSlotId,
};
pub const SpecificationUnitOwner = struct {
    reference_state_id: ReferenceStateId,
    feature_request_id: FeatureRequestId,
    unit_slot_id: UnitSlotId,
};
pub const PlanUnitOwner = struct {
    plan_input_authority_state_id: PlanInputAuthorityStateId,
    unit_slot_id: UnitSlotId,
};
pub const TaskClusterOwner = struct {
    plan_state_id: PlanStateId,
    obligation_cluster_id: ObligationClusterId,
};
pub const ImplementationOperationOwner = struct {
    task_definition_state_id: TaskDefinitionStateId,
    task_id: TaskId,
    operation_intent_id: OperationIntentId,
};

pub const ContentUnitOwnerId = union(enum) {
    reference_chunk: ReferenceChunkOwner,
    reference_global: ReferenceGlobalOwner,
    specification_unit: SpecificationUnitOwner,
    plan_unit: PlanUnitOwner,
    task_cluster: TaskClusterOwner,
    implementation_operation: ImplementationOperationOwner,
};

pub const ImmutableUnitOwnerId = union(enum) {
    reference_chunk: ReferenceChunkOwner,
    reference_global: ReferenceGlobalOwner,
    specification_unit: SpecificationUnitOwner,
    plan_unit: PlanUnitOwner,
    task_cluster: TaskClusterOwner,
    implementation_operation: ImplementationOperationOwner,
    semantic_review: struct {
        parent_unit_owner_id: ContentUnitOwnerId,
        review_slot_id: ReviewSlotId,
    },
};

pub const RequestPurposeKind = enum {
    initial_generation,
    atomic_repair,
    semantic_review,
    clarification_resolution,
    context_followup,
};

pub const RequestPurposeBinding = union(RequestPurposeKind) {
    initial_generation,
    atomic_repair: RepairAuthorizationId,
    semantic_review: SemanticReviewSlotId,
    clarification_resolution: struct {
        clarification_state_id: ClarificationStateId,
        clarification_state_revision: u64,
        clarification_id: ClarificationId,
    },
    context_followup: struct {
        parent_model_request_id: *const ModelRequestId,
        validated_context_request_ordinal: PositiveOrdinal,
    },
};

pub const RequestPurposeRegistry = struct {
    initial_generation: bool = false,
    atomic_repair: bool = false,
    semantic_review: bool = false,
    clarification_resolution: bool = false,
    context_followup: bool = false,

    pub fn init(kinds: []const RequestPurposeKind) ValidationError!RequestPurposeRegistry {
        var result: RequestPurposeRegistry = .{};
        for (kinds) |kind| {
            const enabled = switch (kind) {
                .initial_generation => &result.initial_generation,
                .atomic_repair => &result.atomic_repair,
                .semantic_review => &result.semantic_review,
                .clarification_resolution => &result.clarification_resolution,
                .context_followup => &result.context_followup,
            };
            if (enabled.*) return error.InvalidRequestPurposeRegistry;
            enabled.* = true;
        }
        if (!result.hasAny()) return error.InvalidRequestPurposeRegistry;
        return result;
    }

    pub fn all() RequestPurposeRegistry {
        return .{
            .initial_generation = true,
            .atomic_repair = true,
            .semantic_review = true,
            .clarification_resolution = true,
            .context_followup = true,
        };
    }

    pub fn allows(self: RequestPurposeRegistry, kind: RequestPurposeKind) bool {
        return switch (kind) {
            .initial_generation => self.initial_generation,
            .atomic_repair => self.atomic_repair,
            .semantic_review => self.semantic_review,
            .clarification_resolution => self.clarification_resolution,
            .context_followup => self.context_followup,
        };
    }

    fn hasAny(self: RequestPurposeRegistry) bool {
        return self.initial_generation or self.atomic_repair or self.semantic_review or
            self.clarification_resolution or self.context_followup;
    }
};

pub const ModelRequestId = struct {
    stage_run_epoch_id: StageRunEpochId,
    immutable_unit_owner_id: ImmutableUnitOwnerId,
    model_operation_id: provider_binding.WorkflowModelOperationId,
    purpose: RequestPurposeBinding,
    request_ordinal: PositiveOrdinal,
};

pub const RequestStatus = enum { assigned, invoked, terminal };

pub const TerminalReason = enum {
    accepted,
    needs_user,
    invalid_exhausted,
    blocked,
    failed,
    cancelled,
    not_invoked_authorization_failure,
};

pub const LifecycleTransition = union(enum) {
    invoked,
    terminal: TerminalReason,
};

pub const Record = struct {
    model_request_id: ModelRequestId,
    status: RequestStatus,
    terminal_reason: ?TerminalReason = null,
};

pub const ModelRequestBindingEvidence = opaque {
    pub fn modelRequestId(self: *const ModelRequestBindingEvidence) *const ModelRequestId {
        return @ptrCast(@alignCast(self));
    }
};

pub const ModelRequestIdentityLedger = opaque {
    pub fn stageRunEpochId(self: *const ModelRequestIdentityLedger) StageRunEpochId {
        return ledgerStorage(self).stage_run_epoch_id;
    }

    pub fn revision(self: *const ModelRequestIdentityLedger) LedgerRevision {
        return ledgerStorage(self).revision;
    }

    pub fn recordCount(self: *const ModelRequestIdentityLedger) usize {
        return ledgerStorage(self).record_count;
    }

    pub fn latestRecord(self: *const ModelRequestIdentityLedger) ?*const Record {
        const latest = ledgerStorage(self).latest_record orelse return null;
        return &latest.record;
    }

    pub fn containsRequest(self: *const ModelRequestIdentityLedger, request_id: *const ModelRequestId) bool {
        return resolveRequest(ledgerStorage(self), request_id) != null;
    }

    pub fn record(
        self: *const ModelRequestIdentityLedger,
        request_id: *const ModelRequestId,
    ) ?*const Record {
        const node = resolveRecord(ledgerStorage(self), request_id) orelse return null;
        return &node.record;
    }

    pub fn canonicalRequestId(
        self: *const ModelRequestIdentityLedger,
        request_id: *const ModelRequestId,
    ) ?*const ModelRequestId {
        return resolveRequest(ledgerStorage(self), request_id);
    }
};

pub const Owner = opaque {};

pub const Assignment = struct {
    owner: *Owner,
    model_request_id: *const ModelRequestId,
};

pub const ValidationError = error{
    InvalidStageRunEpochId,
    InvalidRequestPurposeRegistry,
    InvalidImmutableUnitOwnerId,
    InvalidWorkflowModelOperationId,
    InvalidRequestPurposeBinding,
    RequestPurposeNotRegistered,
    ModelRequestRevisionConflict,
    ModelRequestRevisionExhausted,
    ModelRequestOrdinalExhausted,
    ModelRequestOwnerReferenceExhausted,
    ModelRequestBindingInvalid,
    ModelRequestNotFound,
    ModelRequestStatusConflict,
    InvalidModelRequestLifecycleTransition,
};

pub const Error = std.mem.Allocator.Error || ValidationError;

const RecordNode = struct {
    previous: ?*const RecordNode,
    record: Record,
    canonical_model_request_id: *const ModelRequestId,
};

const LedgerStorage = struct {
    owner: *Owner,
    stage_run_epoch_id: StageRunEpochId,
    purpose_registry: RequestPurposeRegistry,
    revision: LedgerRevision,
    record_count: usize,
    latest_record: ?*const RecordNode,
};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    reference_count: usize,
    previous_owner: ?*Owner,
    arena: std.heap.ArenaAllocator,
    ledger: LedgerStorage,
};

pub fn createInitial(
    allocator: std.mem.Allocator,
    stage_run_epoch_id: StageRunEpochId,
    purpose_registry: RequestPurposeRegistry,
) Error!*Owner {
    if (!stage_run_epoch_id.isValid()) return error.InvalidStageRunEpochId;
    if (!purpose_registry.hasAny()) return error.InvalidRequestPurposeRegistry;

    const value = try allocator.create(OwnerStorage);
    errdefer allocator.destroy(value);
    value.* = .{
        .backing_allocator = allocator,
        .reference_count = 1,
        .previous_owner = null,
        .arena = .init(allocator),
        .ledger = undefined,
    };
    errdefer value.arena.deinit();
    const epoch_bytes = try value.arena.allocator().dupe(u8, stage_run_epoch_id.bytes);
    const owner: *Owner = @ptrCast(value);
    value.ledger = .{
        .owner = owner,
        .stage_run_epoch_id = .{ .bytes = epoch_bytes },
        .purpose_registry = purpose_registry,
        .revision = .initial,
        .record_count = 0,
        .latest_record = null,
    };
    return owner;
}

pub fn createSuccessor(
    current: *const ModelRequestIdentityLedger,
    expected_revision: LedgerRevision,
    unit_owner_id: ImmutableUnitOwnerId,
    model_operation_id: provider_binding.WorkflowModelOperationId,
    purpose: RequestPurposeBinding,
) Error!Assignment {
    const current_storage = ledgerStorage(current);
    if (!current_storage.revision.eql(expected_revision)) return error.ModelRequestRevisionConflict;
    try validateUnitOwner(unit_owner_id);
    if (!model_operation_id.isValid()) return error.InvalidWorkflowModelOperationId;
    try validatePurpose(current_storage, unit_owner_id, purpose);

    const request_ordinal = try nextOrdinal(current_storage, unit_owner_id, model_operation_id, purpose);
    const next_revision_value = std.math.add(u64, current_storage.revision.value, 1) catch {
        return error.ModelRequestRevisionExhausted;
    };
    const next_record_count = std.math.add(usize, current_storage.record_count, 1) catch {
        return error.ModelRequestOrdinalExhausted;
    };

    const previous_owner = current_storage.owner;
    const previous_storage = ownerStorage(previous_owner);
    const value = try previous_storage.backing_allocator.create(OwnerStorage);
    errdefer previous_storage.backing_allocator.destroy(value);
    value.* = .{
        .backing_allocator = previous_storage.backing_allocator,
        .reference_count = 1,
        .previous_owner = null,
        .arena = .init(previous_storage.backing_allocator),
        .ledger = undefined,
    };
    errdefer value.arena.deinit();

    const allocator = value.arena.allocator();
    const canonical_model_request_id = try allocator.create(ModelRequestId);
    canonical_model_request_id.* = .{
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .immutable_unit_owner_id = try cloneUnitOwner(allocator, unit_owner_id),
        .model_operation_id = try cloneModelOperation(allocator, model_operation_id),
        .purpose = try clonePurpose(allocator, current_storage, purpose),
        .request_ordinal = request_ordinal,
    };
    const node = try allocator.create(RecordNode);
    node.* = .{
        .previous = current_storage.latest_record,
        .record = .{
            .model_request_id = canonical_model_request_id.*,
            .status = .assigned,
        },
        .canonical_model_request_id = canonical_model_request_id,
    };
    try retainOwner(previous_owner);
    value.previous_owner = previous_owner;
    const owner: *Owner = @ptrCast(value);
    value.ledger = .{
        .owner = owner,
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .purpose_registry = current_storage.purpose_registry,
        .revision = .{ .value = next_revision_value },
        .record_count = next_record_count,
        .latest_record = node,
    };
    return .{ .owner = owner, .model_request_id = canonical_model_request_id };
}

pub fn createLifecycleSuccessor(
    current: *const ModelRequestIdentityLedger,
    expected_revision: LedgerRevision,
    request_id: *const ModelRequestId,
    expected_status: RequestStatus,
    transition: LifecycleTransition,
) Error!*Owner {
    const current_storage = ledgerStorage(current);
    if (!current_storage.revision.eql(expected_revision)) return error.ModelRequestRevisionConflict;
    const current_node = resolveRecord(current_storage, request_id) orelse {
        return error.ModelRequestNotFound;
    };
    const current_record = &current_node.record;
    if (current_record.status != expected_status) return error.ModelRequestStatusConflict;

    const next_record = try transitionRecord(current_record.*, transition);
    const next_revision_value = std.math.add(u64, current_storage.revision.value, 1) catch {
        return error.ModelRequestRevisionExhausted;
    };

    const previous_owner = current_storage.owner;
    const previous_storage = ownerStorage(previous_owner);
    const value = try previous_storage.backing_allocator.create(OwnerStorage);
    errdefer previous_storage.backing_allocator.destroy(value);
    value.* = .{
        .backing_allocator = previous_storage.backing_allocator,
        .reference_count = 1,
        .previous_owner = null,
        .arena = .init(previous_storage.backing_allocator),
        .ledger = undefined,
    };
    errdefer value.arena.deinit();

    const node = try value.arena.allocator().create(RecordNode);
    node.* = .{
        .previous = current_storage.latest_record,
        .record = next_record,
        .canonical_model_request_id = current_node.canonical_model_request_id,
    };
    try retainOwner(previous_owner);
    value.previous_owner = previous_owner;
    const owner: *Owner = @ptrCast(value);
    value.ledger = .{
        .owner = owner,
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .purpose_registry = current_storage.purpose_registry,
        .revision = .{ .value = next_revision_value },
        .record_count = current_storage.record_count,
        .latest_record = node,
    };
    return owner;
}

pub fn ledger(owner: *const Owner) *const ModelRequestIdentityLedger {
    return @ptrCast(&ownerStorageConst(owner).ledger);
}

pub fn deinitOwner(owner: *Owner) void {
    var next: ?*Owner = owner;
    while (next) |current| {
        const value = ownerStorage(current);
        std.debug.assert(value.reference_count > 0);
        value.reference_count -= 1;
        if (value.reference_count != 0) return;
        const previous = value.previous_owner;
        const allocator = value.backing_allocator;
        value.arena.deinit();
        allocator.destroy(value);
        next = previous;
    }
}

pub fn validateUnitOwner(owner: ImmutableUnitOwnerId) ValidationError!void {
    switch (owner) {
        .reference_chunk => |value| try validateContentOwner(.{ .reference_chunk = value }),
        .reference_global => |value| try validateContentOwner(.{ .reference_global = value }),
        .specification_unit => |value| try validateContentOwner(.{ .specification_unit = value }),
        .plan_unit => |value| try validateContentOwner(.{ .plan_unit = value }),
        .task_cluster => |value| try validateContentOwner(.{ .task_cluster = value }),
        .implementation_operation => |value| try validateContentOwner(.{ .implementation_operation = value }),
        .semantic_review => |review| {
            try validateContentOwner(review.parent_unit_owner_id);
            try validateAuthorityId(review.review_slot_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
    }
}

pub fn validateBinding(
    current: *const ModelRequestIdentityLedger,
    expected_revision: LedgerRevision,
    request_id: *const ModelRequestId,
    unit_owner_id: ImmutableUnitOwnerId,
    model_operation_id: provider_binding.WorkflowModelOperationId,
    purpose: RequestPurposeBinding,
) ValidationError!*const ModelRequestBindingEvidence {
    const current_storage = ledgerStorage(current);
    const canonical_request_id = resolveRequest(current_storage, request_id) orelse {
        return error.ModelRequestBindingInvalid;
    };
    if (!current_storage.revision.eql(expected_revision) or
        !authorityIdEql(canonical_request_id.stage_run_epoch_id.bytes, current_storage.stage_run_epoch_id.bytes) or
        !unitOwnerEql(canonical_request_id.immutable_unit_owner_id, unit_owner_id) or
        !canonical_request_id.model_operation_id.eql(model_operation_id) or
        !purposeEqlBounded(canonical_request_id.purpose, purpose, current_storage.record_count + 1))
    {
        return error.ModelRequestBindingInvalid;
    }
    try validateUnitOwner(unit_owner_id);
    if (!model_operation_id.isValid()) return error.ModelRequestBindingInvalid;
    validatePurpose(current_storage, unit_owner_id, purpose) catch {
        return error.ModelRequestBindingInvalid;
    };
    return @ptrCast(canonical_request_id);
}

pub fn unitOwnerEql(left: ImmutableUnitOwnerId, right: ImmutableUnitOwnerId) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .reference_chunk => |value| contentOwnerEql(.{ .reference_chunk = value }, .{ .reference_chunk = right.reference_chunk }),
        .reference_global => |value| contentOwnerEql(.{ .reference_global = value }, .{ .reference_global = right.reference_global }),
        .specification_unit => |value| contentOwnerEql(.{ .specification_unit = value }, .{ .specification_unit = right.specification_unit }),
        .plan_unit => |value| contentOwnerEql(.{ .plan_unit = value }, .{ .plan_unit = right.plan_unit }),
        .task_cluster => |value| contentOwnerEql(.{ .task_cluster = value }, .{ .task_cluster = right.task_cluster }),
        .implementation_operation => |value| contentOwnerEql(.{ .implementation_operation = value }, .{ .implementation_operation = right.implementation_operation }),
        .semantic_review => |value| contentOwnerEql(value.parent_unit_owner_id, right.semantic_review.parent_unit_owner_id) and
            authorityIdEql(value.review_slot_id.bytes, right.semantic_review.review_slot_id.bytes),
    };
}

fn validatePurpose(
    current: *const LedgerStorage,
    unit_owner_id: ImmutableUnitOwnerId,
    purpose: RequestPurposeBinding,
) ValidationError!void {
    const kind = std.meta.activeTag(purpose);
    if (!current.purpose_registry.allows(kind)) return error.RequestPurposeNotRegistered;
    switch (purpose) {
        .initial_generation => {},
        .atomic_repair => |id| try validateAuthorityId(id.bytes, error.InvalidRequestPurposeBinding),
        .semantic_review => |slot_id| {
            try validateAuthorityId(slot_id.bytes, error.InvalidRequestPurposeBinding);
            if (unit_owner_id != .semantic_review or
                !authorityIdEql(unit_owner_id.semantic_review.review_slot_id.bytes, slot_id.bytes))
            {
                return error.InvalidRequestPurposeBinding;
            }
        },
        .clarification_resolution => |binding| {
            try validateAuthorityId(binding.clarification_state_id.bytes, error.InvalidRequestPurposeBinding);
            try validateAuthorityId(binding.clarification_id.bytes, error.InvalidRequestPurposeBinding);
        },
        .context_followup => |binding| {
            const parent = resolveRequest(current, binding.parent_model_request_id) orelse {
                return error.InvalidRequestPurposeBinding;
            };
            if (binding.validated_context_request_ordinal.value == 0 or
                !unitOwnerEql(parent.immutable_unit_owner_id, unit_owner_id))
            {
                return error.InvalidRequestPurposeBinding;
            }
        },
    }
}

fn nextOrdinal(
    current: *const LedgerStorage,
    unit_owner_id: ImmutableUnitOwnerId,
    model_operation_id: provider_binding.WorkflowModelOperationId,
    purpose: RequestPurposeBinding,
) ValidationError!PositiveOrdinal {
    var greatest: u32 = 0;
    var node = current.latest_record;
    while (node) |entry| : (node = entry.previous) {
        const id = entry.record.model_request_id;
        if (unitOwnerEql(id.immutable_unit_owner_id, unit_owner_id) and
            id.model_operation_id.eql(model_operation_id) and
            purposeEqlBounded(id.purpose, purpose, current.record_count + 1))
        {
            greatest = @max(greatest, id.request_ordinal.value);
        }
    }
    return .{ .value = std.math.add(u32, greatest, 1) catch {
        return error.ModelRequestOrdinalExhausted;
    } };
}

fn resolveRequest(current: *const LedgerStorage, expected: *const ModelRequestId) ?*const ModelRequestId {
    const node = resolveRecord(current, expected) orelse return null;
    return node.canonical_model_request_id;
}

fn resolveRecord(current: *const LedgerStorage, expected: *const ModelRequestId) ?*const RecordNode {
    var node = current.latest_record;
    while (node) |entry| : (node = entry.previous) {
        const candidate = entry.canonical_model_request_id;
        if (candidate == expected or modelRequestIdEql(candidate, expected, current.record_count + 1)) {
            return entry;
        }
    }
    return null;
}

fn transitionRecord(current: Record, transition: LifecycleTransition) ValidationError!Record {
    return switch (transition) {
        .invoked => if (current.status == .assigned and current.terminal_reason == null)
            .{
                .model_request_id = current.model_request_id,
                .status = .invoked,
            }
        else
            error.InvalidModelRequestLifecycleTransition,
        .terminal => |reason| switch (current.status) {
            .assigned => if (current.terminal_reason == null and (isNotInvokedReason(reason) or reason == .cancelled))
                .{
                    .model_request_id = current.model_request_id,
                    .status = .terminal,
                    .terminal_reason = reason,
                }
            else
                error.InvalidModelRequestLifecycleTransition,
            .invoked => if (current.terminal_reason == null and !isNotInvokedReason(reason))
                .{
                    .model_request_id = current.model_request_id,
                    .status = .terminal,
                    .terminal_reason = reason,
                }
            else
                error.InvalidModelRequestLifecycleTransition,
            .terminal => error.InvalidModelRequestLifecycleTransition,
        },
    };
}

fn isNotInvokedReason(reason: TerminalReason) bool {
    return switch (reason) {
        .not_invoked_authorization_failure => true,
        .accepted, .needs_user, .invalid_exhausted, .blocked, .failed, .cancelled => false,
    };
}

fn validateContentOwner(owner: ContentUnitOwnerId) ValidationError!void {
    switch (owner) {
        .reference_chunk => |value| {
            try validateAuthorityId(value.reference_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.chunk_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
        .reference_global => |value| {
            try validateAuthorityId(value.reference_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.unit_slot_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
        .specification_unit => |value| {
            try validateAuthorityId(value.reference_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.feature_request_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.unit_slot_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
        .plan_unit => |value| {
            try validateAuthorityId(value.plan_input_authority_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.unit_slot_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
        .task_cluster => |value| {
            try validateAuthorityId(value.plan_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.obligation_cluster_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
        .implementation_operation => |value| {
            try validateAuthorityId(value.task_definition_state_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.task_id.bytes, error.InvalidImmutableUnitOwnerId);
            try validateAuthorityId(value.operation_intent_id.bytes, error.InvalidImmutableUnitOwnerId);
        },
    }
}

fn cloneUnitOwner(allocator: std.mem.Allocator, owner: ImmutableUnitOwnerId) std.mem.Allocator.Error!ImmutableUnitOwnerId {
    return switch (owner) {
        .reference_chunk => |value| .{ .reference_chunk = (try cloneContentOwner(allocator, .{ .reference_chunk = value })).reference_chunk },
        .reference_global => |value| .{ .reference_global = (try cloneContentOwner(allocator, .{ .reference_global = value })).reference_global },
        .specification_unit => |value| .{ .specification_unit = (try cloneContentOwner(allocator, .{ .specification_unit = value })).specification_unit },
        .plan_unit => |value| .{ .plan_unit = (try cloneContentOwner(allocator, .{ .plan_unit = value })).plan_unit },
        .task_cluster => |value| .{ .task_cluster = (try cloneContentOwner(allocator, .{ .task_cluster = value })).task_cluster },
        .implementation_operation => |value| .{ .implementation_operation = (try cloneContentOwner(allocator, .{ .implementation_operation = value })).implementation_operation },
        .semantic_review => |review| .{ .semantic_review = .{
            .parent_unit_owner_id = try cloneContentOwner(allocator, review.parent_unit_owner_id),
            .review_slot_id = .{ .bytes = try allocator.dupe(u8, review.review_slot_id.bytes) },
        } },
    };
}

fn cloneContentOwner(allocator: std.mem.Allocator, owner: ContentUnitOwnerId) std.mem.Allocator.Error!ContentUnitOwnerId {
    return switch (owner) {
        .reference_chunk => |value| .{ .reference_chunk = .{
            .reference_state_id = .{ .bytes = try allocator.dupe(u8, value.reference_state_id.bytes) },
            .chunk_id = .{ .bytes = try allocator.dupe(u8, value.chunk_id.bytes) },
        } },
        .reference_global => |value| .{ .reference_global = .{
            .reference_state_id = .{ .bytes = try allocator.dupe(u8, value.reference_state_id.bytes) },
            .unit_slot_id = .{ .bytes = try allocator.dupe(u8, value.unit_slot_id.bytes) },
        } },
        .specification_unit => |value| .{ .specification_unit = .{
            .reference_state_id = .{ .bytes = try allocator.dupe(u8, value.reference_state_id.bytes) },
            .feature_request_id = .{ .bytes = try allocator.dupe(u8, value.feature_request_id.bytes) },
            .unit_slot_id = .{ .bytes = try allocator.dupe(u8, value.unit_slot_id.bytes) },
        } },
        .plan_unit => |value| .{ .plan_unit = .{
            .plan_input_authority_state_id = .{ .bytes = try allocator.dupe(u8, value.plan_input_authority_state_id.bytes) },
            .unit_slot_id = .{ .bytes = try allocator.dupe(u8, value.unit_slot_id.bytes) },
        } },
        .task_cluster => |value| .{ .task_cluster = .{
            .plan_state_id = .{ .bytes = try allocator.dupe(u8, value.plan_state_id.bytes) },
            .obligation_cluster_id = .{ .bytes = try allocator.dupe(u8, value.obligation_cluster_id.bytes) },
        } },
        .implementation_operation => |value| .{ .implementation_operation = .{
            .task_definition_state_id = .{ .bytes = try allocator.dupe(u8, value.task_definition_state_id.bytes) },
            .task_id = .{ .bytes = try allocator.dupe(u8, value.task_id.bytes) },
            .operation_intent_id = .{ .bytes = try allocator.dupe(u8, value.operation_intent_id.bytes) },
        } },
    };
}

fn cloneModelOperation(
    allocator: std.mem.Allocator,
    value: provider_binding.WorkflowModelOperationId,
) std.mem.Allocator.Error!provider_binding.WorkflowModelOperationId {
    return .{
        .workflow_id = .{ .bytes = try allocator.dupe(u8, value.workflow_id.bytes) },
        .workflow_version = value.workflow_version,
        .workflow_step_id = .{ .bytes = try allocator.dupe(u8, value.workflow_step_id.bytes) },
    };
}

fn clonePurpose(
    allocator: std.mem.Allocator,
    current: *const LedgerStorage,
    purpose: RequestPurposeBinding,
) Error!RequestPurposeBinding {
    return switch (purpose) {
        .initial_generation => .initial_generation,
        .atomic_repair => |id| .{ .atomic_repair = .{ .bytes = try allocator.dupe(u8, id.bytes) } },
        .semantic_review => |id| .{ .semantic_review = .{ .bytes = try allocator.dupe(u8, id.bytes) } },
        .clarification_resolution => |binding| .{ .clarification_resolution = .{
            .clarification_state_id = .{ .bytes = try allocator.dupe(u8, binding.clarification_state_id.bytes) },
            .clarification_state_revision = binding.clarification_state_revision,
            .clarification_id = .{ .bytes = try allocator.dupe(u8, binding.clarification_id.bytes) },
        } },
        .context_followup => |binding| .{ .context_followup = .{
            .parent_model_request_id = resolveRequest(current, binding.parent_model_request_id) orelse {
                return error.InvalidRequestPurposeBinding;
            },
            .validated_context_request_ordinal = binding.validated_context_request_ordinal,
        } },
    };
}

fn contentOwnerEql(left: ContentUnitOwnerId, right: ContentUnitOwnerId) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .reference_chunk => |value| authorityIdEql(value.reference_state_id.bytes, right.reference_chunk.reference_state_id.bytes) and
            authorityIdEql(value.chunk_id.bytes, right.reference_chunk.chunk_id.bytes),
        .reference_global => |value| authorityIdEql(value.reference_state_id.bytes, right.reference_global.reference_state_id.bytes) and
            authorityIdEql(value.unit_slot_id.bytes, right.reference_global.unit_slot_id.bytes),
        .specification_unit => |value| authorityIdEql(value.reference_state_id.bytes, right.specification_unit.reference_state_id.bytes) and
            authorityIdEql(value.feature_request_id.bytes, right.specification_unit.feature_request_id.bytes) and
            authorityIdEql(value.unit_slot_id.bytes, right.specification_unit.unit_slot_id.bytes),
        .plan_unit => |value| authorityIdEql(value.plan_input_authority_state_id.bytes, right.plan_unit.plan_input_authority_state_id.bytes) and
            authorityIdEql(value.unit_slot_id.bytes, right.plan_unit.unit_slot_id.bytes),
        .task_cluster => |value| authorityIdEql(value.plan_state_id.bytes, right.task_cluster.plan_state_id.bytes) and
            authorityIdEql(value.obligation_cluster_id.bytes, right.task_cluster.obligation_cluster_id.bytes),
        .implementation_operation => |value| authorityIdEql(value.task_definition_state_id.bytes, right.implementation_operation.task_definition_state_id.bytes) and
            authorityIdEql(value.task_id.bytes, right.implementation_operation.task_id.bytes) and
            authorityIdEql(value.operation_intent_id.bytes, right.implementation_operation.operation_intent_id.bytes),
    };
}

fn modelRequestIdEql(left: *const ModelRequestId, right: *const ModelRequestId, remaining_depth: usize) bool {
    if (left == right) return true;
    if (remaining_depth == 0) return false;
    return authorityIdEql(left.stage_run_epoch_id.bytes, right.stage_run_epoch_id.bytes) and
        unitOwnerEql(left.immutable_unit_owner_id, right.immutable_unit_owner_id) and
        left.model_operation_id.eql(right.model_operation_id) and
        left.request_ordinal.value == right.request_ordinal.value and
        purposeEqlBounded(left.purpose, right.purpose, remaining_depth - 1);
}

fn purposeEqlBounded(left: RequestPurposeBinding, right: RequestPurposeBinding, remaining_depth: usize) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .initial_generation => true,
        .atomic_repair => |id| authorityIdEql(id.bytes, right.atomic_repair.bytes),
        .semantic_review => |id| authorityIdEql(id.bytes, right.semantic_review.bytes),
        .clarification_resolution => |binding| authorityIdEql(
            binding.clarification_state_id.bytes,
            right.clarification_resolution.clarification_state_id.bytes,
        ) and binding.clarification_state_revision == right.clarification_resolution.clarification_state_revision and
            authorityIdEql(binding.clarification_id.bytes, right.clarification_resolution.clarification_id.bytes),
        .context_followup => |binding| modelRequestIdEql(
            binding.parent_model_request_id,
            right.context_followup.parent_model_request_id,
            remaining_depth,
        ) and
            binding.validated_context_request_ordinal.value == right.context_followup.validated_context_request_ordinal.value,
    };
}

fn validateAuthorityId(bytes: []const u8, invalid_error: ValidationError) ValidationError!void {
    if (bytes.len == 0 or bytes.len > 128) return invalid_error;
    for (bytes) |byte| if (byte < 0x21 or byte > 0x7e) return invalid_error;
}

fn authorityIdEql(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}

fn retainOwner(owner: *Owner) ValidationError!void {
    const value = ownerStorage(owner);
    std.debug.assert(value.reference_count > 0);
    value.reference_count = std.math.add(usize, value.reference_count, 1) catch {
        return error.ModelRequestOwnerReferenceExhausted;
    };
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ledgerStorage(value: *const ModelRequestIdentityLedger) *const LedgerStorage {
    return @ptrCast(@alignCast(value));
}
