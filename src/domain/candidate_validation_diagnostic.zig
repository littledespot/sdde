//! Typed validator evidence for observers. This projection grants no repair or
//! workflow authority; the retained validator/authorization values own that.
const std = @import("std");
pub const Attribution = union(enum) {
    response: @import("model_candidate_origin.zig").Origin,
    candidate,
    missing_response,
};
pub const Diagnostic = union(enum) {
    extraction_text: @import("reference_extraction.zig").TextRejection,
    reconciliation: @import("reference_reconciliation_diagnostic.zig").Rejection,
    token_classifications: @import("token_classification_validation.zig").Rejection,
    coverage: @import("specification_coverage.zig").Rejection,
    support_findings: SupportFindings,
    support: @import("specification_support.zig").Source.Rejection,
    specification: @import("specification_candidate.zig").Rejection,
    source_catalogue: @import("specification_source_binding.zig").Rejection,

    pub fn code(self: Diagnostic) []const u8 {
        return switch (self) {
            .support_findings => |value| if (value.repair_rejection) |reason| @tagName(reason) else @tagName(self),
            else => @tagName(self),
        };
    }

    /// The closed rule this diagnostic reports, as the event stream's `rule_id` (F0002 section 6.2): a tag
    /// of the validator's own closed issue set, never model text. A diagnostic holding several issues reports
    /// the validator's selected one, or an issue set's first nonempty member in declared order. A
    /// diagnostic selecting no issue reports none, and so do review findings, whose `code()` already names
    /// any repair rejection: a fact is stated once.
    pub fn rule(self: Diagnostic) ?[]const u8 {
        return switch (self) {
            .extraction_text => |value| @tagName(value.issue.reason),
            .reconciliation => |value| @tagName(value.issue.rule),
            .token_classifications => |value| {
                inline for (comptime std.meta.fieldNames(@TypeOf(value.issues))) |name| if (@field(value.issues, name).len != 0) return name;
                return null;
            },
            .coverage => |value| @tagName(value.issue),
            .support_findings => null,
            .support => |value| if (value.selected()) |selected| @tagName(selected.issue) else null,
            .specification => |value| @tagName(value.issue.rule),
            .source_catalogue => |value| @tagName(value.reason),
        };
    }

    pub fn origin(self: Diagnostic) ?@import("model_candidate_origin.zig").Origin {
        return switch (self) {
            .extraction_text => |value| value.origin,
            .reconciliation => |value| value.origin,
            .token_classifications => |value| value.origin,
            .coverage => |value| value.origin,
            .support_findings => |value| value.origin,
            .support => |value| if (value.selected()) |selected| selected.origin else null,
            .specification => |value| value.origin,
            .source_catalogue => |value| value.origin,
        };
    }

    /// Coverage checks the assembled candidate and blocks with no replacement or
    /// producer, as does a classification rejection whose
    /// validator rule assigns no producer; an origin there contradicts the rule.
    /// Other live rejections belong to a response.
    pub fn attribution(self: Diagnostic) Attribution {
        if (self == .token_classifications and @import("token_classification_validation.zig").producerless(self.token_classifications.issues))
            return if (self.token_classifications.origin == null) .candidate else .missing_response;
        if (self.origin()) |value| return .{ .response = value };
        return switch (self) {
            .coverage, .source_catalogue => .candidate,
            .extraction_text,
            .reconciliation,
            .token_classifications,
            .support_findings,
            .support,
            .specification,
            => .missing_response,
        };
    }

    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) @import("strict_json.zig").Error!Diagnostic {
        const bytes = try std.json.Stringify.valueAlloc(allocator, self, .{});
        defer allocator.free(bytes);
        return @import("strict_json.zig").decode(Diagnostic, allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    }
};

const authority = @import("required_authority.zig");
pub const SupportFindings = struct {
    revision: u64,
    evidence: []const authority.Evidence,
    origins: []const ?@import("model_candidate_origin.zig").Origin,
    origin: ?@import("model_candidate_origin.zig").Origin,
    repair_rejection: ?@import("source_omission.zig").Rejection,

    pub fn from(inputs: authority.Inputs, rejection: ?@import("source_omission.zig").Rejection) SupportFindings {
        return .{ .revision = inputs.revision, .evidence = inputs.evidence, .origins = inputs.review_origins, .origin = inputs.review_origin, .repair_rejection = rejection };
    }
};
