const std = @import("std");
const evidence = @import("../domain/reference_evidence.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
const maximum = 64 * 1024 * 1024;
// The stage action `prepare-reference-evidence` publishes the citable inputs; the corpus and chunks
// stay function-local (ADR 0031).
pub const inputs_schema = values.schema(.citable_reference_inputs, evidence.Inputs, 1, maximum);
pub const proposals_schema = values.schema(.reference_citation_proposals, evidence.CitationProposals, 1, maximum);
pub const citations_schema = values.schema(.validated_source_citations, evidence.ValidatedCitations, 1, maximum);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ inputs_schema, proposals_schema, citations_schema };

pub const ValidateCitations = struct {
    pub const Action = @import("../actions/reference/validate_source_citations.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, inputs_schema, evidence.Inputs) catch |operation_error| return operation_error;
        const proposals = values.read(&input.step.data, proposals_schema, evidence.CitationProposals) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), source.*, proposals.*) catch |operation_error| return operation_error;
        return publish(self.allocator, citations_schema, evidence.ValidatedCitations, result);
    }
};
