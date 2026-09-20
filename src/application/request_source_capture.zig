//! Pure projection of the selected immutable workflow and retained request.
//! Allocations belong to the capture's temporary arena.
const std = @import("std");
const source = @import("../domain/request_source_snapshot.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const handoff = @import("../domain/model_request_handoff.zig");
pub const Context = struct { graph: *const compilation.CompiledWorkflow, request: *const handoff.Request };
pub const Error = std.mem.Allocator.Error || error{InvalidSourceCapture};

pub fn snapshot(a: std.mem.Allocator, context: Context, caller: []const u8, credentials: []const []const u8) Error!?source.Snapshot {
    const graph = context.graph;
    const document = graph.source orelse return null;
    const request = context.request;
    var resources: std.ArrayList(source.Resource) = .empty;
    const selected = request.sourceResources();
    try append(a, &resources, graph, .prompt, selected.prompt.bytes, credentials);
    if (selected.protocol_prompt) |id| try append(a, &resources, graph, .protocol_prompt, id.bytes, credentials);
    try append(a, &resources, graph, .result, selected.result.bytes, credentials);
    if (selected.input) |id| try append(a, &resources, graph, .input, id.bytes, credentials);
    var selection: source.Selection = .{ .definition = null, .part = null, .paths = &.{} };
    if (request.selectedResultDefinition()) |definition| {
        selection.definition = definition.bytes;
    }
    if (request.part()) |binding| {
        const resource = for (graph.authority.resources) |resource| {
            if (resource.content == .json_composition and resource.content.json_composition == binding.plan) break resource;
        } else return error.InvalidSourceCapture;
        try append(a, &resources, graph, .composition, resource.id.bytes, credentials);
        const part = binding.plan.parts()[binding.part];
        selection.part = part.id.bytes;
        if (binding.plan.definition()) |definition| selection.definition = definition.bytes;
        const paths = try a.alloc([]const []const u8, part.paths.len);
        for (paths, part.paths) |*destination, path| destination.* = path.segments;
        selection.paths = paths;
    }
    return .{
        .workflow = graph.authority.workflow_id.bytes,
        .document = try captureDocument(a, document.path, document.content, credentials),
        .caller = try location(a, graph, caller, credentials),
        .preparation = try location(a, graph, request.binding().operation_id.workflow_step_id.bytes, credentials),
        .resources = resources.items,
        .selection = selection,
    };
}
fn location(a: std.mem.Allocator, graph: *const compilation.CompiledWorkflow, id: []const u8, credentials: []const []const u8) Error!source.Location {
    for (graph.authority.steps) |step| if (std.mem.eql(u8, step.id.bytes, id)) {
        if (step.source_chain.len == 0) return error.InvalidSourceCapture;
        const chain = try a.dupe(source.Entry, step.source_chain);
        for (chain) |*entry| entry.declaration = (try captureDocument(a, "entry", entry.declaration, credentials)).content;
        return .{ .step = id, .chain = chain };
    };
    return error.InvalidSourceCapture;
}
fn append(a: std.mem.Allocator, list: *std.ArrayList(source.Resource), graph: *const compilation.CompiledWorkflow, role: @FieldType(source.Resource, "role"), id: []const u8, credentials: []const []const u8) Error!void {
    for (graph.authority.resources) |resource| if (std.mem.eql(u8, resource.id.bytes, id)) {
        try list.append(a, .{ .role = role, .alias = id, .kind = resource.kind(), .document = try captureDocument(a, resource.source_path orelse return error.InvalidSourceCapture, resource.bytes(), credentials) });
        return;
    };
    return error.InvalidSourceCapture;
}
fn captureDocument(a: std.mem.Allocator, path: []const u8, bytes: []const u8, credentials: []const []const u8) Error!source.Document {
    const clean = try @import("../domain/model_log_redaction.zig").sanitize(a, bytes, credentials);
    if (clean.encoding != .utf8) return error.InvalidSourceCapture;
    return .{ .path = path, .content = clean.bytes, .redacted = clean.redacted };
}
