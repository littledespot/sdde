//! Pure projection of the selected immutable workflow and retained request.
//! Allocations belong to the capture's temporary arena.
const std = @import("std");
const source = @import("../domain/request_source_snapshot.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const handoff = @import("../domain/model_request_handoff.zig");
pub const Context = struct { graph: *const compilation.CompiledWorkflow, request: *const handoff.Request };
pub const Error = std.mem.Allocator.Error || error{ MissingCompositionResource, MissingSourceStep, MissingSourceChain, MissingSourceResource, MissingSourceResourcePath, InvalidSourceEncoding };
pub fn rejection(cause: Error) ?source.CaptureRejection {
    return switch (cause) {
        error.OutOfMemory => null,
        error.MissingCompositionResource => .missing_composition_resource,
        error.MissingSourceStep => .missing_step,
        error.MissingSourceChain => .missing_source_chain,
        error.MissingSourceResource => .missing_resource,
        error.MissingSourceResourcePath => .missing_resource_path,
        error.InvalidSourceEncoding => .invalid_source_encoding,
    };
}

pub fn snapshot(a: std.mem.Allocator, context: Context, caller: []const u8, credentials: []const []const u8) Error!?source.Snapshot {
    const graph = context.graph;
    const document = graph.source orelse return null;
    const request = context.request;
    var resources: std.ArrayList(source.Resource) = .empty;
    const selected = request.sourceResources();
    try append(a, &resources, graph, .prompt, selected.prompt.bytes, credentials);
    if (selected.context) |id| try append(a, &resources, graph, .context, id.bytes, credentials);
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
        } else return error.MissingCompositionResource;
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
        if (step.source_chain.len == 0) return error.MissingSourceChain;
        const chain = try a.dupe(source.Entry, step.source_chain);
        for (chain) |*entry| entry.declaration = (try captureDocument(a, "entry", entry.declaration, credentials)).content;
        return .{ .step = id, .chain = chain };
    };
    return error.MissingSourceStep;
}
fn append(a: std.mem.Allocator, list: *std.ArrayList(source.Resource), graph: *const compilation.CompiledWorkflow, role: @FieldType(source.Resource, "role"), id: []const u8, credentials: []const []const u8) Error!void {
    for (graph.authority.resources) |resource| if (std.mem.eql(u8, resource.id.bytes, id)) {
        try list.append(a, .{ .role = role, .alias = id, .kind = resource.kind(), .document = try captureDocument(a, resource.source_path orelse return error.MissingSourceResourcePath, resource.bytes(), credentials) });
        return;
    };
    return error.MissingSourceResource;
}
fn captureDocument(a: std.mem.Allocator, path: []const u8, bytes: []const u8, credentials: []const []const u8) Error!source.Document {
    const clean = try @import("../domain/model_log_redaction.zig").sanitize(a, bytes, credentials);
    if (clean.encoding != .utf8) return error.InvalidSourceEncoding;
    return .{ .path = path, .content = clean.bytes, .redacted = clean.redacted };
}

test "source projection diagnoses invalid source bytes and retains credential redaction" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const clean = try captureDocument(a, "prompt.md", "before secret-value after", &.{"secret-value"});
    try std.testing.expectEqualStrings("before [REDACTED_CREDENTIAL] after", clean.content);
    try std.testing.expect(clean.redacted);
    try std.testing.expectError(error.InvalidSourceEncoding, captureDocument(a, "prompt.md", "\xff", &.{}));
    try std.testing.expectEqual(.invalid_source_encoding, rejection(error.InvalidSourceEncoding).?);
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, captureDocument(failing.allocator(), "prompt.md", "complete bytes", &.{}));
    try std.testing.expect(rejection(error.OutOfMemory) == null);
}

test "source projection diagnoses missing resources paths steps and source chains" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var steps = [_]compilation.CompiledStep{.{
        .id = .{ .bytes = "call" },
        .operation_id = .{ .bytes = "invoke-model" },
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    }};
    var resources = [_]compilation.CompiledResource{.{ .id = .{ .bytes = "prompt" }, .content = .{ .prompt = "source-secret" } }};
    const graph: compilation.CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = try @import("../domain/telemetry.zig").WorkflowShortcode.parse("SPEC"),
        .authority = .{
            .workflow_id = .{ .bytes = "unrelated-workflow" },
            .workflow_version = 1,
            .invocation_operation_id = .{ .bytes = "core.empty-invocation" },
            .policy_profile_id = .{ .bytes = "core.capability-free@1" },
            .start_step_id = steps[0].id,
            .invocation_outputs = &.{},
            .resources = &resources,
            .steps = &steps,
            .transitions = &.{},
            .maximum_step_executions = 1,
        },
    };
    var selected: std.ArrayList(source.Resource) = .empty;
    try std.testing.expectError(error.MissingSourceResource, append(a, &selected, &graph, .prompt, "foreign", &.{}));
    try std.testing.expectError(error.MissingSourceResourcePath, append(a, &selected, &graph, .prompt, "prompt", &.{}));
    resources[0].source_path = "prompt.md";
    try append(a, &selected, &graph, .prompt, "prompt", &.{"source-secret"});
    try std.testing.expectEqualStrings("[REDACTED_CREDENTIAL]", selected.items[0].document.content);
    try std.testing.expectError(error.MissingSourceStep, location(a, &graph, "foreign", &.{}));
    try std.testing.expectError(error.MissingSourceChain, location(a, &graph, "call", &.{}));
    steps[0].source_chain = &.{.{ .id = "call", .subgraph = null, .kind = .operation, .target = "invoke-model", .declaration = "use: source-secret" }};
    const caller = try location(a, &graph, "call", &.{"source-secret"});
    try std.testing.expectEqualStrings("use: [REDACTED_CREDENTIAL]", caller.chain[0].declaration);
    try std.testing.expectEqual(.missing_resource, rejection(error.MissingSourceResource).?);
    try std.testing.expectEqual(.missing_resource_path, rejection(error.MissingSourceResourcePath).?);
    try std.testing.expectEqual(.missing_step, rejection(error.MissingSourceStep).?);
    try std.testing.expectEqual(.missing_source_chain, rejection(error.MissingSourceChain).?);
    try std.testing.expectEqual(.missing_composition_resource, rejection(error.MissingCompositionResource).?);
}
