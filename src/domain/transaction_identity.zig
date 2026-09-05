const std = @import("std");
const roots = @import("bootstrap_roots.zig");
const feature = @import("feature_identity.zig");
const artifacts = @import("workflow_artifact_registry.zig");

pub const Kind = enum {
    feature_activation,
    bootstrap_authority_refresh,
    state_identity_reservation,
    state_identity_retirement,
    specification_acknowledgement_id_retirement,
    clarification_pause,
    clarification_response,
    clarification_authority_resolution,
    specify_completion,
    plan_input_authority,
    plan_candidate,
    tasks_candidate,
    reference_revision,
    rework_invalidation,
    final_validation_failed,
    localized_task_remediation,
    implementation_reconciliation,
    implementation_completion,
    review_decision,
    task_checkpoint,
    manual_verification,
    task_success,
    task_outcome,
};

pub const FeatureOwner = struct {
    feature_id: feature.FeatureId,
    workflow_artifact_registry_state_id: artifacts.StateId,
};

/// Borrowed engine-owned identity, not a path, lock, or write capability.
pub const StorageOwner = union(enum) {
    project: roots.BootstrapRootRegistryId,
    feature: FeatureOwner,

    pub fn isValid(self: StorageOwner) bool {
        return switch (self) {
            .project => |id| id.isValid(),
            .feature => |owner| owner.workflow_artifact_registry_state_id.isValid() and
                std.mem.eql(u8, owner.feature_id.bytes, owner.workflow_artifact_registry_state_id.feature_id.bytes),
        };
    }

    pub fn eql(self: StorageOwner, other: StorageOwner) bool {
        return switch (self) {
            .project => |id| switch (other) {
                .project => |other_id| id.eql(other_id),
                .feature => false,
            },
            .feature => |owner| switch (other) {
                .feature => |other_owner| std.mem.eql(u8, owner.feature_id.bytes, other_owner.feature_id.bytes) and
                    owner.workflow_artifact_registry_state_id.eql(other_owner.workflow_artifact_registry_state_id),
                .project => false,
            },
        };
    }

    pub fn allows(self: StorageOwner, kind: Kind) bool {
        return switch (self) {
            .project => kind == .feature_activation,
            .feature => kind != .feature_activation,
        };
    }
};

pub const Ordinal = struct {
    value: u64,

    pub fn init(value: u64) ?Ordinal {
        return if (value == 0) null else .{ .value = value };
    }
};

pub const TransactionId = struct {
    storage_owner: StorageOwner,
    ordinal: Ordinal,

    pub fn eql(self: TransactionId, other: TransactionId) bool {
        return self.ordinal.value == other.ordinal.value and self.storage_owner.eql(other.storage_owner);
    }
};
