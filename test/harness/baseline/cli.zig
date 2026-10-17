//! Explicit prepare/acquire/score commands. Only acquire --live can dispatch.
const std = @import("std");
const inputs = @import("freeze.zig");
const acquisition = @import("acquisition.zig");
const files = @import("../files.zig");
const output = @import("../output.zig");
pub const output_root = "zig-out/baseline";

pub const Options = union(enum) {
    prepare: struct { protocol: []const u8, cases: []const u8, template_case: []const u8, budget_plan: []const u8, rubric: []const u8 },
    acquire: struct { freeze: []const u8 },
    score: struct { freeze: []const u8, cases: []const u8, acquisition: []const u8, assessments: []const u8 },
};

pub fn parse(args: []const []const u8) !Options {
    if (args.len == 11 and std.mem.eql(u8, args[0], "prepare") and std.mem.eql(u8, args[1], "--protocol") and std.mem.eql(u8, args[3], "--cases") and std.mem.eql(u8, args[5], "--template-case") and std.mem.eql(u8, args[7], "--budget-plan") and std.mem.eql(u8, args[9], "--rubric")) {
        inline for (.{ 2, 4, 6, 8, 10 }) |index| try @import("../contracts.zig").path(args[index]);
        return .{ .prepare = .{ .protocol = args[2], .cases = args[4], .template_case = args[6], .budget_plan = args[8], .rubric = args[10] } };
    }
    if (args.len == 4 and std.mem.eql(u8, args[0], "acquire") and std.mem.eql(u8, args[1], "--freeze") and std.mem.eql(u8, args[3], "--live")) {
        try @import("../contracts.zig").path(args[2]);
        return .{ .acquire = .{ .freeze = args[2] } };
    }
    if (args.len == 9 and std.mem.eql(u8, args[0], "score") and std.mem.eql(u8, args[1], "--freeze") and std.mem.eql(u8, args[3], "--cases") and std.mem.eql(u8, args[5], "--acquisition") and std.mem.eql(u8, args[7], "--assessments")) {
        inline for (.{ 2, 4, 6, 8 }) |index| try @import("../contracts.zig").path(args[index]);
        return .{ .score = .{ .freeze = args[2], .cases = args[4], .acquisition = args[6], .assessments = args[8] } };
    }
    return error.InvalidArguments;
}

const help =
    \\Usage: zig build baseline -- prepare --protocol <relative-json> --cases <relative-json> --template-case <relative-workflow.case.json> --budget-plan <relative-json> --rubric <relative-json>
    \\       zig build baseline -- acquire --freeze <relative-freeze.json> --live
    \\       zig build baseline -- score --freeze <relative-freeze.json> --cases <relative-json> --acquisition <relative-report.json> --assessments <relative-json>
    \\prepare checks native budget feasibility without credentials/inference. It freezes unchanged A development inputs only for a committed build with an explicit feasible budget decision; otherwise it writes a blocked preparation report.
    \\acquire consumes a one-shot claim for the exact freeze before credentials or dispatch, then runs every listed trial serially in isolated projects with actual production predecessors. Each listed live run requires prior explicit approval. Failed/interrupted attempts cannot restart the same freeze. It enforces frozen stops for this baseline and reports consumed/unspent allowance; future phases remain reserved and unexecuted. Requires TEST_AWS_BEARER_TOKEN_BEDROCK; no automatic environment file loading.
    \\score checks native capture identities and supplied source-backed semantic labels offline. Model-assisted labels remain judgments, never deterministic proof or workflow authority. Missing/disputed labels remain incomplete. Qualification sources are not exported.
    \\Results: zig-out/baseline/<UTC-run>/. prepare/score never dispatch; no default case, provider substitution or publication through diagnostic receipts.
    \\
;

pub fn main(init: std.process.Init) !void {
    const succeeded = command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Baseline command failed: {s}. Retained evidence may be incomplete.\n", .{@errorName(err)}));
        std.process.exit(1);
    };
    if (!succeeded) std.process.exit(1);
}

fn command(init: std.process.Init) !bool {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(init.io, help);
        return true;
    }
    const options = parse(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, "Select explicit baseline prepare, acquire --live, or score inputs; use --help. No API call made.\n");
        return false;
    };
    const bundle_bytes = @embedFile("build_provenance");
    const bundle = try @import("../contracts.zig").decode(@import("../../../build/provenance.zig").Bundle, a, bundle_bytes);
    if (!bundle.complete) return error.IncompleteBuildCapture;
    // Validate every external selection before creating an output or looking up credentials.
    switch (options) {
        .prepare => |selected| {
            const protocol = try files.read(init.io, a, .cwd(), selected.protocol);
            const inventory = try files.read(init.io, a, .cwd(), selected.cases);
            const template_bytes = try files.read(init.io, a, .cwd(), selected.template_case);
            const rubric_bytes = try files.read(init.io, a, .cwd(), selected.rubric);
            const template = try @import("../e2e/contracts.zig").parse(a, template_bytes);
            const captured = try @import("../e2e/fixture.zig").capture(init.io, a, .cwd(), template);
            const path_policy = try @import("../../../src/adapters/filesystem/workspace_path_policy.zig").Resolver.init(init.io, .cwd()).resolve(a);
            var frozen = try inputs.create(a, bundle.identity, protocol, inventory, template_bytes, rubric_bytes, captured, .{ .protocol = selected.protocol, .cases = selected.cases, .template_case = selected.template_case, .rubric = selected.rubric }, path_policy);
            // Exercise every source projection before freezing it; no expected duties are copied.
            for (frozen.trials) |trial| _ = try inputs.project(a, frozen, trial);
            const run = try createRun(init.io);
            defer run.close(init.io);
            const native_project = try inputs.project(a, frozen, frozen.trials[0]);
            try @import("../e2e/fixture.zig").materialize(init.io, run.project, native_project.captured);
            const compiled_budget = try @import("preflight.zig").workflowBudget(init.io, a, run.project, frozen.template.workflow_id);
            const budget_plan = try @import("feasibility.zig").parse(a, try files.read(init.io, a, .cwd(), selected.budget_plan));
            const feasibility = try @import("feasibility.zig").evaluate(init.io, a, .cwd(), budget_plan, frozen.protocol, bundle.identity, compiled_budget);
            try output.write(init.io, run.dir, "budget-feasibility.json", try std.json.Stringify.valueAlloc(a, feasibility, .{ .whitespace = .indent_2 }));
            const store: @import("../evidence.zig").Store = .{ .io = init.io, .allocator = a, .run = run.dir, .secrets = &.{} };
            if (try @import("../e2e/build_evidence.zig").save(store, bundle_bytes) != .captured) return error.IncompleteBuildCapture;
            if (feasibility.status != .feasible or bundle.identity.modified) {
                try output.write(init.io, run.dir, "report.md", try std.fmt.allocPrint(a, "# Baseline preparation\n\nBudget feasibility: {s}. User decision required: {}. Source committed: {}.\n\nNo baseline was frozen; no model call was made. Exact reasons, phase coverage and observed cost evidence are retained in budget-feasibility.json. No workflow token policy was changed.\n", .{ @tagName(feasibility.status), feasibility.user_decision_required, !bundle.identity.modified }));
                try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Baseline preparation blocked: {s}/{s}/budget-feasibility.json\nCommitted baseline and feasible recorded budget decision required. No API call made.\n", .{ output_root, &run.name }));
                return false;
            }
            frozen.admission = .{ .frozen = .{ .budget_plan_source = selected.budget_plan, .feasibility = feasibility } };
            try inputs.requireExecutable(a, frozen);
            const bytes = try std.json.Stringify.valueAlloc(a, frozen, .{});
            try output.write(init.io, run.dir, "freeze.json", bytes);
            try output.write(init.io, run.dir, "plan.json", try std.json.Stringify.valueAlloc(a, frozen.trials, .{ .whitespace = .indent_2 }));
            try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Baseline freeze: {s}/{s}/freeze.json\nA workloads: {d}; inference not run.\n", .{ output_root, &run.name, frozen.trials.len }));
            return true;
        },
        .acquire => |selected| {
            const freeze_bytes = try files.read(init.io, a, .cwd(), selected.freeze);
            const frozen = try inputs.decode(a, freeze_bytes);
            try inputs.requireExecutable(a, frozen);
            try inputs.verifyBuild(frozen.build, bundle.identity);
            try inputs.verifyToolchain(a, frozen.toolchain);
            try inputs.verifySources(init.io, a, .cwd(), frozen);
            // Revalidate the frozen native fixture, not mutable repository examples.
            for (frozen.trials) |trial| _ = try inputs.project(a, frozen, trial);
            const run = try createRun(init.io);
            defer run.close(init.io);
            const native_project = try inputs.project(a, frozen, frozen.trials[0]);
            try @import("../e2e/fixture.zig").materialize(init.io, run.project, native_project.captured);
            const budget = try @import("preflight.zig").workflowBudget(init.io, a, run.project, frozen.template.workflow_id);
            if (budget != frozen.admission.frozen.feasibility.compiled_workflow_budget) return error.BaselineBudgetChanged;
            const freeze_sha256 = try inputs.hash(a, freeze_bytes);
            const experiment = @import("experiment.zig");
            const claim: experiment.Claim = .{ .schema = .@"baseline-experiment-claim/v1", .experiment_sha256 = try inputs.experimentHash(a, frozen), .freeze_sha256 = freeze_sha256, .execution_id = try a.dupe(u8, &run.name), .limits = .{ .maximum_sends = frozen.protocol.limits.maximum_sends, .maximum_actual_tokens = frozen.protocol.limits.maximum_actual_tokens }, .phases = frozen.admission.frozen.feasibility.plan.phases };
            try output.write(init.io, run.dir, "freeze.json", freeze_bytes);
            try experiment.consume(init.io, a, .cwd(), claim);
            try experiment.verify(init.io, a, .cwd(), claim);
            const key = try @import("../environment.zig").credential(init.environ_map, .bedrock_converse);
            const report = try acquisition.acquire(init.io, a, init.gpa, frozen, freeze_sha256, run, key, bundle_bytes, claim);
            // A change during acquisition invalidates this experiment and may
            // never be reported as complete evidence.
            var retained = report;
            inputs.verifySources(init.io, a, .cwd(), frozen) catch |err| {
                retained.complete = false;
                retained.source_error = @errorName(err);
                if (retained.budget.halt_reason == null) retained.budget.halt_reason = .configuration_drift;
                try output.write(init.io, run.dir, "source-error.json", try std.json.Stringify.valueAlloc(a, .{ .diagnostic = @errorName(err) }, .{}));
            };
            const report_bytes = try std.json.Stringify.valueAlloc(a, retained, .{ .whitespace = .indent_2 });
            const safe = try (@import("../evidence.zig").Store{ .io = init.io, .allocator = a, .run = run.dir, .secrets = &.{key} }).redact(a, report_bytes);
            if (!std.mem.eql(u8, safe, report_bytes)) return error.CaptureRedacted;
            try output.write(init.io, run.dir, "acquisition.json", report_bytes);
            try output.write(init.io, run.dir, "report.md", try std.fmt.allocPrint(a, "# Baseline acquisition\n\nScope: full production workflows with actual predecessors.\n\nPlanned workloads: {d}. Physical sends: {d}. Accounted tokens: {d}. Usage complete: {}. Panel complete: {}.\n\nOne-shot baseline claim consumed. Unspent sends: {d}; unspent actual tokens: {any}. Future declared phases remain reserved and unexecuted; their dispatch is unavailable. The same freeze cannot restart.\n\nSemantic assessment has not run. Every trial's native outcome and exact exchange receipts remain in acquisition.json.\n", .{ retained.records.len, retained.budget.physical_sends, retained.budget.total_accounted_tokens, retained.budget.usage_complete, retained.complete, retained.allowance.unspent_physical_sends, retained.allowance.unspent_actual_tokens }));
            try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Baseline acquisition: {s}/{s}/acquisition.json\nPanel complete: {}; semantic assessment not run.\n", .{ output_root, &run.name, retained.complete }));
            return retained.complete;
        },
        .score => |selected| return @import("scoring.zig").command(init.io, a, .cwd(), selected.freeze, selected.cases, selected.acquisition, selected.assessments, bundle.identity),
    }
}

pub fn createRun(io: std.Io) !@import("../e2e/run_directory.zig").Run {
    const parent = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, .cwd(), output_root);
    defer parent.close(io);
    return @import("../e2e/run_directory.zig").Run.create(io, parent);
}
