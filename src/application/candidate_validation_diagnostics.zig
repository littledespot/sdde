//! Read-only projection of native validation evidence, independent of workflow
//! names, step IDs, providers and the lifetime of a released model request.
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const Diagnostic = @import("../domain/candidate_validation_diagnostic.zig").Diagnostic;
pub fn read(view: *const data.View) values.Error!?Diagnostic {
    if (try @import("source_omission_repair_workflow.zig").rejection(view)) |rejected| return .{ .support_findings = .from(.source, rejected.support.inputs, rejected.reason) };
    const extraction = @import("reference_extraction_workflow.zig");
    if (view.contains(extraction.text_schema.key)) {
        const value = try values.read(view, extraction.text_schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .text_rejected) return .{ .extraction_text = value.payload().text_rejected };
    }
    if (view.contains(extraction.validated_schema.key)) {
        const value = try values.read(view, extraction.validated_schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .citation_rejected) return .{ .source_selections = value.payload().citation_rejected };
    }
    if (view.contains(extraction.selections_schema.key)) {
        const value = try values.read(view, extraction.selections_schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .token_classification_rejected) return .{ .token_classifications = value.payload().token_classification_rejected };
        if (value.payload().* == .citation_rejected) return .{ .source_selections = value.payload().citation_rejected };
    }
    const reconciliation = @import("reference_reconciliation_workflow.zig");
    if (try @import("reference_reconciliation_repair_workflow.zig").diagnostic(view)) |rejection| return .{ .reconciliation = rejection };
    for ([_]data.Schema{ reconciliation.summary_schema, reconciliation.dispositions_schema, reconciliation.signals_schema, reconciliation.conflicts_schema }) |schema| {
        if (!view.contains(schema.key)) continue;
        const value = try values.read(view, schema, @import("../domain/reference_candidate_value.zig").Value);
        if (value.payload().* == .reconciliation_rejected) return .{ .reconciliation = value.payload().reconciliation_rejected };
    }
    const spec = @import("specification_workflow.zig");
    if (view.contains(spec.checked_schema.key)) {
        const storage = @import("specification_values.zig").storage;
        const value = storage.payload(try values.read(view, spec.checked_schema, storage.Value));
        if (value.* == .unit_rejected) return .{ .specification = value.unit_rejected };
    }
    const storage = @import("specification_values.zig").storage;
    const repair_schema = @import("specification_coverage_repair_workflow.zig").schema;
    if (view.contains(repair_schema.key)) {
        const value = storage.payload(try values.read(view, repair_schema, storage.Value));
        if (value.* == .coverage_repair) return .{ .coverage = switch (value.coverage_repair) {
            .authorized => |authorized| authorized.rule.coverage,
            .blocked => |blocked| blocked,
        } };
    }
    if (view.contains(spec.coverage_schema.key)) {
        const value = storage.payload(try values.read(view, spec.coverage_schema, storage.Value));
        if (value.* == .coverage_rejected) return .{ .coverage = value.coverage_rejected };
    }
    const support = @import("specification_support_workflow.zig");
    if (view.contains(support.schema.key)) {
        const storage_authority = @import("required_authority_values.zig");
        const value = storage_authority.payload(try values.read(view, support.schema, storage_authority.Value));
        inline for (.{ .support, .principle_support }) |tag| if (value.* == tag) {
            const selected = if (tag == .support) value.support else value.principle_support.result;
            switch (selected) {
                .rejected => |rejected| return if (tag == .support) .{ .support = rejected.rejection } else .{ .principle_review = rejected.rejection },
                .accepted => |accepted| for (accepted.inputs.evidence) |evidence| {
                    if (evidence.finding != .supported) return .{ .support_findings = .from(if (tag == .support) .source else .principles, accepted.inputs, null) };
                },
            }
        };
    }
    return null;
}
