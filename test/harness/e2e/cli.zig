const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
pub const output_root = "zig-out/e2e-spec";

pub fn parse(args: []const []const u8) ![]const u8 {
    if (args.len != 2 or !std.mem.eql(u8, args[0], "--case")) return error.InvalidArguments;
    try @import("../contracts.zig").path(args[1]);
    return args[1];
}

pub fn main(init: std.process.Init) !void {
    if (!try command(init)) std.process.exit(1);
}

fn command(init: std.process.Init) !bool {
    const io = init.io;
    const allocator = init.arena.allocator();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer iterator.deinit();
    _ = iterator.skip();
    var arguments: std.ArrayList([]const u8) = .empty;
    while (iterator.next()) |argument| try arguments.append(allocator, argument);
    if (arguments.items.len == 1 and std.mem.eql(u8, arguments.items[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build e2e-spec -- --case <relative-workflow.case.json>\nRuns the real LLM selected by the case's .sddtoolkit.json, then grades its published specification against the case rubric. This command makes live API calls. Generation uses TEST_AWS_BEARER_TOKEN_BEDROCK; grading uses TEST_EVALUATION_PROVIDER, TEST_EVALUATION_MODEL, TEST_EVALUATION_REGION and the selected TEST_ credential. Load .env.e2e explicitly before running. Retains one UTC-dated run under zig-out/e2e-spec.\n");
        return true;
    }
    const case_path = parse(arguments.items) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Select exactly one E2E case with --case; use --help.\n");
        return false;
    };
    const parent = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, .cwd(), output_root);
    defer parent.close(io);
    const run = try @import("run_directory.zig").Run.create(io, parent);
    defer run.close(io);
    const output = try @import("report.zig").Output.reserve(io, run.dir);
    defer output.close(io);
    var report: c.Report = .{ .started_at_utc = &run.started_at_utc, .execution_id = &run.name, .case_source = case_path, .status = .input_invalid };
    execute(io, allocator, init.environ_map, case_path, run.dir, run.project, &run.name, &report) catch |err| {
        if (report.status != .input_invalid) report.status = .harness_error;
        report.diagnostic = @errorName(err);
    };
    try output.save(io, allocator, report);
    const message = try std.fmt.allocPrint(allocator, "E2E result: {s}\nReport: {s}/{s}/report.md\n", .{ @tagName(report.status), output_root, run.name });
    try std.Io.File.stdout().writeStreamingAll(io, message);
    if (report.specification) |path| try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(allocator, "Specification: {s}/{s}/project/{s}\n", .{ output_root, run.name, path }));
    return report.status == .passed;
}

fn execute(io: std.Io, allocator: std.mem.Allocator, environment: *const std.process.Environ.Map, case_path: []const u8, run: std.Io.Dir, project: std.Io.Dir, execution_id: []const u8, report: *c.Report) !void {
    const case_bytes = try @import("../files.zig").read(io, allocator, .cwd(), case_path);
    try @import("report.zig").write(io, run, "case.json", case_bytes);
    const selected = try c.parse(allocator, case_bytes);
    report.case_id = selected.id;
    report.workflow_id = selected.workflow_id;
    const captured = try fixture.capture(io, allocator, .cwd(), selected);
    try @import("report.zig").write(io, run, "inputs.json", try @import("../../../src/domain/canonical_json.zig").encode(fixture.Capture, allocator, captured));
    try fixture.materialize(io, project, captured);
    const selection = @import("../environment.zig").selection(environment) catch return error.InvalidEvaluationEnvironment;
    const config = @import("../configuration.zig").parse(allocator, captured.evaluation.config_bytes, selection) catch return error.InvalidEvaluationConfiguration;
    report.evaluation_configuration = config;
    const judge_key = try @import("../environment.zig").credential(environment, selection.api);
    const generation_key = try @import("../environment.zig").credential(environment, .bedrock_converse);
    try std.Io.File.stdout().writeStreamingAll(io, "Generating with the selected project's configured LLM...\n");
    const specification = try @import("invoke.zig").run(io, allocator, project, selected, captured, generation_key, report);
    if (!try verifySources(io, allocator, case_path, case_bytes, captured, report)) return;
    const published = specification orelse return;
    const inputs = try @import("evaluation.zig").inputs(allocator, report.*, captured.evaluation, published, execution_id);
    try std.Io.File.stdout().writeStreamingAll(io, "Grading the published specification against the selected rubric...\n");
    const result = @import("../live.zig").run(io, allocator, config, judge_key, inputs) catch |err| {
        report.status = .evaluator_failed;
        report.semantic_quality = .evaluator_error;
        report.diagnostic = @errorName(err);
        return;
    };
    @import("evaluation.zig").apply(report, result);
    _ = try verifySources(io, allocator, case_path, case_bytes, captured, report);
}

fn verifySources(io: std.Io, allocator: std.mem.Allocator, case_path: []const u8, case_bytes: []const u8, captured: fixture.Capture, report: *c.Report) !bool {
    const current = try @import("../files.zig").read(io, allocator, .cwd(), case_path);
    defer allocator.free(current);
    var changed = !std.mem.eql(u8, current, case_bytes);
    fixture.verifySources(io, allocator, .cwd(), captured) catch |err| switch (err) {
        error.FixtureChanged => changed = true,
        else => return err,
    };
    if (changed) {
        report.status = .fixture_changed;
        report.diagnostic = "SOURCE_FIXTURE_CHANGED";
    }
    return !changed;
}
