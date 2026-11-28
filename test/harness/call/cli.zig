const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");
const options_module = @import("options.zig");
const binding_module = @import("../diagnostic_binding.zig");
const report_module = @import("report.zig");
const cost_policy = @import("../model_cost_policy.zig");
const environment_module = @import("../environment.zig");
const provider_api_key = @import("../../../src/adapters/provider/provider_api_key.zig");
pub const output_root = "zig-out/e2e-call";

/// A captured call replays with the key of its own provider family. The family's
/// test variable supplies it, and the replay adapter reads it from the family's one
/// production variable in a map that holds nothing else (ADR 0028).
pub fn bindCredential(source: *const std.process.Environ.Map, replay: *std.process.Environ.Map, family: provider_api_key.Family) error{ MissingTestApiKey, InvalidTestApiKey, OutOfMemory }![]const u8 {
    const key = try environment_module.generationKey(source, family);
    try replay.put(@import("../../../src/adapters/system/provider_api_key_source.zig").variable(family), key);
    return key;
}

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
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: scripts/e2e-call.sh --run <captured-E2E-directory> --workflow <workflow-id> --call <positive-ordinal> --model <model-id> --reasoning-effort <effort|none> [--repeats <positive-count>] [--edit <edit-file.json>]\n" ++
            "Makes one live diagnostic call per repeat (default 1), using unchanged captured input/schema, or with --edit the file's {\"content\":[...],\"schema\":\"...\"} in their place (modified replay; validated before any call). Explicit model and reasoning are validated against the retained project's provider catalogue and registered provider capabilities. Preserves temperature; sends the catalogue entry's maximum output. No retries, repair, workflow continuation, publication or rubric grading.\n" ++
            "Live diagnostics permit only the cost policy's generation tuples (" ++ cost_policy.generation_tuples ++ ") with supported reasoning and compatible retained controls. The captured call's provider selects the credential: " ++ environment_module.generation_key_help ++ ". The shell launcher loads .env.e2e; direct Zig invocation does not. Results: zig-out/e2e-call/<UTC-run>/report.md and report.json.\n");
        return true;
    }
    const options = options_module.parse(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Invalid arguments; use --help. No API call made.\n");
        return false;
    };
    var captured = try @import("capture.zig").load(io, a, .cwd(), options.run, options.workflow, options.call);
    defer captured.deinit();
    const original = captured.call.description.?;
    cost_policy.require(.generation, .{ .bytes = original.provider }, .{ .bytes = options.model }) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Live diagnostic model rejected by the test cost policy. Select one of " ++ cost_policy.generation_tuples ++ " for the captured call's provider, with supported reasoning and compatible retained controls. No API call made.\n");
        return false;
    };
    var binding = try binding_module.rebind(a, original, captured.provider_catalogue, options.model, options.reasoning_effort);
    const edited = if (options.edit) |path| try loadEdit(io, a, .cwd(), path) else null;
    var authority: binding_module.Authorization = .{ .binding = original };
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const family = provider_api_key.Family.of(binding.provider_config) orelse return error.InvalidEvaluationContract;
    const key = bindCredential(init.environ_map, &environment, family) catch |err| switch (err) {
        error.MissingTestApiKey, error.InvalidTestApiKey => {
            try std.Io.File.stderr().writeStreamingAll(io, try std.fmt.allocPrint(a, "Set a valid {s} test credential; no API call made.\n", .{environment_module.generationKeyName(family)}));
            return false;
        },
        error.OutOfMemory => return err,
    };
    var clock: @import("../../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var transport: @import("../../../src/adapters/provider/model_http_exchange.zig").Adapter = .{ .io = io, .clock = clock.clock(), .runtime = .{} };
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
    if (edited) |value| binding = applyEdit(binding, value.edit);
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
        .edit_sha256 = if (edited) |value| try a.dupe(u8, &value.sha256) else null,
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
        var trial = @import("trial.zig").execute(a, io, service, parent, .{ .id = id, .run = .{ .bytes = &run.name }, .sequence = index + 1 });
        try @import("trial.zig").measure(a, &trial);
        trials.appendAssumeCapacity(trial);
        try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Trial {d}/{d}: {s}\n", .{ index + 1, options.repeats, @tagName(trial.outcome) }));
        if (!trial.canContinue()) break;
    }
    report.trials = trials.items;
    try report_module.save(io, a, output, report, key);
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Report: {s}/{s}/report.md\nProtocol checks only; semantic quality not assessed.\n", .{ output_root, &run.name }));
    return report.succeeded();
}

pub const Edited = struct { edit: debug.Edit, sha256: [64]u8 };

/// Modified replay (ADR 0019) replaces only content and schema; the canonical schema
/// compiler and provider serializer validate the result before any send.
pub fn applyEdit(description: debug.Description, edit: debug.Edit) debug.Description {
    var result = description;
    result.content = edit.content;
    result.schema = edit.schema;
    return result;
}

/// Reads an edit file: the closed `{"content":[...],"schema":"..."}` a modified replay
/// sends instead of the captured content and schema.
pub fn loadEdit(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, path: []const u8) !Edited {
    const bytes = try @import("../files.zig").read(io, a, root, path);
    const edit = @import("../../../src/domain/strict_json.zig").decode(debug.Edit, a, bytes, .{ .maximum_depth = 64 }) catch |err|
        return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEdit;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return .{ .edit = edit, .sha256 = std.fmt.bytesToHex(digest, .lower) };
}
