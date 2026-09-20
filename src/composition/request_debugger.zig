//! Native diagnostic composition; it never constructs or invokes a workflow runner.
const std = @import("std");
const debug = @import("../domain/request_debugger.zig");
const ports = @import("../ports/request_replay.zig");
const runtime_module = @import("root.zig");
const store_module = @import("../adapters/filesystem/request_debugger_store.zig");
const provider_module = @import("../adapters/provider/request_replay.zig");
const server_module = @import("../adapters/system/request_debugger_server.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, feature_name: []const u8, environment: *const std.process.Environ.Map) !void {
    const feature_id = @import("../domain/feature_identity.zig").FeatureId.parse(feature_name) orelse return error.InvalidFeatureDirectory;
    var runtime: runtime_module.Runtime = undefined;
    runtime.init(io, allocator, .cwd(), .{});
    defer runtime.deinit();
    if (runtime.boot != .ready) return error.DebuggerBootstrapFailed;
    const roots = runtime.boot.ready.roots.registry();
    const directories = @import("../adapters/filesystem/directory_access.zig");
    const specs = try directories.open(io, .cwd(), roots.featureDirectoryRoots().specs);
    defer specs.close(io);
    const feature = try directories.open(io, specs, feature_id.bytes);
    defer feature.close(io);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var store: store_module.Store = .{ .io = io, .feature = feature };
    var authority: Authority = .{ .runtime = &runtime };
    var compiler: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var provider: provider_module.Adapter = .{
        .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = Authority.authorize },
        .environment = environment,
        .transport = runtime.provider_runtime.transport.port(),
        .clock = runtime.clock.clock(),
        .compiler = compiler.compiler(),
    };
    var random: [16]u8 = undefined;
    io.random(&random);
    const run_id = try std.fmt.allocPrint(arena.allocator(), "debugger-{s}", .{std.fmt.bytesToHex(random, .lower)});
    var session: Session = .{ .io = io, .allocator = arena.allocator(), .run_id = .{ .bytes = run_id }, .service = .{ .provider = provider.provider(), .store = store.port() } };
    try session.calls.appendSlice(session.allocator, try store.load(session.allocator));
    try session.inspect();
    try (server_module.Server{ .io = io, .allocator = allocator, .session = .{ .context = @ptrCast(&session), .list_fn = Session.list, .replay_fn = Session.replay } }).serve();
}

const Authority = struct {
    runtime: *runtime_module.Runtime,
    fn authorize(context: *ports.Context, description: debug.Description) ports.Error!void {
        const self: *Authority = @ptrCast(@alignCast(context));
        const services = &self.runtime.boot.ready;
        const graph = services.workflows.registry().resolve(.{ .bytes = description.workflow_id }) orelse return error.ReplayUnauthorized;
        const selected: @import("../domain/workflow_execution.zig").SelectedWorkflow = .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} }, .graph = graph };
        var outcome = self.runtime.providers.bind().invoke(&selected, &services.config.config().models, services.roots.registry().llmProviderConfig());
        defer outcome.deinit();
        if (outcome != .ready) return error.ReplayUnauthorized;
        const binding = (@import("../actions/provider/resolve_provider_model_binding.zig").Action{}).execute(graph, .{ .bytes = description.request_step }, outcome.ready.registry(), outcome.ready.allowlist()) catch return error.ReplayUnauthorized;
        if (!std.mem.eql(u8, binding.slot_id.bytes, description.model_slot) or !std.mem.eql(u8, binding.registry_entry.provider.bytes, description.provider) or !std.mem.eql(u8, binding.registry_entry.model.bytes, description.model) or
            !std.meta.eql(binding.registry_entry.config, description.provider_config) or !debug.sameOptional(binding.reasoning_effort, description.reasoning_effort) or
            !std.meta.eql(binding.controls, description.controls) or binding.response_mode != description.response_mode) return error.ReplayUnauthorized;
    }
};
const Session = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    run_id: @import("../domain/telemetry.zig").Identifier,
    next_sequence: u64 = 1,
    service: @import("../application/request_replay.zig").Service,
    calls: std.ArrayList(debug.Call) = .empty,

    fn inspect(self: *Session) ports.Error!void {
        for (self.calls.items) |*call| {
            if (call.description != null and call.response != null and debug.sameOptional(call.response_provenance, "provider_body") and std.mem.eql(u8, call.response_encoding, "utf8")) call.validation = try self.service.provider.inspect(self.allocator, call.description.?, call.response.?);
        }
    }
    fn list(context: *ports.Context, _: std.mem.Allocator) ports.Error![]const debug.Call {
        const self: *Session = @ptrCast(@alignCast(context));
        return self.calls.items;
    }
    fn replay(context: *ports.Context, _: std.mem.Allocator, input: debug.ReplayInput) ports.Error![]const debug.Call {
        const self: *Session = @ptrCast(@alignCast(context));
        if (input.call >= self.calls.items.len) return error.InvalidReplay;
        const parent = self.calls.items[input.call];
        var random: [16]u8 = undefined;
        self.io.random(&random);
        const id = try self.allocator.dupe(u8, &std.fmt.bytesToHex(random, .lower));
        const sequence = self.next_sequence;
        self.next_sequence = std.math.add(u64, sequence, 1) catch return error.InvalidReplay;
        const result = try self.service.replay(self.allocator, .{ .id = id, .run = self.run_id, .sequence = sequence }, parent, input);
        // The incoming HTTP edit is request-scoped; own the retained descriptor.
        const encoded = try std.json.Stringify.valueAlloc(self.allocator, result.request.description, .{});
        const description = debug.Description.decode(self.allocator, encoded) catch return error.InvalidReplay;
        try self.calls.append(self.allocator, .{
            .run = self.run_id.bytes,
            .sequence = sequence,
            .execution_order = sequence,
            .id = id,
            .workflow = description.workflow_id,
            .action = "replay-model-request",
            .node = parent.node,
            .request_step = description.request_step,
            .slot = description.model_slot,
            .kind = "replay",
            .original = parent.original,
            .original_run = result.request.original_run,
            .parent = parent.id,
            .parent_run = parent.run,
            .description = description,
            .source_snapshot = result.request.source_snapshot,
            .source_overrides = result.request.source_overrides,
            .request = result.request.body,
            .request_complete = true,
            .replay = input.mode,
            .response = result.response.body,
            .response_provenance = if (result.response.outcome == .received and result.response.status == 200) "provider_body" else @tagName(result.response.outcome),
            .response_encoding = @tagName(result.response.encoding),
            .response_status = result.response.status,
            .response_diagnostic = result.response.diagnostic,
            .validation = result.validation,
        });
        return self.calls.items;
    }
};
