//! The four generic repair operations (ADR 0033): one registered contract of closed variants per
//! operation, selected by the step's `owner`. These tests prove that every variant is the contract
//! of the per-owner operation it will replace (data effects, outcomes, association, role, retry rule),
//! that the compiler selects and checks one variant alone, that a step whose `owner` disagrees with
//! the data it runs on fails terminally, and that steps using one generic operation keep their own
//! retry authority. The owner's rules stay in its own binding; the removed per-owner operations'
//! behaviour is the behaviour of those bindings, which the generic operation selects by `owner`.
const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const operation = @import("domain/workflow_operation.zig");
const inventory = @import("domain/workflow_inventory.zig");
const definition_schema = @import("domain/workflow_definition_schema.zig");
const resource_binding = @import("domain/workflow_resource_binding.zig");
const graph_compilation = @import("domain/workflow_graph_compilation.zig");
const graph_validation = @import("domain/workflow_graph_validation.zig");
const repair_owner = @import("domain/repair_owner.zig");
const retry = @import("domain/workflow_retry.zig");
const result_schema_parser = @import("adapters/parsers/model_result_schemas.zig");
const parser_adapter = @import("adapters/parsers/workflow_definitions.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const bindings = @import("application/workflow_operation_binding.zig");
const startup = @import("application/startup_routine.zig");
const generic = @import("application/repair_workflow.zig");
const native = @import("composition/native_workflow_operations.zig");
const core = @import("composition/core_workflow_operations.zig");

const Operation = repair_owner.Operation;
const RepairOwner = repair_owner.RepairOwner;
const Registry = operations.Registry;
const Entry = operations.Entry;

fn GenericOf(comptime op: Operation) type {
    return switch (op) {
        .authorize => generic.AuthorizeRepair,
        .build_input => generic.BuildRepairInput,
        .parse => generic.ParseRepair,
        .merge => generic.MergeRepair,
    };
}

const operation_count = @typeInfo(Operation).@"enum".fields.len;

const Key = pipeline.DataKey;

/// The facts one per-owner repair operation stated before ADR 0033 replaced it: its data effects,
/// outcomes, role, outcome association, retry rule and parameters. The 29 rows were taken from the 29
/// registered per-owner operations on 14 November 2026, immediately before those operations and their
/// action files were deleted (E4 step 5), so the evidence that every variant states what its operation
/// stated survives the deletion. `outcomes` is the former operation's, with the dispositions
/// authorizer's `more`; the variant drops that one outcome (DE4 7). The retry row names the scope only:
/// the former maximum was `maxInt(u32)` for every merge, and each variant's maximum is the owner's
/// (DE4 6).
const Fact = struct {
    op: Operation,
    owner: RepairOwner,
    requires: []const Key,
    optional: []const Key,
    produces: []const Key,
    replaces: []const Key,
    invalidates: []const Key,
    outcomes: []const workflow.OutcomeTag,
    role: retry.Role,
    association: @import("domain/workflow_outcome_association.zig").Descriptor,
    retry: ?struct { scope: retry.Scope },
    parameters: []const struct { []const u8, operation.ParameterKind, bool, i64 },
    gates: usize,
    side_effect: pipeline.SideEffect,
};

const frozen = [_]Fact{
    .{ .op = .authorize, .owner = .reference_text, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .text_validated_reference_extraction }, .optional = &.{}, .produces = &.{.reference_text_repair_authorization}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .invalid, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_extraction, .evidence = .text_validated_reference_extraction, .result = .reference_text_repair_authorization } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .reference_extraction, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .validated_reference_selections }, .optional = &.{}, .produces = &.{.reference_extraction_repair_authorization}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .invalid, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .text_validated_reference_extraction, .evidence = .validated_reference_selections, .result = .reference_extraction_repair_authorization } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .reference_summary, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_summary }, .optional = &.{}, .produces = &.{.reference_reconciliation_repair}, .replaces = &.{}, .invalidates = &.{.validated_reference_summary}, .outcomes = &.{ .ok, .more, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .validated_reference_summary, .result = .reference_reconciliation_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .reference_dispositions, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_dispositions }, .optional = &.{}, .produces = &.{.reference_reconciliation_repair}, .replaces = &.{}, .invalidates = &.{.validated_reference_dispositions}, .outcomes = &.{ .ok, .more, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .validated_reference_dispositions, .result = .reference_reconciliation_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .reference_signals, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_signals }, .optional = &.{}, .produces = &.{.reference_reconciliation_repair}, .replaces = &.{}, .invalidates = &.{ .validated_reference_dispositions, .validated_reference_signals }, .outcomes = &.{ .ok, .more, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .validated_reference_signals, .result = .reference_reconciliation_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .reference_conflicts, .requires = &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_conflicts }, .optional = &.{}, .produces = &.{.reference_reconciliation_repair}, .replaces = &.{}, .invalidates = &.{ .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts }, .outcomes = &.{ .ok, .more, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .validated_reference_conflicts, .result = .reference_reconciliation_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .source_omission, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review }, .optional = &.{ .specification_generation_session, .identified_specification_content }, .produces = &.{.source_omission_repair}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .more, .invalid, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result, .result = .source_omission_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .specification_unit, .requires = &.{ .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_generation_session, .parsed_specification_unit, .validated_specification_unit, .packet_guidance }, .optional = &.{}, .produces = &.{.specification_repair_authorization}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .more, .invalid, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_specification_unit, .evidence = .validated_specification_unit, .result = .specification_repair_authorization } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .specification_support, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .packet_guidance }, .optional = &.{}, .produces = &.{.specification_support_repair}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .more, .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .authorize, .owner = .specification_coverage, .requires = &.{ .specification_generation_session, .accounted_reference_reconciliation, .identified_specification_content, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .specification_coverage }, .optional = &.{}, .produces = &.{.specification_coverage_repair}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .blocked, .failed }, .role = .authorize, .association = .{ .repair_authorize = .{ .kind = .candidate, .subject = .specification_generation_session, .evidence = .specification_coverage, .result = .specification_coverage_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .reference_text, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .structured_token_candidates, .reference_text_repair_authorization }, .optional = &.{}, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .reference_extraction, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .structured_token_candidates, .text_validated_reference_extraction, .reference_extraction_repair_authorization }, .optional = &.{}, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .reference_reconciliation, .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .packet_guidance }, .optional = &.{}, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .source_omission, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair, .packet_guidance }, .optional = &.{ .specification_generation_session, .identified_specification_content }, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .specification_unit, .requires = &.{ .specification_generation_session, .specification_repair_authorization, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .packet_guidance }, .optional = &.{}, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .build_input, .owner = .specification_support, .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair, .packet_guidance }, .optional = &.{}, .produces = &.{.model_input_packet}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .independent, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .reference_text, .requires = &.{ .reference_text_repair_authorization, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .optional = &.{}, .produces = &.{.reference_text_repair_result}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .invalid, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .candidate, .subject = .reference_text_repair_authorization, .evidence = .reference_text_repair_authorization, .result = .reference_text_repair_result } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .reference_extraction, .requires = &.{ .reference_extraction_repair_authorization, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .optional = &.{}, .produces = &.{.reference_extraction_repair_result}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .invalid, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .candidate, .subject = .reference_extraction_repair_authorization, .evidence = .reference_extraction_repair_authorization, .result = .reference_extraction_repair_result } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .reference_reconciliation, .requires = &.{ .reference_reconciliation_repair, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.reference_reconciliation_repair}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .candidate, .subject = .reference_reconciliation_repair, .evidence = .reference_reconciliation_repair, .result = .reference_reconciliation_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .source_omission, .requires = &.{ .source_omission_repair, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.source_omission_repair}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .authority, .subject = .source_omission_repair, .evidence = .source_omission_repair, .result = .source_omission_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .specification_unit, .requires = &.{ .specification_repair_authorization, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.specification_repair_authorization}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .candidate, .subject = .specification_repair_authorization, .evidence = .specification_repair_authorization, .result = .specification_repair_authorization } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .parse, .owner = .specification_support, .requires = &.{ .specification_support_repair, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.specification_support_repair}, .invalidates = &.{}, .outcomes = &.{ .ok, .failed }, .role = .none, .association = .{ .preserve = .{ .kind = .candidate, .subject = .specification_support_repair, .evidence = .specification_support_repair, .result = .specification_support_repair } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .reference_text, .requires = &.{ .valid_toolchain, .citable_reference_inputs, .reference_passive_literals, .parsed_reference_extraction, .reference_text_repair_authorization, .reference_text_repair_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.parsed_reference_extraction}, .invalidates = &.{ .text_validated_reference_extraction, .reference_text_repair_authorization, .reference_text_repair_result }, .outcomes = &.{ .ok, .invalid, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .parsed_reference_extraction, .evidence = .reference_text_repair_authorization, .result = .parsed_reference_extraction } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .reference_extraction, .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .optional = &.{}, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &.{ .validated_reference_selections, .reference_extraction_repair_authorization, .reference_extraction_repair_result }, .outcomes = &.{ .ok, .invalid, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .text_validated_reference_extraction, .evidence = .reference_extraction_repair_authorization, .result = .text_validated_reference_extraction } }, .retry = null, .parameters = &.{}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .reference_reconciliation, .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain }, .optional = &.{}, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &.{.reference_reconciliation_repair}, .outcomes = &.{ .ok, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .reference_reconciliation_repair, .result = .parsed_reference_reconciliation } }, .retry = .{ .scope = .repair }, .parameters = &.{.{ "retry-limit", .integer, true, 0 }}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .source_omission_extraction, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair, .structured_token_candidates, .text_validated_reference_extraction }, .optional = &.{ .specification_generation_session, .identified_specification_content }, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &.{ .validated_reference_selections, .preserved_token_identities, .prepared_reference_claims, .validated_reference_claims, .reference_claim_identities, .reference_extraction_ledger, .accounted_reference_extraction, .reference_reconciliation_items, .reference_reconciliation_layout, .reference_reconciliation_plan, .reference_reconciliation_progress, .reference_reconciliation_input, .parsed_reference_reconciliation, .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair }, .outcomes = &.{ .ok, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .text_validated_reference_extraction, .evidence = .source_omission_repair, .result = .text_validated_reference_extraction } }, .retry = .{ .scope = .repair }, .parameters = &.{.{ "retry-limit", .integer, true, 0 }}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .source_omission_reconciliation, .requires = &.{ .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair, .parsed_reference_reconciliation }, .optional = &.{ .specification_generation_session, .identified_specification_content }, .produces = &.{}, .replaces = &.{.parsed_reference_reconciliation}, .invalidates = &.{ .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts, .reference_reconciliation_identities, .reference_reconciliation_records, .accounted_reference_reconciliation, .specification_support_review, .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate, .source_omission_repair }, .outcomes = &.{ .ok, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .source_omission_repair, .result = .parsed_reference_reconciliation } }, .retry = .{ .scope = .repair }, .parameters = &.{.{ "retry-limit", .integer, true, 0 }}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .specification_unit, .requires = &.{ .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_generation_session, .parsed_specification_unit, .specification_repair_authorization }, .optional = &.{}, .produces = &.{}, .replaces = &.{.parsed_specification_unit}, .invalidates = &.{ .validated_specification_unit, .specification_repair_authorization }, .outcomes = &.{ .ok, .failed }, .role = .merge, .association = .{ .repair_merge = .{ .kind = .candidate, .subject = .parsed_specification_unit, .evidence = .specification_repair_authorization, .result = .parsed_specification_unit } }, .retry = .{ .scope = .repair }, .parameters = &.{.{ "retry-limit", .integer, true, 0 }}, .gates = 0, .side_effect = .none },
    .{ .op = .merge, .owner = .specification_support, .requires = &.{ .required_authority_inputs, .specification_support_review, .model_request_identity_ledger, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair, .packet_guidance }, .optional = &.{}, .produces = &.{}, .replaces = &.{.specification_support_review}, .invalidates = &.{.specification_support_repair}, .outcomes = &.{ .ok, .more, .invalid, .failed }, .role = .merge_validate, .association = .{ .repair_validate = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_repair, .result = .specification_support_review } }, .retry = .{ .scope = .repair }, .parameters = &.{.{ "retry-limit", .integer, true, 0 }}, .gates = 0, .side_effect = .none },
};

fn factOf(op: Operation, owner: RepairOwner) !Fact {
    var found: ?Fact = null;
    for (frozen) |fact| if (fact.op == op and fact.owner == owner) {
        try std.testing.expect(found == null);
        found = fact;
    };
    return found orelse error.MissingFrozenFact;
}

test "the owners are a closed set of 13 with 29 variants over four operations" {
    try std.testing.expectEqual(@as(usize, 13), @typeInfo(RepairOwner).@"enum".fields.len);
    try std.testing.expectEqual(@as(usize, 10), repair_owner.served(.authorize).len);
    try std.testing.expectEqual(@as(usize, 6), repair_owner.served(.build_input).len);
    try std.testing.expectEqual(@as(usize, 6), repair_owner.served(.parse).len);
    try std.testing.expectEqual(@as(usize, 7), repair_owner.served(.merge).len);
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        const op: Operation = @enumFromInt(field.value);
        // The selector's allowed values are derived from the owners the operation serves, in order.
        try std.testing.expectEqual(repair_owner.served(op).len, repair_owner.values(op).len);
        inline for (comptime repair_owner.served(op), 0..) |owner, index| {
            try std.testing.expectEqualStrings(owner.id(), repair_owner.values(op)[index]);
            try std.testing.expect(owner.serves(op));
        }
        // Each operation registers exactly one contract with one variant per served owner.
        try std.testing.expectEqual(repair_owner.served(op).len, GenericOf(op).contract.variants.len);
        try std.testing.expectEqualStrings(op.id(), GenericOf(op).contract.id);
        try std.testing.expectEqualStrings(generic.selector, GenericOf(op).contract.selector.?);
    }
    // Every owner is used by at least one operation, and the ids are dashed, unique and parse back.
    inline for (@typeInfo(RepairOwner).@"enum".fields) |field| {
        const owner: RepairOwner = @enumFromInt(field.value);
        var used: usize = 0;
        inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
            if (owner.serves(@enumFromInt(op_field.value))) used += 1;
        }
        try std.testing.expect(used >= 1);
        try std.testing.expectEqual(@as(?RepairOwner, owner), RepairOwner.parse(owner.id()));
        try std.testing.expect(std.mem.indexOfScalar(u8, owner.id(), '_') == null);
        try std.testing.expect(workflow.WorkflowParameterId.parse(owner.id()) != null);
    }
    try std.testing.expect(RepairOwner.parse("") == null);
    try std.testing.expect(RepairOwner.parse("reference_text") == null);
    try std.testing.expect(RepairOwner.parse("Reference-Text") == null);
    try std.testing.expect(RepairOwner.parse("reference-text ") == null);
    try std.testing.expect(RepairOwner.parse("specification") == null);
}

test "every variant states what the per-owner operation it replaced stated, but for the named differences" {
    var variant_count: usize = 0;
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        const shell = GenericOf(op).contract;
        try std.testing.expect(shell.isShell());
        inline for (comptime repair_owner.served(op)) |owner| {
            const fact = try factOf(op, owner);
            const variant = shell.resolve(owner.id()).?;
            variant_count += 1;
            try std.testing.expectEqualStrings(op.id(), variant.id);
            try std.testing.expectEqual(operation.Kind.step, variant.kind);
            // The data effects, side effect, association and role are the owner's own, stated once.
            try std.testing.expectEqualSlices(pipeline.DataKey, fact.requires, variant.requires);
            try std.testing.expectEqualSlices(pipeline.DataKey, fact.optional, variant.optional);
            try std.testing.expectEqualSlices(pipeline.DataKey, fact.produces, variant.produces);
            try std.testing.expectEqualSlices(pipeline.DataKey, fact.replaces, variant.replaces);
            try std.testing.expectEqualSlices(pipeline.DataKey, fact.invalidates, variant.invalidates);
            try std.testing.expectEqual(fact.side_effect, variant.side_effect);
            try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, variant.runner_accounting);
            try std.testing.expectEqual(fact.role, variant.repair_role);
            try std.testing.expect(fact.association.eql(variant.outcome_association));
            try std.testing.expectEqual(fact.gates, variant.gates.len);
            try std.testing.expect(variant.iteration == null);
            // Outcomes: the owner's, without the one outcome it can no longer reach (DE4 7).
            var expected: [8]workflow.OutcomeTag = undefined;
            var count: usize = 0;
            for (fact.outcomes) |outcome| {
                if (repair_owner.unreachableOutcome(op, owner)) |dropped| if (outcome == dropped) continue;
                expected[count] = outcome;
                count += 1;
            }
            try std.testing.expectEqualSlices(workflow.OutcomeTag, expected[0..count], variant.outcomes);
            // Retry rule: the owner's scope, with the owner's maximum (DE4 6), and none where the owner's
            // merge forbade a `retry-limit`.
            if (fact.retry) |rule| {
                const limit = variant.retry_limit.?;
                try std.testing.expectEqual(rule.scope, limit.scope);
                try std.testing.expectEqual(repair_owner.retryMaximum(owner).?, limit.maximum);
            } else {
                try std.testing.expect(variant.retry_limit == null);
            }
            // Parameters: the closed `owner` selector first, then the owner's own.
            const selector = variant.parameters[0];
            try std.testing.expectEqualStrings(generic.selector, selector.id);
            try std.testing.expectEqual(operation.ParameterKind.enumeration, selector.kind);
            try std.testing.expect(selector.required and selector.workflow_definition_safe);
            try std.testing.expectEqual(repair_owner.values(op).len, selector.allowed_values.len);
            try std.testing.expectEqual(fact.parameters.len + 1, variant.parameters.len);
            for (fact.parameters, variant.parameters[1..]) |before, after| {
                try std.testing.expectEqualStrings(before[0], after.id);
                try std.testing.expectEqual(before[1], after.kind);
                try std.testing.expectEqual(before[2], after.required);
                try std.testing.expectEqual(before[3], after.integer_min);
                // The only own parameter is the merge's `retry-limit`, bounded by the owner's maximum.
                try std.testing.expectEqualStrings(retry.parameter_id, after.id);
                try std.testing.expectEqual(@as(i64, variant.retry_limit.?.maximum), after.integer_max);
            }
        }
    }
    // The frozen table is one row per served (operation, owner) pair: 29, no pair twice, none missing.
    try std.testing.expectEqual(@as(usize, 29), variant_count);
    try std.testing.expectEqual(@as(usize, 29), frozen.len);
    for (frozen) |fact| try std.testing.expect(fact.owner.serves(fact.op));
}

test "the owners' retry maxima are the YAML values the per-owner merges declare today" {
    try std.testing.expectEqual(@as(?u32, 128), repair_owner.retryMaximum(.reference_reconciliation));
    try std.testing.expectEqual(@as(?u32, 1), repair_owner.retryMaximum(.source_omission_extraction));
    try std.testing.expectEqual(@as(?u32, 1), repair_owner.retryMaximum(.source_omission_reconciliation));
    try std.testing.expectEqual(@as(?u32, 64), repair_owner.retryMaximum(.specification_unit));
    try std.testing.expectEqual(@as(?u32, 2), repair_owner.retryMaximum(.specification_support));
    // The text and extraction merges forbid a `retry-limit`, as they do today.
    try std.testing.expect(repair_owner.retryMaximum(.reference_text) == null);
    try std.testing.expect(repair_owner.retryMaximum(.reference_extraction) == null);
    // Only the dispositions authorizer drops an outcome it cannot reach.
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        inline for (@typeInfo(RepairOwner).@"enum".fields) |field| {
            const owner: RepairOwner = @enumFromInt(field.value);
            const dropped = repair_owner.unreachableOutcome(op, owner);
            const expected: ?workflow.OutcomeTag = if (op == .authorize and owner == .reference_dispositions) .more else null;
            try std.testing.expectEqual(expected, dropped);
        }
    }
}

// ---- registry, compiler and graph validation ----

fn unused(_: ?*void, _: operations.Input) operations.Error!execution.Candidate {
    return error.InvocationFailureUnrecorded;
}

/// A registry holding one generic operation, an invocation that produces what a variant requires, and
/// a sink step for the `more` branch.
fn registryFor(a: std.mem.Allocator, comptime op: Operation, produced: []const pipeline.DataKey) !Registry {
    const context = try a.create(GenericOf(op));
    context.* = undefined;
    const entries = try a.dupe(Entry, &.{
        .{ .contract = .{ .id = "repair.input", .kind = .invocation, .produces = produced, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unused) },
        native.variantEntry(GenericOf(op), context),
        .{ .contract = .{ .id = "repair.sink", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unused) },
    });
    return .{ .operations = entries, .data_schemas = &native.schemas, .policies = &core.profiles, .gates = &.{} };
}

/// The evidence only the model request's own stages create: the runner's accounting transitions and the
/// admission and observation results. No registered operation, an invocation included, may produce it
/// (`validAccounting`, the model invocation contract).
fn runnerAccounted(key: pipeline.DataKey) bool {
    return switch (key) {
        .accounted_model_attempt, .assigned_provider_operation, .invoked_provider_operation, .terminal_provider_operation, .model_payload_schema_result, .model_envelope_result, .provider_invocation_validation_result, .provider_invocation_result, .provider_authorization_result => true,
        else => false,
    };
}

/// What an invocation provides for a one-step workflow: every key a variant requires, replaces or
/// invalidates, once, and none it produces. The runner-accounted evidence is left out, so a variant
/// that requires it (the parse and merge steps that follow a model call) cannot pass the data-flow
/// check in a test workflow; it still compiles and is admitted.
fn inputKeys(a: std.mem.Allocator, variants: []const operation.Contract) ![]const pipeline.DataKey {
    var keys: std.ArrayList(pipeline.DataKey) = .empty;
    for (variants) |variant| {
        for ([_][]const pipeline.DataKey{ variant.requires, variant.replaces, variant.invalidates }) |list| for (list) |key| {
            if (runnerAccounted(key) or std.mem.indexOfScalar(pipeline.DataKey, variant.produces, key) != null) continue;
            if (std.mem.indexOfScalar(pipeline.DataKey, keys.items, key) == null) try keys.append(a, key);
        };
    }
    return keys.items;
}

fn requiresRunnerEvidence(variant: operation.Contract) bool {
    for (variant.requires) |key| if (runnerAccounted(key)) return true;
    return false;
}

fn emptyInventory() inventory.Inventory {
    return .{ .capability = undefined, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{}, .resource_ordinals = &.{} };
}

fn compileYaml(a: std.mem.Allocator, registry: *const Registry, yaml: []const u8) ![]const compilation.CompiledWorkflow {
    var parser: parser_adapter.Adapter = .{};
    var result_schema: result_schema_parser.Adapter = .{};
    const raw = try startup.steps.parseWorkflows(parser.parser(), a, &.{.{ .ordinal = 1, .bytes = yaml }});
    const definitions = try definition_schema.validate(a, raw);
    const manifest = try resource_binding.resolve(a, emptyInventory(), definitions);
    return graph_compilation.compile(registry, result_schema.compiler(), a, definitions, emptyInventory(), manifest, &.{});
}

const head =
    \\schema: workflow/v1
    \\id: repair-flow
    \\version: 1
    \\shortcode: REPF
    \\invoke: repair.input
    \\policy: core.capability-free@1
    \\
;

fn terminalFor(outcome: workflow.OutcomeTag) []const u8 {
    return switch (outcome) {
        .ok => "end.ok",
        .more => "sink",
        .invalid => "end.invalid",
        .blocked => "end.blocked",
        .failed => "end.failed",
        .cancelled => "end.cancelled",
        .needs_user => "end.needs-user",
    };
}

/// A one-step workflow: `use: op_id` with `with_text` and every outcome in `outcomes` mapped.
fn singleStep(a: std.mem.Allocator, op_id: []const u8, with_text: []const u8, outcomes: []const workflow.OutcomeTag) ![]const u8 {
    var yaml: std.Io.Writer.Allocating = .init(a);
    try yaml.writer.writeAll(head);
    try yaml.writer.print("start: run\nsteps:\n  run:\n    use: {s}\n    with: {{{s}}}\n    on: {{", .{ op_id, with_text });
    for (outcomes, 0..) |outcome, index| {
        if (index != 0) try yaml.writer.writeAll(", ");
        try yaml.writer.print("{s}: {s}", .{ @tagName(outcome), terminalFor(outcome) });
    }
    try yaml.writer.writeAll("}\n");
    // The `more` branch needs a step to run; every other outcome ends the workflow, and a step that
    // nothing reaches is itself a rejected graph.
    if (std.mem.indexOfScalar(workflow.OutcomeTag, outcomes, .more) != null) try yaml.writer.writeAll("  sink:\n    use: repair.sink\n    on: {ok: end.ok}\n");
    return yaml.written();
}

fn withText(a: std.mem.Allocator, owner: RepairOwner, limit: ?u32) ![]const u8 {
    return if (limit) |value| std.fmt.allocPrint(a, "owner: {s}, retry-limit: {d}", .{ owner.id(), value }) else std.fmt.allocPrint(a, "owner: {s}", .{owner.id()});
}

test "each of the 29 variants compiles and is the step's one checked contract" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var accepted: usize = 0;
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        inline for (comptime repair_owner.served(op)) |owner| {
            const shell = GenericOf(op).contract;
            const variant = shell.resolve(owner.id()).?;
            const registry = try registryFor(a, op, try inputKeys(a, &.{variant}));
            try std.testing.expect(registry.validate());
            const yaml = try singleStep(a, op.id(), try withText(a, owner, if (variant.retry_limit) |limit| limit.maximum else null), variant.outcomes);
            const graphs = try compileYaml(a, &registry, yaml);
            const step = graphs[0].authority.steps[0];
            const entry = registry.resolveOperation(workflow.OperationId.parse(op.id()).?).?;
            try std.testing.expectEqualStrings(owner.id(), compilation.selectorValue(entry.contract, step.parameters).?);
            // The step carries exactly this variant's effects, outcomes, role, association and retry authority.
            try std.testing.expect(compilation.matchesContract(variant, step));
            try std.testing.expectEqual(variant.retry_limit != null, step.retry_authority != null);
            try std.testing.expect(registry.stepsMatchVariants(graphs[0].authority.steps));
            // The data-flow check needs the evidence the runner's accounting creates after a model call, which
            // a test invocation cannot provide: those variants are checked by the compile and variant match.
            if (!requiresRunnerEvidence(variant)) _ = try graph_validation.validate(a, graphs, &registry);
            accepted += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 29), accepted);
}

test "a step names an owner with no variant of the operation, an unknown owner or none, and compilation rejects it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rejected: usize = 0;
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        const first = repair_owner.served(op)[0];
        const first_variant = GenericOf(op).contract.resolve(first.id()).?;
        const registry = try registryFor(a, op, try inputKeys(a, &.{first_variant}));
        const outcomes = first_variant.outcomes;
        // An owner that has no variant of this operation (ADR 0033: variants only where an owner uses it today).
        inline for (@typeInfo(RepairOwner).@"enum".fields) |field| {
            const owner: RepairOwner = @enumFromInt(field.value);
            if (comptime owner.serves(op)) continue;
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, null), outcomes)));
            rejected += 1;
        }
        // A value outside the closed set, its spelling variants, and a missing or mistyped selector.
        for ([_][]const u8{ "owner: nope", "owner: reference_text", "owner: Reference-Text", "owner: ''", "owner: 3", "owner: true", "", "retry-limit: 1" }) |with| {
            // Either the definition schema or the compiler rejects it; none is ever compiled.
            try std.testing.expect(if (compileYaml(a, &registry, try singleStep(a, op.id(), with, outcomes))) |_| false else |_| true);
            rejected += 1;
        }
    }
    // 23 owners without a variant (13 x 4 - 29) and 8 malformed selectors for each of four operations.
    try std.testing.expectEqual(@as(usize, 23 + 8 * operation_count), rejected);
}

test "compilation rejects an outcome the variant does not declare and a declared outcome left unmapped" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        inline for (comptime repair_owner.served(op)) |owner| {
            const variant = GenericOf(op).contract.resolve(owner.id()).?;
            const registry = try registryFor(a, op, try inputKeys(a, &.{variant}));
            const with = try withText(a, owner, if (variant.retry_limit) |limit| limit.maximum else null);
            // Dropping the last declared outcome leaves it unmapped.
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), with, variant.outcomes[0 .. variant.outcomes.len - 1])));
            // Every outcome the variant does not declare is undeclared for this step.
            for (std.enums.values(workflow.OutcomeTag)) |tag| {
                if (std.mem.indexOfScalar(workflow.OutcomeTag, variant.outcomes, tag) != null) continue;
                if (tag == .needs_user) continue; // no terminal exists for it in this policy's test workflow
                var extended: [8]workflow.OutcomeTag = undefined;
                @memcpy(extended[0..variant.outcomes.len], variant.outcomes);
                extended[variant.outcomes.len] = tag;
                try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), with, extended[0 .. variant.outcomes.len + 1])));
            }
        }
    }
    // DE4 7: the dispositions authorizer declares no `more`, so a step that maps it rejects, while the
    // summary, signals and conflicts authorizers keep it.
    const dispositions = GenericOf(.authorize).contract.resolve(RepairOwner.reference_dispositions.id()).?;
    try std.testing.expectEqualSlices(workflow.OutcomeTag, &.{ .ok, .blocked, .failed }, dispositions.outcomes);
    for ([_]RepairOwner{ .reference_summary, .reference_signals, .reference_conflicts }) |kept| {
        try std.testing.expect(std.mem.indexOfScalar(workflow.OutcomeTag, GenericOf(.authorize).contract.resolve(kept.id()).?.outcomes, .more) != null);
    }
    try std.testing.expectEqualSlices(workflow.OutcomeTag, &.{ .blocked, .failed }, GenericOf(.authorize).contract.resolve(RepairOwner.specification_coverage.id()).?.outcomes);
}

test "a merge takes a retry-limit within its owner's maximum, and no other variant or owner takes one" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        inline for (comptime repair_owner.served(op)) |owner| {
            const variant = GenericOf(op).contract.resolve(owner.id()).?;
            const registry = try registryFor(a, op, try inputKeys(a, &.{variant}));
            if (variant.retry_limit) |limit| {
                // Required: a missing limit rejects; the maximum itself and zero are accepted; one above rejects.
                try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, null), variant.outcomes)));
                _ = try compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, limit.maximum), variant.outcomes));
                _ = try compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, 0), variant.outcomes));
                try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, limit.maximum + 1), variant.outcomes)));
                const step = (try compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, limit.maximum), variant.outcomes)))[0].authority.steps[0];
                try std.testing.expectEqual(limit.maximum, step.retry_authority.?.limit.value);
                try std.testing.expectEqual(limit.scope, step.retry_authority.?.scope);
            } else {
                // Forbidden: a `retry-limit` the variant does not declare rejects.
                try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, 1), variant.outcomes)));
                _ = try compileYaml(a, &registry, try singleStep(a, op.id(), try withText(a, owner, null), variant.outcomes));
            }
        }
    }
}

test "registry admission rejects a repair variant whose role, association or retry parameter do not fit" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const merge_context = try a.create(generic.MergeRepair);
    merge_context.* = undefined;
    const merge_entry = native.variantEntry(generic.MergeRepair, merge_context);
    const authorize_context = try a.create(generic.AuthorizeRepair);
    authorize_context.* = undefined;
    const authorize_entry = native.variantEntry(generic.AuthorizeRepair, authorize_context);
    const base_merge = try a.dupe(operation.Variant, generic.MergeRepair.contract.variants);
    const base_authorize = try a.dupe(operation.Variant, generic.AuthorizeRepair.contract.variants);
    const input: Entry = .{ .contract = .{ .id = "repair.input", .kind = .invocation, .produces = &.{}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unused) };
    const faults = [_]struct { merge: bool, fault: usize }{
        // A merge variant without its merge role cannot carry repair-scope retry authority.
        .{ .merge = true, .fault = 0 },
        // A repair-scope retry authority without the `retry-limit` parameter it belongs to.
        .{ .merge = true, .fault = 1 },
        // A `retry-limit` parameter without retry authority.
        .{ .merge = true, .fault = 2 },
        // An operation-scope retry on a merge role.
        .{ .merge = true, .fault = 3 },
        // An authorize variant whose association is a merge's.
        .{ .merge = false, .fault = 0 },
        // An authorize variant with a merge role.
        .{ .merge = false, .fault = 1 },
        // Two authorize variants with the same selector value.
        .{ .merge = false, .fault = 2 },
    };
    for (faults) |case| {
        const variants = try a.dupe(operation.Variant, if (case.merge) base_merge else base_authorize);
        const target = &variants[if (case.merge) 5 else 0];
        switch (case.fault) {
            0 => if (case.merge) {
                target.repair_role = .none;
            } else switch (target.outcome_association) {
                .repair_authorize => |binding| target.outcome_association = .{ .repair_merge = binding },
                else => unreachable,
            },
            1 => if (case.merge) {
                target.parameters = target.parameters[0..1];
            } else {
                target.repair_role = .merge;
            },
            2 => if (case.merge) {
                target.retry_limit = null;
            } else {
                // Two variants with one selector value: neither could be selected alone.
                target.value = variants[1].value;
            },
            3 => target.retry_limit = .{ .maximum = 2, .scope = .operation },
            else => unreachable,
        }
        var changed = if (case.merge) merge_entry else authorize_entry;
        changed.contract.variants = variants;
        const registry: Registry = .{ .operations = try a.dupe(Entry, &.{ input, changed }), .data_schemas = &native.schemas, .policies = &core.profiles, .gates = &.{} };
        try std.testing.expect(!registry.validate());
    }
    // The unmodified entries are admitted.
    for ([_]Entry{ merge_entry, authorize_entry }) |entry| {
        const registry: Registry = .{ .operations = try a.dupe(Entry, &.{ input, entry }), .data_schemas = &native.schemas, .policies = &core.profiles, .gates = &.{} };
        try std.testing.expect(registry.validate());
    }
}

test "a compiled step whose effects belong to another owner's variant is rejected by validation and publication" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = GenericOf(.merge).contract.resolve(RepairOwner.specification_unit.id()).?;
    const support = GenericOf(.merge).contract.resolve(RepairOwner.specification_support.id()).?;
    const registry = try registryFor(a, .merge, try inputKeys(a, &.{unit}));
    const graph = (try compileYaml(a, &registry, try singleStep(a, "merge-repair", try withText(a, .specification_unit, 3), unit.outcomes)))[0];
    try std.testing.expect(registry.stepsMatchVariants(graph.authority.steps));
    // Each field a variant states, taken from the other owner's variant, no longer matches.
    for (0..5) |fault| {
        var tampered = graph.authority.steps[0];
        switch (fault) {
            0 => tampered.requires = support.requires,
            1 => tampered.replaces = support.replaces,
            2 => tampered.outcomes = support.outcomes,
            3 => tampered.repair_role = support.repair_role,
            4 => tampered.outcome_association = support.outcome_association,
            else => unreachable,
        }
        try std.testing.expect(!compilation.matchesContract(unit, tampered));
        const steps = try a.dupe(compilation.CompiledStep, &.{tampered});
        try std.testing.expect(!registry.stepsMatchVariants(steps));
        var changed = graph;
        changed.authority.steps = steps;
        try std.testing.expect(if (graph_validation.validate(a, &.{changed}, &registry)) |_| false else |_| true);
    }
}

test "steps that use one generic operation keep their own retry authority" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = GenericOf(.merge).contract.resolve(RepairOwner.specification_unit.id()).?;
    const support = GenericOf(.merge).contract.resolve(RepairOwner.reference_reconciliation.id()).?;
    // One invocation provides what both variants need. A merge invalidates what it consumed, so a test
    // step republishes it (as the workflow's validation step does) before the same owner's merge runs again.
    const context = try a.create(generic.MergeRepair);
    context.* = undefined;
    const registry: Registry = .{
        .operations = try a.dupe(Entry, &.{
            .{ .contract = .{ .id = "repair.input", .kind = .invocation, .produces = try inputKeys(a, &.{ unit, support }), .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unused) },
            native.variantEntry(generic.MergeRepair, context),
            .{ .contract = .{ .id = "repair.restore", .kind = .step, .produces = unit.invalidates, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unused) },
        }),
        .data_schemas = &native.schemas,
        .policies = &core.profiles,
        .gates = &.{},
    };
    try std.testing.expect(registry.validate());
    var yaml: std.Io.Writer.Allocating = .init(a);
    try yaml.writer.writeAll(head);
    try yaml.writer.writeAll(
        \\start: left
        \\steps:
        \\  left:
        \\    use: merge-repair
        \\    with: {owner: specification-unit, retry-limit: 3}
        \\    on: {ok: restore, failed: end.failed}
        \\  restore:
        \\    use: repair.restore
        \\    on: {ok: right}
        \\  right:
        \\    use: merge-repair
        \\    with: {owner: specification-unit, retry-limit: 5}
        \\    on: {ok: after, failed: end.failed}
        \\  after:
        \\    use: merge-repair
        \\    with: {owner: reference-reconciliation, retry-limit: 128}
        \\    on: {ok: end.ok, failed: end.failed}
        \\
    );
    const graph = (try compileYaml(a, &registry, yaml.written()))[0];
    var left: ?compilation.CompiledStep = null;
    var right: ?compilation.CompiledStep = null;
    var after: ?compilation.CompiledStep = null;
    for (graph.authority.steps) |step| {
        if (std.mem.eql(u8, step.id.bytes, "left")) left = step;
        if (std.mem.eql(u8, step.id.bytes, "right")) right = step;
        if (std.mem.eql(u8, step.id.bytes, "after")) after = step;
    }
    // The same operation, three compiled instances: each has its own identity, limit and variant.
    try std.testing.expectEqualStrings(left.?.operation_id.bytes, right.?.operation_id.bytes);
    try std.testing.expectEqualStrings(left.?.operation_id.bytes, after.?.operation_id.bytes);
    const left_id = left.?.retry_authority.?.operation_instance_id.bytes;
    const right_id = right.?.retry_authority.?.operation_instance_id.bytes;
    const after_id = after.?.retry_authority.?.operation_instance_id.bytes;
    try std.testing.expect(!std.mem.eql(u8, left_id, right_id));
    try std.testing.expect(!std.mem.eql(u8, left_id, after_id));
    try std.testing.expect(!std.mem.eql(u8, right_id, after_id));
    try std.testing.expectEqual(@as(u32, 3), left.?.retry_authority.?.limit.value);
    try std.testing.expectEqual(@as(u32, 5), right.?.retry_authority.?.limit.value);
    try std.testing.expectEqual(@as(u32, 128), after.?.retry_authority.?.limit.value);
    try std.testing.expectEqual(retry.Role.merge, left.?.repair_role);
    try std.testing.expectEqual(retry.Role.merge, after.?.repair_role);
    try std.testing.expect(compilation.matchesContract(unit, left.?));
    try std.testing.expect(compilation.matchesContract(unit, right.?));
    try std.testing.expect(compilation.matchesContract(support, after.?));
    _ = try graph_validation.validate(a, &.{graph}, &registry);
}

// ---- running a step: the owner's binding, selected by `owner` ----

fn stepFor(comptime op: Operation, owner_value: ?[]const u8, storage: *[1]compilation.CompiledParameter) compilation.CompiledStep {
    storage[0] = .{ .id = .{ .bytes = generic.selector }, .value = .{ .enumeration = owner_value orelse "" } };
    return .{
        .id = .{ .bytes = "repair" },
        .operation_id = .{ .bytes = op.id() },
        .parameters = if (owner_value != null) storage else &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    };
}

fn inputFor(step: *const compilation.CompiledStep) operations.Input {
    return .{ .step = .{ .data = .{}, .step = step, .resources = &.{}, .model_binding = null, .log = .init(.{ .bytes = "TEST".* }) } };
}

/// A generic operation whose owner bindings hold only an allocator: with none of the owner's native
/// facts present they fail before they use anything else.
fn contextFor(comptime G: type) G {
    var result: G = undefined;
    inline for (@typeInfo(G).@"struct".fields) |field| @field(result, field.name).allocator = std.testing.allocator;
    return result;
}

fn failure(result: operations.Error!execution.Candidate) ?operations.Error {
    return if (result) |_| null else |err| err;
}

test "a generic operation runs the selected owner's binding and fails as that binding fails" {
    var covered: usize = 0;
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        var context = contextFor(GenericOf(op));
        inline for (comptime repair_owner.served(op)) |owner| {
            const T = generic.OwnerBinding(op, owner);
            // The generic operation holds the owner's own binding, so the owner's rules exist once.
            try std.testing.expect(@TypeOf(@field(context, @tagName(owner))) == T);
            var storage: [1]compilation.CompiledParameter = undefined;
            const step = stepFor(op, owner.id(), &storage);
            const input = inputFor(&step);
            // With none of the owner's native facts present, both the generic operation and the owner's
            // binding fail the run terminally, with the same operation error.
            const direct = failure(T.invoke(&@field(context, @tagName(owner)), input));
            const selected = failure(GenericOf(op).invoke(&context, input));
            try std.testing.expect(direct != null);
            try std.testing.expectEqual(direct, selected);
            covered += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 29), covered);
}

test "a tampered step is never run: a missing selector, an unknown owner or one with no variant fails terminally" {
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        var context = contextFor(GenericOf(op));
        for ([_]?[]const u8{ null, "", "nope", "reference_text", "Reference-Text" }) |value| {
            var storage: [1]compilation.CompiledParameter = undefined;
            const step = stepFor(op, value, &storage);
            try std.testing.expectEqual(@as(?operations.Error, error.RepairOwnerUnresolved), failure(GenericOf(op).invoke(&context, inputFor(&step))));
        }
        inline for (@typeInfo(RepairOwner).@"enum".fields) |field| {
            const owner: RepairOwner = @enumFromInt(field.value);
            if (comptime owner.serves(op)) continue;
            var storage: [1]compilation.CompiledParameter = undefined;
            const step = stepFor(op, owner.id(), &storage);
            try std.testing.expectEqual(@as(?operations.Error, error.RepairOwnerMismatch), failure(GenericOf(op).invoke(&context, inputFor(&step))));
        }
        // An invocation input is not a step: nothing is selected.
        try std.testing.expectEqual(@as(?operations.Error, error.OperationWrongKind), failure(GenericOf(op).invoke(&context, .{ .invocation = .{ .arguments = &.{} } })));
    }
}

test "the core operations refuse an input of the wrong kind or arguments they do not take, each with its own cause" {
    var storage: [1]compilation.CompiledParameter = undefined;
    const step = stepFor(.authorize, null, &storage);
    const empty_invocation = core.entries[0];
    const noop = core.entries[1];
    try std.testing.expectEqual(.ok, (try empty_invocation.invoke(.{ .invocation = .{ .arguments = &.{} } })).outcome);
    try std.testing.expectError(error.OperationWrongKind, empty_invocation.invoke(inputFor(&step)));
    try std.testing.expectError(error.InvocationArgumentsInvalid, empty_invocation.invoke(.{ .invocation = .{ .arguments = &.{"extra"} } }));
    try std.testing.expectEqual(.ok, (try noop.invoke(inputFor(&step))).outcome);
    try std.testing.expectError(error.OperationWrongKind, noop.invoke(.{ .invocation = .{ .arguments = &.{} } }));
}

test "a merge that cannot continue its retry accounting fails with its own cause and forwards the domain's" {
    const atomic = @import("domain/atomic_repair.zig");
    var merge: atomic.Merge = .{ .authorization = .{ .bytes = "authorization" }, .owner = .workflow_step, .operation = .replace, .revision_before = 1, .revision_after = 2, .changed = true, .origin = null };
    // No record of the merge: the repaired candidate cannot name what to continue from.
    try std.testing.expectError(error.LastRepairMissing, repair_owner.mergeTransition(null, .native));
    try std.testing.expectError(error.LastRepairMissing, repair_owner.validatedMergeTransition(null, .resolved));
    // A record without its permit is the domain's own `InvalidAtomicRepair`, reaching the report as it is.
    try std.testing.expectError(error.InvalidAtomicRepair, repair_owner.mergeTransition(merge, .native));
    try std.testing.expectError(error.InvalidAtomicRepair, repair_owner.validatedMergeTransition(merge, .recurring));
    merge.retry = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
    const native_merge = try repair_owner.mergeTransition(merge, .dependent_review);
    try std.testing.expectEqual(retry.ValidationMode.dependent_review, native_merge.merged.validation);
    try std.testing.expect(native_merge.merged.changed and native_merge.merged.revision_after == 2);
    const validated = try repair_owner.validatedMergeTransition(merge, .recurring);
    try std.testing.expectEqual(retry.Validation.recurring, validated.merged_validated.result);
}

fn coveredBy(inner: []const pipeline.DataKey, outer: []const pipeline.DataKey) bool {
    for (inner) |key| if (std.mem.indexOfScalar(pipeline.DataKey, outer, key) == null) return false;
    return true;
}

test "no variant's required keys are covered by another variant's, so the data flow alone tells the owners apart" {
    // What this proves: within one operation, for every ordered pair of owners (x, y), x requires a key
    // that y does not. A graph position whose data satisfy owner y's variant therefore cannot satisfy
    // owner x's, so the compiler's data-flow check (not a run-time check) rejects a step that names x
    // there. The stronger statement that an `owner` which names the wrong native fact at a position that
    // holds the keys of several owners fails terminally (the reconciliation authorizers, whose keys
    // coexist in the graph) is proved against real facts in `reference_reconciliation_test.zig`.
    var covered: usize = 0;
    inline for (@typeInfo(Operation).@"enum".fields) |op_field| {
        const op: Operation = @enumFromInt(op_field.value);
        const variants = GenericOf(op).contract.variants;
        for (variants, 0..) |inner, index| for (variants, 0..) |outer, other| {
            if (index != other and coveredBy(inner.requires, outer.requires)) covered += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 0), covered);
}

/// The 29 per-owner repair operations ADR 0033 replaced, deleted in E4 step 5 together with their
/// bindings' registrations and action files. A workflow that names one of them is rejected as an
/// unknown operation, with no alias.
const removed_operations = [_][]const u8{
    "authorize-reference-text-repair",             "authorize-reference-extraction-repair", "authorize-reference-summary-repair",
    "authorize-reference-dispositions-repair",     "authorize-reference-signals-repair",    "authorize-reference-conflicts-repair",
    "authorize-source-omission-repair",            "authorize-specification-repair",        "authorize-specification-support-repair",
    "authorize-specification-coverage-repair",     "build-reference-text-repair-input",     "build-reference-extraction-repair-input",
    "build-reference-reconciliation-repair-input", "build-source-omission-repair-input",    "build-specification-repair-input",
    "build-specification-support-repair-input",    "parse-reference-text-repair",           "parse-reference-extraction-repair",
    "parse-reference-reconciliation-repair",       "parse-source-omission-repair",          "parse-specification-repair",
    "parse-specification-support-repair",          "merge-reference-text-repair",           "merge-reference-extraction-repair",
    "merge-reference-reconciliation-repair",       "merge-source-extraction-repair",        "merge-source-reconciliation-repair",
    "merge-specification-repair",                  "merge-specification-support-repair",
};

fn subgraphStep(a: std.mem.Allocator, op_id: []const u8, with_text: []const u8, outcomes: []const workflow.OutcomeTag) ![]const u8 {
    var yaml: std.Io.Writer.Allocating = .init(a);
    try yaml.writer.writeAll(head);
    // The called subgraph's exits are the operation's outcomes and the caller maps each of them; a
    // `more` branch stays inside the subgraph, on a step of its own.
    try yaml.writer.writeAll("start: run\nsteps:\n  run: { call: guarded, on: {");
    var exits: usize = 0;
    for (outcomes) |outcome| {
        if (outcome == .more) continue;
        if (exits != 0) try yaml.writer.writeAll(", ");
        try yaml.writer.print("{s}: {s}", .{ @tagName(outcome), terminalFor(outcome) });
        exits += 1;
    }
    try yaml.writer.print("}} }}\nsubgraphs:\n  guarded:\n    start: only\n    steps:\n      only:\n        use: {s}\n        with: {{{s}}}\n        on: {{", .{ op_id, with_text });
    for (outcomes, 0..) |outcome, index| {
        if (index != 0) try yaml.writer.writeAll(", ");
        try yaml.writer.print("{s}: {s}", .{ @tagName(outcome), if (outcome == .more) "sink" else terminalFor(outcome) });
    }
    try yaml.writer.writeAll("}\n");
    if (std.mem.indexOfScalar(workflow.OutcomeTag, outcomes, .more) != null) try yaml.writer.writeAll("      sink:\n        use: repair.sink\n        on: {ok: end.ok}\n");
    return yaml.written();
}

test "a workflow that names a removed per-owner repair operation is rejected as an unknown operation, at a step and in a called subgraph" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 29), removed_operations.len);
    const owner = RepairOwner.reference_text;
    const variant = GenericOf(.merge).contract.resolve(owner.id()).?;
    const registry = try registryFor(a, .merge, try inputKeys(a, &.{variant}));
    const with = try withText(a, owner, null);
    // Control: the generic operation named at the same positions compiles, so a rejection below is about
    // the operation named, not the position or the other fields of the step.
    _ = try compileYaml(a, &registry, try singleStep(a, "merge-repair", with, variant.outcomes));
    _ = try compileYaml(a, &registry, try subgraphStep(a, "merge-repair", with, variant.outcomes));
    for (removed_operations) |id| {
        // The reason is the registry's: the id resolves to no operation, and nothing aliases it.
        try std.testing.expect(registry.resolveOperation(workflow.OperationId.parse(id).?) == null);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try singleStep(a, id, with, variant.outcomes)));
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, try subgraphStep(a, id, with, variant.outcomes)));
    }
}

test "the production registry holds the four generic repair operations with their variants, and none of the 29 they replaced" {
    // The adapters are built but never called: only the registry the composition root assembles is read.
    const io = std.testing.io;
    const root = std.Io.Dir.cwd();
    var project_source = @import("adapters/filesystem/toolchain_authority_source.zig").Adapter.init(io, root);
    var document_parser: @import("adapters/parsers/toolchain_documents.zig").Adapter = .{};
    var reference_source: @import("adapters/filesystem/reference_directory_inspector.zig").Adapter = .{ .io = io, .project_root = root };
    var feature_source: @import("adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = io, .project_root = root };
    var feature_inputs: @import("adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = root };
    var reference_contents: @import("adapters/filesystem/reference_corpus_source.zig").Adapter = .{ .io = io, .project_root = root };
    var markdown_reader: @import("adapters/parsers/markdown_reference.zig").Adapter = .{ .io = io };
    var reference_ids: @import("adapters/system/reference_state_identity.zig").Adapter = .{ .io = io };
    const inputs = @import("adapters/parsers/clarification_inputs.zig");
    const normalization = @import("unicode_normalization");
    var assembly: native.Assembly = undefined;
    assembly.init(std.testing.allocator, project_source.projectCapturer(), project_source.presetEnumerator(), project_source.presetCapturer(), document_parser.parser(), @import("composition/toolchain_policy_registry.zig").registry, .{ .normalize_fn = normalization.nfc }, reference_source.inspector(), feature_source.inspector(), feature_inputs.capturer(), inputs.stateParser(), inputs.formParser(), reference_contents.enumerator(), reference_contents.capturer(), markdown_reader.decoderPort(), .{ .fold_fn = normalization.caseFold }, reference_ids.source(), .{ .boundary_fn = normalization.lexicalBoundary });
    try std.testing.expect(assembly.registry.validate());
    // Each generic operation is one registered shell whose variants are the owners it serves: 10, 6, 6 and 7.
    const counts = [operation_count]usize{ 10, 6, 6, 7 };
    inline for (@typeInfo(Operation).@"enum".fields, counts) |field, expected| {
        const op: Operation = @enumFromInt(field.value);
        const entry = assembly.registry.resolveOperation(workflow.OperationId.parse(op.id()).?).?;
        try std.testing.expect(entry.contract.isShell());
        try std.testing.expectEqual(expected, entry.contract.variants.len);
        try std.testing.expectEqual(expected, comptime repair_owner.served(op).len);
    }
    // They are the only operations with variants, and none of the replaced operations is registered.
    var with_variants: usize = 0;
    for (assembly.registry.operations) |entry| {
        if (entry.contract.hasVariants()) with_variants += 1;
    }
    try std.testing.expectEqual(@as(usize, operation_count), with_variants);
    for (removed_operations) |id| try std.testing.expect(assembly.registry.resolveOperation(workflow.OperationId.parse(id).?) == null);
}
