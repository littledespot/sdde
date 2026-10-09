//! Diagnostic reporting only; no pass threshold or workflow success rule.
const std = @import("std");
const c = @import("contracts.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const score = @import("score.zig");
pub const Trial = struct {
    case_id: []const u8,
    family: []const u8,
    split: @FieldType(c.Case, "split"),
    input_origin: std.meta.Tag(@FieldType(c.Case, "input")),
    repeat: u16,
    variant: enum { baseline, candidate },
    request: ?[]const u8 = null,
    guidance_bytes: usize,
    input_bytes: usize,
    schema_bytes: usize,
    request_bytes: ?usize = null,
    response_bytes: ?usize = null,
    validation: ?debug.Validation = null,
    outcome: ?score.Outcome = null,
    failure: ?[]const u8 = null,
    elapsed_ns: ?i96 = null,
};
pub const Totals = struct {
    declared_trials: u64 = 0,
    completed_replays: u64 = 0,
    operational_failures: u64 = 0,
    protocol_rejected: u64 = 0,
    native_rejected: u64 = 0,
    scored: u64 = 0,
    exact_semantic_cases: u64 = 0,
    required_roles: u64 = 0,
    missing_supported_roles: u64 = 0,
    assigned_pairs: u64 = 0,
    unsupported_pairs: u64 = 0,
    wrong_basis_pairs: u64 = 0,
    normalized_responses: u64 = 0,
    observed_input_tokens: u64 = 0,
    observed_output_tokens: u64 = 0,
    trials_with_usage: u64 = 0,
};
pub fn totals(trials: []const Trial) [2]Totals {
    var result: [2]Totals = .{ .{}, .{} };
    for (trials) |trial| {
        const total = &result[@intFromEnum(trial.variant)];
        total.declared_trials += 1;
        if (trial.failure != null) total.operational_failures += 1;
        if (trial.validation) |validation| {
            total.completed_replays += 1;
            if (validation.normalization != .none) total.normalized_responses += 1;
            if (validation.input_tokens != null and validation.output_tokens != null) total.trials_with_usage += 1;
            total.observed_input_tokens += validation.input_tokens orelse 0;
            total.observed_output_tokens += validation.output_tokens orelse 0;
        }
        if (trial.outcome) |outcome| switch (outcome) {
            .protocol_rejected => total.protocol_rejected += 1,
            .native_rejected => total.native_rejected += 1,
            .scored => |counts| {
                total.scored += 1;
                total.required_roles += counts.required_roles;
                total.missing_supported_roles += counts.missing_supported_roles;
                total.assigned_pairs += counts.assigned_pairs;
                total.unsupported_pairs += counts.unsupported_pairs;
                total.wrong_basis_pairs += counts.wrong_basis_pairs;
                if (counts.missing_supported_roles == 0 and counts.unsupported_pairs == 0) total.exact_semantic_cases += 1;
            },
        };
    }
    return result;
}
pub fn markdown(a: std.mem.Allocator, live: bool, reviewed: bool, trials: []const Trial) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    const w = &out.writer;
    try w.print("# Authoring-role calibration\n\nMode: {s}. Labels: {s}. No quality pass threshold is assigned.\n\n", .{ if (live) "live diagnostic" else "offline preparation; no semantic outcomes", if (reviewed) "human-reviewed" else "proposed" });
    try w.writeAll("Semantic counts below are conditional on protocol and native admission. Unusable answers remain in the declared trial denominator. Required-role omissions and unsupported signal/role pairs are separate measures. Wrong-basis pairs are the subset of unsupported pairs whose role has at least one labelled allowed group; assignments to roles with empty allowed sets remain unsupported without a wrong-basis count. A wrong-basis assignment can also leave a required role missing. Optional labels permit ambiguity. Repeats from one source family are correlated; these counts do not establish statistical reliability. Correction and repair are not run.\n\n");
    try w.writeAll("| Variant | Trials | Scored | Protocol rejected | Native rejected | Operational failures | Missing / required roles | Unsupported / assigned pairs | Wrong-basis / unsupported pairs | Exact semantic cases |\n| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n");
    for (totals(trials), 0..) |value, index| {
        if (value.declared_trials == 0) continue;
        try w.print("| {s} | {d} | {d} | {d} | {d} | {d} | {d}/{d} | {d}/{d} | {d}/{d} | {d} |\n", .{ if (index == 0) "baseline" else "candidate", value.declared_trials, value.scored, value.protocol_rejected, value.native_rejected, value.operational_failures, value.missing_supported_roles, value.required_roles, value.unsupported_pairs, value.assigned_pairs, value.wrong_basis_pairs, value.unsupported_pairs, value.exact_semantic_cases });
    }
    try w.writeAll("\n");
    for (totals(trials), 0..) |value, index| {
        if (value.declared_trials == 0) continue;
        try w.print("{s}: observed tokens {d} in / {d} out, complete usage in {d}/{d} trials; {d} normalized responses. Missing usage is unknown, not zero cost.\n\n", .{ if (index == 0) "Baseline" else "Candidate", value.observed_input_tokens, value.observed_output_tokens, value.trials_with_usage, value.declared_trials, value.normalized_responses });
    }
    try w.writeAll("| Case | Origin | Repeat | Variant | Outcome | Missing roles | Unsupported pairs | Wrong-basis pairs |\n| --- | --- | ---: | --- | --- | ---: | ---: | ---: |\n");
    for (trials) |trial| {
        const counts: score.Counts = if (trial.outcome != null and trial.outcome.? == .scored) trial.outcome.?.scored else .{};
        try w.print("| {s} | {s} | {d} | {s} | {s} | {d} | {d} | {d} |\n", .{ trial.case_id, @tagName(trial.input_origin), trial.repeat, @tagName(trial.variant), if (trial.failure != null) "operational_failure" else if (trial.outcome) |value| @tagName(value) else "not_run", counts.missing_supported_roles, counts.unsupported_pairs, counts.wrong_basis_pairs });
    }
    try w.writeAll("\nInspect paired rows and unchanged repeats before promoting guidance. JSON retains exact request IDs, byte contributions, provider usage/latency and measured replay duration; logs/debugger retains immutable requests and responses. Upstream controlled premises are constructed, not model extraction results. Captured premises retain upstream errors and require independent labels.\n");
    return out.toOwnedSlice();
}
