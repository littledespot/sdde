const std = @import("std");
const options_module = @import("options.zig");
const binding_module = @import("../diagnostic_binding.zig");
const report_module = @import("report.zig");
pub const output_root = "zig-out/e2e-call";

pub fn main(init: std.process.Init) !void {
    const succeeded = command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Call diagnostic failed: {s}.\n", .{@errorName(err)}));
        std.process.exit(1);
    };
    if (!succeeded) std.process.exit(1);
}

fn command(init: std.process.Init) !bool {
    const io = init.io;
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: scripts/e2e-call.sh --run <captured-E2E-directory> --workflow <workflow-id> --call <positive-ordinal> --model <model-id> --reasoning-effort <effort|none> [--repeats <positive-count>]\n" ++
            "Makes one live diagnostic call per repeat (default 1), using unchanged captured input/schema. Explicit model and reasoning are validated against the retained project's provider catalogue and registered provider capabilities. Preserves temperature, response mode and output-token allowance. No retries, repair, workflow continuation, publication or rubric grading.\n" ++
            "Requires TEST_AWS_BEARER_TOKEN_BEDROCK. The shell launcher loads .env.e2e; direct Zig invocation does not. Results: zig-out/e2e-call/<UTC-run>/report.md and report.json.\n");
        return true;
    }
    const options = options_module.parse(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Invalid arguments; use --help. No API call made.\n");
        return false;
    };
    var captured = try @import("capture.zig").load(io, a, .cwd(), options.run, options.workflow, options.call);
    defer captured.deinit();
    const original = captured.call.description.?;
    const binding = try binding_module.rebind(a, original, captured.provider_catalogue, options.model, options.reasoning_effort);
    var authority: binding_module.Authorization = .{ .binding = original };
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const key = @import("../environment.zig").credential(init.environ_map, .bedrock_invoke) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Set a valid TEST_AWS_BEARER_TOKEN_BEDROCK test credential; no API call made.\n");
        return false;
    };
    try environment.put("AWS_BEARER_TOKEN_BEDROCK", key);
    var clock: @import("../../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var transport: @import("../../../src/adapters/provider/bedrock_http.zig").Adapter = .{ .io = io, .clock = clock.clock(), .runtime = .{} };
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var provider: @import("../../../src/adapters/provider/request_replay.zig").Adapter = .{
        .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = binding_module.Authorization.authorize },
        .environment = &environment,
        .transport = transport.port(),
        .clock = clock.clock(),
        .compiler = parser.compiler(),
    };
    // Reconstruct the original with the canonical encoder before overriding it.
    try binding_module.validateBinding(original);
    if (!std.mem.eql(u8, try provider.provider().prepare(a, original), captured.call.request.?)) return error.CaptureMismatch;
    authority.binding = binding;
    // Validate schema, serialization and credential exclusion before dispatch.
    _ = try provider.provider().prepare(a, binding);
    const output_parent = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, .cwd(), output_root);
    defer output_parent.close(io);
    const run = try @import("../e2e/run_directory.zig").Run.create(io, output_parent);
    defer run.close(io);
    const output = try @import("../e2e/report.zig").Output.reserve(io, run.dir);
    defer output.close(io);
    var report: report_module.Report = .{
        .started_at_utc = &run.started_at_utc,
        .options = options,
        .parent_run = captured.call.run,
        .parent_call = captured.call.id,
        .original_binding = original,
        .effective_binding = binding,
        .context_path = captured.context_path,
        .request_path = captured.request_path,
    };
    const plan = try std.json.Stringify.valueAlloc(a, .{ .selection = report, .source_snapshot = captured.call.source_snapshot }, .{ .whitespace = .indent_2 });
    var sanitized = try @import("../../../src/domain/model_log_redaction.zig").sanitize(a, plan, &.{key});
    defer sanitized.deinit(a);
    if (sanitized.redacted) return error.InvalidReplay;
    try @import("../output.zig").write(io, run.dir, "plan.json", plan);
    var store: @import("../../../src/adapters/filesystem/request_debugger_store.zig").Store = .{ .io = io, .feature = run.dir };
    const service: @import("../../../src/application/request_replay.zig").Service = .{ .provider = provider.provider(), .store = store.port() };
    var parent = captured.call;
    parent.description = binding;
    var trials: std.ArrayList(@import("trial.zig").Trial) = .empty;
    try trials.ensureTotalCapacity(a, options.repeats);
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Captured-call diagnostics: {s}/{s}\n", .{ output_root, &run.name }));
    for (0..options.repeats) |index| {
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        const id = try a.dupe(u8, &std.fmt.bytesToHex(random, .lower));
        const trial = @import("trial.zig").execute(a, io, service, parent, .{ .id = id, .run = .{ .bytes = &run.name }, .sequence = index + 1 });
        trials.appendAssumeCapacity(trial);
        try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Trial {d}/{d}: {s}\n", .{ index + 1, options.repeats, @tagName(trial.outcome) }));
        if (!trial.canContinue()) break;
    }
    report.trials = trials.items;
    try report_module.save(io, a, output, report, key);
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Report: {s}/{s}/report.md\nProtocol checks only; semantic quality not assessed.\n", .{ output_root, &run.name }));
    return report.succeeded();
}
