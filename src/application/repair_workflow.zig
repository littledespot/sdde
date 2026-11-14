//! The four generic repair operations (ADR 0033): `authorize-repair`, `build-repair-input`,
//! `parse-repair` and `merge-repair`. Each is one registered contract made of closed variants, one
//! per owner that uses the operation today, selected per step by the required `owner` parameter
//! (ADR 0030 "Contract variants"). A variant is built from its owner's own binding declarations
//! (its data effects, outcomes, association, role and retry rule), so each of them exists once, in
//! the owner's binding.
//!
//! The owner's rules stay in its own binding file; this file only selects them. Each operation holds
//! its owners' bindings, and `invoke` selects one through one exhaustive `switch` over the closed
//! `RepairOwner` enum, with no default branch, callback table or dispatcher. `owner` selects a
//! variant and a binding and grants no policy, scope or defect identity: the owner's binding reads
//! only the owner's own keys, and checks them against the native facts they carry, so a step whose
//! `owner` disagrees with the data it runs on fails as a terminal runner rejection, never as a YAML
//! outcome. The model call stays a separate `request-model` step; release and routing stay YAML.
const std = @import("std");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const operation = @import("../domain/workflow_operation.zig");
const repair_owner = @import("../domain/repair_owner.zig");
const workflow = @import("../domain/workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const extraction_repair = @import("reference_extraction_repair_workflow.zig");
const reconciliation_repair = @import("reference_reconciliation_repair_workflow.zig");
const source_omission = @import("source_omission_repair_workflow.zig");
const specification_repair = @import("specification_repair_workflow.zig");
const support_repair = @import("specification_support_repair_workflow.zig");
const coverage_repair = @import("specification_coverage_repair_workflow.zig");
const text_repair = @import("reference_text_repair_workflow.zig");

const Operation = repair_owner.Operation;
const RepairOwner = repair_owner.RepairOwner;

/// The one closed enumeration parameter that selects a variant.
pub const selector = repair_owner.selector;

/// The binding of `owner`'s variant of `op`: the owner's own binding type, or `void` for an owner
/// that has no variant of the operation. Every owner is named in every operation's switch, so a
/// new owner is a compile error here until each operation says what it does with it.
pub fn OwnerBinding(comptime op: Operation, comptime owner: RepairOwner) type {
    return switch (op) {
        .authorize => switch (owner) {
            .reference_text => text_repair.Authorize,
            .reference_extraction => extraction_repair.Authorize,
            .reference_summary => reconciliation_repair.Authorize(.summary),
            .reference_dispositions => reconciliation_repair.Authorize(.dispositions),
            .reference_signals => reconciliation_repair.Authorize(.signals),
            .reference_conflicts => reconciliation_repair.Authorize(.conflicts),
            .source_omission => source_omission.Authorize,
            .specification_unit => specification_repair.Authorize,
            .specification_support => support_repair.Authorize,
            .specification_coverage => coverage_repair.Authorize,
            .reference_reconciliation, .source_omission_extraction, .source_omission_reconciliation => void,
        },
        .build_input => switch (owner) {
            .reference_text => text_repair.BuildInput,
            .reference_extraction => extraction_repair.BuildInput,
            .reference_reconciliation => reconciliation_repair.BuildInput,
            .source_omission => source_omission.BuildInput,
            .specification_unit => specification_repair.BuildInput,
            .specification_support => support_repair.BuildInput,
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission_extraction, .source_omission_reconciliation, .specification_coverage => void,
        },
        .parse => switch (owner) {
            .reference_text => text_repair.Parse,
            .reference_extraction => extraction_repair.Parse,
            .reference_reconciliation => reconciliation_repair.Parse,
            .source_omission => source_omission.Parse,
            .specification_unit => specification_repair.Parse,
            .specification_support => support_repair.Parse,
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission_extraction, .source_omission_reconciliation, .specification_coverage => void,
        },
        .merge => switch (owner) {
            .reference_text => text_repair.Merge,
            .reference_extraction => extraction_repair.Merge,
            .reference_reconciliation => reconciliation_repair.Merge,
            .source_omission_extraction => source_omission.Merge(.extraction),
            .source_omission_reconciliation => source_omission.Merge(.reconciliation),
            .specification_unit => specification_repair.Merge,
            .specification_support => support_repair.Merge,
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission, .specification_coverage => void,
        },
    };
}

fn selectorDescriptor(comptime op: Operation) operation.ParameterDescriptor {
    return .{ .id = selector, .kind = .enumeration, .required = true, .workflow_definition_safe = true, .allowed_values = repair_owner.values(op) };
}

fn withoutOutcome(comptime outcomes: []const workflow.OutcomeTag, comptime dropped: ?workflow.OutcomeTag) []const workflow.OutcomeTag {
    const result = comptime blk: {
        var list: [outcomes.len]workflow.OutcomeTag = undefined;
        var count: usize = 0;
        for (outcomes) |outcome| {
            if (dropped != null and outcome == dropped.?) continue;
            list[count] = outcome;
            count += 1;
        }
        const final: [count]workflow.OutcomeTag = list[0..count].*;
        break :blk final;
    };
    return &result;
}

/// The variant of `owner`'s binding `T`: a complete contract built from the owner's own declarations,
/// with the selector first among its parameters and the owner's retry maximum
/// (`repair_owner.retryMaximum`) where its merge takes a `retry-limit`.
fn variantOf(comptime op: Operation, comptime owner: RepairOwner, comptime T: type) operation.Variant {
    const effects: repair_owner.Effects = T.effects;
    const declared: []const workflow.OutcomeTag = if (@hasDecl(T, "outcomes")) &T.outcomes else &.{ .ok, .failed };
    const maximum: ?u32 = if (@hasDecl(T, "retry_limit"))
        (repair_owner.retryMaximum(owner) orelse @compileError("a merge that takes a retry-limit states its owner's maximum"))
    else
        null;
    const parameters = comptime blk: {
        const own = if (@hasDecl(T, "parameters")) T.parameters else [0]operation.ParameterDescriptor{};
        var list: [1 + own.len]operation.ParameterDescriptor = undefined;
        list[0] = selectorDescriptor(op);
        for (own, 0..) |descriptor, index| {
            list[1 + index] = descriptor;
            if (std.mem.eql(u8, descriptor.id, "retry-limit")) list[1 + index].integer_max = maximum.?;
        }
        const final = list;
        break :blk final;
    };
    return .{
        .value = owner.id(),
        .parameters = &parameters,
        .requires = effects.requires,
        .optional = effects.optional,
        .produces = effects.produces,
        .replaces = effects.replaces,
        .invalidates = effects.invalidates,
        .outcomes = withoutOutcome(declared, repair_owner.unreachableOutcome(op, owner)),
        .side_effect = .none,
        .runner_accounting = .none,
        .repair_role = if (@hasDecl(T, "repair_role")) T.repair_role else .none,
        .outcome_association = if (@hasDecl(T, "outcome_association")) T.outcome_association else .independent,
        .gates = if (@hasDecl(T, "gates")) &T.gates else &.{},
        .retry_limit = if (maximum) |limit| .{ .maximum = limit, .scope = T.retry_limit.scope } else null,
        .iteration = null,
    };
}

/// The variants of `op`, one per owner it serves, in the owners' declaration order.
pub fn variantsOf(comptime op: Operation) [repair_owner.served(op).len]operation.Variant {
    @setEvalBranchQuota(100_000);
    var list: [repair_owner.served(op).len]operation.Variant = undefined;
    inline for (repair_owner.served(op), 0..) |owner, index| list[index] = variantOf(op, owner, OwnerBinding(op, owner));
    return list;
}

fn shell(comptime op: Operation, comptime list: []const operation.Variant) operation.Contract {
    return .{ .id = op.id(), .kind = .step, .outcomes = &.{}, .side_effect = .none, .selector = selector, .variants = list };
}

/// The owner a step's `owner` parameter names. The compiler has already admitted the value and
/// selected the variant, so a missing or unknown value here is a tampered step, not a workflow
/// outcome.
fn ownerOf(comptime contract: operation.Contract, input: operations.Input) operations.Error!RepairOwner {
    const step = switch (input) {
        .step => |value| value.step,
        .invocation => return error.OperationWrongKind,
    };
    const value = compilation.selectorValue(contract, step.parameters) orelse return error.RepairOwnerUnresolved;
    return RepairOwner.parse(value) orelse error.RepairOwnerUnresolved;
}

pub const AuthorizeRepair = struct {
    const variants = variantsOf(.authorize);
    pub const contract = shell(.authorize, &variants);
    reference_text: text_repair.Authorize,
    reference_extraction: extraction_repair.Authorize,
    reference_summary: reconciliation_repair.Authorize(.summary),
    reference_dispositions: reconciliation_repair.Authorize(.dispositions),
    reference_signals: reconciliation_repair.Authorize(.signals),
    reference_conflicts: reconciliation_repair.Authorize(.conflicts),
    source_omission: source_omission.Authorize,
    specification_unit: specification_repair.Authorize,
    specification_support: support_repair.Authorize,
    specification_coverage: coverage_repair.Authorize,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        return switch (try ownerOf(contract, input)) {
            .reference_text => text_repair.Authorize.invoke(&self.reference_text, input),
            .reference_extraction => extraction_repair.Authorize.invoke(&self.reference_extraction, input),
            .reference_summary => reconciliation_repair.Authorize(.summary).invoke(&self.reference_summary, input),
            .reference_dispositions => reconciliation_repair.Authorize(.dispositions).invoke(&self.reference_dispositions, input),
            .reference_signals => reconciliation_repair.Authorize(.signals).invoke(&self.reference_signals, input),
            .reference_conflicts => reconciliation_repair.Authorize(.conflicts).invoke(&self.reference_conflicts, input),
            .source_omission => source_omission.Authorize.invoke(&self.source_omission, input),
            .specification_unit => specification_repair.Authorize.invoke(&self.specification_unit, input),
            .specification_support => support_repair.Authorize.invoke(&self.specification_support, input),
            .specification_coverage => coverage_repair.Authorize.invoke(&self.specification_coverage, input),
            .reference_reconciliation, .source_omission_extraction, .source_omission_reconciliation => error.RepairOwnerMismatch,
        };
    }
};

pub const BuildRepairInput = struct {
    const variants = variantsOf(.build_input);
    pub const contract = shell(.build_input, &variants);
    reference_text: text_repair.BuildInput,
    reference_extraction: extraction_repair.BuildInput,
    reference_reconciliation: reconciliation_repair.BuildInput,
    source_omission: source_omission.BuildInput,
    specification_unit: specification_repair.BuildInput,
    specification_support: support_repair.BuildInput,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        return switch (try ownerOf(contract, input)) {
            .reference_text => text_repair.BuildInput.invoke(&self.reference_text, input),
            .reference_extraction => extraction_repair.BuildInput.invoke(&self.reference_extraction, input),
            .reference_reconciliation => reconciliation_repair.BuildInput.invoke(&self.reference_reconciliation, input),
            .source_omission => source_omission.BuildInput.invoke(&self.source_omission, input),
            .specification_unit => specification_repair.BuildInput.invoke(&self.specification_unit, input),
            .specification_support => support_repair.BuildInput.invoke(&self.specification_support, input),
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission_extraction, .source_omission_reconciliation, .specification_coverage => error.RepairOwnerMismatch,
        };
    }
};

pub const ParseRepair = struct {
    const variants = variantsOf(.parse);
    pub const contract = shell(.parse, &variants);
    reference_text: text_repair.Parse,
    reference_extraction: extraction_repair.Parse,
    reference_reconciliation: reconciliation_repair.Parse,
    source_omission: source_omission.Parse,
    specification_unit: specification_repair.Parse,
    specification_support: support_repair.Parse,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        return switch (try ownerOf(contract, input)) {
            .reference_text => text_repair.Parse.invoke(&self.reference_text, input),
            .reference_extraction => extraction_repair.Parse.invoke(&self.reference_extraction, input),
            .reference_reconciliation => reconciliation_repair.Parse.invoke(&self.reference_reconciliation, input),
            .source_omission => source_omission.Parse.invoke(&self.source_omission, input),
            .specification_unit => specification_repair.Parse.invoke(&self.specification_unit, input),
            .specification_support => support_repair.Parse.invoke(&self.specification_support, input),
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission_extraction, .source_omission_reconciliation, .specification_coverage => error.RepairOwnerMismatch,
        };
    }
};

pub const MergeRepair = struct {
    const variants = variantsOf(.merge);
    pub const contract = shell(.merge, &variants);
    reference_text: text_repair.Merge,
    reference_extraction: extraction_repair.Merge,
    reference_reconciliation: reconciliation_repair.Merge,
    source_omission_extraction: source_omission.Merge(.extraction),
    source_omission_reconciliation: source_omission.Merge(.reconciliation),
    specification_unit: specification_repair.Merge,
    specification_support: support_repair.Merge,

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        return switch (try ownerOf(contract, input)) {
            .reference_text => text_repair.Merge.invoke(&self.reference_text, input),
            .reference_extraction => extraction_repair.Merge.invoke(&self.reference_extraction, input),
            .reference_reconciliation => reconciliation_repair.Merge.invoke(&self.reference_reconciliation, input),
            .source_omission_extraction => source_omission.Merge(.extraction).invoke(&self.source_omission_extraction, input),
            .source_omission_reconciliation => source_omission.Merge(.reconciliation).invoke(&self.source_omission_reconciliation, input),
            .specification_unit => specification_repair.Merge.invoke(&self.specification_unit, input),
            .specification_support => support_repair.Merge.invoke(&self.specification_support, input),
            .reference_summary, .reference_dispositions, .reference_signals, .reference_conflicts, .source_omission, .specification_coverage => error.RepairOwnerMismatch,
        };
    }
};
