//! Frozen development inputs. Evaluator labels never enter a target project.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const evaluation = @import("../contracts.zig");
const fixture = @import("../e2e/fixture.zig");
const workflow = @import("../e2e/contracts.zig");

pub const SourceCase = struct {
    id: []const u8,
    feature_id: []const u8,
    variant: comparison.Variant,
    sources: []const comparison.Source,
};
pub const InputPaths = struct { protocol: []const u8, cases: []const u8, template_case: []const u8, rubric: []const u8 };
pub const Toolchain = struct {
    compiler: []const u8,
    target: []const u8,
    cpu: []const u8,
    features: []const usize,
    optimize: std.builtin.OptimizeMode,
};

pub fn toolchain(a: std.mem.Allocator) !Toolchain {
    return .{
        .compiler = @import("builtin").zig_version_string,
        .target = try @import("builtin").target.zigTriple(a),
        .cpu = @import("builtin").cpu.model.name,
        .features = try a.dupe(usize, &@import("builtin").cpu.features.ints),
        .optimize = @import("builtin").mode,
    };
}

pub fn verifyToolchain(a: std.mem.Allocator, expected: Toolchain) !void {
    const current = try toolchain(a);
    if (!std.mem.eql(u8, current.compiler, expected.compiler) or !std.mem.eql(u8, current.target, expected.target) or
        !std.mem.eql(u8, current.cpu, expected.cpu) or !std.mem.eql(usize, current.features, expected.features) or current.optimize != expected.optimize) return error.BaselineBuildChanged;
}
pub const Freeze = struct {
    schema: enum { @"baseline-freeze/v3" },
    acquisition_scope: enum { full_workflow } = .full_workflow,
    build: @import("../../../build/provenance.zig").Identity,
    toolchain: Toolchain,
    path_policy: @import("../../../src/domain/bootstrap_roots.zig").WorkspacePathPolicy,
    protocol_sha256: []const u8,
    inventory_sha256: []const u8,
    template_sha256: []const u8,
    rubric_sha256: []const u8,
    input_paths: InputPaths,
    protocol: comparison.Protocol,
    template: workflow.Case,
    inputs: fixture.Capture,
    sources: []const SourceCase,
    trials: []const comparison.Trial,
    admission: union(enum) {
        preparation,
        frozen: struct { budget_plan_source: []const u8, feasibility: @import("feasibility.zig").Report },
    } = .preparation,
};

pub fn hash(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// Experiment identity follows the closed frozen value, independently of
/// insignificant formatting in its external JSON representation.
pub fn experimentHash(a: std.mem.Allocator, frozen: Freeze) ![]const u8 {
    const bytes = try std.json.Stringify.valueAlloc(a, frozen, .{});
    defer a.free(bytes);
    return hash(a, bytes);
}

pub fn create(a: std.mem.Allocator, build: @import("../../../build/provenance.zig").Identity, protocol_bytes: []const u8, inventory_bytes: []const u8, template_bytes: []const u8, rubric_bytes: []const u8, inputs: fixture.Capture, paths: InputPaths, path_policy: @import("../../../src/domain/bootstrap_roots.zig").WorkspacePathPolicy) !Freeze {
    inline for (std.meta.fields(InputPaths)) |field| try evaluation.path(@field(paths, field.name));
    const protocol = try comparison.parseProtocol(a, protocol_bytes);
    const inventory = try comparison.parseInventory(a, inventory_bytes);
    const template = try workflow.parse(a, template_bytes);
    const rubric = try evaluation.parseRubric(a, rubric_bytes);
    if (rubric.pass_threshold_percent == null) return error.UnscoredBaselineRubric;
    try evaluatorSeparation(inputs, paths);
    var captured = inputs;
    captured.evaluation.rubric = rubric;
    captured.evaluation.rubric_bytes = rubric_bytes;
    captured.evaluation.case.rubric = paths.rubric;
    captured.evaluation.case_bytes = try std.json.Stringify.valueAlloc(a, captured.evaluation.case, .{});
    try @import("../compatibility/cli.zig").preflight(a, inputs.config);
    var cases: std.ArrayList(SourceCase) = .empty;
    for (inventory.cases) |example| if (example.partition == .development) {
        try cases.append(a, .{ .id = example.id, .feature_id = example.feature_id, .variant = example.variant, .sources = example.sources });
    };
    return .{
        .schema = .@"baseline-freeze/v3",
        .build = build,
        .toolchain = try toolchain(a),
        .path_policy = path_policy,
        .protocol_sha256 = try hash(a, protocol_bytes),
        .inventory_sha256 = try hash(a, inventory_bytes),
        .template_sha256 = try hash(a, template_bytes),
        .rubric_sha256 = try hash(a, rubric_bytes),
        .input_paths = paths,
        .protocol = protocol,
        .template = template,
        .inputs = captured,
        .sources = try cases.toOwnedSlice(a),
        .trials = try comparison.plan(a, inventory, protocol, .baseline),
    };
}

pub fn decode(a: std.mem.Allocator, bytes: []const u8) !Freeze {
    const value = try @import("../../../src/domain/strict_json.zig").decode(Freeze, a, bytes, .{ .maximum_depth = 128 });
    try comparison.validateProtocol(value.protocol);
    inline for (std.meta.fields(InputPaths)) |field| try evaluation.path(@field(value.input_paths, field.name));
    for ([_][]const u8{ value.protocol_sha256, value.inventory_sha256, value.template_sha256, value.rubric_sha256, value.build.source_sha256 }) |identity| {
        if (identity.len != 64) return error.InvalidBaselineFreeze;
        for (identity) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return error.InvalidBaselineFreeze;
    }
    const rubric = try evaluation.parseRubric(a, value.inputs.evaluation.rubric_bytes);
    const evaluation_case = try evaluation.parseCase(a, value.inputs.evaluation.case_bytes);
    if (rubric.pass_threshold_percent == null or !std.mem.eql(u8, value.inputs.evaluation.case.rubric, value.input_paths.rubric) or
        !std.mem.eql(u8, value.rubric_sha256, try hash(a, value.inputs.evaluation.rubric_bytes)) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, evaluation_case, .{}), try std.json.Stringify.valueAlloc(a, value.inputs.evaluation.case, .{})) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, rubric, .{}), try std.json.Stringify.valueAlloc(a, value.inputs.evaluation.rubric, .{}))) return error.InvalidBaselineFreeze;
    try evaluatorSeparation(value.inputs, value.input_paths);
    try @import("../compatibility/cli.zig").preflight(a, value.inputs.config);
    _ = try workflow.parse(a, try std.json.Stringify.valueAlloc(a, value.template, .{}));
    if (value.sources.len != value.protocol.development_features * 3 or value.trials.len != value.sources.len * value.protocol.repetitions) return error.InvalidBaselineFreeze;
    var ordinal: usize = 0;
    for (value.sources, 0..) |example, index| {
        if (!evaluation.id(example.id) or !evaluation.id(example.feature_id) or example.sources.len == 0) return error.InvalidBaselineFreeze;
        for (value.sources[0..index]) |prior| if (std.mem.eql(u8, prior.id, example.id)) return error.InvalidBaselineFreeze;
        for (example.sources, 0..) |source, source_index| {
            try evaluation.path(source.path);
            if (!evaluation.id(source.id) or !evaluation.text(source.text)) return error.InvalidBaselineFreeze;
            for (example.sources[0..source_index]) |prior| if (std.mem.eql(u8, source.id, prior.id) or std.ascii.eqlIgnoreCase(source.path, prior.path)) return error.InvalidBaselineFreeze;
        }
        for (0..value.protocol.repetitions) |repetition| {
            const trial = value.trials[ordinal];
            ordinal += 1;
            if (trial.ordinal != ordinal or trial.arm != .A or trial.repetition != repetition + 1 or
                !std.mem.eql(u8, trial.case_id, example.id) or !std.mem.eql(u8, trial.feature_id, example.feature_id)) return error.InvalidBaselineFreeze;
        }
    }
    return value;
}

pub fn requireExecutable(a: std.mem.Allocator, frozen: Freeze) !void {
    if (frozen.admission != .frozen or frozen.build.modified) return error.BaselineNotFrozen;
    const admitted = frozen.admission.frozen;
    try evaluation.path(admitted.budget_plan_source);
    const report = admitted.feasibility;
    if (report.status != .feasible or report.user_decision_required or report.workflow_authority or
        report.plan.decision != .retain_existing_scope or report.configured_workflow_budget != report.plan.workflow_token_budget or
        report.plan.maximum_sends != frozen.protocol.limits.maximum_sends or report.plan.maximum_actual_tokens != frozen.protocol.limits.maximum_actual_tokens) return error.BaselineBudgetNotAdmitted;
    try verifyBuild(frozen.build, report.baseline_build);
    _ = a;
}

/// Reconstruct the freeze from its explicitly selected original inputs. A
/// self-reported digest cannot certify edited case membership or template maps.
/// Qualification sources remain internal and are never exported to a project.
pub fn verifySources(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, frozen: Freeze) !void {
    const files = @import("../files.zig");
    const protocol_bytes = try files.read(io, a, repository, frozen.input_paths.protocol);
    const inventory_bytes = try files.read(io, a, repository, frozen.input_paths.cases);
    const template_bytes = try files.read(io, a, repository, frozen.input_paths.template_case);
    const rubric_bytes = try files.read(io, a, repository, frozen.input_paths.rubric);
    if (!std.mem.eql(u8, try hash(a, protocol_bytes), frozen.protocol_sha256) or
        !std.mem.eql(u8, try hash(a, inventory_bytes), frozen.inventory_sha256) or
        !std.mem.eql(u8, try hash(a, template_bytes), frozen.template_sha256) or
        !std.mem.eql(u8, try hash(a, rubric_bytes), frozen.rubric_sha256)) return error.FixtureChanged;
    const selected = try workflow.parse(a, template_bytes);
    const path_policy = try @import("../../../src/adapters/filesystem/workspace_path_policy.zig").Resolver.init(io, repository).resolve(a);
    var current = try create(a, frozen.build, protocol_bytes, inventory_bytes, template_bytes, rubric_bytes, try fixture.capture(io, a, repository, selected), frozen.input_paths, path_policy);
    // Offline scoring may inspect an older toolchain; acquisition verifies its
    // own exact compiler/target/options separately before dispatch.
    current.toolchain = frozen.toolchain;
    current.admission = frozen.admission;
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, current, .{}), try std.json.Stringify.valueAlloc(a, frozen, .{}))) return error.InvalidBaselineFreeze;
    if (frozen.admission == .frozen) {
        try requireExecutable(a, frozen);
        const admission = frozen.admission.frozen;
        const plan = try @import("feasibility.zig").parse(a, try files.read(io, a, repository, admission.budget_plan_source));
        const checked = try @import("feasibility.zig").evaluate(io, a, repository, plan, frozen.protocol, frozen.build, admission.feasibility.configured_workflow_budget);
        if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, checked, .{}), try std.json.Stringify.valueAlloc(a, admission.feasibility, .{}))) return error.BaselineBudgetChanged;
    }
}

pub const Project = struct { selected: workflow.Case, captured: fixture.Capture };

fn evaluatorSeparation(inputs: fixture.Capture, paths: InputPaths) !void {
    // These source roles are declared evaluator inputs. They cannot become
    // production inputs through a template mapping under another destination.
    for (inputs.files) |file| {
        for ([_][]const u8{ paths.cases, paths.rubric, inputs.evaluation.case_source, inputs.evaluation.case.rubric }) |evaluator_path| {
            if (std.mem.eql(u8, file.mapping.source, evaluator_path)) return error.EvaluatorInputInProject;
        }
    }
}

pub fn configuredRoot(a: std.mem.Allocator, frozen: Freeze, key: @import("../../../src/domain/bootstrap_roots.zig").PathKey, raw: []const u8) !@import("../../../src/domain/bootstrap_roots.zig").NormalizedConfiguredPath {
    return (@import("../../../src/actions/bootstrap/validate_configured_root_path_policy.zig").Action{ .policy = frozen.path_policy }).execute(a, key, raw);
}

/// Replace only the explicitly selected reference input with source bytes. The
/// ordinary production ingestion/grouping path constructs every predecessor.
pub fn project(a: std.mem.Allocator, frozen: Freeze, trial: comparison.Trial) !Project {
    try evaluatorSeparation(frozen.inputs, frozen.input_paths);
    const example = for (frozen.sources) |value| {
        if (std.mem.eql(u8, value.id, trial.case_id) and std.mem.eql(u8, value.feature_id, trial.feature_id)) break value;
    } else return error.InvalidBaselineTrial;
    var config = try (@import("../../../src/actions/config/decode_sddtoolkit_config.zig").Action{}).execute(a, frozen.inputs.config);
    defer config.deinit();
    const references = (try configuredRoot(a, frozen, .references, config.value().paths.references)).relative_path;
    const target_root = try std.fs.path.join(a, &.{ references, example.feature_id });
    const original_root = try std.fs.path.join(a, &.{ references, frozen.template.reference });
    var captured_files: std.ArrayList(fixture.CapturedFile) = .empty;
    var mappings: std.ArrayList(workflow.Copy) = .empty;
    for (frozen.inputs.files) |file| {
        if (@import("../../../src/domain/relative_directory_path.zig").contains(original_root, file.mapping.destination)) continue;
        if (@import("../../../src/domain/relative_directory_path.zig").contains(references, file.mapping.destination)) return error.UnselectedReferenceInput;
        try captured_files.append(a, file);
        try mappings.append(a, file.mapping);
    }
    const evaluation_sources = try a.alloc(evaluation.Source, example.sources.len);
    const documents = try a.alloc(evaluation.Document, example.sources.len);
    for (example.sources, evaluation_sources, documents) |source, *selected, *document| {
        const mapping: workflow.Copy = .{
            .source = try std.fs.path.join(a, &.{ "baseline-sources", example.id, source.path }),
            .destination = try std.fs.path.join(a, &.{ target_root, source.path }),
        };
        try evaluation.path(mapping.source);
        try evaluation.path(mapping.destination);
        try mappings.append(a, mapping);
        try captured_files.append(a, .{ .mapping = mapping, .bytes = source.text });
        selected.* = .{ .id = source.id, .path = mapping.source };
        document.* = .{ .id = source.id, .text = source.text };
    }
    var selected = frozen.template;
    selected.id = example.id;
    selected.feature = example.feature_id;
    selected.reference = example.feature_id;
    selected.files = try mappings.toOwnedSlice(a);
    _ = try workflow.parse(a, try std.json.Stringify.valueAlloc(a, selected, .{}));
    var captured = frozen.inputs;
    captured.files = try captured_files.toOwnedSlice(a);
    captured.evaluation.case.id = example.id;
    captured.evaluation.case.sources = evaluation_sources;
    captured.evaluation.case_bytes = try std.json.Stringify.valueAlloc(a, captured.evaluation.case, .{});
    captured.evaluation.sources = documents;
    try fixture.validateEvaluationSources(a, captured, references, selected.reference);
    return .{ .selected = selected, .captured = captured };
}

pub fn verifyBuild(expected: @import("../../../build/provenance.zig").Identity, current: @import("../../../build/provenance.zig").Identity) !void {
    if (!std.mem.eql(u8, expected.revision, current.revision) or !std.mem.eql(u8, expected.source_sha256, current.source_sha256) or expected.modified != current.modified) return error.BaselineBuildChanged;
}
