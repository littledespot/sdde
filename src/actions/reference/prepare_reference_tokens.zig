const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const naming = @import("../../domain/naming_policy.zig");
const safety = @import("../../domain/toolchain_safety.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const grammar = @import("../../domain/path_token_grammar.zig");
const literals = @import("../../domain/passive_literals.zig");
const tokens = @import("../../domain/structured_tokens.zig");
const text_port = @import("../../ports/unicode_normalizer.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum {
    build_grammar,
    scan_literals,
    assign_literals,
    validate_literals,
    extract_facts,
    assign_candidates,
};

/// Stage-owned diagnostic slot: the step a failing run stopped at, or the step a cancelled run
/// did not start. The binding hands it to the runner (ADR 0031).
pub const Diagnostic = struct { step: ?Step = null };

/// The failure representation of the six absorbed actions, unchanged. `Cancelled` means the
/// runtime stopped being active; the runner reports which stop it was.
pub const Error = grammar.Error || literals.Error || tokens.Error || error{Cancelled};

/// What crosses the stage edge: the grammar, the validated passive-literal registry and the
/// structured token candidates. Everything is allocated from the scratch allocator.
pub const Outputs = struct {
    grammar: grammar.Grammar,
    registry: literals.Registry,
    candidates: tokens.Candidates,
};

/// One stage: build the superset path-token grammar from the compiled naming policy and the
/// citable inputs, scan, identify and validate the passive literals, and extract and identify the
/// structured token candidates. Its steps route no outcome of their own: each success continues to
/// the next and every failure ends the stage. It holds only text services and reads no
/// filesystem.
pub const Action = struct {
    normalizer: text_port.Normalizer,
    case_folder: text_port.CaseFolder,
    classifier: text_port.LexicalClassifier,
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-reference-tokens",
        .kind = .action,
        .requires = &.{ .compiled_naming_policy, .valid_toolchain, .citable_reference_inputs },
        .produces = &.{ .path_token_grammar, .reference_passive_literals, .structured_token_candidates },
        .side_effect = .none,
    };

    pub fn execute(self: Action, scratch: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, policy: naming.Compiled, current: *const safety.ValidToolchain, inputs: evidence.Inputs) Error!Outputs {
        const compiled = steps.buildGrammar(self.normalizer, self.case_folder, scratch, policy, current, inputs) catch |err| return stopped(diagnostic, .build_grammar, err);
        try checkpoint(diagnostic, runtime, .scan_literals);
        const candidates = steps.scanLiterals(self.normalizer, self.case_folder, self.classifier, scratch, compiled, current, inputs) catch |err| return stopped(diagnostic, .scan_literals, err);
        try checkpoint(diagnostic, runtime, .assign_literals);
        const assigned = steps.assignLiterals(scratch, candidates) catch |err| return stopped(diagnostic, .assign_literals, err);
        try checkpoint(diagnostic, runtime, .validate_literals);
        const registry = steps.validateLiterals(self.normalizer, self.case_folder, self.classifier, scratch, assigned, current, inputs) catch |err| return stopped(diagnostic, .validate_literals, err);
        try checkpoint(diagnostic, runtime, .extract_facts);
        const facts = steps.extractFacts(scratch, inputs) catch |err| return stopped(diagnostic, .extract_facts, err);
        try checkpoint(diagnostic, runtime, .assign_candidates);
        const token_candidates = steps.assignCandidates(scratch, inputs, facts) catch |err| return stopped(diagnostic, .assign_candidates, err);
        return .{ .grammar = compiled, .registry = registry, .candidates = token_candidates };
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The six internal steps. Each is one typed function with its own tests; none is registered,
/// addressable or composable from workflow YAML. The text services are the three types of one
/// port module, and no step takes any other port.
pub const steps = struct {
    pub fn buildGrammar(normalizer: text_port.Normalizer, case_folder: text_port.CaseFolder, allocator: std.mem.Allocator, policy: naming.Compiled, current: *const safety.ValidToolchain, inputs: evidence.Inputs) grammar.Error!grammar.Grammar {
        return grammar.build(allocator, policy, current, inputs, normalizer, case_folder);
    }

    pub fn scanLiterals(normalizer: text_port.Normalizer, case_folder: text_port.CaseFolder, classifier: text_port.LexicalClassifier, allocator: std.mem.Allocator, compiled: grammar.Grammar, current: *const safety.ValidToolchain, inputs: evidence.Inputs) literals.Error!literals.Candidates {
        return literals.collect(allocator, compiled, current, inputs, normalizer, case_folder, classifier);
    }

    pub fn assignLiterals(allocator: std.mem.Allocator, candidates: literals.Candidates) literals.Error!literals.Assigned {
        return literals.assign(allocator, candidates);
    }

    pub fn validateLiterals(normalizer: text_port.Normalizer, case_folder: text_port.CaseFolder, classifier: text_port.LexicalClassifier, allocator: std.mem.Allocator, assigned: literals.Assigned, current: *const safety.ValidToolchain, inputs: evidence.Inputs) literals.Error!literals.Registry {
        return literals.validate(allocator, assigned, current, inputs, normalizer, case_folder, classifier);
    }

    pub fn extractFacts(allocator: std.mem.Allocator, inputs: evidence.Inputs) tokens.Error!tokens.Facts {
        return tokens.extract(allocator, inputs);
    }

    pub fn assignCandidates(allocator: std.mem.Allocator, inputs: evidence.Inputs, facts: tokens.Facts) tokens.Error!tokens.Candidates {
        return tokens.assign(allocator, inputs, facts);
    }
};
