const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
const reports = @import("report.zig");
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
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build e2e-spec -- --case <relative-workflow.case.json>\nRuns the real LLM selected by the case's .sddtoolkit.json and captures its published specification with the case's sources and rubric for human adjudication. No model grades the output. This command makes live API calls. Live generation permits only Bedrock openai.gpt-oss-20b-1:0 or au.anthropic.claude-haiku-5-5 from ap-southeast-2. Set TEST_AWS_BEARER_TOKEN_BEDROCK; load .env.e2e explicitly before running. Retains one UTC-dated run under zig-out/e2e-spec.\n");
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
    const output = try reports.Output.reserve(io, run.dir);
    defer output.close(io);
    var report: c.Report = .{ .schema = .@"spec-e2e-report/v10", .started_at_utc = &run.started_at_utc, .execution_id = &run.name, .case_source = case_path, .status = .input_invalid };
    report.build = .{
        .source = (try @import("../contracts.zig").decode(@import("../../../build/provenance.zig").Bundle, allocator, @embedFile("build_provenance"))).identity,
        .zig_version = @import("builtin").zig_version_string,
        .target = @tagName(@import("builtin").cpu.arch) ++ "-" ++ @tagName(@import("builtin").os.tag) ++ "-" ++ @tagName(@import("builtin").abi),
        .optimize = @tagName(@import("builtin").mode),
    };
    execute(io, allocator, init.environ_map, case_path, run.dir, run.project, &run.name, &report) catch |err| {
        if (report.status != .input_invalid) report.status = .harness_error;
        report.diagnostic = @errorName(err);
    };
    return finish(io, allocator, output, report, output_root, &run.name, .stdout(), .stderr());
}

/// Final reporting cannot replace the workflow outcome or authorize a successful
/// command when its retained reports could not be finalized.
pub fn finish(io: std.Io, allocator: std.mem.Allocator, output: reports.Output, report: c.Report, root: []const u8, run: []const u8, stdout: std.Io.File, stderr: std.Io.File) !bool {
    var final = report;
    try @import("acceptance.zig").apply(allocator, &final);
    var report_error: ?[]const u8 = null;
    output.save(io, allocator, final) catch |err| {
        report_error = @errorName(err);
    };
    const message = try reports.terminal(allocator, final, root, run);
    defer allocator.free(message);
    try stdout.writeStreamingAll(io, message);
    if (report.specification) |path| {
        const location = try std.fmt.allocPrint(allocator, "Specification: {s}/{s}/project/{s}\n", .{ root, run, path });
        defer allocator.free(location);
        try stdout.writeStreamingAll(io, location);
    }
    if (report_error) |cause| {
        try stderr.writeStreamingAll(io, "E2E report finalization failed: ");
        try stderr.writeStreamingAll(io, cause);
        try stderr.writeStreamingAll(io, ". report.json and report.md may be incomplete; inspect the retained workflow result and events.\n");
    }
    return report_error == null and try @import("acceptance.zig").commandSucceeded(allocator, final);
}

fn execute(io: std.Io, allocator: std.mem.Allocator, environment: *const std.process.Environ.Map, case_path: []const u8, run: std.Io.Dir, project: std.Io.Dir, execution_id: []const u8, report: *c.Report) !void {
    const case_bytes = try @import("../files.zig").read(io, allocator, .cwd(), case_path);
    try @import("../output.zig").write(io, run, "case.json", case_bytes);
    const selected = try c.parse(allocator, case_bytes);
    report.case_id = selected.id;
    report.workflow_id = selected.workflow_id;
    report.expected_outcome = selected.expected_outcome;
    const captured = try fixture.capture(io, allocator, .cwd(), selected);
    report.evaluation_case_id = captured.evaluation.case.id;
    try @import("../output.zig").write(io, run, "inputs.json", try std.json.Stringify.valueAlloc(allocator, captured, .{ .whitespace = .indent_2 }));
    try fixture.materialize(io, project, captured);
    var generation_config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(allocator, captured.config);
    defer generation_config.deinit();
    try @import("../model_cost_policy.zig").requireConfiguredSlots(&generation_config.value().models);
    // Human adjudication applies the rubric threshold, so a rubric without one
    // could never accept this run; stop before any billed send.
    if (captured.evaluation.rubric.pass_threshold_percent == null) {
        report.status = .threshold_unconfigured;
        report.diagnostic = "ACCEPTANCE_THRESHOLD_UNCONFIGURED";
        return;
    }
    const generation_keys = try @import("../environment.zig").generationKeys(environment, &generation_config.value().models);
    try std.Io.File.stdout().writeStreamingAll(io, "Generating with the selected project's configured LLM...\n");
    const secrets = try @import("../environment.zig").secrets(allocator, generation_keys);
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = allocator, .run = run, .secrets = secrets };
    const reconstruction = try @import("build_evidence.zig").save(store, @embedFile("build_provenance"));
    report.build.?.inputs_file = "build-inputs.json";
    report.build.?.reconstruction = reconstruction;
    const specification = try @import("invoke.zig").run(io, allocator, project, selected, captured, generation_keys, store, report, .{ .purpose = .whole_workflow });
    if (!try verifySources(io, allocator, case_path, case_bytes, captured, report)) return;
    const published = specification orelse return;
    if (selected.expected_outcome != .publication) return;
    report.evaluation_inputs = try @import("evaluation.zig").inputs(allocator, report.*, captured.evaluation, published, execution_id);
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
