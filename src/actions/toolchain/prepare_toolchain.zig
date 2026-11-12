const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const accounting = @import("../../domain/toolchain_accounting.zig");
const schema = @import("../../domain/toolchain_schema.zig");
const inheritance = @import("../../domain/toolchain_inheritance.zig");
const composition = @import("../../domain/toolchain_composition.zig");
const safety = @import("../../domain/toolchain_safety.zig");
const source_port = @import("../../ports/toolchain_authority_source.zig");
const parser_port = @import("../../ports/toolchain_document_parser.zig");
const pipeline = @import("../../domain/pipeline.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum {
    capture_project,
    inventory_presets,
    capture_presets,
    parse_documents,
    validate_project,
    validate_registry,
    resolve_inheritance,
    compose,
    validate_safety,
};

/// Stage-owned diagnostic slot. A Zig error carries no payload, so a failing run records
/// the step it stopped at here before returning the unchanged error. A cancelled run
/// records the step it did not start.
pub const Diagnostic = struct { step: ?Step = null };

/// The failure representation of the nine absorbed actions, unchanged. `Cancelled` means the
/// runtime stopped being active; the runner reports which stop it was.
pub const Error = toolchain.Error || error{Cancelled};

/// One stage: capture the project and preset documents, parse them, validate, resolve,
/// compose and safety-validate the toolchain. Its steps route no outcome of their own: each
/// success continues to the next and every failure ends the stage.
pub const Action = struct {
    project_source: source_port.ProjectCapturer,
    preset_source: source_port.PresetEnumerator,
    preset_capture: source_port.PresetCapturer,
    parser: parser_port.Parser,
    policies: toolchain.PolicyRegistry,
    pub const contract: pipeline.NodeContract = .{ .id = "prepare-toolchain", .kind = .action, .requires = &.{}, .produces = &.{.valid_toolchain}, .side_effect = .filesystem_read };

    /// Intermediates live in `scratch`; only the safety-valid owner is allocated from `retained`.
    pub fn execute(self: Action, scratch: std.mem.Allocator, retained: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic) Error!*safety.Owner {
        const project_capture = steps.captureProject(self.project_source, scratch) catch |err| return stopped(diagnostic, .capture_project, err);
        try checkpoint(diagnostic, runtime, .inventory_presets);
        const entries = steps.inventoryPresets(self.preset_source, scratch) catch |err| return stopped(diagnostic, .inventory_presets, err);
        try checkpoint(diagnostic, runtime, .capture_presets);
        const preset_captures = steps.capturePresets(self.preset_capture, scratch, project_capture, entries) catch |err| return stopped(diagnostic, .capture_presets, err);
        try checkpoint(diagnostic, runtime, .parse_documents);
        const documents = steps.parseDocuments(self.parser, scratch, project_capture, preset_captures) catch |err| return stopped(diagnostic, .parse_documents, err);
        try checkpoint(diagnostic, runtime, .validate_project);
        const project = steps.validateProject(scratch, documents) catch |err| return stopped(diagnostic, .validate_project, err);
        try checkpoint(diagnostic, runtime, .validate_registry);
        const registry = steps.validateRegistry(scratch, documents) catch |err| return stopped(diagnostic, .validate_registry, err);
        try checkpoint(diagnostic, runtime, .resolve_inheritance);
        const resolved = steps.resolveInheritance(scratch, project, registry) catch |err| return stopped(diagnostic, .resolve_inheritance, err);
        try checkpoint(diagnostic, runtime, .compose);
        const composed = steps.compose(scratch, project, resolved) catch |err| return stopped(diagnostic, .compose, err);
        try checkpoint(diagnostic, runtime, .validate_safety);
        return steps.validateSafety(retained, composed, self.policies) catch |err| return stopped(diagnostic, .validate_safety, err);
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The nine internal steps. Each is one typed function with its own tests; none is
/// registered, addressable or composable from workflow YAML. A step that reaches a port takes
/// exactly that port, never the `Action`, and a step that reads does not parse.
pub const steps = struct {
    pub fn captureProject(source: source_port.ProjectCapturer, allocator: std.mem.Allocator) toolchain.Error!toolchain.Capture {
        return source.captureProject(allocator) catch error.InvalidToolchain;
    }

    pub fn inventoryPresets(source: source_port.PresetEnumerator, allocator: std.mem.Allocator) toolchain.Error![]const toolchain.Entry {
        return source.inventoryPresets(allocator) catch error.InvalidToolchain;
    }

    /// The capture budget is checked before any preset is read.
    pub fn capturePresets(source: source_port.PresetCapturer, allocator: std.mem.Allocator, project: toolchain.Capture, entries: []const toolchain.Entry) toolchain.Error![]const toolchain.Capture {
        try accounting.validateCaptureBudget(project, entries);
        const captures = allocator.alloc(toolchain.Capture, entries.len) catch return error.InvalidToolchain;
        for (entries, captures) |entry, *capture| {
            capture.* = source.capturePreset(entry, allocator) catch return error.InvalidToolchain;
        }
        return captures;
    }

    /// Parses the project capture followed by the preset captures. The parser returns exactly one
    /// document per capture, in order, so the first is the project's and the rest are the presets';
    /// a short or long result rejects rather than silently dropping a preset.
    pub fn parseDocuments(parser: parser_port.Parser, allocator: std.mem.Allocator, project: toolchain.Capture, presets: []const toolchain.Capture) toolchain.Error![]const toolchain.RawDocument {
        const captures = allocator.alloc(toolchain.Capture, presets.len + 1) catch return error.InvalidToolchain;
        captures[0] = project;
        @memcpy(captures[1..], presets);
        const documents = parser.parse(allocator, captures) catch return error.InvalidToolchain;
        if (documents.len != captures.len) return error.InvalidToolchain;
        return documents;
    }

    pub fn validateProject(allocator: std.mem.Allocator, documents: []const toolchain.RawDocument) toolchain.Error!toolchain.Project {
        if (documents.len == 0) return error.InvalidToolchain;
        return schema.parseProject(allocator, documents[0]);
    }

    pub fn validateRegistry(allocator: std.mem.Allocator, documents: []const toolchain.RawDocument) toolchain.Error!toolchain.Registry {
        if (documents.len == 0) return error.InvalidToolchain;
        const registry = try schema.parseRegistry(allocator, documents[1..]);
        try inheritance.validateCompleteRegistry(allocator, registry);
        return registry;
    }

    pub fn resolveInheritance(allocator: std.mem.Allocator, project: toolchain.Project, registry: toolchain.Registry) toolchain.Error!toolchain.Resolved {
        return inheritance.resolve(allocator, project, registry);
    }

    pub fn compose(allocator: std.mem.Allocator, project: toolchain.Project, resolved: toolchain.Resolved) toolchain.Error!toolchain.Composed {
        return composition.compose(allocator, project, resolved);
    }

    /// Only this step constructs the safety-valid owner.
    pub fn validateSafety(allocator: std.mem.Allocator, composed: toolchain.Composed, policies: toolchain.PolicyRegistry) toolchain.Error!*safety.Owner {
        return safety.validate(allocator, composed, policies);
    }
};
