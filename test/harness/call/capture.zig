//! Read-only selection of an exact recorded exchange, never workflow recovery.
const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");
const engine_config = @import("../../../src/domain/config.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const files = @import("../files.zig");
const paths = @import("../contracts.zig");
const workflow_ids = @import("../../../src/domain/workflow.zig");
const CallContext = @import("../e2e/call_context.zig").CallContext;

pub const Captured = struct {
    arena: std.heap.ArenaAllocator,
    config_owner: engine_config.Owned,
    call: debug.Call,
    config: engine_config.SDDToolKitConfig,
    provider_catalogue: []const u8,
    context: CallContext,
    run_path: []const u8,
    feature_path: []const u8,
    context_path: []const u8,
    request_path: []const u8,

    pub fn deinit(self: *Captured) void {
        self.config_owner.deinit();
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn load(io: std.Io, allocator: std.mem.Allocator, root: std.Io.Dir, run_path: []const u8, workflow: []const u8, ordinal: u32) !Captured {
    try paths.path(run_path);
    if (workflow_ids.WorkflowId.parse(workflow) == null or ordinal == 0) return error.InvalidCallSelection;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const run = try directories.open(io, root, run_path);
    defer run.close(io);
    const selected = try @import("../e2e/contracts.zig").parse(a, try files.read(io, a, run, "case.json"));
    if (!std.mem.eql(u8, selected.workflow_id, workflow)) return error.CapturedWorkflowMismatch;
    const project = try directories.open(io, run, "project");
    defer project.close(io);
    const config_bytes = try files.read(io, a, project, engine_config.engine_config_basename);
    if (config_bytes.len > engine_config.max_engine_config_bytes) return error.EngineConfigParseError;
    var config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(allocator, config_bytes);
    errdefer config.deinit();
    const policy = try @import("../../../src/adapters/filesystem/workspace_path_policy.zig").Resolver.init(io, project).resolve(a);
    const specs = try (@import("../../../src/actions/bootstrap/validate_configured_root_path_policy.zig").Action{ .policy = policy }).execute(a, .specs, config.config.paths.specs);
    const providers = try (@import("../../../src/actions/bootstrap/validate_llm_provider_config_path_policy.zig").Action{ .policy = policy }).execute(a, config.config.paths.providers);
    const catalogue = try files.read(io, a, project, providers.relative_path);
    const feature_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ specs.relative_path, selected.feature });
    try paths.path(feature_path);
    const feature = try directories.open(io, project, feature_path);
    defer feature.close(io);
    const context_relative = try @import("../evidence.zig").Store.path(a, .generation, ordinal, .context);
    const request_relative = try @import("../evidence.zig").Store.path(a, .generation, ordinal, .request);
    const context_bytes = try files.read(io, a, run, context_relative);
    const request_bytes = try files.read(io, a, run, request_relative);
    if (redacted(context_bytes) or redacted(request_bytes)) return error.CaptureRedacted;
    const context = try CallContext.decode(a, context_bytes);
    var store: @import("../../../src/adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = feature };
    const call = try select(try store.load(a), context, workflow, ordinal, request_bytes);
    const owned_run_path = try a.dupe(u8, run_path);
    const context_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ run_path, context_relative });
    const request_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ run_path, request_relative });
    return .{
        .arena = arena,
        .config_owner = config,
        .call = call,
        .config = config.config,
        .provider_catalogue = catalogue,
        .context = context,
        .run_path = owned_run_path,
        .feature_path = feature_path,
        .context_path = context_path,
        .request_path = request_path,
    };
}

/// Origins are execution-local. Multiple archive runs with the same workflow
/// and identity are ambiguous even when one happens to have matching bytes.
pub fn select(calls: []const debug.Call, context: CallContext, workflow: []const u8, ordinal: u32, wire: []const u8) !debug.Call {
    if (ordinal == 0 or context.call != ordinal) return error.CaptureMismatch;
    if (context.kind != .inference or context.origin.kind != .inference) return error.CaptureNotInference;
    var id_buffer: [128]u8 = undefined;
    const id = try @import("../../../src/domain/model_call_lineage.zig").callId(&id_buffer, context.origin);
    var selected: ?debug.Call = null;
    for (calls) |call| {
        if (!std.mem.eql(u8, call.id, id) or !std.mem.eql(u8, call.workflow, workflow)) continue;
        if (selected != null) return error.CaptureAmbiguous;
        selected = call;
    }
    const call = selected orelse return error.CaptureMissing;
    if (call.replay != null) return error.CaptureMismatch;
    if (call.redacted or redacted(wire)) return error.CaptureRedacted;
    if (!call.request_complete or call.request == null or call.description == null) return error.CaptureIncomplete;
    const description = call.description.?;
    if (description.operation_kind != .inference) return error.CaptureNotInference;
    if (workflow_ids.WorkflowStepId.parse(call.node) == null or workflow_ids.OperationId.parse(call.action) == null or
        !std.mem.eql(u8, call.request.?, wire) or !std.mem.eql(u8, call.request_step, context.request_step) or
        !std.mem.eql(u8, call.slot, context.slot) or !std.mem.eql(u8, description.workflow_id, workflow) or
        !std.mem.eql(u8, description.request_step, context.request_step) or !std.mem.eql(u8, description.model_slot, context.slot) or
        !std.mem.eql(u8, description.model, context.model) or !debug.sameOptional(description.reasoning_effort, context.reasoning_effort) or
        description.response_mode != context.response_mode or !std.mem.eql(u8, description.schema, context.response_schema) or
        description.content.len != context.content.len or context.attempt != context.origin.attempt.value) return error.CaptureMismatch;
    if (description.provider_config != .aws_bedrock or description.provider_config.aws_bedrock.region != context.region) return error.CaptureMismatch;
    for (description.content, context.content) |expected, actual| {
        if (std.meta.activeTag(expected) != std.meta.activeTag(actual) or !std.mem.eql(u8, expected.bytes(), actual.bytes())) return error.CaptureMismatch;
    }
    if (call.source_snapshot) |snapshot| {
        if (!snapshot.matches(workflow, call.node, context.request_step)) return error.CaptureMismatch;
        if (snapshot.document.redacted) return error.CaptureRedacted;
        for (snapshot.resources) |resource| if (resource.document.redacted) return error.CaptureRedacted;
    }
    return call;
}

fn redacted(bytes: []const u8) bool {
    return std.mem.indexOf(u8, bytes, @import("../../../src/domain/model_log_redaction.zig").marker) != null;
}
