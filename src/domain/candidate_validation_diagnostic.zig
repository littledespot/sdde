//! Typed validator evidence for observers. This projection grants no repair or
//! workflow authority; the retained validator/authorization values own that.
const std = @import("std");
pub const Diagnostic = union(enum) {
    extraction_text: @import("reference_extraction.zig").TextRejection,
    reconciliation: @import("reference_reconciliation_diagnostic.zig").Rejection,
    token_classifications: @import("token_classification_validation.zig").Rejection,
    source_selections: @import("reference_selection_validation.zig").Rejection,
    coverage: @import("specification_coverage.zig").Rejection,
    support_findings: SupportFindings,
    support: @import("specification_support.zig").Source.Rejection,
    principle_review: @import("specification_support.zig").Contract(.principles).Rejection,
    specification: @import("specification_candidate.zig").Rejection,

    pub fn origin(self: Diagnostic) ?@import("model_candidate_origin.zig").Origin {
        return switch (self) {
            .extraction_text => |value| value.origin,
            .reconciliation => |value| value.origin,
            .token_classifications => |value| value.origin,
            .source_selections => |value| value.origin,
            .coverage => |value| value.origin,
            .support_findings => |value| value.origin,
            .support => |value| if (value.selected()) |selected| selected.origin else null,
            .principle_review => |value| if (value.selected()) |selected| selected.origin else null,
            .specification => |value| value.origin,
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
    purpose: @import("specification_support.zig").Purpose,
    revision: u64,
    evidence: []const authority.Evidence,
    origins: []const ?@import("model_candidate_origin.zig").Origin,
    origin: ?@import("model_candidate_origin.zig").Origin,
    repair_rejection: ?@import("source_omission.zig").Rejection,

    pub fn from(purpose: @import("specification_support.zig").Purpose, inputs: authority.Inputs, rejection: ?@import("source_omission.zig").Rejection) SupportFindings {
        return .{ .purpose = purpose, .revision = inputs.revision, .evidence = inputs.evidence, .origins = inputs.review_origins, .origin = inputs.review_origin, .repair_rejection = rejection };
    }
};
