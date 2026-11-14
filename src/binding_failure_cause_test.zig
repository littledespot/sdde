//! Every closed binding failure cause (`step_binding_error.zig`, `repair_owner.zig`) is accounted for here
//! exactly once: a test raises it through the production check that names it, or it is listed as one no
//! offline test names. A cause cannot join a set without joining one of the lists below, and a list holds
//! no name that is no cause, so a rejection's label cannot be left unexamined without that being on record.
const std = @import("std");
const compilation = @import("domain/workflow_compilation.zig");
const data = @import("domain/pipeline_data.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const step_binding = @import("domain/step_binding_error.zig");
const repair_owner = @import("domain/repair_owner.zig");
const values = @import("application/pipeline_values.zig");
const composition = @import("application/json_composition_workflow.zig");
const required_authority = @import("application/required_authority_workflow.zig");
const provider_lifecycle = @import("application/provider_operation_lifecycle_workflow.zig");
const model_envelope = @import("application/model_envelope_workflow.zig");
const clarification_refresh = @import("application/clarification_refresh_workflow.zig");
const clarification_input = @import("application/clarification_input_workflow.zig");
const feature_logging = @import("application/feature_logging_workflow.zig");
const feature_directory = @import("domain/feature_directory.zig");
const feature_directory_workflow = @import("application/feature_directory_workflow.zig");
const request_workflow_tests = @import("model_request_workflow_test.zig");

const bare_step: compilation.CompiledStep = .{
    .id = .{ .bytes = "bare" },
    .operation_id = .{ .bytes = "test.bare" },
    .parameters = &.{},
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

fn stepInput(step: *const compilation.CompiledStep, view: data.View, resources: []const compilation.CompiledResource) operations.Input {
    return .{ .step = .{ .data = view, .step = step, .resources = resources, .model_binding = null, .log = .init(.{ .bytes = "TEST".* }) } };
}

const Row = struct { cause: []const u8, run: *const fn () anyerror!void };

/// A binding that checks only what the step carries fails before it reads any data.
fn compositionWithoutResource() anyerror!void {
    var binding: composition.Initialize = .{ .allocator = std.testing.allocator };
    _ = try composition.Initialize.invoke(&binding, stepInput(&bare_step, .{}, &.{}));
}

fn compositionResourceOfAnotherKind() anyerror!void {
    const parameters = [_]compilation.CompiledParameter{.{ .id = .{ .bytes = "composition" }, .value = .{ .resource = .{ .bytes = "composition" } } }};
    const resources = [_]compilation.CompiledResource{.{ .id = .{ .bytes = "composition" }, .content = .{ .prompt = "a prompt is no JSON composition" } }};
    var step = bare_step;
    step.parameters = &parameters;
    var binding: composition.Initialize = .{ .allocator = std.testing.allocator };
    _ = try composition.Initialize.invoke(&binding, stepInput(&step, .{}, &resources));
}

fn compositionRetainsAbsentValue() anyerror!void {
    const none: data.View = .{};
    _ = try composition.Owner.create(std.testing.allocator, &none, &.{.json_composition});
}

fn rejectedDecodeWithoutDiagnostic() anyerror!void {
    // A decoder that failed names its failure; one that does not is no evidence of a rejected response.
    const none: data.View = .{};
    _ = try model_envelope.capture(std.testing.allocator, &none, error.InvalidModelEnvelope, null);
}

fn transitionNotInvoked() anyerror!void {
    var binding: provider_lifecycle.Advance = .{};
    _ = try provider_lifecycle.Advance.invoke(&binding, stepInput(&bare_step, .{}, &.{}));
}

fn policyNotBound() anyerror!void {
    var binding: required_authority.SourcePreservationPolicy = .{ .allocator = std.testing.allocator };
    _ = try required_authority.SourcePreservationPolicy.invoke(&binding, stepInput(&bare_step, .{}, &.{}));
}

fn clarificationNotReady() anyerror!void {
    const clarifications = @import("domain/clarification_inputs.zig");
    const refreshed = @import("domain/clarification_refresh.zig");
    const captured = try values.create(std.testing.allocator, clarification_input.inputs_schema, clarifications.Inputs, .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} });
    defer values.destroy(captured);
    const state = try values.create(std.testing.allocator, clarification_refresh.state_schema, refreshed.Result, .{ .blocked = .authentication_required });
    defer values.destroy(state);
    var view: data.View = .{};
    view.slots[@intFromEnum(clarification_input.inputs_schema.key)] = captured;
    view.slots[@intFromEnum(clarification_refresh.state_schema.key)] = state;
    var binding: clarification_refresh.Render = .{ .allocator = std.testing.allocator };
    _ = try clarification_refresh.Render.invoke(&binding, stepInput(&bare_step, view, &.{}));
}

/// Feature logging is activated by a port the composition root binds; a step run with none bound stops
/// on its own cause and leaves the directory it was given as it was.
fn featureLoggingActivatorUnbound() anyerror!void {
    const prior_value: feature_directory.Directory = .{
        .selector = .{ .feature_id = .{ .bytes = "chosen" }, .project_relative_path = "specs/chosen" },
        .root_observation = .absent,
        .observation = .absent,
    };
    const prior = try values.create(std.testing.allocator, feature_directory_workflow.directory, feature_directory.Directory, prior_value);
    defer values.destroy(prior);
    var view: data.View = .{};
    view.slots[@intFromEnum(feature_directory_workflow.directory.key)] = prior;
    var binding: feature_logging.Activate = .{ .allocator = std.testing.allocator };
    const raised = feature_logging.Activate.invoke(&binding, stepInput(&bare_step, view, &.{}));
    try std.testing.expectEqualDeep(prior_value, (try values.read(&view, feature_directory_workflow.directory, feature_directory.Directory)).*);
    _ = try raised;
}

/// Each row raises its cause from the binding's own check: the binding runs unchanged against the smallest
/// input that makes the check fail.
const rows = [_]Row{
    .{ .cause = "CompositionResourceInvalid", .run = compositionWithoutResource },
    .{ .cause = "CompositionResourceInvalid", .run = compositionResourceOfAnotherKind },
    .{ .cause = "CompositionRetainedValueMissing", .run = compositionRetainsAbsentValue },
    .{ .cause = "ProtocolDiagnosticMissing", .run = rejectedDecodeWithoutDiagnostic },
    .{ .cause = "LifecycleTransitionInvalid", .run = transitionNotInvoked },
    .{ .cause = "RequiredAuthorityPolicyUnbound", .run = policyNotBound },
    .{ .cause = "ClarificationStateNotReady", .run = clarificationNotReady },
    .{ .cause = "FeatureLoggingActivatorUnbound", .run = featureLoggingActivatorUnbound },
};

test "each row raises the cause it names through the binding's own check" {
    for (rows) |row| {
        const raised = row.run();
        if (raised) |_| return error.CauseNotRaised else |err| try std.testing.expectEqualStrings(row.cause, @errorName(err));
    }
}

/// Causes a test in another file raises through the production check and asserts by name. This list is a
/// naming pin only: the pin below proves that the named file mentions the cause (as `error.<cause>` or as a
/// quoted name), not that a test asserts it. The rows above and `withheld_causes` are executable proof.
const asserted_elsewhere = [_]struct { cause: []const u8, file: []const u8 }{
    .{ .cause = "OperationWrongKind", .file = "src/repair_operations_test.zig" },
    .{ .cause = "InvocationArgumentsInvalid", .file = "src/repair_operations_test.zig" },
    .{ .cause = "KernelBindingNotInvocable", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "RequestStageStopped", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "HarnessFailureStopped", .file = "test/harness/e2e/trace.zig" },
    .{ .cause = "RepairOwnerMismatch", .file = "src/repair_operations_test.zig" },
    .{ .cause = "RepairOwnerUnresolved", .file = "src/repair_operations_test.zig" },
    .{ .cause = "LastRepairMissing", .file = "src/repair_operations_test.zig" },
    .{ .cause = "RepairStateMismatch", .file = "src/reference_reconciliation_test.zig" },
    .{ .cause = "GuidanceResourceInvalid", .file = "src/packet_guidance_test.zig" },
    .{ .cause = "CandidatePacketForeign", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "CandidateNotAdmitted", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "RequestDeclarationInvalid", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "RequestResourceMissing", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "RequestLedgerForeign", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "LifecycleEvidenceForeign", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "LifecycleStatusConflict", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "OperationOutcomeNotAdmitted", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "ObservationOutcomeMissing", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "ObservationLoggingBlocked", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "DecodeEvidenceInconsistent", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "ProtocolRetryNotApplicable", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "ProtocolPromptMissing", .file = "src/model_request_workflow_test.zig" },
    .{ .cause = "ReferenceStageMismatch", .file = "src/reference_extraction_test.zig" },
    .{ .cause = "ReconciliationPhaseInvalid", .file = "src/reference_reconciliation_test.zig" },
    .{ .cause = "ReconciliationSizeMissing", .file = "src/reference_reconciliation_test.zig" },
    .{ .cause = "PathTokenTextMissing", .file = "src/path_token_test.zig" },
};

/// The causes no offline test raises yet, because the check that names each one either needs state that no
/// fixture builds (a composition candidate, a specification or reference owner's own value, a repair
/// authorization with no permit) or is one the runner's own checks refuse first, and a binding's own
/// check of its input is reachable then only through a hand-built view. A cause leaves this list only
/// with the test that raises it.
const not_triggered = [_][]const u8{
    // Composition and request preparation
    "RequestCompositionConflict",
    "CompositionPartMissing",
    "CompositionStateMismatch",
    "CandidateOriginUnavailable",
    // Provider lifecycle
    "ProviderAuthorizationResultMissing",
    "LifecycleRecordMissing",
    "ObservationNotValidated",
    "RequestOutcomeNotTerminal",
    "PayloadCheckInconsistent",
    // Reference, specification and project bindings
    "ReferenceCandidateUnavailable",
    "ReferencePartUnavailable",
    "SpecificationBriefMissing",
    "ProjectAuthorityMissing",
    "SupportReviewStateInvalid",
    // Invocation and repair owners
    "InvocationFailureUnrecorded",
    "RepairPermitMissing",
    "RepairCandidateMissing",
};

const sets = .{ step_binding.RequestPreparation, step_binding.ProviderLifecycle, step_binding.StepBinding, step_binding.Invocation, repair_owner.Error };

fn isCause(name: []const u8) bool {
    inline for (sets) |Set| {
        inline for (@typeInfo(Set).error_set.?) |cause| {
            if (std.mem.eql(u8, cause.name, name)) return true;
        }
    }
    return false;
}

/// In how many lists the cause stands; the rows of one cause count once.
fn accounts(cause: []const u8) usize {
    var count: usize = 0;
    var in_rows = false;
    for (rows) |row| in_rows = in_rows or std.mem.eql(u8, row.cause, cause);
    count += @intFromBool(in_rows);
    for (request_workflow_tests.withheld_causes) |name| count += @intFromBool(std.mem.eql(u8, name, cause));
    for (asserted_elsewhere) |entry| count += @intFromBool(std.mem.eql(u8, entry.cause, cause));
    for (not_triggered) |name| count += @intFromBool(std.mem.eql(u8, name, cause));
    return count;
}

test "every binding failure cause is raised by a test or listed as not yet raised, exactly once" {
    inline for (sets) |Set| {
        inline for (@typeInfo(Set).error_set.?) |cause| {
            if (accounts(cause.name) != 1) std.debug.print("binding failure cause accounted {d} times: {s}\n", .{ accounts(cause.name), cause.name });
            try std.testing.expectEqual(@as(usize, 1), accounts(cause.name));
        }
    }
    // Nothing is listed that is no cause.
    for (rows) |row| try std.testing.expect(isCause(row.cause));
    for (request_workflow_tests.withheld_causes) |name| try std.testing.expect(isCause(name));
    for (asserted_elsewhere) |entry| try std.testing.expect(isCause(entry.cause));
    for (not_triggered) |name| try std.testing.expect(isCause(name));
}

test "a cause asserted in another file is named by that file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    for (asserted_elsewhere) |entry| {
        const source = try std.Io.Dir.cwd().readFileAlloc(io, entry.file, allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(source);
        var raised: [96]u8 = undefined;
        var named: [96]u8 = undefined;
        const as_error = try std.fmt.bufPrint(&raised, "error.{s}", .{entry.cause});
        const as_name = try std.fmt.bufPrint(&named, "\"{s}\"", .{entry.cause});
        try std.testing.expect(std.mem.indexOf(u8, source, as_error) != null or std.mem.indexOf(u8, source, as_name) != null);
    }
}
