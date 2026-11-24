const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const feature = @import("../../domain/feature_directory.zig");
const identity = @import("../../domain/feature_identity.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const evidence = @import("../../domain/actor_evidence.zig");
const source_port = @import("../../ports/workflow_state_source.zig");
const parser_port = @import("../../ports/actor_evidence_parser.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum { capture_registry, parse_registry, validate_registry };

/// Stage-owned diagnostic slot: the step a failing run stopped at, or the step a cancelled run did not start.
pub const Diagnostic = struct { step: ?Step = null };

pub const Error = source_port.Error || evidence.Error || error{Cancelled};

/// What crosses the stage edge: the registry file's bytes as captured, none when the feature has published no registry,
/// and the registry itself, the empty one at revision 0 when there are no bytes.
pub const Outputs = struct { capture: ?[]const u8, registry: evidence.Registry };

/// The registry's document read as its closed contract, before any rule is checked.
pub const Parsed = struct { value: ?evidence.Registry };

/// One stage: capture the feature's actor-evidence registry, read it as its closed contract, then validate it against the
/// feature and the clarification state it must join (ADR 0025). Its steps route no outcome of their own: each success
/// continues to the next and every failure ends the stage.
pub const Action = struct {
    source: ?source_port.Capturer = null,
    parser: parser_port.Parser,
    pub const contract: pipeline.NodeContract = .{
        .id = "prepare-actor-evidence",
        .kind = .action,
        .requires = &.{ .activated_feature_directory, .feature_artifact_paths, .clarification_inputs },
        .produces = &.{ .raw_actor_evidence, .actor_evidence_registry },
        .side_effect = .filesystem_read,
    };

    pub fn execute(self: Action, scratch: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, observed: feature.Directory, paths: artifacts.FeaturePaths, inputs: clarification.Inputs) Error!Outputs {
        try checkpoint(diagnostic, runtime, .capture_registry);
        const bytes = steps.captureRegistry(self.source, scratch, observed, paths) catch |err| return stopped(diagnostic, .capture_registry, err);
        try checkpoint(diagnostic, runtime, .parse_registry);
        const parsed = steps.parseRegistry(self.parser, scratch, bytes) catch |err| return stopped(diagnostic, .parse_registry, err);
        try checkpoint(diagnostic, runtime, .validate_registry);
        const registry = steps.validateRegistry(parsed, observed.selector.feature_id, inputs.state) catch |err| return stopped(diagnostic, .validate_registry, err);
        return .{ .capture = bytes, .registry = registry };
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The three internal steps. Each is one typed function with its own tests; none is registered, addressable or composable
/// from workflow YAML. A step that reaches a port takes exactly that port, never the `Action`.
pub const steps = struct {
    pub fn captureRegistry(source: ?source_port.Capturer, allocator: std.mem.Allocator, observed: feature.Directory, paths: artifacts.FeaturePaths) source_port.Error!?[]const u8 {
        return (source orelse return error.FeatureInputUnavailable).capture(allocator, observed, paths);
    }

    pub fn parseRegistry(parser: parser_port.Parser, allocator: std.mem.Allocator, bytes: ?[]const u8) evidence.Error!Parsed {
        return .{ .value = if (bytes) |document| try parser.parse(allocator, document) else null };
    }

    /// The registry is the feature's, an append-only sequence, and joins every response of the clarification state. A
    /// feature that has published none has the empty registry, which joins a state with no response.
    pub fn validateRegistry(parsed: Parsed, selected: identity.FeatureId, state: clarification.ValidatedState) evidence.Error!evidence.Registry {
        const registry = parsed.value orelse evidence.empty(selected);
        try evidence.validate(registry, selected);
        if (state.value) |current| try evidence.validateJoin(registry, current);
        return registry;
    }
};
