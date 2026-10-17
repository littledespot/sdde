//! Fresh one-exchange diagnostic through the ordinary production invocation.
const std = @import("std");
const c = @import("../e2e/contracts.zig");
const fixture = @import("../e2e/fixture.zig");
const reports = @import("report.zig");
pub const output_root = "zig-out/provider-compatibility";

pub fn parse(args: []const []const u8) ![]const u8 {
    if (args.len != 3 or !std.mem.eql(u8, args[0], "--case") or !std.mem.eql(u8, args[2], "--live")) return error.InvalidArguments;
    try @import("../contracts.zig").path(args[1]);
    return args[1];
}

pub fn preflight(a: std.mem.Allocator, config_bytes: []const u8) !void {
    var config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, config_bytes);
    defer config.deinit();
    try @import("../model_cost_policy.zig").requireConfiguredSlots(&config.value().models);
    try @import("../frozen_binding.zig").validateModels(a, &config.value().models);
    const logging = try @import("../../../src/domain/log_policy.zig").canonicalizeConfiguredLevel(config.value().logs.level);
    switch (logging.threshold) {
        .trace, .debug => {},
        else => return error.CompleteCaptureRequired,
    }
}

pub fn main(init: std.process.Init) !void {
    if (!try command(init)) std.process.exit(1);
}

fn command(init: std.process.Init) !bool {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, "Usage: zig build provider-compatibility -- --case <relative-workflow.case.json> --live\nMakes at most one fresh production Bedrock GPT-OSS-20B inference exchange, retains exact evidence, then stops before the next workflow step. No retries, judge or publication authority. Requires separately approved bounded live execution and TEST_AWS_BEARER_TOKEN_BEDROCK. Results: zig-out/provider-compatibility/<UTC-run>/report.json and report.md.\n");
        return true;
    }
    const case_path = parse(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, "Select one explicit --case <path> --live; use --help. No API call made.\n");
        return false;
    };
    const parent = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(init.io, .cwd(), output_root);
    defer parent.close(init.io);
    const run = try @import("../e2e/run_directory.zig").Run.create(init.io, parent);
    defer run.close(init.io);
    const output = try @import("../e2e/report.zig").Output.reserve(init.io, run.dir);
    defer output.close(init.io);
    var report: reports.Report = .{ .schema = .@"provider-compatibility-report/v1", .started_at_utc = &run.started_at_utc, .case_source = case_path, .execution_id = &run.name };
    const bundle = try @import("../contracts.zig").decode(@import("../../../build/provenance.zig").Bundle, a, @embedFile("build_provenance"));
    report.build = .{ .source = bundle.identity, .zig_version = @import("builtin").zig_version_string, .target = @tagName(@import("builtin").cpu.arch) ++ "-" ++ @tagName(@import("builtin").os.tag) ++ "-" ++ @tagName(@import("builtin").abi), .optimize = @tagName(@import("builtin").mode) };
    execute(init.io, a, init.environ_map, case_path, run, &report) catch |err| {
        if (report.status != .input_invalid) report.status = .harness_error;
        report.diagnostic = @errorName(err);
    };
    return finish(init.io, a, output, report, &run.name, .stdout(), .stderr());
}

pub fn finish(io: std.Io, a: std.mem.Allocator, output: @import("../e2e/report.zig").Output, report: reports.Report, run: []const u8, stdout: std.Io.File, stderr: std.Io.File) !bool {
    reports.save(io, a, output, report) catch |err| {
        try stderr.writeStreamingAll(io, try std.fmt.allocPrint(a, "Compatibility report finalization failed: {s}. Evidence is incomplete.\n", .{@errorName(err)}));
        return false;
    };
    try stdout.writeStreamingAll(io, try std.fmt.allocPrint(a, "Provider compatibility: {s}\nReports: {s}/{s}/report.md and report.json\n", .{ @tagName(report.status), output_root, run }));
    return report.status == .compatible;
}

fn execute(io: std.Io, a: std.mem.Allocator, environment: *const std.process.Environ.Map, case_path: []const u8, run: @import("../e2e/run_directory.zig").Run, report: *reports.Report) !void {
    const case_bytes = try @import("../files.zig").read(io, a, .cwd(), case_path);
    const selected = try c.parse(a, case_bytes);
    const captured = try fixture.capture(io, a, .cwd(), selected);
    try preflight(a, captured.config);
    try @import("../output.zig").write(io, run.dir, "case.json", case_bytes);
    try @import("../output.zig").write(io, run.dir, "inputs.json", try std.json.Stringify.valueAlloc(a, captured, .{ .whitespace = .indent_2 }));
    try fixture.materialize(io, run.project, captured);
    // Cost/config/capture checks above precede credential access.
    const key = try @import("../environment.zig").credential(environment, .bedrock_converse);
    const secrets = [_][]const u8{key};
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = a, .run = run.dir, .secrets = &secrets };
    report.status = .inconclusive;
    report.build.?.reconstruction = try @import("../e2e/build_evidence.zig").save(store, @embedFile("build_provenance"));
    report.build.?.inputs_file = "build-inputs.json";
    var workflow: c.Report = .{ .schema = .@"spec-e2e-report/v4", .started_at_utc = report.started_at_utc, .status = .input_invalid };
    var probe: @import("../e2e/invoke.zig").Probe = .{};
    defer reports.applyExecution(report, probe, workflow);
    _ = try @import("../e2e/invoke.zig").run(io, a, run.project, selected, captured, key, store, &workflow, .{ .purpose = .{ .single_exchange = &probe } });
    const current = try @import("../files.zig").read(io, a, .cwd(), case_path);
    if (!std.mem.eql(u8, current, case_bytes)) return error.FixtureChanged;
    try fixture.verifySources(io, a, .cwd(), captured);
    const run_path = try std.fmt.allocPrint(a, "{s}/{s}", .{ output_root, &run.name });
    report.inspection = try @import("inspection.zig").inspect(io, a, environment, .cwd(), run_path, selected.workflow_id, probe, workflow);
    report.status = switch (report.inspection.status) {
        .compatible => .compatible,
        .incompatible => .incompatible,
        .inconclusive => .inconclusive,
    };
}
