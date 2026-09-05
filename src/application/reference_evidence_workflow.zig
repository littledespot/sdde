const std = @import("std");
const evidence = @import("../domain/reference_evidence.zig");
const ingestion = @import("reference_ingestion_workflow.zig");
const reference = @import("../domain/reference_ingestion.zig");
const feature = @import("../domain/feature_directory.zig");
const feature_values = @import("feature_directory_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
const maximum = 64 * 1024 * 1024;
pub const corpus_schema = values.schema(.identified_reference_corpus, evidence.Corpus, 1, maximum);
pub const chunks_schema = values.schema(.reference_chunks, evidence.Chunks, 1, maximum);
pub const inputs_schema = values.schema(.citable_reference_inputs, evidence.Inputs, 1, maximum);
pub const proposals_schema = values.schema(.reference_citation_proposals, evidence.CitationProposals, 1, maximum);
pub const citations_schema = values.schema(.validated_source_citations, evidence.ValidatedCitations, 1, maximum);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ corpus_schema, chunks_schema, inputs_schema, proposals_schema, citations_schema };

pub const Assign = struct {
    pub const Action = @import("../actions/reference/assign_reference_identities.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, ingestion.inputs_schema, reference.Inputs) catch return error.OperationExecutionFailed;
        const directory = values.read(&input.step.data, feature_values.directory, feature.Directory) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), source.*, directory.selector.feature_id) catch return error.OperationExecutionFailed;
        return publish(self.allocator, corpus_schema, evidence.Corpus, result);
    }
};
pub const BuildChunks = struct {
    pub const Action = @import("../actions/reference/build_reference_chunks.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const corpus = values.read(&input.step.data, corpus_schema, evidence.Corpus) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), corpus.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, chunks_schema, evidence.Chunks, result);
    }
};
pub const ValidateChunks = struct {
    pub const Action = @import("../actions/reference/validate_reference_chunks.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, ingestion.inputs_schema, reference.Inputs) catch return error.OperationExecutionFailed;
        const directory = values.read(&input.step.data, feature_values.directory, feature.Directory) catch return error.OperationExecutionFailed;
        const corpus = values.read(&input.step.data, corpus_schema, evidence.Corpus) catch return error.OperationExecutionFailed;
        const chunks = values.read(&input.step.data, chunks_schema, evidence.Chunks) catch return error.OperationExecutionFailed;
        const result = self.action.execute(source.*, directory.selector.feature_id, corpus.*, chunks.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, inputs_schema, evidence.Inputs, result);
    }
};
pub const ValidateCitations = struct {
    pub const Action = @import("../actions/reference/validate_source_citations.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const proposals = values.read(&input.step.data, proposals_schema, evidence.CitationProposals) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), source.*, proposals.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, citations_schema, evidence.ValidatedCitations, result);
    }
};
