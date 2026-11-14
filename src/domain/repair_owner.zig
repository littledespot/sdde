//! The owners of the four generic repair operations (ADR 0033). One closed enum names every
//! repairable owner of the Specify workflow; the generic operation a step uses selects the
//! contract variant and the owner's rules from the step's `owner` parameter. It is a distinct type
//! from `ImmutableUnitOwnerId` and `atomic_repair.Merge.owner`, which name the repaired unit's
//! owner inside one repair, not the step's route. `owner` selects rules and a contract variant only:
//! it grants no policy, scope or defect identity (ADR 0033, ADR 0023).
const std = @import("std");
const pipeline = @import("pipeline.zig");
const retry = @import("workflow_retry.zig");

/// The one closed enumeration parameter that selects a repair operation's variant.
pub const selector = "owner";

/// Why a generic repair operation cannot run for its step (ADR 0033). An absent required key stays the
/// data-flow error it is; these name what the owner bindings find wrong once the data is there.
pub const Error = error{
    /// The compiled `owner` disagrees with the native owner the authorization, diagnostic or context
    /// determines, or the owner has no variant of the operation (ADR 0033: terminal, never routable).
    RepairOwnerMismatch,
    /// The step carries no `owner` selector, or its value names no owner.
    RepairOwnerUnresolved,
    /// The authorization carries no repair permit.
    RepairPermitMissing,
    /// The repaired candidate records no merge to continue from.
    LastRepairMissing,
    /// The retained state is not in the state this repair operation consumes.
    RepairStateMismatch,
    /// The rejected state holds no candidate to repair.
    RepairCandidateMissing,
};

/// The retry accounting's view of the merge a repair step just made. A missing record and a record
/// without its permit each fail the step with their own cause, never with a generic failure.
pub fn mergeTransition(last: ?@import("atomic_repair.zig").Merge, validation: retry.ValidationMode) error{ LastRepairMissing, InvalidAtomicRepair }!retry.Transition {
    return (last orelse return error.LastRepairMissing).transition(validation);
}

/// `mergeTransition` for a merge that validates in the same step and reports its result.
pub fn validatedMergeTransition(last: ?@import("atomic_repair.zig").Merge, result: retry.Validation) error{ LastRepairMissing, InvalidAtomicRepair }!retry.Transition {
    return (last orelse return error.LastRepairMissing).validatedTransition(result);
}

/// The data one owner's step reads, publishes, replaces and invalidates, stated once, beside the
/// owner's rules (the owner's binding declares it, and its variant of the generic operation is built
/// from it). No owner's repair step has a side effect.
pub const Effects = struct {
    requires: []const pipeline.DataKey,
    optional: []const pipeline.DataKey = &.{},
    produces: []const pipeline.DataKey = &.{},
    replaces: []const pipeline.DataKey = &.{},
    invalidates: []const pipeline.DataKey = &.{},
};

/// The generic repair operations: the four registered operations that replace the per-owner ones.
pub const Operation = enum {
    authorize,
    build_input,
    parse,
    merge,

    /// The registered operation ID.
    pub fn id(self: Operation) []const u8 {
        return switch (self) {
            .authorize => "authorize-repair",
            .build_input => "build-repair-input",
            .parse => "parse-repair",
            .merge => "merge-repair",
        };
    }
};

pub const RepairOwner = enum {
    reference_text,
    reference_extraction,
    reference_summary,
    reference_dispositions,
    reference_signals,
    reference_conflicts,
    reference_reconciliation,
    source_omission,
    source_omission_extraction,
    source_omission_reconciliation,
    specification_unit,
    specification_support,
    specification_coverage,

    /// The stable dashed value a workflow names in its `owner` parameter.
    pub fn id(self: RepairOwner) []const u8 {
        return switch (self) {
            inline else => |member| comptime dashed(@tagName(member)),
        };
    }

    /// The owner a step's `owner` value names, or null for a value outside the closed set.
    pub fn parse(value: []const u8) ?RepairOwner {
        inline for (@typeInfo(RepairOwner).@"enum".fields) |field| {
            const member: RepairOwner = @enumFromInt(field.value);
            if (std.mem.eql(u8, value, comptime dashed(field.name))) return member;
        }
        return null;
    }

    /// Whether the owner has a variant of `operation`: only the operations an owner uses today
    /// (ADR 0033's table). A step that names an owner without one rejects at compilation.
    pub fn serves(self: RepairOwner, operation: Operation) bool {
        return switch (operation) {
            .authorize => switch (self) {
                .reference_text, .reference_extraction, .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission, .specification_unit, .specification_support, .specification_coverage => true,
                .reference_reconciliation, .source_omission_extraction, .source_omission_reconciliation => false,
            },
            .build_input, .parse => switch (self) {
                .reference_text, .reference_extraction, .reference_reconciliation, .source_omission, .specification_unit, .specification_support => true,
                .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission_extraction, .source_omission_reconciliation, .specification_coverage => false,
            },
            .merge => switch (self) {
                .reference_text, .reference_extraction, .reference_reconciliation, .source_omission_extraction, .source_omission_reconciliation, .specification_unit, .specification_support => true,
                .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission, .specification_coverage => false,
            },
        };
    }
};

/// What the 13 owners' merges accept as their `retry-limit` (ADR 0033 derived choice 6, user decision
/// DE4 6, 13 November 2026): each owner's maximum is the value its YAML step declares today. Null
/// means the owner's merge forbids a `retry-limit` (the text and extraction merges, as today), and an
/// owner without a merge has none to bound. The native key population stays the one in
/// `workflow_retry`; this only bounds the allowance a workflow may declare.
pub fn retryMaximum(owner: RepairOwner) ?u32 {
    return switch (owner) {
        .reference_reconciliation => 128,
        .source_omission_extraction, .source_omission_reconciliation => 1,
        .specification_unit => 64,
        .specification_support => 2,
        .reference_text, .reference_extraction, .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission, .specification_coverage => null,
    };
}

/// An outcome the operation's variant of this owner never declares because the owner cannot reach it
/// (DE4 7): admission binds one disposition to every assigned claim (ADR 0046), so the dispositions
/// authorizer never hands a replacement straight to merge, as `more` would.
pub fn unreachableOutcome(operation: Operation, owner: RepairOwner) ?@import("workflow.zig").OutcomeTag {
    return switch (operation) {
        .authorize => switch (owner) {
            .reference_dispositions => .more,
            .reference_text, .reference_extraction, .reference_summary, .reference_signals, .reference_conflicts, .reference_reconciliation, .source_omission, .source_omission_extraction, .source_omission_reconciliation, .specification_unit, .specification_support, .specification_coverage => null,
        },
        .build_input, .parse, .merge => null,
    };
}

/// The dashed ID of an owner's tag name: `reference_text` is `reference-text`.
pub fn dashed(comptime name: []const u8) []const u8 {
    @setEvalBranchQuota(10_000);
    const result = comptime blk: {
        var bytes: [name.len]u8 = undefined;
        for (name, 0..) |byte, index| bytes[index] = if (byte == '_') '-' else byte;
        const final = bytes;
        break :blk final;
    };
    return &result;
}

fn servedCount(comptime operation: Operation) usize {
    var count: usize = 0;
    for (@typeInfo(RepairOwner).@"enum".fields) |field| {
        const member: RepairOwner = @enumFromInt(field.value);
        if (member.serves(operation)) count += 1;
    }
    return count;
}

/// The owners that have a variant of `operation`, in declaration order.
pub fn served(comptime operation: Operation) []const RepairOwner {
    const result = comptime blk: {
        var members: [servedCount(operation)]RepairOwner = undefined;
        var index: usize = 0;
        for (@typeInfo(RepairOwner).@"enum".fields) |field| {
            const member: RepairOwner = @enumFromInt(field.value);
            if (member.serves(operation)) {
                members[index] = member;
                index += 1;
            }
        }
        const final = members;
        break :blk final;
    };
    return &result;
}

/// The values of the `owner` parameter a generic operation allows: exactly the owners it serves.
pub fn values(comptime operation: Operation) []const []const u8 {
    @setEvalBranchQuota(100_000);
    const result = comptime blk: {
        var names: [servedCount(operation)][]const u8 = undefined;
        for (served(operation), 0..) |member, index| names[index] = member.id();
        const final = names;
        break :blk final;
    };
    return &result;
}
