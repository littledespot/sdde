//! Read-only projection of native validation evidence, independent of workflow
//! names, step IDs, providers and the lifetime of a released model request.
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const Diagnostic = @import("../domain/candidate_validation_diagnostic.zig").Diagnostic;
pub fn read(view: *const data.View) values.Error!?Diagnostic {
    const extraction = @import("reference_extraction_workflow.zig");
    if (view.contains(extraction.validated_schema.key)) {
        const value = try values.read(view, extraction.validated_schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .citation_rejected) return .{ .source_selections = value.payload().citation_rejected };
    }
    if (view.contains(extraction.selections_schema.key)) {
        const value = try values.read(view, extraction.selections_schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .token_classification_rejected) return .{ .token_classifications = value.payload().token_classification_rejected };
        if (value.payload().* == .citation_rejected) return .{ .source_selections = value.payload().citation_rejected };
    }
    const spec = @import("specification_repair_workflow.zig");
    if (view.contains(spec.authorization_schema.key)) {
        const storage = @import("specification_values.zig").storage;
        const value = storage.payload(try values.read(view, spec.authorization_schema, storage.Value));
        if (value.* == .repair_authorization) {
            const authorization = value.repair_authorization;
            return .{ .specification_repair = .{ .owner = authorization.owner, .revision = authorization.revision, .target = authorization.target, .rule = authorization.rule } };
        }
    }
    return null;
}
