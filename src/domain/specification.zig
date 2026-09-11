//! Specification content and editable-view structure. Shape, IDs and evidence
//! references are mechanical contracts; none establish semantic adequacy.
const std = @import("std");
const text = @import("typed_text.zig");
const reference = @import("reference_extraction.zig");

pub const version = "specification/v1";
pub const Error = error{InvalidSpecification};
pub const Kind = enum {
    acceptance_criterion,
    user_visible_outcome,
    edge_case,
    functional_requirement,
    business_rule,
    assumption,
    non_goal,
    prohibited_behavior,
    entity,

    pub fn prefix(self: Kind) []const u8 {
        return switch (self) {
            .acceptance_criterion => "AC",
            .user_visible_outcome => "UO",
            .edge_case => "EC",
            .functional_requirement => "FR",
            .business_rule => "BR",
            .assumption => "AS",
            .non_goal => "NG",
            .prohibited_behavior => "PB",
            .entity => "EN",
        };
    }

    pub fn heading(self: Kind) []const u8 {
        return switch (self) {
            .acceptance_criterion => "### Acceptance Criteria",
            .user_visible_outcome => "### User-Visible Outcomes",
            .edge_case => "### Edge Cases",
            .functional_requirement => "### Functional Requirements",
            .business_rule => "### Business Rules",
            .assumption => "#### Assumptions",
            .non_goal => "#### Explicit Non-Goals",
            .prohibited_behavior => "#### Prohibited Behaviors",
            .entity => "### Key Entities _(include if feature involves data)_",
        };
    }
};

/// Mandatory business-content families; optional section presence never changes
/// this contract. Semantic support and completeness remain authority obligations.
pub const required_record_families = [_]Kind{ .acceptance_criterion, .functional_requirement };
pub fn requiresRecords(kind: Kind) bool {
    return std.mem.indexOfScalar(Kind, &required_record_families, kind) != null;
}
pub fn hasRecords(content: IdentifiedContent, kind: Kind) bool {
    for (content.records) |record| if (record.proposal.content == kind) return true;
    return false;
}

pub const Id = struct {
    kind: Kind,
    ordinal: u32,

    pub fn parse(bytes: []const u8) ?Id {
        if (bytes.len < 6 or bytes[2] != '-') return null;
        const digits = bytes[3..];
        if (digits.len > 3 and digits[0] == '0') return null;
        for (digits) |byte| if (!std.ascii.isDigit(byte)) return null;
        const ordinal = std.fmt.parseInt(u32, digits, 10) catch return null;
        if (ordinal == 0) return null;
        inline for (comptime std.meta.tags(Kind)) |kind| {
            if (std.mem.eql(u8, bytes[0..2], kind.prefix())) return .{ .kind = kind, .ordinal = ordinal };
        }
        return null;
    }
};

pub const ResponseId = struct { ordinal: u64 };
pub const Provenance = struct {
    claim_ids: []const reference.ClaimId,
    citation_ids: []const reference.CitationId,
    clarification_response_ids: []const ResponseId,
};
pub const BusinessValue = union(enum) {
    normalized: text.BusinessText,
    exact_copy: struct { token_id: reference.tokens.Id, citation_id: reference.CitationId },
};
pub const AttributedValue = struct { value: BusinessValue, provenance: Provenance };
pub const Brief = struct { title: AttributedValue, description: AttributedValue, primary_goal: AttributedValue };

/// This shared field shape is used by semantic content and its text projection.
/// Projection bytes never supply provenance, applicability or gate authority.
pub fn Content(comptime Value: type) type {
    if (Value != BusinessValue and Value != Scalar) @compileError("unsupported specification text boundary");
    return union(Kind) {
        acceptance_criterion: struct { given: Value, when: Value, then: Value },
        user_visible_outcome: struct { text: Value },
        edge_case: struct { condition: Value, expected_outcome: Value },
        functional_requirement: struct { text: Value },
        business_rule: struct { text: Value },
        assumption: struct { text: Value },
        non_goal: struct { text: Value },
        prohibited_behavior: struct { text: Value },
        entity: struct { name: Value, business_meaning: Value, relationships: []const Value },
    };
}

pub const RecordProposal = struct { content: Content(BusinessValue), provenance: Provenance };
pub const ApplicabilityProposal = struct {
    disposition: enum { required, not_applicable },
    basis: AttributedValue,
};
pub const ContentProposal = struct {
    display_name: AttributedValue,
    primary_user_story: AttributedValue,
    records: []const RecordProposal,
    entities: ApplicabilityProposal,
};

/// Structural candidate parsing only; current authority/text validation is a
/// subsequent boundary. No model-supplied identity or completion field exists.
pub fn parseProposal(allocator: std.mem.Allocator, bytes: []const u8) (std.mem.Allocator.Error || Error)!ContentProposal {
    return @import("strict_json.zig").decode(ContentProposal, allocator, bytes, .{
        .maximum_depth = @import("model_result_schema.zig").max_json_depth,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidSpecification,
    };
}
pub const IdentifiedRecord = struct { id: Id, proposal: RecordProposal };
pub const IdentifiedContent = struct {
    display_name: AttributedValue,
    primary_user_story: AttributedValue,
    records: []const IdentifiedRecord,
    entities: ApplicabilityProposal,
};

/// Direct complete typed-content comparison, including provenance and IDs.
/// No digest, persisted comparison record or generated-view authority is used.
pub fn sameContent(allocator: std.mem.Allocator, a: IdentifiedContent, b: IdentifiedContent) std.mem.Allocator.Error!bool {
    const left = try std.json.Stringify.valueAlloc(allocator, a, .{});
    defer allocator.free(left);
    const right = try std.json.Stringify.valueAlloc(allocator, b, .{});
    defer allocator.free(right);
    return std.mem.eql(u8, left, right);
}

/// Captured unescaped Markdown field; deliberately not BusinessText authority.
pub const CodeSpan = struct { start: usize, end: usize };
pub const Scalar = struct { bytes: []const u8, code_spans: []const CodeSpan = &.{} };
pub const CapturedRecord = struct { id: ?Id, content: Content(Scalar) };
pub const CapturedDocument = struct {
    display_name: Scalar,
    primary_user_story: Scalar,
    records: []const CapturedRecord,
    /// A missing section cannot assert a supported not_applicable decision.
    entity_section: enum { present, omitted },
};

/// Shape validation only. Caller owns an arena for parsed/constructed records.
/// Optional collections have no minimum count. H-008 owns required evidence.
pub fn validateDocument(document: CapturedDocument, require_ids: bool) Error!void {
    try scalar(document.display_name);
    try scalar(document.primary_user_story);
    var previous: ?Kind = null;
    for (document.records, 0..) |record, index| {
        const kind: Kind = record.content;
        if (previous != null and @intFromEnum(kind) < @intFromEnum(previous.?)) return error.InvalidSpecification;
        previous = kind;
        if (kind == .entity and document.entity_section != .present) return error.InvalidSpecification;
        if (record.id) |id| {
            if (id.kind != kind or id.ordinal == 0) return error.InvalidSpecification;
            for (document.records[0..index]) |other| {
                if (other.id != null and std.meta.eql(id, other.id.?)) return error.InvalidSpecification;
            }
        } else if (require_ids) return error.InvalidSpecification;
        switch (record.content) {
            inline else => |content| inline for (@typeInfo(@TypeOf(content)).@"struct".fields) |field| {
                const value = @field(content, field.name);
                if (comptime field.type == Scalar) {
                    try scalar(value);
                } else {
                    for (value) |relationship| try scalar(relationship);
                }
            },
        }
    }
}

fn scalar(value: Scalar) Error!void {
    if (std.mem.trim(u8, value.bytes, " \t\r\n").len == 0 or !text.validScalar(value.bytes)) return error.InvalidSpecification;
    var prior_end: usize = 0;
    for (value.code_spans, 0..) |span, index| {
        // Adjacent closing/opening backticks would merge and lose span identity.
        if ((index != 0 and span.start <= prior_end) or span.end <= span.start or span.end > value.bytes.len or
            (value.bytes[span.start] & 0xc0) == 0x80 or
            (span.end < value.bytes.len and (value.bytes[span.end] & 0xc0) == 0x80)) return error.InvalidSpecification;
        prior_end = span.end;
    }
}
