//! Source-review wire values. Native evidence is reconstructed from the bound
//! requirement; stored findings retain the full canonical review contract.
const std = @import("std");
const a = @import("required_authority.zig");
const r = @import("reference_reconciliation.zig");
const SourceId = @import("reference_identity.zig").SourceId;
const loss = @import("source_omission.zig").Location;
const evidence = @import("specification_support_evidence.zig");
const codec = @import("model_candidate_json.zig");
const json = @import("strict_json.zig");

pub const Decision = enum {
    supported,
    ambiguous,
    conflicting,
    unsupported,
    candidate_omission,
    candidate_invalid,
    inconclusive,
    not_applicable,

    pub fn finding(self: Decision) a.Finding {
        return switch (self) {
            .not_applicable => .supported,
            inline else => |value| @field(a.Finding, @tagName(value)),
        };
    }
    pub fn fromFinding(value: a.Finding) error{}!Decision {
        return switch (value) {
            inline else => |tag| @field(Decision, @tagName(tag)),
        };
    }
};
pub const Canonical = struct {
    pub const model_field_projection = Value;
    pub const model_prose = .{ .question = @import("text_field_policy.zig").Field.clarification_question };
    loss: loss = .{ .unlocalized = .{} },
    preservation: ?@import("source_omission.zig").comparisons.Evidence = null,
    kind: Decision,
    provenance: @import("specification.zig").Selection,
    source_ids: []const SourceId,
    detail: []const u8,
    missing_obligation: ?[]const u8 = null,
    question: ?[]const u8 = null,
    authority_gap: ?a.AuthorityGap = null,
};

pub fn fixedClaims(required: evidence.Requirements) ?[]const r.ClaimId {
    return required.rule(.supported, .{ .unlocalized = .{} }).fixedClaims();
}

const Positive = struct { source_ids: []const SourceId, detail: []const u8 };
const Question = struct {
    pub const model_prose = .{ .question = @import("text_field_policy.zig").Field.clarification_question };
    source_ids: []const SourceId,
    detail: []const u8,
    question: []const u8,
};
const Explanation = struct { source_ids: []const SourceId, detail: []const u8 };
const Omission = struct { source_ids: []const SourceId, detail: []const u8, missing_obligation: []const u8 };
const Invalid = struct { source_ids: []const SourceId, detail: []const u8, authority_gap: ?a.AuthorityGap };
pub const Detail = struct {
    pub const model_prose = .{ .question = @import("text_field_policy.zig").Field.clarification_question };
    detail: []const u8,
    missing_obligation: ?[]const u8 = null,
    question: ?[]const u8 = null,
    authority_gap: ?a.AuthorityGap = null,
};

/// The verdicts one source request offers. Null means a required request,
/// which keeps its result definition's complete verdict set.
pub const Offered = std.EnumSet(Decision);

/// Whether a request offering these verdicts presents a verdict's rule.
pub fn offers(offered: ?Offered, verdicts: []const Decision) bool {
    const set = offered orelse return true;
    for (verdicts) |verdict| if (set.contains(verdict)) return true;
    return false;
}

/// A retained authority gap is reachable only when `candidate_invalid` and a
/// gap kind are both offered; the excluded-variant restriction removes it
/// from the nested gap otherwise.
pub fn carriesGap(offered: ?Offered) bool {
    if (!offers(offered, &.{.candidate_invalid})) return false;
    inline for (comptime std.meta.tags(a.AuthorityGap.GapKind)) |kind| if (offers(offered, &.{Decision.fromFinding(kind.finding()) catch unreachable})) return true;
    return false;
}

/// Whether any offered verdict carries a top-level question.
pub fn carriesQuestion(offered: ?Offered) bool {
    inline for (comptime std.meta.tags(Decision)) |verdict| if (evidence.questionRequired(verdict.finding()) and offers(offered, &.{verdict})) return true;
    return false;
}

/// Correction result shapes. The retained verdict and whether its request
/// offers an authority gap select one (ADR 0023, D10.2); a shape is never
/// chosen by its definition name.
pub const DetailCorrection = enum {
    detail,
    omission_detail,
    gap_detail,
    invalid_detail,

    pub fn of(decision: Decision, gap: bool) DetailCorrection {
        if (decision == .candidate_invalid and gap) return .invalid_detail;
        if (decision == .candidate_omission) return .omission_detail;
        return if (evidence.questionRequired(decision.finding())) .gap_detail else .detail;
    }
};
pub const SelectionCorrection = enum {
    selection,
    invalid_selection,

    pub fn of(decision: Decision, gap: bool) SelectionCorrection {
        return if (decision == .candidate_invalid and gap) .invalid_selection else .selection;
    }
};

/// Decode the selected correction shape without permitting a missing obligation
/// or admitting omission-only fields into another retained finding.
pub fn decodeDetail(a_alloc: std.mem.Allocator, bytes: []const u8, shape: DetailCorrection) json.Error!Detail {
    switch (shape) {
        .omission_detail => {
            const value = try codec.decode(struct { detail: []const u8, missing_obligation: []const u8 }, a_alloc, bytes);
            return .{ .detail = value.detail, .missing_obligation = value.missing_obligation };
        },
        .invalid_detail => {
            const value = try codec.decode(struct { detail: []const u8, authority_gap: ?a.AuthorityGap }, a_alloc, bytes);
            return .{ .detail = value.detail, .authority_gap = value.authority_gap };
        },
        .gap_detail => {
            const value = try codec.decode(struct { detail: []const u8, question: []const u8 }, a_alloc, bytes);
            return .{ .detail = value.detail, .question = value.question };
        },
        .detail => {
            const value = try codec.decode(struct { detail: []const u8 }, a_alloc, bytes);
            return .{ .detail = value.detail };
        },
    }
}

pub const Value = union(enum) {
    supported: Positive,
    ambiguous: Question,
    conflicting: Question,
    unsupported: Question,
    candidate_omission: Omission,
    candidate_invalid: Invalid,
    inconclusive: Explanation,
    not_applicable: Positive,
};

/// Complete findings for one native record assignment. The model may reorder
/// entries, but cannot choose which required fields are assessed.
pub const BatchFinding = struct { requirement_ordinal: u32, value: Value };
pub const Batch = struct { findings: []const BatchFinding };

/// Resolve only subject-bound or diagnostic claims. An unlocalized negative
/// finding may use source-only evidence, never an arbitrary eligible subset.
/// Null means no claim set can be bound to this verdict for the subject.
fn resolvedClaims(required: evidence.Requirements, kind: Decision, location: loss) ?[]const r.ClaimId {
    // The native pre-authoring source-purpose rule fixes an empty claim set;
    // its model-selected source IDs are validated separately. No catalogue is
    // promoted into a positive authored association.
    if (required.rule(kind.finding(), location).fixedClaims()) |claims| return claims;
    if (kind == .candidate_omission) return &.{};
    if (required.supported_provenance) |provenance| return provenance.claim_ids;
    if (required.positive_claims == .exact_set) return required.eligible_claim_ids;
    if ((kind == .supported or kind == .not_applicable) and required.eligible_claim_ids.len != 0) return null;
    if (required.eligible_claim_ids.len == 1) return required.eligible_claim_ids;
    if (kind != .supported and kind != .not_applicable) return &.{};
    return null;
}
fn claimsFor(required: evidence.Requirements, kind: Decision, location: loss) json.Error![]const r.ClaimId {
    return resolvedClaims(required, kind, location) orelse error.InvalidJsonDocument;
}

/// Whether an unlocalized verdict of this kind can be canonicalized for the
/// subject. An advisory assignment withholds every verdict that does not
/// resolve; every subject of required review resolves (ADR 0023).
pub fn resolves(required: evidence.Requirements, kind: Decision) bool {
    return resolvedClaims(required, kind, .{ .unlocalized = .{} }) != null;
}

pub fn decode(a_alloc: std.mem.Allocator, bytes: []const u8, required: evidence.Requirements) json.Error!Canonical {
    return canonical(try codec.decode(Value, a_alloc, bytes), required);
}

pub fn canonical(value: Value, required: evidence.Requirements) json.Error!Canonical {
    const kind: Decision = switch (value) {
        inline else => |_, tag| @field(Decision, @tagName(tag)),
    };
    const location: loss = .{ .unlocalized = .{} };
    const claims = try claimsFor(required, kind, location);
    const selected: @import("specification.zig").Selection = .{ .claim_ids = claims, .clarification_response_ids = &.{} };
    return switch (value) {
        .supported, .not_applicable => |positive| .{ .kind = kind, .provenance = selected, .source_ids = positive.source_ids, .detail = positive.detail },
        .ambiguous, .conflicting, .unsupported => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail, .question = negative.question },
        .candidate_omission => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail, .missing_obligation = negative.missing_obligation, .loss = location },
        .candidate_invalid => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail, .authority_gap = negative.authority_gap },
        .inconclusive => |negative| .{ .kind = kind, .provenance = selected, .source_ids = negative.source_ids, .detail = negative.detail },
    };
}

pub fn bindLoss(required: evidence.Requirements, value: Canonical, location: loss, proof: @import("source_omission.zig").comparisons.Evidence) json.Error!Canonical {
    if (value.kind != .candidate_omission or !evidence.validObligation(value.kind.finding(), value.missing_obligation)) return error.InvalidJsonDocument;
    var bound = value;
    bound.loss = location;
    bound.preservation = proof;
    bound.provenance.claim_ids = try claimsFor(required, .candidate_omission, bound.loss);
    return bound;
}

/// Test fixtures project a canonical finding into the current model contract.
/// Production admission always decodes and validates the response again.
pub fn encode(a_alloc: std.mem.Allocator, value: Canonical, required: evidence.Requirements) json.Error![]const u8 {
    _ = required;
    if (!evidence.validObligation(value.kind.finding(), value.missing_obligation) or (value.kind != .candidate_invalid and value.authority_gap != null)) return error.InvalidJsonDocument;
    const positive: Positive = .{ .source_ids = value.source_ids, .detail = value.detail };
    const selected: Value = switch (value.kind) {
        .supported => .{ .supported = positive },
        .not_applicable => .{ .not_applicable = positive },
        .ambiguous => .{ .ambiguous = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .conflicting => .{ .conflicting = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .unsupported => .{ .unsupported = .{ .source_ids = value.source_ids, .detail = value.detail, .question = value.question orelse "" } },
        .candidate_omission => .{ .candidate_omission = .{ .source_ids = value.source_ids, .detail = value.detail, .missing_obligation = value.missing_obligation.? } },
        .candidate_invalid => .{ .candidate_invalid = .{ .source_ids = value.source_ids, .detail = value.detail, .authority_gap = value.authority_gap } },
        .inconclusive => .{ .inconclusive = .{ .source_ids = value.source_ids, .detail = value.detail } },
    };
    return codec.encode(Value, a_alloc, selected);
}

pub const Selection = struct { source_ids: []const SourceId };
pub const InvalidSelection = struct { source_ids: []const SourceId, authority_gap_source_ids: ?[]const SourceId };
pub fn decodeSelection(a_alloc: std.mem.Allocator, bytes: []const u8, claims: []const r.ClaimId) json.Error!struct { provenance: @import("specification.zig").Selection, source_ids: []const SourceId } {
    const selected = try codec.decode(Selection, a_alloc, bytes);
    return .{ .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} }, .source_ids = selected.source_ids };
}
