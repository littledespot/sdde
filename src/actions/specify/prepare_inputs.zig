const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const feature = @import("../../domain/feature_directory.zig");
const identity = @import("../../domain/feature_identity.zig");
const path = @import("../../domain/relative_directory_path.zig");
const reference = @import("../../domain/reference_selector.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const state = @import("../../domain/specification_state.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const forms = @import("../../domain/clarification_form.zig");
const invocation_types = @import("../../domain/specify_invocation.zig");
const normalizer_port = @import("../../ports/unicode_normalizer.zig");
const feature_port = @import("../../ports/feature_directory_inspector.zig");
const reference_port = @import("../../ports/reference_directory_inspector.zig");
const state_port = @import("../../ports/workflow_state_source.zig");
const input_port = @import("../../ports/feature_input_source.zig");
const parser_port = @import("../../ports/clarification_input_parser.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum {
    normalize_feature,
    validate_feature,
    inspect_feature,
    normalize_reference,
    validate_reference,
    inspect_reference,
    resolve_paths,
    capture_state,
    parse_state,
    capture_clarifications,
    parse_clarification_state,
    validate_clarification_state,
    validate_clarification_forms,
};

/// Stage-owned diagnostic slot: the step a failing run stopped at, or the step a cancelled run
/// did not start. The binding hands it to the runner (ADR 0031).
pub const Diagnostic = struct { step: ?Step = null };

/// The failure representation of the thirteen absorbed actions, unchanged. `Cancelled` means the
/// runtime stopped being active; the runner reports which stop it was.
pub const Error = normalizer_port.Error || feature.Error || feature_port.Error || reference.Error ||
    reference_port.Error || artifacts.FeaturePathError || state_port.Error || state.Error ||
    input_port.Error || clarification.Error || error{Cancelled};

/// What crosses the stage edge. Everything is allocated from the scratch allocator except `prior`,
/// which owns its data in the retained allocator.
pub const Outputs = struct {
    feature: feature.Directory,
    selector: feature.Selector,
    reference: reference.Directory,
    paths: artifacts.FeaturePaths,
    captures: clarification.Captures,
    inputs: clarification.Inputs,
    prior: state.Prior,
};

/// One stage: validate the invocation's feature directory and reference selector, inspect both,
/// resolve the feature's artifact paths, then read and validate the prior specification state and
/// the clarification inputs. Its steps route no outcome of their own: each success continues to
/// the next and every failure ends the stage.
pub const Action = struct {
    normalizer: normalizer_port.Normalizer,
    feature_roots: ?feature.Roots = null,
    artifact_roots: ?artifacts.FeatureRoots = null,
    feature_inspector: feature_port.Inspector,
    reference_inspector: reference_port.Inspector,
    state_source: ?state_port.Capturer = null,
    contracts: ?state.ContractSource = null,
    input_source: input_port.Capturer,
    state_parser: parser_port.StateParser,
    form_parser: parser_port.FormParser,
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-inputs",
        .kind = .action,
        .requires = &.{.specify_invocation},
        .produces = &.{ .feature_directory, .relative_feature_directory, .reference_directory, .feature_artifact_paths, .prior_specification_state, .prior_principle_registry, .raw_clarification_inputs, .clarification_inputs },
        .side_effect = .filesystem_read,
    };

    /// Intermediates and the edge values live in `scratch`; the prior state and the bytes it was
    /// parsed from live in `retained`.
    pub fn execute(self: Action, scratch: std.mem.Allocator, retained: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, invocation: invocation_types.Invocation) Error!Outputs {
        const feature_candidate = steps.normalizeFeature(self.normalizer, scratch, invocation) catch |err| return stopped(diagnostic, .normalize_feature, err);
        try checkpoint(diagnostic, runtime, .validate_feature);
        const selector = steps.validateFeature(scratch, feature_candidate, self.feature_roots) catch |err| return stopped(diagnostic, .validate_feature, err);
        try checkpoint(diagnostic, runtime, .inspect_feature);
        const observed = steps.inspectFeature(self.feature_inspector, scratch, selector) catch |err| return stopped(diagnostic, .inspect_feature, err);
        try checkpoint(diagnostic, runtime, .normalize_reference);
        const reference_candidate = steps.normalizeReference(self.normalizer, scratch, invocation) catch |err| return stopped(diagnostic, .normalize_reference, err);
        try checkpoint(diagnostic, runtime, .validate_reference);
        const reference_selector = steps.validateReference(reference_candidate) catch |err| return stopped(diagnostic, .validate_reference, err);
        try checkpoint(diagnostic, runtime, .inspect_reference);
        const reference_directory = steps.inspectReference(self.reference_inspector, scratch, reference_selector) catch |err| return stopped(diagnostic, .inspect_reference, err);
        try checkpoint(diagnostic, runtime, .resolve_paths);
        const paths = steps.resolvePaths(scratch, self.artifact_roots, observed) catch |err| return stopped(diagnostic, .resolve_paths, err);
        try checkpoint(diagnostic, runtime, .capture_state);
        const state_bytes = steps.captureState(self.state_source, retained, observed, paths) catch |err| return stopped(diagnostic, .capture_state, err);
        try checkpoint(diagnostic, runtime, .parse_state);
        const prior = steps.parseState(retained, self.contracts, observed.selector.feature_id, state_bytes) catch |err| return stopped(diagnostic, .parse_state, err);
        try checkpoint(diagnostic, runtime, .capture_clarifications);
        const captures = steps.captureClarifications(self.input_source, scratch, observed, paths) catch |err| return stopped(diagnostic, .capture_clarifications, err);
        try checkpoint(diagnostic, runtime, .parse_clarification_state);
        const parsed = steps.parseClarificationState(self.state_parser, scratch, captures) catch |err| return stopped(diagnostic, .parse_clarification_state, err);
        try checkpoint(diagnostic, runtime, .validate_clarification_state);
        const validated = steps.validateClarificationState(parsed, paths.feature.feature_id) catch |err| return stopped(diagnostic, .validate_clarification_state, err);
        try checkpoint(diagnostic, runtime, .validate_clarification_forms);
        const inputs = steps.validateClarificationForms(self.form_parser, scratch, validated, captures) catch |err| return stopped(diagnostic, .validate_clarification_forms, err);
        return .{ .feature = observed, .selector = selector, .reference = reference_directory, .paths = paths, .captures = captures, .inputs = inputs, .prior = prior };
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The thirteen internal steps. Each is one typed function with its own tests; none is
/// registered, addressable or composable from workflow YAML. A step that reaches a port takes
/// exactly that port, never the `Action`, and a step that reads does not parse.
pub const steps = struct {
    pub fn normalizeFeature(normalizer: normalizer_port.Normalizer, allocator: std.mem.Allocator, invocation: invocation_types.Invocation) normalizer_port.Error!feature.NormalizedCandidate {
        const nfc = try normalizer.nfc(allocator, invocation.raw_feature, path.max_bytes);
        defer allocator.free(nfc);
        return .{ .bytes = try path.normalize(allocator, nfc) };
    }

    pub fn validateFeature(allocator: std.mem.Allocator, candidate: feature.NormalizedCandidate, roots: ?feature.Roots) feature.Error!feature.Selector {
        return feature.validate(allocator, candidate, roots orelse return error.InvalidFeatureDirectory);
    }

    pub fn inspectFeature(inspector: feature_port.Inspector, allocator: std.mem.Allocator, selector: feature.Selector) feature_port.Error!feature.Directory {
        return inspector.inspect(allocator, selector);
    }

    pub fn normalizeReference(normalizer: normalizer_port.Normalizer, allocator: std.mem.Allocator, invocation: invocation_types.Invocation) normalizer_port.Error!reference.NormalizedCandidate {
        const nfc = try normalizer.nfc(allocator, invocation.raw_reference, reference.max_bytes);
        defer allocator.free(nfc);
        return .{ .bytes = try path.normalize(allocator, nfc) };
    }

    pub fn validateReference(candidate: reference.NormalizedCandidate) reference.Error!reference.RelativeSelector {
        return reference.validate(candidate);
    }

    pub fn inspectReference(inspector: reference_port.Inspector, allocator: std.mem.Allocator, selector: reference.RelativeSelector) reference_port.Error!reference.Directory {
        return inspector.inspect(allocator, selector);
    }

    pub fn resolvePaths(allocator: std.mem.Allocator, roots: ?artifacts.FeatureRoots, selected: feature.Directory) artifacts.FeaturePathError!artifacts.FeaturePaths {
        return artifacts.resolveFeaturePaths(allocator, roots orelse return error.InvalidFeatureArtifactPath, selected.selector);
    }

    /// Reads the state file's bytes, or reports it absent; it never parses them.
    pub fn captureState(source: ?state_port.Capturer, allocator: std.mem.Allocator, selected: feature.Directory, paths: artifacts.FeaturePaths) state_port.Error!?[]const u8 {
        return (source orelse return error.FeatureInputUnavailable).capture(allocator, selected, paths);
    }

    pub fn parseState(allocator: std.mem.Allocator, contracts: ?state.ContractSource, selected: identity.FeatureId, bytes: ?[]const u8) state.Error!state.Prior {
        return state.parse(allocator, bytes, selected, contracts);
    }

    pub fn captureClarifications(source: input_port.Capturer, allocator: std.mem.Allocator, observed: feature.Directory, paths: artifacts.FeaturePaths) input_port.Error!clarification.Captures {
        return source.capture(allocator, observed, paths);
    }

    pub fn parseClarificationState(parser: parser_port.StateParser, allocator: std.mem.Allocator, captured: clarification.Captures) clarification.Error!clarification.ParsedState {
        return .{ .value = if (captured.state) |bytes| try parser.parse(allocator, bytes) else null };
    }

    pub fn validateClarificationState(parsed: clarification.ParsedState, selected: identity.FeatureId) clarification.Error!clarification.ValidatedState {
        return clarification.validate(parsed, selected);
    }

    pub fn validateClarificationForms(parser: parser_port.FormParser, allocator: std.mem.Allocator, validated: clarification.ValidatedState, captured: clarification.Captures) clarification.Error!clarification.Inputs {
        const registry = validated.value orelse {
            if (captured.forms.len != 0) return error.InvalidClarificationInput;
            return .{ .state = validated, .submissions = &.{}, .protected_forms = &.{} };
        };
        if (captured.forms.len != registry.records.len) return error.InvalidClarificationInput;
        var submissions: std.ArrayList(clarification.Submission) = .empty;
        errdefer submissions.deinit(allocator);
        var protected: std.ArrayList(clarification.FormCapture) = .empty;
        errdefer protected.deinit(allocator);
        for (registry.records, captured.forms) |record, capture| {
            const id = clarification.Id.parse(record.id).?;
            if (capture.id.index() != id.index()) return error.InvalidClarificationInput;
            var binding: forms.Binding = .{ .state_ordinal = registry.state_ordinal, .state_revision = registry.revision, .record_revision = record.revision, .status = record.status };
            if (record.status == .resolved_by_authority) {
                const expected = try forms.renderAuthorityAudit(allocator, record, registry);
                defer allocator.free(expected);
                if (!std.mem.eql(u8, expected, capture.bytes)) return error.InvalidClarificationInput;
                continue;
            }
            const response = if (record.response_id) |response_id| clarification.findResponse(registry, response_id).? else null;
            if (response) |saved| {
                if (!std.mem.eql(u8, saved.submitted_form_bytes, capture.bytes)) return error.InvalidClarificationInput;
                binding = .{ .state_ordinal = saved.input_state_ordinal, .state_revision = saved.input_state_revision, .record_revision = saved.input_record_revision, .status = .open };
            }
            const submitted = try parser.parse(allocator, capture.bytes, record, binding);
            if (response) |saved| {
                if (!sameAnswer(saved.answer, submitted.answer) or
                    (record.status == .resolved_by_user and submitted.requested_status != .closed) or
                    (record.status == .cancelled_by_user and submitted.requested_status != .cancel)) return error.InvalidClarificationInput;
            }
            if (submitted.requested_status == .closed) try protected.append(allocator, capture);
            try submissions.append(allocator, .{
                .id = id,
                .subject = record.subject,
                .authority = record.authority,
                .requested_status = submitted.requested_status,
                .answer = submitted.answer,
                .origin = if (response != null) .recorded else .submitted,
            });
        }
        const owned = try submissions.toOwnedSlice(allocator);
        errdefer allocator.free(owned);
        return .{ .state = validated, .submissions = owned, .protected_forms = try protected.toOwnedSlice(allocator) };
    }
};

fn sameAnswer(left: clarification.Answer, right: clarification.Answer) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .none => true,
        .business_text => |text| std.mem.eql(u8, text, right.business_text),
        .selected_option => |key| std.mem.eql(u8, key, right.selected_option),
        .defer_reason => |reason| std.mem.eql(u8, reason, right.defer_reason),
        .cancel_reason => |reason| std.mem.eql(u8, reason, right.cancel_reason),
        .selected_options => |keys| blk: {
            if (keys.len != right.selected_options.len) break :blk false;
            for (keys, right.selected_options) |a, b| if (!std.mem.eql(u8, a, b)) break :blk false;
            break :blk true;
        },
    };
}
