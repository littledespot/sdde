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
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build e2e-spec -- --case <relative-workflow.case.json>\nRuns the real LLM selected by the case's .sddtoolkit.json, then grades its published specification against the case rubric. This command makes live API calls. Live generation and grading permit only Bedrock openai.gpt-oss-20b-1:0 from ap-southeast-2. Explicitly set TEST_EVALUATION_PROVIDER=bedrock, TEST_EVALUATION_MODEL=openai.gpt-oss-20b-1:0, TEST_EVALUATION_REGION=ap-southeast-2 and TEST_AWS_BEARER_TOKEN_BEDROCK. Load .env.e2e explicitly before running. Retains one UTC-dated run under zig-out/e2e-spec.\n");
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
    var report: c.Report = .{ .schema = .@"spec-e2e-report/v7", .started_at_utc = &run.started_at_utc, .execution_id = &run.name, .case_source = case_path, .status = .input_invalid };
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
    const selection = @import("../environment.zig").selection(environment) catch |err| return if (err == error.DisallowedTestModel) err else error.InvalidEvaluationEnvironment;
    const config = @import("../configuration.zig").parse(allocator, captured.evaluation.config_bytes, selection) catch return error.InvalidEvaluationConfiguration;
    report.evaluation_configuration = config;
    const qualification = @import("../grader_qualification.zig");
    const grader = try qualification.inspect(io, allocator, .cwd(), captured.evaluation.case.grading_qualification, captured.evaluation.case, captured.evaluation.rubric_bytes, captured.evaluation.sources, config);
    report.grader_qualification = grader;
    if (captured.evaluation.rubric.pass_threshold_percent == null) {
        report.status = .quality_unresolved;
        report.diagnostic = "ACCEPTANCE_THRESHOLD_UNCONFIGURED";
        return;
    }
    const judge_key = try @import("../environment.zig").credential(environment, selection.api);
    const generation_key = try @import("../environment.zig").credential(environment, .bedrock_converse);
    try std.Io.File.stdout().writeStreamingAll(io, "Generating with the selected project's configured LLM...\n");
    const secrets = [_][]const u8{ generation_key, judge_key };
    const store: @import("../evidence.zig").Store = .{ .io = io, .allocator = allocator, .run = run, .secrets = &secrets };
    const reconstruction = try @import("build_evidence.zig").save(store, @embedFile("build_provenance"));
    report.build.?.inputs_file = "build-inputs.json";
    report.build.?.reconstruction = reconstruction;
    const specification = try @import("invoke.zig").run(io, allocator, project, selected, captured, generation_key, store, report, .{ .purpose = .whole_workflow });
    if (!try verifySources(io, allocator, case_path, case_bytes, captured, report)) return;
    const published = specification orelse return;
    if (selected.expected_outcome != .publication) return;
    const inputs = try @import("evaluation.zig").inputs(allocator, report.*, captured.evaluation, published, execution_id);
    report.evaluation_inputs = inputs;
    const observed_independence = try @import("../judge_independence.zig").fromObserved(report.models, config);
    const current_grader = try qualification.inspect(io, allocator, .cwd(), captured.evaluation.case.grading_qualification, captured.evaluation.case, captured.evaluation.rubric_bytes, captured.evaluation.sources, config);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, grader, .{}), try std.json.Stringify.valueAlloc(allocator, current_grader, .{}))) {
        report.status = .quality_unresolved;
        report.diagnostic = "GRADER_AUTHORITY_CHANGED";
        return;
    }
    try std.Io.File.stdout().writeStreamingAll(io, "Grading the published specification against the selected rubric...\n");
    var result = @import("../live.zig").run(io, allocator, config, judge_key, inputs, store) catch |err| {
        report.status = .evaluator_failed;
        report.semantic_quality = .evaluator_error;
        report.diagnostic = @errorName(err);
        if (err == error.EvidenceCaptureFailed) report.evidence_error = @errorName(err);
        return;
    };
    result.grader_qualification = grader;
    if (result.outcome == .evaluated) result.acceptance = @import("../acceptance_gate.zig").from(inputs.rubric, result.outcome.evaluated, observed_independence, if (grader == .qualified) .qualified else .unresolved);
    @import("evaluation.zig").apply(report, result);
    _ = try verifySources(io, allocator, case_path, case_bytes, captured, report);
    const final_grader = try qualification.inspect(io, allocator, .cwd(), captured.evaluation.case.grading_qualification, captured.evaluation.case, captured.evaluation.rubric_bytes, captured.evaluation.sources, config);
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, grader, .{}), try std.json.Stringify.valueAlloc(allocator, final_grader, .{}))) {
        report.status = .fixture_changed;
        report.diagnostic = "GRADER_QUALIFICATION_CHANGED";
    }
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
