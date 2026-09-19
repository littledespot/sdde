//! Persisted comparison evidence for compiled extraction bindings. It is never
//! parsed as a schema, request, executable graph or fallback authority.
const std = @import("std");
const compilation = @import("workflow_compilation.zig");
const workflow = @import("workflow.zig");
const pipeline = @import("pipeline.zig");
pub const Error = std.mem.Allocator.Error || error{REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE};
pub const Resource = struct { id: workflow.WorkflowResourceId, bytes: []const u8 };
pub const Part = struct { node: workflow.WorkflowStepId, operation: workflow.OperationId, parameters: []const compilation.CompiledParameter };
pub const Extraction = struct {
    node: workflow.WorkflowStepId,
    assembly_node: workflow.WorkflowStepId,
    result_schema: Resource,
    composition: Resource,
    parts: []const Part,
};
pub const Binding = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    request_contract: enum { @"model-request/v1" },
    partition: @FieldType(@import("reference_evidence.zig").Chunks, "partition"),
    extractions: []const Extraction,
};

/// Borrows captured graph bytes; the caller retains the compiled authority.
pub fn capture(allocator: std.mem.Allocator, authority: compilation.SemanticAuthority, partition: @FieldType(Binding, "partition")) Error!Binding {
    const flow = @import("workflow_data_flow.zig").analyze(allocator, authority) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else unavailable();
    defer allocator.free(flow);
    var extractions: std.ArrayList(Extraction) = .empty;
    errdefer {
        for (extractions.items) |entry| allocator.free(entry.parts);
        extractions.deinit(allocator);
    }
    for (authority.steps, 0..) |step, index| {
        if (!contains(step.replaces, .reference_extraction_progress) or !contains(step.requires, .validated_assembled_json)) continue;
        const producers = @import("workflow_data_flow.zig").producers(allocator, authority, index, .assembled_json) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else unavailable();
        defer allocator.free(producers);
        if (producers.len == 0) return unavailable();
        for (producers) |assembly| {
            const plan = (flow[assembly] orelse return unavailable()).composition.plan orelse return unavailable();
            const selected = for (authority.resources) |resource| {
                if (resource.content == .json_composition and resource.content.json_composition == plan) break resource;
            } else return unavailable();
            var parts: std.ArrayList(Part) = .empty;
            errdefer parts.deinit(allocator);
            for (authority.steps, 0..) |producer, producer_index| {
                if ((flow[producer_index] orelse return unavailable()).composition.plan != plan or
                    !@import("workflow_model.zig").assignsRequest(producer.produces, producer.replaces)) continue;
                try parts.append(allocator, .{ .node = producer.id, .operation = producer.operation_id, .parameters = producer.parameters });
            }
            if (parts.items.len == 0) return unavailable();
            const owned_parts = try parts.toOwnedSlice(allocator);
            errdefer allocator.free(owned_parts);
            try extractions.append(allocator, .{
                .node = step.id,
                .assembly_node = authority.steps[assembly].id,
                .result_schema = .{ .id = plan.resultAlias(), .bytes = plan.resultSchema().bytes() },
                .composition = .{ .id = selected.id, .bytes = selected.bytes() },
                .parts = owned_parts,
            });
        }
    }
    if (extractions.items.len == 0) return unavailable();
    return .{ .workflow_id = authority.workflow_id, .workflow_version = authority.workflow_version, .request_contract = .@"model-request/v1", .partition = partition, .extractions = try extractions.toOwnedSlice(allocator) };
}

pub fn validate(allocator: std.mem.Allocator, stored: ?Binding, authority: ?*const compilation.SemanticAuthority, partition: @FieldType(Binding, "partition")) Error!void {
    const binding = stored orelse return unavailable();
    const current = authority orelse return unavailable();
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const expected = try capture(a, current.*, partition);
    // Both values have the same closed native type and deterministic field order.
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, expected, .{}), try std.json.Stringify.valueAlloc(a, binding, .{}))) return unavailable();
}

fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}
fn unavailable() Error {
    return error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE;
}
