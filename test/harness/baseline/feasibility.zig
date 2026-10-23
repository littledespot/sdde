//! Offline budget planning from retained native exchanges. This module cannot
//! dispatch, change a workflow budget, amend a contract, or authorize a run.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const contracts = @import("../contracts.zig");
const native = @import("../e2e/contracts.zig");
const files = @import("../files.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const provenance = @import("../../../build/provenance.zig");

pub const Phase = enum { baseline, selection, qualification };
pub const UserDecision = union(enum) {
    unresolved,
    /// A recorded user decision to retain the declared scope and existing
    /// compiled policy. This cannot approve a larger production budget.
    retain_existing_scope: struct { record: []const u8 },
};
pub const BudgetPlan = struct {
    schema: enum { @"baseline-budget-plan/v1" },
    phases: []const Phase,
    workflow_token_budget: u64,
    maximum_sends: u64,
    maximum_actual_tokens: u64,
    projection: enum { worst_observed_workflow },
    decision: UserDecision,
    /// Explicit native E2E run directories, never hand-entered usage estimates.
    evidence_runs: []const []const u8,
};
pub const Evidence = struct {
    directory: []const u8,
    report_sha256: []const u8,
    inputs_sha256: []const u8,
    build: provenance.Identity,
    case_id: []const u8,
    execution_id: []const u8,
    sends: u64,
    actual_tokens: ?u64,
    known_actual_tokens: u64,
    usage_complete: bool,
    completed_workflow: bool,
    completed_product_flow: bool,
    budget_exhausted: bool,
    observed_workflow_budget: ?u64,
    /// Failed/blocked workflows retain their whole observed chain, including
    /// review and repair; their cost is a lower bound on completion cost.
    cost_extent: enum { complete, stopped_lower_bound },
};
pub const Coverage = struct { phase: Phase, acquisition_scope: enum { full_workflow } = .full_workflow, minimum_workloads: u64, maximum_workloads: u64 };
pub const Reason = enum {
    unresolved_user_decision,
    uncommitted_baseline,
    no_usage_evidence,
    incomplete_usage,
    no_complete_product_flow_evidence,
    workflow_budget_unconfirmed,
    observed_workflow_budget_exhaustion,
    compiled_workflow_budget_mismatch,
    projected_send_budget_exceeded,
    projected_token_budget_exceeded,
};
pub const Report = struct {
    schema: enum { @"baseline-budget-feasibility/v1" },
    status: enum { feasible, infeasible, insufficient },
    projection: enum { worst_observed_workflow } = .worst_observed_workflow,
    /// Costs from different historical builds inform planning only. They never
    /// form the committed baseline or semantic-quality evidence.
    evidence_role: enum { diagnostic_cost_planning } = .diagnostic_cost_planning,
    plan: BudgetPlan,
    baseline_build: provenance.Identity,
    compiled_workflow_budget: u64,
    phases: []const Coverage,
    evidence: []const Evidence,
    minimum_workloads: u64,
    maximum_workloads: u64,
    worst_observed_sends: ?u64,
    worst_observed_tokens: ?u64,
    projected_minimum_sends: ?u64,
    projected_maximum_sends: ?u64,
    projected_minimum_tokens: ?u64,
    projected_maximum_tokens: ?u64,
    reasons: []const Reason,
    user_decision_required: bool,
    workflow_authority: bool = false,
};

pub fn parse(a: std.mem.Allocator, bytes: []const u8) !BudgetPlan {
    const plan = try contracts.decode(BudgetPlan, a, bytes);
    try validate(plan);
    return plan;
}
pub fn validate(plan: BudgetPlan) !void {
    if (plan.workflow_token_budget == 0 or plan.maximum_sends == 0 or plan.maximum_actual_tokens == 0 or plan.phases.len == 0) return error.InvalidBudgetPlan;
    var baseline = false;
    for (plan.phases, 0..) |phase, index| {
        if (phase == .baseline) baseline = true;
        for (plan.phases[0..index]) |prior| if (prior == phase) return error.InvalidBudgetPlan;
    }
    if (!baseline) return error.InvalidBudgetPlan;
    if (plan.decision == .retain_existing_scope and !contracts.text(plan.decision.retain_existing_scope.record)) return error.InvalidBudgetPlan;
    for (plan.evidence_runs, 0..) |path, index| {
        try contracts.path(path);
        for (plan.evidence_runs[0..index]) |prior| if (std.mem.eql(u8, prior, path)) return error.InvalidBudgetPlan;
    }
}

/// Caller supplies the actual budget from its validated compiled native graph.
/// Every retained value uses the caller's arena. No credentials are consulted.
pub fn evaluate(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, plan: BudgetPlan, protocol: comparison.Protocol, baseline_build: provenance.Identity, compiled_workflow_budget: u64) !Report {
    try validate(plan);
    try comparison.validateProtocol(protocol);
    if (compiled_workflow_budget == 0 or plan.maximum_sends != protocol.limits.maximum_sends or plan.maximum_actual_tokens != protocol.limits.maximum_actual_tokens) return error.InvalidBudgetPlan;
    const evidence = try a.alloc(Evidence, plan.evidence_runs.len);
    for (plan.evidence_runs, evidence) |path, *item| item.* = try readEvidence(io, a, repository, path, protocol);
    return summarize(a, plan, protocol, baseline_build, compiled_workflow_budget, evidence);
}

fn hash(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}
fn sameJson(comptime T: type, a: std.mem.Allocator, left: T, right: T) !bool {
    return std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}
fn readEvidence(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, path: []const u8, protocol: comparison.Protocol) !Evidence {
    const run = try directories.open(io, repository, path);
    defer run.close(io);
    const report_bytes = try files.read(io, a, run, "report.json");
    const report = @import("../../../src/domain/strict_json.zig").decode(native.Report, a, report_bytes, .{ .maximum_depth = 128 }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBudgetEvidence,
    };
    if (report.schema != .@"spec-e2e-report/v9" or report.origin != .live or report.build == null or report.evidence_error != null or
        report.case_id == null or report.execution_id == null or report.workflow_id == null or report.model_calls == 0 or report.attempts.len != report.model_calls) return error.InvalidBudgetEvidence;
    const source = report.build.?;
    if (source.reconstruction != .captured or source.inputs_file == null) return error.InvalidBudgetEvidence;
    const build_bytes = try files.read(io, a, run, source.inputs_file.?);
    const bundle = try contracts.decode(provenance.Bundle, a, build_bytes);
    if (!std.mem.eql(u8, bundle.schema, "build-inputs/v1") or !bundle.complete or !try sameJson(provenance.Identity, a, source.source, bundle.identity)) return error.InvalidBudgetEvidence;
    const selected = try native.parse(a, try files.read(io, a, run, "case.json"));
    if (!std.mem.eql(u8, selected.id, report.case_id.?) or !std.mem.eql(u8, selected.workflow_id, report.workflow_id.?)) return error.InvalidBudgetEvidence;
    const input_bytes = try files.read(io, a, run, "inputs.json");
    const input = try contracts.decode(@import("../e2e/fixture.zig").Capture, a, input_bytes);
    try @import("../compatibility/cli.zig").preflight(a, input.config);
    var expected_config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, input.config);
    defer expected_config.deinit();
    if (!std.mem.eql(u8, input.config_source, selected.config) or !std.mem.eql(u8, input.evaluation.case_source, selected.evaluation_case) or
        input.files.len != selected.files.len or
        !try sameJson([]const []const u8, a, input.directories, selected.directories)) return error.InvalidBudgetEvidence;
    for (input.files, selected.files) |file, mapping| if (!std.mem.eql(u8, file.mapping.source, mapping.source) or !std.mem.eql(u8, file.mapping.destination, mapping.destination)) return error.InvalidBudgetEvidence;
    const project = try directories.open(io, run, "project");
    defer project.close(io);
    if (!std.mem.eql(u8, input.config, try files.read(io, a, project, ".sddtoolkit.json"))) return error.InvalidBudgetEvidence;
    for (input.files) |file| {
        try contracts.path(file.mapping.destination);
        if (!std.mem.eql(u8, file.bytes, try files.read(io, a, project, file.mapping.destination))) return error.InvalidBudgetEvidence;
    }
    var tokens: u64 = 0;
    var usage_complete = report.usage_complete;
    const captured_attempts = try capturedAttempts(a, report);
    for (captured_attempts) |captured| {
        if (try callTokens(io, a, repository, run, path, selected.workflow_id, captured.ordinal, protocol, captured.attempt, &expected_config.value().models)) |actual| {
            tokens = std.math.add(u64, tokens, actual) catch return error.InvalidBudgetEvidence;
        } else usage_complete = false;
    }
    if (usage_complete and report.total_tokens != tokens) return error.InvalidBudgetEvidence;
    if (report.token_accounting) |snapshot| {
        if (!snapshot.total_budget.isValid() or snapshot.total_tokens != report.total_tokens or
            snapshot.usage_unavailable == report.usage_complete) return error.InvalidBudgetEvidence;
        var actual: u128 = 0;
        for (report.attempts) |attempt| if (attempt.usage) |usage| {
            actual = std.math.add(u128, actual, usage.total_tokens) catch return error.InvalidBudgetEvidence;
        };
        if (actual != snapshot.total_tokens) return error.InvalidBudgetEvidence;
    }
    const completed = report.publication_check == .passed and (report.workflow_outcome == .ok or report.workflow_outcome == .needs_user);
    const budget_exhausted = if (report.terminal_rejection) |rejection| rejection.kind == .token_budget and rejection.detail != null and std.mem.eql(u8, rejection.detail.?, "WorkflowTokenBudgetExceeded") else false;
    return .{
        .directory = try a.dupe(u8, path),
        .report_sha256 = try hash(a, report_bytes),
        .inputs_sha256 = try hash(a, input_bytes),
        .build = source.source,
        .case_id = report.case_id.?,
        .execution_id = report.execution_id.?,
        .sends = std.math.cast(u64, captured_attempts.len) orelse return error.InvalidBudgetEvidence,
        .actual_tokens = if (usage_complete) tokens else null,
        .known_actual_tokens = tokens,
        .usage_complete = usage_complete,
        .completed_workflow = completed,
        .completed_product_flow = completed and report.workflow_outcome == .ok,
        .budget_exhausted = budget_exhausted,
        .observed_workflow_budget = if (report.token_accounting) |snapshot| snapshot.total_budget.value else null,
        .cost_extent = if (completed) .complete else .stopped_lower_bound,
    };
}

const CapturedAttempt = struct { ordinal: usize, attempt: native.Attempt };

/// Physical receipt ordinals and native origins are separate identities. Native
/// non-delivery may have no exchange; every other attempt requires its own one.
fn capturedAttempts(a: std.mem.Allocator, report: native.Report) ![]const CapturedAttempt {
    if (report.model_calls != report.attempts.len) return error.InvalidBudgetEvidence;
    const matched = try a.alloc(bool, report.attempts.len);
    defer a.free(matched);
    @memset(matched, false);
    const captured = try a.alloc(CapturedAttempt, report.admission_exchanges.len);
    errdefer a.free(captured);
    var not_sent: usize = 0;
    for (report.attempts, 0..) |attempt, index| {
        if (attempt.origin.kind != .inference or attempt.origin.request.value == 0 or attempt.origin.attempt.value == 0 or
            (attempt.accounting == .exact_usage) != (attempt.usage != null)) return error.InvalidBudgetEvidence;
        for (report.attempts[0..index]) |prior| if (std.meta.eql(prior.origin, attempt.origin)) return error.InvalidBudgetEvidence;
        if (@import("../e2e/observation.zig").provenNotSent(attempt)) not_sent += 1;
    }
    if (not_sent != report.not_sent_operations) return error.InvalidBudgetEvidence;
    for (report.admission_exchanges, captured, 0..) |exchange, *entry, index| {
        if (exchange.call != index + 1) return error.InvalidBudgetEvidence;
        const selected = for (report.attempts, 0..) |attempt, attempt_index| {
            if (std.meta.eql(attempt.origin, exchange.origin)) break attempt_index;
        } else return error.InvalidBudgetEvidence;
        if (matched[selected] or !std.meta.eql(exchange.usage, report.attempts[selected].usage)) return error.InvalidBudgetEvidence;
        matched[selected] = true;
        entry.* = .{ .ordinal = exchange.call, .attempt = report.attempts[selected] };
    }
    for (report.attempts, matched) |attempt, found| if (!found and !@import("../e2e/observation.zig").provenNotSent(attempt)) return error.InvalidBudgetEvidence;
    return captured;
}

fn callTokens(io: std.Io, allocator: std.mem.Allocator, repository: std.Io.Dir, run: std.Io.Dir, path: []const u8, workflow_id: []const u8, ordinal: usize, protocol: comparison.Protocol, attempt: native.Attempt, expected_models: *const @import("../../../src/domain/config.zig").ModelsConfig) !?u64 {
    // Archive/body values are scratch and never escape this iteration. Backing
    // storage follows the caller's allocator: an outer arena may retain chunks
    // until its own lifetime ends even after this scratch arena is deinitialized.
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    var captured = try @import("../call/capture.zig").load(io, a, repository, path, workflow_id, std.math.cast(u32, ordinal) orelse return error.InvalidBudgetEvidence);
    defer captured.deinit();
    const description = captured.call.description.?;
    const context = captured.context.common();
    // The loader matched the capture to this configuration; the frozen cohort is Bedrock.
    const region = switch (description.provider_config) {
        .aws_bedrock => |config| config.region,
        .empty_object, .anthropic => return error.InvalidBudgetEvidence,
    };
    const wire: @import("../../../src/adapters/provider/model_http_transport.zig").Request = .{ .target = .{ .aws_bedrock = .{ .region = region, .model = .{ .bytes = context.model } } }, .body = captured.call.request.?, .api_key = "", .deadline_monotonic_ms = 1 };
    try @import("../frozen_binding.zig").validateDescription(a, description, wire, expected_models);
    if (!std.mem.eql(u8, description.provider, protocol.provider) or !std.mem.eql(u8, description.model, protocol.model) or !std.mem.eql(u8, @tagName(region), protocol.region)) return error.InvalidBudgetEvidence;
    _ = try @import("../diagnostic_binding.zig").rebind(a, description, captured.provider_catalogue, description.model, description.reasoning_effort);
    if (!std.mem.eql(u8, try preparedWire(a, description), captured.call.request.?)) return error.InvalidBudgetEvidence;
    if (!std.meta.eql(attempt.origin, context.origin) or !std.mem.eql(u8, attempt.step, context.request_step)) return error.InvalidBudgetEvidence;
    const outcome_path = try @import("../evidence.zig").Store.path(a, .generation, ordinal, .outcome);
    const outcome = try contracts.decode(@import("../e2e/trace.zig").TransportOutcome, a, try files.read(io, a, run, outcome_path));
    const status: ?u16 = if (outcome == .received) outcome.received.status else null;
    if (captured.call.response_status != null and captured.call.response_status != status) return error.InvalidBudgetEvidence;
    if (@import("../e2e/observation.zig").provenNotSent(attempt)) {
        if (outcome != .failed or outcome.failed.delivery != .not_sent or captured.call.response != null) return error.InvalidBudgetEvidence;
        return 0;
    }
    const raw = captured.call.response;
    const actual = attempt.usage;
    if (attempt.accounting != .exact_usage and actual != null) return error.InvalidBudgetEvidence;
    if (raw == null or status != 200 or actual == null) {
        return null;
    }
    if (!std.mem.eql(u8, captured.call.response_encoding, "utf8") or captured.call.response_provenance == null or !std.mem.eql(u8, captured.call.response_provenance.?, "provider_body")) {
        return null;
    }
    const response_path = try @import("../evidence.zig").Store.path(a, .generation, ordinal, .response);
    if (!std.mem.eql(u8, raw.?, try files.read(io, a, run, response_path))) return error.InvalidBudgetEvidence;
    var parsed = try @import("../../../src/domain/strict_json.zig").parse(a, raw.?, .{ .maximum_depth = 128 }, false, null);
    defer parsed.deinit();
    var decoded = @import("../../../src/adapters/provider/bedrock_response.zig").decodeConverse(a, parsed.value, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            return null;
        },
    };
    defer decoded.deinit(a);
    if (!std.meta.eql(decoded.usage, actual.?)) return error.InvalidBudgetEvidence;
    return decoded.usage.total_tokens;
}

const Offline = struct {
    fn exchange(_: *@import("../../../src/adapters/provider/model_http_transport.zig").Context, _: std.mem.Allocator, _: @import("../../../src/adapters/provider/model_http_transport.zig").Request) @import("../../../src/adapters/provider/model_http_transport.zig").Error!@import("../../../src/adapters/provider/model_http_transport.zig").Response {
        return error.Cancelled;
    }
    fn now(_: *@import("../../../src/ports/provider_authorization_lease.zig").Context) error{ClockUnavailable}!u64 {
        return error.ClockUnavailable;
    }
};
fn preparedWire(a: std.mem.Allocator, description: @import("../../../src/domain/model_request_description.zig").Description) ![]const u8 {
    // Existing production serializer and selected-model contract own all body
    // fields. No transport or credentials are available to this offline check.
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const binding = @import("../diagnostic_binding.zig");
    var authority: binding.Authorization = .{ .binding = description };
    var offline: Offline = .{};
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var provider: @import("../../../src/adapters/provider/request_replay.zig").Adapter = .{
        .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = binding.Authorization.authorize },
        .environment = &environment,
        .transport = .{ .context = @ptrCast(&offline), .exchange_fn = Offline.exchange },
        .clock = .{ .context = @ptrCast(&offline), .now_fn = Offline.now },
        .compiler = parser.compiler(),
    };
    return provider.provider().prepare(a, description);
}

pub fn phaseWorkloads(protocol: comparison.Protocol, phase: Phase) !Coverage {
    const bounds: [2]u64 = switch (phase) {
        .baseline => .{ protocol.development_features, protocol.development_features },
        .selection => .{ try multiply(protocol.development_features, 2), try multiply(protocol.development_features, 2) },
        .qualification => .{ try multiply(protocol.qualification.minimum_features, 2), try multiply(protocol.qualification.maximum_features, 2) },
    };
    const variants_repetitions = try multiply(3, protocol.repetitions);
    return .{ .phase = phase, .minimum_workloads = try multiply(bounds[0], variants_repetitions), .maximum_workloads = try multiply(bounds[1], variants_repetitions) };
}

fn summarize(a: std.mem.Allocator, plan: BudgetPlan, protocol: comparison.Protocol, baseline_build: provenance.Identity, compiled_workflow_budget: u64, evidence: []const Evidence) !Report {
    const phases = try a.alloc(Coverage, plan.phases.len);
    var minimum_workloads: u64 = 0;
    var maximum_workloads: u64 = 0;
    for (plan.phases, phases) |phase, *coverage| {
        coverage.* = try phaseWorkloads(protocol, phase);
        minimum_workloads = try add(minimum_workloads, coverage.minimum_workloads);
        maximum_workloads = try add(maximum_workloads, coverage.maximum_workloads);
    }
    var reasons: std.ArrayList(Reason) = .empty;
    if (plan.decision == .unresolved) try reasons.append(a, .unresolved_user_decision);
    if (baseline_build.modified) try reasons.append(a, .uncommitted_baseline);
    if (plan.workflow_token_budget != compiled_workflow_budget) try reasons.append(a, .compiled_workflow_budget_mismatch);
    var completed: u32 = 0;
    var worst_sends: ?u64 = null;
    var worst_tokens: ?u64 = null;
    var incomplete_usage = false;
    var budget_unconfirmed = false;
    var budget_exhausted = false;
    for (evidence) |item| {
        worst_sends = @max(worst_sends orelse 0, item.sends);
        if (item.actual_tokens) |tokens| worst_tokens = @max(worst_tokens orelse 0, tokens);
        if (!item.usage_complete) incomplete_usage = true;
        if (item.completed_product_flow) completed += 1;
        if (item.observed_workflow_budget == null or item.observed_workflow_budget.? != compiled_workflow_budget) budget_unconfirmed = true;
        budget_exhausted = budget_exhausted or item.budget_exhausted;
    }
    if (evidence.len == 0) try reasons.append(a, .no_usage_evidence);
    if (incomplete_usage) try reasons.append(a, .incomplete_usage);
    if (completed == 0) try reasons.append(a, .no_complete_product_flow_evidence);
    if (budget_unconfirmed) try reasons.append(a, .workflow_budget_unconfirmed);
    if (budget_exhausted) try reasons.append(a, .observed_workflow_budget_exhaustion);
    const min_sends = if (worst_sends) |cost| try multiply(cost, minimum_workloads) else null;
    const max_sends = if (worst_sends) |cost| try multiply(cost, maximum_workloads) else null;
    const min_tokens = if (worst_tokens) |cost| try multiply(cost, minimum_workloads) else null;
    const max_tokens = if (worst_tokens) |cost| try multiply(cost, maximum_workloads) else null;
    const send_over = max_sends != null and max_sends.? > plan.maximum_sends;
    const token_over = max_tokens != null and max_tokens.? > plan.maximum_actual_tokens;
    if (send_over) try reasons.append(a, .projected_send_budget_exceeded);
    if (token_over) try reasons.append(a, .projected_token_budget_exceeded);
    // Stopped runs are diagnostic lower bounds, not evidence that every panel
    // feature has the same completion cost. They require investigation/decision
    // and cannot turn an outside-panel failure into an infeasible panel claim.
    const infeasible = completed != 0 and !incomplete_usage and (send_over or token_over or plan.workflow_token_budget != compiled_workflow_budget);
    return .{
        .schema = .@"baseline-budget-feasibility/v1",
        .status = if (infeasible) .infeasible else if (reasons.items.len != 0) .insufficient else .feasible,
        .plan = plan,
        .baseline_build = baseline_build,
        .compiled_workflow_budget = compiled_workflow_budget,
        .phases = phases,
        .evidence = evidence,
        .minimum_workloads = minimum_workloads,
        .maximum_workloads = maximum_workloads,
        .worst_observed_sends = worst_sends,
        .worst_observed_tokens = worst_tokens,
        .projected_minimum_sends = min_sends,
        .projected_maximum_sends = max_sends,
        .projected_minimum_tokens = min_tokens,
        .projected_maximum_tokens = max_tokens,
        .reasons = try reasons.toOwnedSlice(a),
        .user_decision_required = plan.decision == .unresolved or infeasible or budget_exhausted or plan.workflow_token_budget != compiled_workflow_budget,
    };
}
fn multiply(left: u64, right: u64) !u64 {
    return std.math.mul(u64, left, right) catch error.InvalidBudgetPlan;
}
fn add(left: u64, right: u64) !u64 {
    return std.math.add(u64, left, right) catch error.InvalidBudgetPlan;
}

fn testPlan() BudgetPlan {
    return .{ .schema = .@"baseline-budget-plan/v1", .phases = &.{.baseline}, .workflow_token_budget = 100000, .maximum_sends = 1000, .maximum_actual_tokens = 2000000, .projection = .worst_observed_workflow, .decision = .unresolved, .evidence_runs = &.{} };
}
fn testBuild(modified: bool) provenance.Identity {
    return .{ .revision = "5816d9bed631acabcb256025e911bb565b8f9771", .source_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", .modified = modified };
}
fn testEvidence(completed: bool) Evidence {
    return .{ .directory = "evidence/run", .report_sha256 = "report", .inputs_sha256 = "inputs", .build = testBuild(true), .case_id = "source-case", .execution_id = "source-run", .sends = 37, .actual_tokens = 101002, .known_actual_tokens = 101002, .usage_complete = true, .completed_workflow = completed, .completed_product_flow = completed, .budget_exhausted = !completed, .observed_workflow_budget = if (completed) 100000 else null, .cost_extent = if (completed) .complete else .stopped_lower_bound };
}
fn hasReason(report: Report, reason: Reason) bool {
    return std.mem.indexOfScalar(Reason, report.reasons, reason) != null;
}

test "budget plan is closed requires declared phase coverage and accepts no hand entered cost" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var plan = testPlan();
    const bytes = try std.json.Stringify.valueAlloc(a, plan, .{});
    _ = try parse(a, bytes);
    const invented_usage = try std.mem.replaceOwned(u8, a, bytes, "\"maximum_sends\":1000", "\"actual_tokens_per_workflow\":1,\"maximum_sends\":1000");
    try std.testing.expectError(error.InvalidEvaluationContract, parse(a, invented_usage));
    plan.phases = &.{.qualification};
    try std.testing.expectError(error.InvalidBudgetPlan, validate(plan));
    plan.phases = &.{ .baseline, .baseline };
    try std.testing.expectError(error.InvalidBudgetPlan, validate(plan));
    plan = testPlan();
    plan.evidence_runs = &.{"../outside"};
    try std.testing.expectError(error.InvalidEvaluationContract, validate(plan));
    plan = testPlan();
    plan.decision = .{ .retain_existing_scope = .{ .record = "" } };
    try std.testing.expectError(error.InvalidBudgetPlan, validate(plan));
}

test "budget feasibility derives complete frozen phase workloads without shrinking a panel" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    var plan = testPlan();
    plan.phases = &.{ .baseline, .selection, .qualification };
    const report = try summarize(a, plan, protocol, testBuild(true), 100000, &.{});
    try std.testing.expectEqual(.insufficient, report.status);
    try std.testing.expectEqual(@as(u64, 360), report.minimum_workloads);
    try std.testing.expectEqual(@as(u64, 504), report.maximum_workloads);
    try std.testing.expectEqual(@as(u64, 72), report.phases[0].minimum_workloads);
    try std.testing.expectEqual(@as(u64, 144), report.phases[1].minimum_workloads);
    try std.testing.expectEqual(@as(u64, 288), report.phases[2].maximum_workloads);
    try std.testing.expect(report.projected_minimum_tokens == null);
    try std.testing.expect(hasReason(report, .no_usage_evidence));
    try std.testing.expect(hasReason(report, .uncommitted_baseline));
    try std.testing.expect(report.user_decision_required and !report.workflow_authority);
}

test "budget stopped diagnostic costs remain lower bounds and cannot establish panel infeasibility" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    const report = try summarize(a, testPlan(), protocol, testBuild(true), 100000, &.{testEvidence(false)});
    try std.testing.expectEqual(.insufficient, report.status);
    try std.testing.expectEqual(@as(?u64, 7272144), report.projected_minimum_tokens);
    try std.testing.expectEqual(@as(?u64, 2664), report.projected_minimum_sends);
    try std.testing.expectEqual(.stopped_lower_bound, report.evidence[0].cost_extent);
    try std.testing.expect(hasReason(report, .projected_token_budget_exceeded));
    try std.testing.expect(hasReason(report, .observed_workflow_budget_exhaustion));
    try std.testing.expect(hasReason(report, .workflow_budget_unconfirmed));
    try std.testing.expect(hasReason(report, .no_complete_product_flow_evidence));
    try std.testing.expect(report.user_decision_required);
}

test "only complete known usage committed source and explicit existing scope can pass budget planning" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    var plan = testPlan();
    plan.decision = .{ .retain_existing_scope = .{ .record = "User retained this explicit phase scope and compiled budget before dispatch." } };
    var observed = testEvidence(true);
    observed.sends = 1;
    observed.actual_tokens = 500;
    observed.known_actual_tokens = 500;
    const sufficient = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.feasible, sufficient.status);
    try std.testing.expect(!sufficient.user_decision_required);
    observed.actual_tokens = 40000;
    observed.known_actual_tokens = 40000;
    const over = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.infeasible, over.status);
    try std.testing.expect(hasReason(over, .projected_token_budget_exceeded));
    observed.actual_tokens = null;
    observed.known_actual_tokens = 17;
    observed.usage_complete = false;
    const unknown = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.insufficient, unknown.status);
    try std.testing.expect(hasReason(unknown, .incomplete_usage));
    try std.testing.expect(unknown.worst_observed_tokens == null);
    // A supplied decision cannot raise the compiled production policy.
    plan.workflow_token_budget = 200000;
    const mismatch = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.insufficient, mismatch.status);
    try std.testing.expect(hasReason(mismatch, .compiled_workflow_budget_mismatch));
    try std.testing.expect(mismatch.user_decision_required);
}

test "global workflow budget overshoot retains full cost without establishing completion" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    var plan = testPlan();
    plan.decision = .{ .retain_existing_scope = .{ .record = "User retained the existing global workflow budget and experiment scope." } };
    var observed = testEvidence(false);
    observed.actual_tokens = 110000;
    observed.known_actual_tokens = 110000;
    observed.observed_workflow_budget = 100000;
    const report = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.insufficient, report.status);
    try std.testing.expect(hasReason(report, .observed_workflow_budget_exhaustion));
    try std.testing.expect(hasReason(report, .no_complete_product_flow_evidence));
    try std.testing.expect(hasReason(report, .projected_token_budget_exceeded));
    try std.testing.expect(!hasReason(report, .workflow_budget_unconfirmed));
    try std.testing.expectEqual(@as(?u64, 110000), report.worst_observed_tokens);
    try std.testing.expectEqual(@as(?u64, 7920000), report.projected_minimum_tokens);
    try std.testing.expect(report.user_decision_required);
    try std.testing.expectEqual(@as(?u64, 100000), report.evidence[0].observed_workflow_budget);
}

test "external budget evidence rejects unknown native report fields before any usage estimate" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "run", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "run/report.json", .data = "{\"started_at_utc\":\"test\",\"status\":\"workflow_failed\",\"invented_tokens\":1}" });
    var plan = testPlan();
    plan.evidence_runs = &.{"run"};
    try std.testing.expectError(error.InvalidBudgetEvidence, evaluate(std.testing.io, a, temporary.dir, plan, protocol, testBuild(false), 100000));
}

test "an early legitimate clarification cannot prove full product review and repair cost feasibility" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    var plan = testPlan();
    plan.decision = .{ .retain_existing_scope = .{ .record = "User retained existing explicit scope." } };
    var observed = testEvidence(true);
    observed.completed_product_flow = false;
    observed.sends = 1;
    observed.actual_tokens = 500;
    observed.known_actual_tokens = 500;
    const report = try summarize(a, plan, protocol, testBuild(false), 100000, &.{observed});
    try std.testing.expectEqual(.insufficient, report.status);
    try std.testing.expect(hasReason(report, .no_complete_product_flow_evidence));
    try std.testing.expect(report.evidence[0].completed_workflow);
    try std.testing.expect(!report.evidence[0].completed_product_flow);
}

test "budget usage proof binds actual wire controls to the canonical prepared request" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const description: @import("../../../src/domain/model_request_description.zig").Description = .{
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 } } },
        .model_slot = "generation",
        .workflow_id = "budget-example",
        .workflow_version = 1,
        .request_step = "request",
        .content = &.{.{ .user = "Retain the source behavior." }},
        .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
        .schema = "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}",
        .response_mode = .native_schema,
        .controls = .{ .temperature = .fixed },
        .reasoning_effort = "low",
        .operation_kind = .inference,
    };
    const original = try preparedWire(a, description);
    try std.testing.expect(std.mem.indexOf(u8, original, "\"temperature\":0.1") != null);
    const altered = try std.mem.replaceOwned(u8, a, original, "\"temperature\":0.1", "\"temperature\":0.2");
    try std.testing.expect(!std.mem.eql(u8, try preparedWire(a, description), altered));
    var wrong = description;
    wrong.protocol_prompt = "Unregistered protocol";
    try std.testing.expectError(error.InvalidReplay, preparedWire(a, wrong));
}

test "persisted feasibility report requires its explicit closed version" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    const report = try summarize(a, testPlan(), protocol, testBuild(true), 100000, &.{});
    const bytes = try std.json.Stringify.valueAlloc(a, report, .{});
    _ = try contracts.decode(Report, a, bytes);
    const missing = try std.mem.replaceOwned(u8, a, bytes, "\"schema\":\"baseline-budget-feasibility/v1\",", "");
    try std.testing.expect(!std.mem.eql(u8, bytes, missing));
    try std.testing.expectError(error.InvalidEvaluationContract, contracts.decode(Report, a, missing));
    const unknown = try std.mem.replaceOwned(u8, a, bytes, "baseline-budget-feasibility/v1", "baseline-budget-feasibility/v2");
    try std.testing.expectError(error.InvalidEvaluationContract, contracts.decode(Report, a, unknown));
}

test "budget evidence joins physical origins independently of native unsent operation positions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const unsent: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const second: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(4, 3, 7).?;
    const attempts = [_]native.Attempt{
        .{ .origin = second, .step = "later-required", .accounting = .exact_usage, .usage = usage },
        .{ .origin = unsent, .step = "advisory-stopped-before-send", .accounting = .not_sent, .usage = null },
        .{ .origin = first, .step = "first-required", .accounting = .exact_usage, .usage = usage },
    };
    const exchanges = [_]@import("admission.zig").Exchange{
        .{ .call = 1, .origin = first, .usage = usage },
        .{ .call = 2, .origin = second, .usage = usage },
    };
    const report: native.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-10-17T00:00:00Z", .status = .generated, .model_calls = 3, .not_sent_operations = 1, .total_tokens = 14, .attempts = &attempts, .admission_exchanges = &exchanges };
    const joined = try capturedAttempts(a, report);
    try std.testing.expectEqual(@as(usize, 2), joined.len);
    try std.testing.expectEqual(@as(usize, 1), joined[0].ordinal);
    try std.testing.expectEqualDeep(first, joined[0].attempt.origin);
    try std.testing.expectEqualDeep(second, joined[1].attempt.origin);
    var wrong = report;
    wrong.admission_exchanges = exchanges[0..1];
    try std.testing.expectError(error.InvalidBudgetEvidence, capturedAttempts(a, wrong));
    var unknown = attempts;
    unknown[1].accounting = .unavailable;
    wrong = report;
    wrong.attempts = &unknown;
    wrong.not_sent_operations = 0;
    try std.testing.expectError(error.InvalidBudgetEvidence, capturedAttempts(a, wrong));
    var duplicate = exchanges;
    duplicate[1].origin = first;
    wrong = report;
    wrong.admission_exchanges = &duplicate;
    try std.testing.expectError(error.InvalidBudgetEvidence, capturedAttempts(a, wrong));
    duplicate = exchanges;
    duplicate[1].usage = null;
    wrong.admission_exchanges = &duplicate;
    try std.testing.expectError(error.InvalidBudgetEvidence, capturedAttempts(a, wrong));
    wrong = report;
    wrong.not_sent_operations = 0;
    try std.testing.expectError(error.InvalidBudgetEvidence, capturedAttempts(a, wrong));
}
