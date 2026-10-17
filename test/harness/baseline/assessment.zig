//! Evaluator-only bridge from supplied semantic judgments to comparison labels.
//! Native acquisitions own execution facts. Citations establish byte provenance,
//! not semantic truth, workflow validity, or publication authority.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const contracts = @import("../contracts.zig");
const reviews = @import("reviews.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
const upstream = @import("upstream.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidAssessment};
pub const Provenance = struct {
    kind: enum { human, model_assisted },
    assessor: []const u8,
};
pub const Output = struct {
    id: []const u8,
    /// Attempt one is an original response/uncorrected native projection,
    /// never a replacement/correction.
    attempt: u32,
    text: []const u8,
    sha256: []const u8,
};
/// Supplied by the native acquisition reader, never decoded from the assessor's
/// document. The digest binds all outputs, exact requests, frozen inputs and
/// execution records; this module additionally checks cited output byte hashes.
pub const Capture = struct {
    trial_ordinal: u32,
    case_id: []const u8,
    acquisition_sha256: []const u8,
    scope: enum { diagnostic, workflow },
    initial_status: comparison.Status,
    status: comparison.Status,
    initial_structural_valid: bool,
    structural_valid: bool,
    published: bool,
    corrective_sends: u32,
    physical_sends: u32,
    usage: ?comparison.Usage,
    elapsed_ns: ?u64,
    uncertain_delivery: bool,
    outputs: []const Output,
    /// Native semantic targets; assessors cannot omit inconvenient outputs or
    /// substitute a different response from the acquisition.
    initial_output_ids: []const []const u8,
    final_output_ids: []const []const u8,
    findings: []const CapturedFinding = &.{},
    review_coverage: []const ReviewCoverage = &.{},
    project_documents: []const ProjectDocument = &.{},
    final_content_valid: bool = false,
    /// Independently assessed native extraction/reconciliation assignments.
    /// These never substitute for original specification-generation labels.
    upstream_targets: []const upstream.Target = &.{},
};
pub const ProjectDocument = struct { path: []const u8, text: []const u8 };
pub const ProjectRef = struct { path: []const u8, quote: []const u8 };
pub const CapturedFinding = struct {
    native: reviews.Finding,
    output_id: ?[]const u8,
    purpose: @import("../../../src/domain/model_request_identity.zig").RequestPurposeKind,
    raw_verification: reviews.Verification,
};
pub const ReviewCoverage = struct { origin: Origin, output_id: ?[]const u8, review: ?reviews.Review, projected: bool, expected_findings: ?u32 = null };
pub const FindingJudgment = struct {
    ordinal: u32,
    origin: Origin,
    requirement: @import("../../../src/domain/required_authority.zig").Id,
    kind: reviews.Kind,
    expected_kind: reviews.Kind,
    correct: bool,
    provenance: Provenance,
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_refs: []const OutputRef,
    scoring_disputed: bool = false,
    project_refs: []const ProjectRef = &.{},
};
pub const FindingResult = struct {
    native: reviews.Finding,
    corrective: bool,
    correct: ?bool,
    expected_kind: ?reviews.Kind,
    provenance: ?Provenance,
    disputed: bool,
};
pub const OutputRef = struct { output_id: []const u8, quote: []const u8 };
pub const DutyLabel = struct {
    id: []const u8,
    preserved: bool,
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_refs: []const OutputRef,
};
pub const IssueKind = enum {
    unsupported_behavior,
    lost_restrictions,
    wrong_support,
    harmful_diagnoses,
    harmful_repairs,
    false_gaps,
};
pub const Issue = struct {
    id: []const u8,
    kind: IssueKind,
    count: u32,
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_refs: []const OutputRef,
};
pub const Labels = struct {
    /// Exact native response identities assessed together. Final selection can
    /// include corrections; original selection may include attempt one only.
    output_ids: []const []const u8,
    duties: []const DutyLabel,
    questions_correct: bool,
    question_evidence: ?QuestionEvidence = null,
    issues: []const Issue,
};
pub const QuestionEvidence = struct {
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_refs: []const OutputRef,
};
pub const Attribution = struct {
    stage: comparison.FailureStage,
    explanation: []const u8,
    source_refs: []const comparison.SourceRef,
    output_refs: []const OutputRef,
};
pub const Entry = struct {
    trial_ordinal: u32,
    acquisition_sha256: []const u8,
    provenance: Provenance,
    initial: ?Labels,
    final: ?Labels,
    scoring_disputed: bool,
    /// A supplied semantic attribution, independent of chronological trace
    /// terminal stage. Absence remains unknown rather than a guessed cause.
    attribution: ?Attribution,
    findings: []const FindingJudgment = &.{},
    /// Current content only; cumulative Labels.issues continue to retain every
    /// earlier harmful event even if a correction subsequently fixes the text.
    final_current_issues: ?[]const Issue = null,
    /// Evaluator-only judgment of the exact native published artifact against
    /// the rubric frozen before acquisition. It cannot authorize publication.
    published_rubric: ?@import("useful_completion.zig").Supplied = null,
    upstream: []const upstream.Judgment = &.{},
};
pub const Document = struct { schema: u32, entries: []const Entry };
pub const Evidence = enum { complete, incomplete, disputed, not_required };
pub const Result = struct {
    observation: comparison.Observation,
    evidence: Evidence,
    provenance: ?Provenance,
    findings: []const FindingResult,
    finding_evidence_complete: bool,
    final_current_fidelity: ?bool,
    upstream: upstream.Assessment,

    pub fn deinit(self: Result, a: std.mem.Allocator) void {
        a.free(self.observation.initial.duties);
        a.free(self.observation.duties);
        a.free(self.findings);
        self.upstream.deinit(a);
    }
};

/// Arena-owned closed decoding, including duplicate-key and unknown-field
/// rejection. Semantic/source/output validation follows once captures are read.
pub fn parse(a: std.mem.Allocator, bytes: []const u8) Error!Document {
    const document = contracts.decode(Document, a, bytes) catch |err| return map(err);
    if (document.schema != 2) return error.InvalidAssessment;
    for (document.entries, 0..) |entry, index| {
        try validateEntryIdentity(entry);
        for (document.entries[0..index]) |prior| {
            if (prior.trial_ordinal == entry.trial_ordinal) return error.InvalidAssessment;
        }
    }
    return document;
}

pub fn entryFor(document: Document, ordinal: u32) ?Entry {
    for (document.entries) |entry| if (entry.trial_ordinal == ordinal) return entry;
    return null;
}

/// Reject assessor entries that have no native trial/capture. Callers then
/// evaluate every planned trial, passing null for missing assessor entries.
pub fn validateAssociations(document: Document, captures: []const Capture) Error!void {
    if (document.schema != 2) return error.InvalidAssessment;
    for (captures, 0..) |capture, index| {
        for (captures[0..index]) |prior| if (prior.trial_ordinal == capture.trial_ordinal) return error.InvalidAssessment;
    }
    for (document.entries, 0..) |entry, index| {
        try validateEntryIdentity(entry);
        for (document.entries[0..index]) |prior| if (prior.trial_ordinal == entry.trial_ordinal) return error.InvalidAssessment;
        for (captures) |capture| {
            if (capture.trial_ordinal == entry.trial_ordinal) {
                if (!std.mem.eql(u8, entry.acquisition_sha256, capture.acquisition_sha256)) return error.InvalidAssessment;
                break;
            }
        } else return error.InvalidAssessment;
    }
}

pub fn evaluate(a: std.mem.Allocator, example: comparison.Case, capture: Capture, supplied: ?Entry) Error!Result {
    comparison.validateCase(example) catch |err| return map(err);
    try validateCapture(example, capture);
    if (supplied) |entry| {
        try validateEntryIdentity(entry);
        if (entry.trial_ordinal != capture.trial_ordinal or !std.mem.eql(u8, entry.acquisition_sha256, capture.acquisition_sha256)) return error.InvalidAssessment;
        if (capture.status == .unattempted) return error.InvalidAssessment;
        if (entry.initial) |labels| try validateLabels(example, capture, labels, true);
        if (entry.final) |labels| try validateLabels(example, capture, labels, false);
        if (entry.attribution) |attribution| {
            if (!contracts.text(attribution.explanation) or attribution.source_refs.len == 0) return error.InvalidAssessment;
            try validateSourceRefs(example, attribution.source_refs);
            try validateOutputRefs(capture, attribution.output_refs, null);
        }
        if (entry.initial != null and entry.final != null) try retainInitialIssues(entry.initial.?, entry.final.?);
        try validateFindingJudgments(example, capture, entry.findings);
        if (entry.final_current_issues) |issues| {
            try validateIssues(example, capture, issues, capture.final_output_ids);
            if (entry.final) |labels| try retainCurrentIssues(issues, labels.issues);
        }
    }
    const initial_labels: ?Labels = if (supplied) |entry| entry.initial else null;
    const final_labels: ?Labels = if (supplied) |entry| entry.final else null;
    const initial_complete = completeLabels(example, capture.initial_status, initial_labels);
    const final_complete = completeLabels(example, capture.status, final_labels);
    const disputed = if (supplied) |entry| entry.scoring_disputed else false;
    const required = capture.status != .unattempted;
    const upstream_assessment = upstream.evaluate(a, example, capture.upstream_targets, if (supplied) |entry| entry.upstream else &.{}) catch |err| return map(err);
    errdefer upstream_assessment.deinit(a);
    const finding_results = try projectFindings(a, capture, if (supplied) |entry| entry.findings else &.{});
    errdefer a.free(finding_results);
    if (supplied) |entry| if (entry.final) |labels| {
        if (!entry.scoring_disputed and completeLabels(example, capture.status, labels)) {
            var incorrect: u64 = 0;
            for (finding_results) |finding| if (finding.correct != null and !finding.correct.?) {
                incorrect += 1;
            };
            if ((try projectIssues(labels.issues)).harmful_diagnoses < incorrect) return error.InvalidAssessment;
        }
    };
    var findings_complete = true;
    for (capture.review_coverage) |coverage| if (!coverage.projected) {
        findings_complete = false;
    };
    for (finding_results) |finding| if (finding.correct == null) {
        findings_complete = false;
    };
    const candidate_complete = initial_complete and final_complete and supplied != null;
    const complete = candidate_complete and findings_complete and upstream_assessment.original_evidence_complete;
    var finding_disputed = false;
    for (finding_results) |finding| if (finding.disputed) {
        finding_disputed = true;
    };
    const initial_duties = try projectDuties(a, initial_labels);
    errdefer a.free(initial_duties);
    const final_duties = try projectDuties(a, final_labels);
    errdefer a.free(final_duties);
    const initial_issues = if (initial_labels) |labels| try projectIssues(labels.issues) else comparison.Issues{};
    const final_issues = if (final_labels) |labels| try projectIssues(labels.issues) else initial_issues;
    return .{
        .evidence = if (!required) .not_required else if (disputed or finding_disputed or upstream_assessment.original.disputed != 0) .disputed else if (!complete) .incomplete else .complete,
        .provenance = if (supplied) |entry| entry.provenance else null,
        .findings = finding_results,
        .finding_evidence_complete = findings_complete,
        .final_current_fidelity = currentFidelity(example, capture, supplied),
        .upstream = upstream_assessment,
        .observation = .{
            .trial_ordinal = capture.trial_ordinal,
            .initial = .{
                .status = capture.initial_status,
                .duties = initial_duties,
                .questions_correct = questionsCorrect(initial_labels),
                .structural_valid = capture.initial_structural_valid,
                .issues = initial_issues,
            },
            .status = capture.status,
            .duties = final_duties,
            .questions_correct = questionsCorrect(final_labels),
            .structural_valid = capture.structural_valid,
            .published = capture.published,
            .corrective_sends = capture.corrective_sends,
            .physical_sends = capture.physical_sends,
            .issues = final_issues,
            .usage = capture.usage,
            .elapsed_ns = capture.elapsed_ns,
            .uncertain_delivery = capture.uncertain_delivery,
            // Finding-type accuracy is a separate metric. Its missing labels
            // cannot erase independently supplied candidate-duty judgments.
            .scoring_disputed = required and (disputed or !candidate_complete),
            .initial_scoring_disputed = required and (disputed or !initial_complete),
            .failure_stage = if (supplied) |entry| if (entry.attribution) |attribution| attribution.stage else null else null,
        },
    };
}

fn validateEntryIdentity(entry: Entry) Error!void {
    if (!digest(entry.acquisition_sha256) or !contracts.id(entry.provenance.assessor)) return error.InvalidAssessment;
}
fn digest(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}
fn successful(status: comparison.Status) bool {
    return status == .completed or status == .clarification;
}
fn validateCapture(example: comparison.Case, capture: Capture) Error!void {
    if (!std.mem.eql(u8, example.id, capture.case_id) or !digest(capture.acquisition_sha256)) return error.InvalidAssessment;
    if (capture.status == .unattempted) {
        if (capture.initial_status != .unattempted or capture.outputs.len != 0 or capture.initial_output_ids.len != 0 or capture.final_output_ids.len != 0 or capture.findings.len != 0 or capture.review_coverage.len != 0 or capture.upstream_targets.len != 0 or capture.published or capture.initial_structural_valid or capture.structural_valid or
            capture.physical_sends != 0 or capture.corrective_sends != 0 or capture.usage != null or capture.elapsed_ns != null or capture.uncertain_delivery) return error.InvalidAssessment;
    } else {
        if (capture.initial_status == .unattempted or capture.physical_sends == 0 or capture.corrective_sends >= capture.physical_sends) return error.InvalidAssessment;
    }
    if ((capture.initial_structural_valid and !successful(capture.initial_status)) or (capture.structural_valid and !successful(capture.status))) return error.InvalidAssessment;
    if (capture.published and (capture.scope != .workflow or capture.status != .completed or !capture.structural_valid)) return error.InvalidAssessment;
    for (capture.outputs, 0..) |output, index| {
        // Raw model output can be empty or malformed candidate data. Retain its
        // exact UTF-8 bytes and hash; nonempty semantic citations are separate.
        if (!contracts.id(output.id) or output.attempt == 0 or !std.unicode.utf8ValidateSlice(output.text) or !digest(output.sha256)) return error.InvalidAssessment;
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(output.text, &hash, .{});
        const expected = std.fmt.bytesToHex(hash, .lower);
        if (!std.mem.eql(u8, &expected, output.sha256)) return error.InvalidAssessment;
        for (capture.outputs[0..index]) |prior| if (std.mem.eql(u8, output.id, prior.id)) return error.InvalidAssessment;
    }
    for (capture.upstream_targets) |target| if (target.output_id) |id| {
        const output = try outputFor(capture, id);
        if (target.text == null or target.sha256 == null or target.origin.attempt.value != output.attempt or
            !std.mem.eql(u8, target.text.?, output.text) or !std.mem.eql(u8, target.sha256.?, output.sha256)) return error.InvalidAssessment;
    };
    if (capture.final_content_valid and capture.final_output_ids.len == 0) return error.InvalidAssessment;
    for (capture.project_documents, 0..) |document, index| {
        contracts.path(document.path) catch return error.InvalidAssessment;
        if (!std.unicode.utf8ValidateSlice(document.text)) return error.InvalidAssessment;
        for (capture.project_documents[0..index]) |prior| if (std.mem.eql(u8, prior.path, document.path)) return error.InvalidAssessment;
    }
    for (capture.initial_output_ids, 0..) |id, index| {
        const output = try outputFor(capture, id);
        if (output.attempt != 1) return error.InvalidAssessment;
        if (selected(capture.initial_output_ids[0..index], id)) return error.InvalidAssessment;
    }
    for (capture.final_output_ids, 0..) |id, index| {
        _ = try outputFor(capture, id);
        if (selected(capture.final_output_ids[0..index], id)) return error.InvalidAssessment;
    }
    for (capture.review_coverage, 0..) |coverage, index| {
        if (coverage.origin.request.value == 0 or coverage.origin.attempt.value == 0 or (coverage.projected and (coverage.output_id == null or coverage.review == null))) return error.InvalidAssessment;
        if (coverage.output_id) |id| {
            const output = try outputFor(capture, id);
            if (output.attempt != coverage.origin.attempt.value) return error.InvalidAssessment;
        }
        for (capture.review_coverage[0..index]) |prior| if (std.meta.eql(prior.origin, coverage.origin)) return error.InvalidAssessment;
    }
    for (capture.findings, 0..) |finding, index| {
        if (finding.native.ordinal == 0 or finding.native.origin.request.value == 0 or finding.native.origin.attempt.value == 0) return error.InvalidAssessment;
        for (capture.findings[0..index]) |prior| if (prior.native.ordinal == finding.native.ordinal and std.meta.eql(prior.native.origin, finding.native.origin)) return error.InvalidAssessment;
        if (finding.output_id) |id| {
            const output = try outputFor(capture, id);
            if (output.attempt != finding.native.origin.attempt.value) return error.InvalidAssessment;
        }
        for (capture.review_coverage) |coverage| {
            if (std.meta.eql(coverage.origin, finding.native.origin)) {
                const review: reviews.Review = switch (finding.native.kind) {
                    .source => .source,
                    .principles => .principles,
                    .preservation => .preservation,
                };
                if (coverage.review == null or coverage.review.? != review) return error.InvalidAssessment;
                break;
            }
        } else return error.InvalidAssessment;
    }
}

fn capturedFinding(capture: Capture, ordinal: u32, origin: Origin) Error!CapturedFinding {
    for (capture.findings) |finding| if (finding.native.ordinal == ordinal and std.meta.eql(finding.native.origin, origin)) return finding;
    return error.InvalidAssessment;
}
fn validateFindingJudgments(example: comparison.Case, capture: Capture, judgments: []const FindingJudgment) Error!void {
    for (judgments, 0..) |judgment, index| {
        const finding = try capturedFinding(capture, judgment.ordinal, judgment.origin);
        if (!std.meta.eql(finding.native.kind, judgment.kind) or !std.meta.eql(finding.native.requirement, judgment.requirement) or
            !contracts.id(judgment.provenance.assessor) or !contracts.text(judgment.explanation) or judgment.source_refs.len == 0 or judgment.output_refs.len == 0) return error.InvalidAssessment;
        if (std.meta.activeTag(judgment.expected_kind) != std.meta.activeTag(judgment.kind) or judgment.correct != std.meta.eql(judgment.kind, judgment.expected_kind)) return error.InvalidAssessment;
        if (judgment.kind == .principles and judgment.project_refs.len == 0) return error.InvalidAssessment;
        for (judgment.project_refs, 0..) |reference, reference_index| {
            if (!contracts.text(reference.quote)) return error.InvalidAssessment;
            const document = for (capture.project_documents) |document| {
                if (std.mem.eql(u8, reference.path, document.path)) break document;
            } else return error.InvalidAssessment;
            if (std.mem.indexOf(u8, document.text, reference.quote) == null) return error.InvalidAssessment;
            for (judgment.project_refs[0..reference_index]) |prior| if (std.mem.eql(u8, prior.path, reference.path) and std.mem.eql(u8, prior.quote, reference.quote)) return error.InvalidAssessment;
        }
        const output_id = finding.output_id orelse return error.InvalidAssessment;
        var cites_finding = false;
        for (judgment.output_refs) |reference| if (std.mem.eql(u8, reference.output_id, output_id)) {
            cites_finding = true;
        };
        if (!cites_finding) return error.InvalidAssessment;
        for (judgments[0..index]) |prior| if (prior.ordinal == judgment.ordinal and std.meta.eql(prior.origin, judgment.origin)) return error.InvalidAssessment;
        try validateSourceRefs(example, judgment.source_refs);
        try validateOutputRefs(capture, judgment.output_refs, null);
    }
}
fn projectFindings(a: std.mem.Allocator, capture: Capture, judgments: []const FindingJudgment) Error![]const FindingResult {
    const result = try a.alloc(FindingResult, capture.findings.len);
    for (capture.findings, result) |finding, *projected| {
        projected.* = .{ .native = finding.native, .corrective = finding.native.origin.attempt.value > 1 or finding.purpose == .atomic_repair, .correct = null, .expected_kind = null, .provenance = null, .disputed = false };
        for (judgments) |judgment| if (judgment.ordinal == finding.native.ordinal and std.meta.eql(judgment.origin, finding.native.origin)) {
            projected.provenance = judgment.provenance;
            projected.disputed = judgment.scoring_disputed;
            if (!judgment.scoring_disputed and finding.raw_verification == .complete) {
                projected.correct = judgment.correct;
                projected.expected_kind = judgment.expected_kind;
            }
            break;
        };
    }
    return result;
}
fn outputFor(capture: Capture, id: []const u8) Error!Output {
    for (capture.outputs) |output| if (std.mem.eql(u8, output.id, id)) return output;
    return error.InvalidAssessment;
}
fn selected(ids: []const []const u8, id: []const u8) bool {
    for (ids) |value| if (std.mem.eql(u8, value, id)) return true;
    return false;
}
fn validateSourceRefs(example: comparison.Case, refs: []const comparison.SourceRef) Error!void {
    for (refs, 0..) |reference, index| {
        if (!contracts.text(reference.quote)) return error.InvalidAssessment;
        const source = for (example.sources) |source| {
            if (std.mem.eql(u8, source.id, reference.source_id)) break source;
        } else return error.InvalidAssessment;
        if (std.mem.indexOf(u8, source.text, reference.quote) == null) return error.InvalidAssessment;
        for (refs[0..index]) |prior| if (std.mem.eql(u8, prior.source_id, reference.source_id) and std.mem.eql(u8, prior.quote, reference.quote)) return error.InvalidAssessment;
    }
}
fn validateOutputRefs(capture: Capture, refs: []const OutputRef, selection: ?[]const []const u8) Error!void {
    for (refs, 0..) |reference, index| {
        const output = try outputFor(capture, reference.output_id);
        if (!contracts.text(reference.quote) or std.mem.indexOf(u8, output.text, reference.quote) == null) return error.InvalidAssessment;
        if (selection) |ids| if (!selected(ids, reference.output_id)) return error.InvalidAssessment;
        for (refs[0..index]) |prior| if (std.mem.eql(u8, prior.output_id, reference.output_id) and std.mem.eql(u8, prior.quote, reference.quote)) return error.InvalidAssessment;
    }
}
fn validateLabels(example: comparison.Case, capture: Capture, labels: Labels, initial: bool) Error!void {
    const status = if (initial) capture.initial_status else capture.status;
    const target_ids = if (initial) capture.initial_output_ids else capture.final_output_ids;
    if (target_ids.len != labels.output_ids.len) return error.InvalidAssessment;
    // Native review may fail before any complete specification exists. Final
    // cumulative issues can still cite that review's exact raw output; they do
    // not create a semantic candidate or an initial-generation success.
    if (labels.output_ids.len == 0 and (labels.duties.len != 0 or (initial and labels.issues.len != 0) or labels.questions_correct or successful(status))) return error.InvalidAssessment;
    for (labels.output_ids, 0..) |id, index| {
        const output = try outputFor(capture, id);
        if (!selected(target_ids, id)) return error.InvalidAssessment;
        if (initial and output.attempt != 1) return error.InvalidAssessment;
        for (labels.output_ids[0..index]) |prior| if (std.mem.eql(u8, id, prior)) return error.InvalidAssessment;
    }
    if (!successful(status) and (labels.questions_correct or (initial and (labels.duties.len != 0 or labels.issues.len != 0)))) return error.InvalidAssessment;
    if (labels.question_evidence) |evidence| {
        if (!contracts.text(evidence.explanation) or evidence.source_refs.len == 0 or evidence.output_refs.len == 0) return error.InvalidAssessment;
        try validateSourceRefs(example, evidence.source_refs);
        try validateOutputRefs(capture, evidence.output_refs, labels.output_ids);
    }
    for (labels.duties, 0..) |duty, index| {
        if (!contracts.text(duty.explanation) or duty.source_refs.len == 0 or (duty.preserved and duty.output_refs.len == 0)) return error.InvalidAssessment;
        for (example.duties) |expected| {
            if (std.mem.eql(u8, expected.id, duty.id)) break;
        } else return error.InvalidAssessment;
        for (labels.duties[0..index]) |prior| if (std.mem.eql(u8, prior.id, duty.id)) return error.InvalidAssessment;
        try validateSourceRefs(example, duty.source_refs);
        try validateOutputRefs(capture, duty.output_refs, labels.output_ids);
    }
    try validateIssues(example, capture, labels.issues, if (initial) labels.output_ids else null);
}
fn validateIssues(example: comparison.Case, capture: Capture, issues: []const Issue, selection: ?[]const []const u8) Error!void {
    for (issues, 0..) |issue, index| {
        if (!contracts.id(issue.id) or issue.count == 0 or !contracts.text(issue.explanation) or issue.source_refs.len == 0) return error.InvalidAssessment;
        for (issues[0..index]) |prior| if (std.mem.eql(u8, prior.id, issue.id)) return error.InvalidAssessment;
        try validateSourceRefs(example, issue.source_refs);
        // Final issue counts cover the complete chain, including earlier output.
        try validateOutputRefs(capture, issue.output_refs, selection);
    }
}
fn currentFidelity(example: comparison.Case, capture: Capture, supplied: ?Entry) ?bool {
    if (example.expected_terminal != .completed or capture.status == .unattempted) return null;
    // A dispatched workload with no complete current content is a known
    // complete-fidelity failure. Missing semantic labels matter only when
    // native content actually exists to assess.
    if (!capture.final_content_valid) return false;
    const entry = supplied orelse return null;
    if (entry.scoring_disputed) return null;
    const labels = entry.final orelse return null;
    const issues = entry.final_current_issues orelse return null;
    if (labels.duties.len != example.duties.len) return null;
    if (capture.status == .clarification or issues.len != 0) return false;
    for (labels.duties) |duty| if (!duty.preserved) return false;
    return true;
}
fn retainInitialIssues(initial: Labels, final: Labels) Error!void {
    for (initial.issues) |prior| {
        for (final.issues) |current| {
            if (std.mem.eql(u8, current.id, prior.id)) {
                if (current.kind != prior.kind or current.count != prior.count or !std.mem.eql(u8, current.explanation, prior.explanation) or
                    current.source_refs.len != prior.source_refs.len or current.output_refs.len != prior.output_refs.len) return error.InvalidAssessment;
                for (prior.source_refs, current.source_refs) |before, after| {
                    if (!std.mem.eql(u8, before.source_id, after.source_id) or !std.mem.eql(u8, before.quote, after.quote)) return error.InvalidAssessment;
                }
                for (prior.output_refs, current.output_refs) |before, after| {
                    if (!std.mem.eql(u8, before.output_id, after.output_id) or !std.mem.eql(u8, before.quote, after.quote)) return error.InvalidAssessment;
                }
                break;
            }
        } else return error.InvalidAssessment;
    }
}
fn retainCurrentIssues(current: []const Issue, cumulative: []const Issue) Error!void {
    for (current) |issue| {
        for (cumulative) |event| {
            if (std.mem.eql(u8, issue.id, event.id)) {
                if (issue.kind != event.kind or issue.count > event.count) return error.InvalidAssessment;
                break;
            }
        } else return error.InvalidAssessment;
    }
}
fn completeLabels(example: comparison.Case, status: comparison.Status, labels: ?Labels) bool {
    if (labels) |value| {
        if (successful(status) and value.duties.len != example.duties.len) return false;
        if ((value.questions_correct or status == .clarification) and value.question_evidence == null) return false;
        return true;
    }
    return false;
}
fn questionsCorrect(labels: ?Labels) bool {
    return if (labels) |value| value.questions_correct and value.question_evidence != null else false;
}
fn projectDuties(a: std.mem.Allocator, labels: ?Labels) Error![]comparison.DutyAssessment {
    const count = if (labels) |value| value.duties.len else 0;
    const result = try a.alloc(comparison.DutyAssessment, count);
    if (labels) |value| for (value.duties, result) |label, *assessment| {
        assessment.* = .{ .id = label.id, .preserved = label.preserved };
    };
    return result;
}
fn projectIssues(issues: []const Issue) Error!comparison.Issues {
    var result: comparison.Issues = .{};
    for (issues) |issue| switch (issue.kind) {
        inline else => |kind| {
            const field = &@field(result, @tagName(kind));
            field.* = std.math.add(u32, field.*, issue.count) catch return error.InvalidAssessment;
        },
    };
    return result;
}
fn map(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidAssessment;
}

const Test = struct {
    const source_text = "A delivery may be sent only after consent; retain its receipt for 30 days.";
    const original = "Send after consent and retain the receipt for 30 days.";
    const correction = "Send immediately and delete the receipt.";
    fn hash(comptime text: []const u8) [64]u8 {
        @setEvalBranchQuota(10000);
        var bytes: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(text, &bytes, .{});
        return std.fmt.bytesToHex(bytes, .lower);
    }
    const original_hash = hash(original);
    const correction_hash = hash(correction);
    const acquisition = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const sources = [_]comparison.Source{.{ .id = "delivery-source", .path = "references/delivery.md", .text = source_text }};
    const refs = [_]comparison.SourceRef{.{ .source_id = "delivery-source", .quote = source_text }};
    const original_refs = [_]OutputRef{.{ .output_id = "initial-records", .quote = original }};
    const correction_refs = [_]OutputRef{.{ .output_id = "corrected-records", .quote = correction }};
    fn example() comparison.Case {
        return .{
            .id = "delivery-base",
            .feature_id = "delivery",
            .partition = .development,
            .variant = .base,
            .domain = "messaging",
            .size = .small,
            .risk_tags = &.{"restriction"},
            .sources = &sources,
            .duties = &.{.{ .id = "consent-retention", .description = "Consent gates sending and receipts remain for thirty days.", .source_refs = &refs, .exact_values = &.{"30 days"} }},
            .expected_terminal = .completed,
            .expected_questions = &.{},
            .permissible_alternatives = &.{},
            .forbidden_additions = &.{"Send without consent."},
        };
    }
    fn capture() Capture {
        return .{
            .trial_ordinal = 3,
            .case_id = "delivery-base",
            .acquisition_sha256 = acquisition,
            .scope = .diagnostic,
            .initial_status = .completed,
            .status = .completed,
            .initial_structural_valid = true,
            .structural_valid = true,
            .published = false,
            .corrective_sends = 1,
            .physical_sends = 2,
            .usage = .{ .input_tokens = 31, .output_tokens = 17 },
            .elapsed_ns = 250,
            .uncertain_delivery = false,
            .outputs = &.{ .{ .id = "initial-records", .attempt = 1, .text = original, .sha256 = &original_hash }, .{ .id = "corrected-records", .attempt = 2, .text = correction, .sha256 = &correction_hash } },
            .initial_output_ids = &.{"initial-records"},
            .final_output_ids = &.{"corrected-records"},
        };
    }
    fn initial() Labels {
        return .{ .output_ids = &.{"initial-records"}, .duties = &.{.{ .id = "consent-retention", .preserved = true, .explanation = "The sending condition and receipt duration are both retained.", .source_refs = &refs, .output_refs = &original_refs }}, .questions_correct = false, .issues = &.{} };
    }
    fn entry() Entry {
        return .{
            .trial_ordinal = 3,
            .acquisition_sha256 = acquisition,
            .provenance = .{ .kind = .human, .assessor = "reviewer-a" },
            .initial = initial(),
            .final = .{ .output_ids = &.{"corrected-records"}, .duties = &.{.{ .id = "consent-retention", .preserved = false, .explanation = "The correction removes both the condition and retention duty.", .source_refs = &refs, .output_refs = &correction_refs }}, .questions_correct = false, .issues = &.{.{ .id = "removed-consent", .kind = .harmful_repairs, .count = 1, .explanation = "A correction replaced good content with contradictory behavior.", .source_refs = &refs, .output_refs = &correction_refs }} },
            .scoring_disputed = false,
            .attribution = .{ .stage = .repair, .explanation = "The original retained the duty; its correction removed it.", .source_refs = &refs, .output_refs = &correction_refs },
        };
    }
};

test "supplied source-backed assessment preserves original versus harmful correction and native execution facts" {
    const a = std.testing.allocator;
    const result = try evaluate(a, Test.example(), Test.capture(), Test.entry());
    defer result.deinit(a);
    try std.testing.expectEqual(Evidence.complete, result.evidence);
    try std.testing.expect(result.observation.initial.duties[0].preserved);
    try std.testing.expect(!result.observation.duties[0].preserved);
    try std.testing.expectEqual(@as(u32, 1), result.observation.issues.harmful_repairs);
    try std.testing.expectEqual(comparison.FailureStage.repair, result.observation.failure_stage.?);
    try std.testing.expectEqual(@as(u32, 2), result.observation.physical_sends);
    try std.testing.expectEqual(@as(u64, 31), result.observation.usage.?.input_tokens);
    try std.testing.expect(!result.observation.published);
    try std.testing.expectEqual(.human, result.provenance.?.kind);
}

test "missing final judgments keep independently assessed original fidelity and block whole-chain evidence" {
    var entry = Test.entry();
    entry.final = null;
    entry.final_current_issues = null;
    const result = try evaluate(std.testing.allocator, Test.example(), Test.capture(), entry);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(.incomplete, result.evidence);
    try std.testing.expect(result.observation.scoring_disputed);
    try std.testing.expect(!result.observation.initial_scoring_disputed);
    try std.testing.expectEqual(.semantic_success, comparison.initialOutcome(Test.example(), result.observation));
}

test "original upstream evidence is mandatory without replacing independently assessed generation fidelity" {
    const targets = [_]upstream.Target{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .output_id = "initial-records", .text = Test.original, .sha256 = &Test.original_hash },
        .{ .call = 2, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } }, .purpose = .initial_generation, .owner_kind = .reference_chunk, .output_id = "corrected-records", .text = Test.correction, .sha256 = &Test.correction_hash },
    };
    var capture = Test.capture();
    capture.upstream_targets = &targets;
    var entry = Test.entry();
    const missing = try evaluate(std.testing.allocator, Test.example(), capture, entry);
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(.incomplete, missing.evidence);
    try std.testing.expectEqual(@as(u32, 1), missing.upstream.original.unknown);
    try std.testing.expectEqual(.semantic_success, comparison.initialOutcome(Test.example(), missing.observation));
    entry.upstream = &.{.{ .origin = targets[0].origin, .output_id = targets[0].output_id, .output_sha256 = targets[0].sha256, .outcome = .faithful, .explanation = "MOCK original extraction retains the consent and duration requirements.", .source_refs = &Test.refs, .output_quote = Test.original }};
    const supplied = try evaluate(std.testing.allocator, Test.example(), capture, entry);
    defer supplied.deinit(std.testing.allocator);
    try std.testing.expectEqual(.complete, supplied.evidence);
    try std.testing.expect(supplied.upstream.original_evidence_complete);
    try std.testing.expect(!supplied.upstream.corrective_evidence_complete);
    try std.testing.expectEqual(@as(u32, 1), supplied.upstream.corrective.unknown);
    var substituted = targets;
    substituted[0].text = Test.correction;
    substituted[0].sha256 = &Test.correction_hash;
    capture.upstream_targets = &substituted;
    try std.testing.expectError(error.InvalidAssessment, evaluate(std.testing.allocator, Test.example(), capture, entry));
}

test "missing disputed and partial semantic labels remain incomplete instead of inventing success" {
    const a = std.testing.allocator;
    const missing = try evaluate(a, Test.example(), Test.capture(), null);
    defer missing.deinit(a);
    try std.testing.expectEqual(Evidence.incomplete, missing.evidence);
    try std.testing.expect(missing.observation.scoring_disputed);
    try std.testing.expectEqual(@as(usize, 0), missing.observation.initial.duties.len);
    try std.testing.expectEqual(@as(usize, 0), missing.observation.duties.len);
    try std.testing.expect(missing.observation.failure_stage == null);
    var entry = Test.entry();
    entry.provenance.kind = .model_assisted;
    entry.scoring_disputed = true;
    const disputed = try evaluate(a, Test.example(), Test.capture(), entry);
    defer disputed.deinit(a);
    try std.testing.expectEqual(Evidence.disputed, disputed.evidence);
    try std.testing.expectEqual(.model_assisted, disputed.provenance.?.kind);
    entry.scoring_disputed = false;
    entry.final.?.duties = &.{};
    const partial = try evaluate(a, Test.example(), Test.capture(), entry);
    defer partial.deinit(a);
    try std.testing.expectEqual(Evidence.incomplete, partial.evidence);
    try std.testing.expect(partial.observation.scoring_disputed);
    try std.testing.expectEqual(@as(usize, 0), partial.observation.duties.len);
}

test "assessment rejects substituted acquisition output identities citations and corrected first-pass content" {
    const a = std.testing.allocator;
    const bad_digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    var entry = Test.entry();
    entry.acquisition_sha256 = bad_digest;
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    entry = Test.entry();
    entry.trial_ordinal += 1;
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    entry = Test.entry();
    entry.initial.?.output_ids = &.{"corrected-records"};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    entry = Test.entry();
    var duty = entry.initial.?.duties[0];
    duty.output_refs = &.{.{ .output_id = "initial-records", .quote = "This text was never generated." }};
    entry.initial.?.duties = &.{duty};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    duty = Test.entry().initial.?.duties[0];
    duty.source_refs = &.{.{ .source_id = "delivery-source", .quote = "Consent is optional." }};
    entry.initial.?.duties = &.{duty};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    duty.source_refs = &.{.{ .source_id = "foreign-source", .quote = Test.source_text }};
    entry.initial.?.duties = &.{duty};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    var capture = Test.capture();
    var output = capture.outputs[0];
    output.text = "Substituted output bytes.";
    capture.outputs = &.{output};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, Test.entry()));
}

test "assessment rejects foreign duplicate duty identities erased initial issue events and diagnostic publication" {
    const a = std.testing.allocator;
    var entry = Test.entry();
    var duty = entry.initial.?.duties[0];
    duty.id = "foreign-duty";
    entry.initial.?.duties = &.{duty};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    duty = Test.entry().initial.?.duties[0];
    entry.initial.?.duties = &.{ duty, duty };
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    entry = Test.entry();
    entry.initial.?.issues = &.{.{ .id = "original-loss", .kind = .wrong_support, .count = 1, .explanation = "The original has a wrong support attribution.", .source_refs = &Test.refs, .output_refs = &Test.original_refs }};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
    var capture = Test.capture();
    capture.published = true;
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, Test.entry()));
}

test "native target sets reject cherry picked substituted and duplicate assessment outputs" {
    const a = std.testing.allocator;
    var capture = Test.capture();
    capture.initial_output_ids = &.{ "initial-records", "initial-records" };
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, Test.entry()));
    capture = Test.capture();
    capture.initial_output_ids = &.{"corrected-records"};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, Test.entry()));
    capture = Test.capture();
    capture.final_output_ids = &.{ "initial-records", "corrected-records" };
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, Test.entry()));
    var entry = Test.entry();
    entry.final.?.output_ids = &.{"initial-records"};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), Test.capture(), entry));
}

test "unrelated source backed clarification requires question evidence and remains a supplied semantic judgment" {
    const a = std.testing.allocator;
    const source_text = "Urgent requests require manager sign-off. Ordinary request approval is unspecified.";
    const output_text = "Urgent requests require manager sign-off. Who authorizes ordinary requests?";
    const output_hash = comptime Test.hash(output_text);
    const source_refs = [_]comparison.SourceRef{.{ .source_id = "approvals", .quote = source_text }};
    const output_refs = [_]OutputRef{.{ .output_id = "gap-candidate", .quote = output_text }};
    const example: comparison.Case = .{
        .id = "approval-gap",
        .feature_id = "approval",
        .partition = .development,
        .variant = .base,
        .domain = "work-orders",
        .size = .small,
        .risk_tags = &.{"unresolved-authority"},
        .sources = &.{.{ .id = "approvals", .path = "references/approvals.md", .text = source_text }},
        .duties = &.{.{ .id = "urgent-owner", .description = "Preserve urgent approval and ask about the missing ordinary owner.", .source_refs = &source_refs, .exact_values = &.{} }},
        .expected_terminal = .clarification,
        .expected_questions = &.{"Who authorizes ordinary requests?"},
        .permissible_alternatives = &.{},
        .forbidden_additions = &.{"Ordinary requests use manager approval."},
    };
    var capture = Test.capture();
    capture.case_id = example.id;
    capture.initial_status = .clarification;
    capture.status = .clarification;
    capture.corrective_sends = 0;
    capture.physical_sends = 1;
    capture.outputs = &.{.{ .id = "gap-candidate", .attempt = 1, .text = output_text, .sha256 = &output_hash }};
    capture.initial_output_ids = &.{"gap-candidate"};
    capture.final_output_ids = &.{"gap-candidate"};
    const labels: Labels = .{
        .output_ids = &.{"gap-candidate"},
        .duties = &.{.{ .id = "urgent-owner", .preserved = true, .explanation = "The known urgent condition remains, and the missing ordinary owner is not invented.", .source_refs = &source_refs, .output_refs = &output_refs }},
        .questions_correct = true,
        .question_evidence = .{ .explanation = "The source explicitly leaves ordinary approval unspecified; the candidate asks for that owner.", .source_refs = &source_refs, .output_refs = &output_refs },
        .issues = &.{},
    };
    var entry = Test.entry();
    entry.initial = labels;
    entry.final = labels;
    entry.attribution = null;
    const assessed = try evaluate(a, example, capture, entry);
    defer assessed.deinit(a);
    try std.testing.expectEqual(Evidence.complete, assessed.evidence);
    try std.testing.expect(assessed.observation.initial.questions_correct);
    try std.testing.expect(assessed.observation.questions_correct);
    try std.testing.expect(assessed.observation.failure_stage == null);
    entry.final.?.question_evidence = null;
    const incomplete = try evaluate(a, example, capture, entry);
    defer incomplete.deinit(a);
    try std.testing.expectEqual(Evidence.incomplete, incomplete.evidence);
    try std.testing.expect(incomplete.observation.scoring_disputed);
    try std.testing.expect(!incomplete.observation.questions_correct);
}

test "closed assessment document rejects unknown duplicate foreign and stale association identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = Test.entry();
    const bytes = try std.json.Stringify.valueAlloc(a, Document{ .schema = 2, .entries = &.{entry} }, .{});
    const parsed = try parse(a, bytes);
    const old_version = try std.mem.replaceOwned(u8, a, bytes, "\"schema\":2", "\"schema\":1");
    try std.testing.expectError(error.InvalidAssessment, parse(a, old_version));
    try validateAssociations(parsed, &.{Test.capture()});
    try std.testing.expect(entryFor(parsed, 3) != null);
    try std.testing.expect(entryFor(parsed, 99) == null);
    try std.testing.expectError(error.InvalidAssessment, validateAssociations(parsed, &.{}));
    var capture = Test.capture();
    capture.acquisition_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    try std.testing.expectError(error.InvalidAssessment, validateAssociations(parsed, &.{capture}));
    const duplicate = try std.json.Stringify.valueAlloc(a, Document{ .schema = 2, .entries = &.{ entry, entry } }, .{});
    try std.testing.expectError(error.InvalidAssessment, parse(a, duplicate));
    const unknown = try std.fmt.allocPrint(a, "{{\"native_status\":\"completed\",{s}", .{bytes[1..]});
    try std.testing.expectError(error.InvalidAssessment, parse(a, unknown));
    const duplicate_key = try std.fmt.allocPrint(a, "{{\"schema\":1,{s}", .{bytes[1..]});
    try std.testing.expectError(error.InvalidAssessment, parse(a, duplicate_key));
    const native_override = try std.mem.replaceOwned(u8, a, bytes, "\"provenance\":", "\"physical_sends\":0,\"provenance\":");
    try std.testing.expectError(error.InvalidAssessment, parse(a, native_override));
}

test "unattempted and failed captures retain native outcomes without semantic attribution guesses" {
    const a = std.testing.allocator;
    var capture = Test.capture();
    capture.status = .unattempted;
    capture.initial_status = .unattempted;
    capture.initial_structural_valid = false;
    capture.structural_valid = false;
    capture.outputs = &.{};
    capture.initial_output_ids = &.{};
    capture.final_output_ids = &.{};
    capture.corrective_sends = 0;
    capture.physical_sends = 0;
    capture.usage = null;
    capture.elapsed_ns = null;
    const result = try evaluate(a, Test.example(), capture, null);
    defer result.deinit(a);
    try std.testing.expectEqual(Evidence.not_required, result.evidence);
    try std.testing.expectEqual(comparison.Status.unattempted, result.observation.status);
    try std.testing.expect(!result.observation.scoring_disputed);
    capture = Test.capture();
    capture.status = .provider_failed;
    capture.structural_valid = false;
    capture.usage = null;
    capture.uncertain_delivery = true;
    const failed = try evaluate(a, Test.example(), capture, null);
    defer failed.deinit(a);
    try std.testing.expectEqual(comparison.Status.provider_failed, failed.observation.status);
    try std.testing.expect(failed.observation.usage == null);
    try std.testing.expect(failed.observation.failure_stage == null);
    try std.testing.expect(failed.observation.uncertain_delivery);
    capture = Test.capture();
    capture.initial_status = .malformed;
    capture.status = .malformed;
    capture.initial_structural_valid = false;
    capture.structural_valid = false;
    capture.initial_output_ids = &.{};
    capture.final_output_ids = &.{};
    const empty_hash = comptime Test.hash("");
    capture.outputs = &.{.{ .id = "empty-original", .attempt = 1, .text = "", .sha256 = &empty_hash }};
    const empty = try evaluate(a, Test.example(), capture, null);
    defer empty.deinit(a);
    try std.testing.expectEqual(comparison.Status.malformed, empty.observation.status);
    try std.testing.expectEqual(Evidence.incomplete, empty.evidence);
}

fn allocationScenario(a: std.mem.Allocator) !void {
    const result = try evaluate(a, Test.example(), Test.capture(), Test.entry());
    defer result.deinit(a);
}
test "assessment bridge cleans up each allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

const FindingTest = struct {
    // Named container constants own every returned slice. Runtime array
    // literals containing helper results would borrow a returned stack frame.
    const native_value = native();
    const captured_values = [_]CapturedFinding{.{ .native = native_value, .output_id = "initial-records", .purpose = .semantic_review, .raw_verification = .complete }};
    const coverage_values = [_]ReviewCoverage{.{ .origin = native_value.origin, .output_id = "initial-records", .review = .source, .projected = true, .expected_findings = 1 }};
    const judgment_values = [_]FindingJudgment{judgment()};
    const cumulative_issues = [_]Issue{
        Test.entry().final.?.issues[0],
        .{ .id = "wrong-finding-type", .kind = .harmful_diagnoses, .count = 1, .explanation = "MOCK an unsupported ambiguity diagnosis was issued.", .source_refs = &Test.refs, .output_refs = &Test.original_refs },
    };
    fn native() reviews.Finding {
        return .{
            .ordinal = 1,
            .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } },
            .requirement = .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 1 } }, .slot = .disposition },
            .kind = .{ .source = .ambiguous },
            .detail = "MOCK model incorrectly claims the consent condition is ambiguous.",
            .source_ids = &.{.{ .ordinal = 1 }},
            .principle_citations = &.{},
            .missing_obligation = null,
            .question = "MOCK is consent necessary?",
            .authority_gap = null,
            .admission = .accepted,
        };
    }
    fn capture() Capture {
        var value = Test.capture();
        value.final_content_valid = true;
        value.findings = &captured_values;
        value.review_coverage = &coverage_values;
        value.project_documents = &.{.{ .path = "principles/approval.md", .text = "Retain source-required approval conditions." }};
        return value;
    }
    fn judgment() FindingJudgment {
        return .{
            .ordinal = native().ordinal,
            .origin = native().origin,
            .requirement = native().requirement,
            .kind = native().kind,
            .expected_kind = .{ .source = .supported },
            .correct = false,
            .provenance = .{ .kind = .human, .assessor = "finding-reviewer" },
            .explanation = "MOCK the source explicitly requires consent, so an ambiguity diagnosis is the wrong type.",
            .source_refs = &Test.refs,
            .output_refs = &Test.original_refs,
        };
    }
    fn entry() Entry {
        var value = Test.entry();
        value.findings = &judgment_values;
        value.final.?.issues = &cumulative_issues;
        value.final_current_issues = &.{};
        return value;
    }
};

test "finding correctness is supplied source-backed expected type rather than native admission truth" {
    const a = std.testing.allocator;
    const result = try evaluate(a, Test.example(), FindingTest.capture(), FindingTest.entry());
    defer result.deinit(a);
    try std.testing.expectEqual(Evidence.complete, result.evidence);
    try std.testing.expectEqual(@as(?bool, false), result.findings[0].correct);
    try std.testing.expectEqualDeep(FindingTest.judgment().expected_kind, result.findings[0].expected_kind.?);
    try std.testing.expectEqual(.accepted, result.findings[0].native.admission);
    try std.testing.expect(result.observation.initial.duties[0].preserved);
    try std.testing.expectEqual(@as(u32, 1), result.observation.issues.harmful_diagnoses);
    var entry = FindingTest.entry();
    entry.findings = &.{};
    const missing = try evaluate(a, Test.example(), FindingTest.capture(), entry);
    defer missing.deinit(a);
    try std.testing.expectEqual(Evidence.incomplete, missing.evidence);
    try std.testing.expect(missing.findings[0].correct == null);
    try std.testing.expect(!missing.observation.scoring_disputed);
    try std.testing.expect(missing.observation.initial.duties[0].preserved);
    var judgment = FindingTest.judgment();
    judgment.scoring_disputed = true;
    entry.findings = &.{judgment};
    const disputed = try evaluate(a, Test.example(), FindingTest.capture(), entry);
    defer disputed.deinit(a);
    try std.testing.expectEqual(Evidence.disputed, disputed.evidence);
    try std.testing.expect(disputed.findings[0].correct == null and disputed.findings[0].expected_kind == null);
}

test "review harm before any specification candidate remains source-backed cumulative evidence" {
    var capture = FindingTest.capture();
    capture.initial_status = .blocked;
    capture.status = .blocked;
    capture.initial_structural_valid = false;
    capture.structural_valid = false;
    capture.initial_output_ids = &.{};
    capture.final_output_ids = &.{};
    capture.final_content_valid = false;
    var entry = FindingTest.entry();
    entry.initial = .{ .output_ids = &.{}, .duties = &.{}, .questions_correct = false, .issues = &.{} };
    entry.final = .{ .output_ids = &.{}, .duties = &.{}, .questions_correct = false, .issues = FindingTest.cumulative_issues[1..] };
    entry.final_current_issues = null;
    entry.attribution = .{ .stage = .review, .explanation = "MOCK review returned the wrong diagnosis before generation completed.", .source_refs = &Test.refs, .output_refs = &Test.original_refs };
    const result = try evaluate(std.testing.allocator, Test.example(), capture, entry);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(.complete, result.evidence);
    try std.testing.expectEqual(@as(u32, 1), result.observation.issues.harmful_diagnoses);
    try std.testing.expectEqual(@as(?bool, false), result.final_current_fidelity);
    try std.testing.expectEqual(@as(usize, 0), result.observation.initial.duties.len);
    entry.final.?.issues = &.{};
    try std.testing.expectError(error.InvalidAssessment, evaluate(std.testing.allocator, Test.example(), capture, entry));
    capture.findings = &.{};
    capture.review_coverage = &.{};
    entry.findings = &.{};
    const mechanical = try evaluate(std.testing.allocator, Test.example(), capture, entry);
    defer mechanical.deinit(std.testing.allocator);
    try std.testing.expectEqual(.complete, mechanical.evidence);
    try std.testing.expectEqual(@as(u32, 0), mechanical.observation.issues.harmful_diagnoses);
}

test "finding judgments reject foreign identities kinds quotes duplicates and underreported wrong-type harm" {
    const a = std.testing.allocator;
    var entry = FindingTest.entry();
    var judgment = FindingTest.judgment();
    judgment.kind = .{ .source = .conflicting };
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    judgment = FindingTest.judgment();
    judgment.correct = true;
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    judgment = FindingTest.judgment();
    judgment.origin.request.value = 999;
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    judgment = FindingTest.judgment();
    judgment.source_refs = &.{.{ .source_id = "delivery-source", .quote = "Consent is never required." }};
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    judgment = FindingTest.judgment();
    entry.findings = &.{ judgment, judgment };
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    entry = FindingTest.entry();
    entry.final.?.issues = Test.entry().final.?.issues;
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), FindingTest.capture(), entry));
    entry.final.?.duties = &.{};
    const partial = try evaluate(a, Test.example(), FindingTest.capture(), entry);
    defer partial.deinit(a);
    try std.testing.expectEqual(Evidence.incomplete, partial.evidence);
    try std.testing.expectEqual(@as(?bool, false), partial.findings[0].correct);
}

test "principle finding assessments require quoted frozen project policy and exact declared vocabulary" {
    const a = std.testing.allocator;
    var capture = FindingTest.capture();
    var finding = FindingTest.native();
    finding.kind = .{ .principles = .compatible };
    capture.findings = &.{.{ .native = finding, .output_id = "initial-records", .purpose = .semantic_review, .raw_verification = .complete }};
    capture.review_coverage = &.{.{ .origin = finding.origin, .output_id = "initial-records", .review = .principles, .projected = true, .expected_findings = 1 }};
    var judgment = FindingTest.judgment();
    judgment.kind = finding.kind;
    judgment.expected_kind = finding.kind;
    judgment.correct = true;
    var entry = FindingTest.entry();
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, entry));
    judgment.project_refs = &.{.{ .path = "principles/approval.md", .quote = "Retain source-required approval conditions." }};
    entry.findings = &.{judgment};
    const valid = try evaluate(a, Test.example(), capture, entry);
    defer valid.deinit(a);
    try std.testing.expectEqual(@as(?bool, true), valid.findings[0].correct);
    judgment.project_refs = &.{.{ .path = "principles/approval.md", .quote = "Approval is optional." }};
    entry.findings = &.{judgment};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, entry));
}

test "final current fidelity requires explicit current issues while retaining earlier harmful events" {
    const a = std.testing.allocator;
    var capture = Test.capture();
    capture.final_content_valid = true;
    capture.final_output_ids = &.{"initial-records"};
    var entry = Test.entry();
    entry.final.?.output_ids = &.{"initial-records"};
    var duty = entry.final.?.duties[0];
    duty.preserved = true;
    duty.output_refs = &Test.original_refs;
    entry.final.?.duties = &.{duty};
    const missing = try evaluate(a, Test.example(), capture, entry);
    defer missing.deinit(a);
    try std.testing.expect(missing.final_current_fidelity == null);
    entry.final_current_issues = &.{};
    const recovered = try evaluate(a, Test.example(), capture, entry);
    defer recovered.deinit(a);
    try std.testing.expectEqual(@as(?bool, true), recovered.final_current_fidelity);
    try std.testing.expectEqual(@as(u32, 1), recovered.observation.issues.harmful_repairs);
    capture.final_output_ids = &.{"corrected-records"};
    entry.final.?.output_ids = &.{"corrected-records"};
    duty.output_refs = &Test.correction_refs;
    entry.final.?.duties = &.{duty};
    const current_issue: Issue = .{ .id = "current-unsupported-rule", .kind = .unsupported_behavior, .count = 1, .explanation = "MOCK the current candidate contains an unsupported behavior.", .source_refs = &Test.refs, .output_refs = &Test.correction_refs };
    entry.final_current_issues = &.{current_issue};
    try std.testing.expectError(error.InvalidAssessment, evaluate(a, Test.example(), capture, entry));
    entry.final.?.issues = &.{ Test.entry().final.?.issues[0], current_issue };
    const harmed = try evaluate(a, Test.example(), capture, entry);
    defer harmed.deinit(a);
    try std.testing.expectEqual(@as(?bool, false), harmed.final_current_fidelity);
}

test "dispatched native failures without complete content fail final fidelity without erasing original labels" {
    const a = std.testing.allocator;
    for ([_]comparison.Status{ .provider_failed, .malformed, .truncated, .blocked }) |status| {
        var capture = Test.capture();
        capture.status = status;
        capture.structural_valid = false;
        capture.final_content_valid = false;
        capture.final_output_ids = &.{};
        var entry = Test.entry();
        entry.final = null;
        const result = try evaluate(a, Test.example(), capture, entry);
        defer result.deinit(a);
        try std.testing.expectEqual(@as(?bool, false), result.final_current_fidelity);
        try std.testing.expectEqual(comparison.Status.completed, result.observation.initial.status);
        try std.testing.expect(result.observation.initial.duties[0].preserved);
    }
    var unattempted = Test.capture();
    unattempted.status = .unattempted;
    unattempted.initial_status = .unattempted;
    unattempted.initial_structural_valid = false;
    unattempted.structural_valid = false;
    unattempted.outputs = &.{};
    unattempted.initial_output_ids = &.{};
    unattempted.final_output_ids = &.{};
    unattempted.physical_sends = 0;
    unattempted.corrective_sends = 0;
    unattempted.usage = null;
    unattempted.elapsed_ns = null;
    const skipped = try evaluate(a, Test.example(), unattempted, null);
    defer skipped.deinit(a);
    try std.testing.expect(skipped.final_current_fidelity == null);
}
