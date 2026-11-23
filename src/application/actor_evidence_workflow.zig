//! Native bindings of the clarification authentication chain (ADR 0025). YAML owns where each step sits and the loop over the
//! forms that await an account; the population is frozen by the plan and each pass runs under its own runner-issued lease.
//! Evidence is recorded and the answers accepted by one stage action, so the registry and the responses cannot diverge.
const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const feature = @import("../domain/feature_directory.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const clarification = @import("../domain/clarification_inputs.zig");
const authentication = @import("../domain/clarification_authentication.zig");
const evidence = @import("../domain/actor_evidence.zig");
const workflow_iteration = @import("../domain/workflow_iteration.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const logging = @import("feature_logging_workflow.zig");
const clarification_values = @import("clarification_input_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const prepare = @import("../actions/specify/prepare_actor_evidence.zig");
const accept = @import("../actions/clarification/accept_clarification_responses.zig");

/// The registry file as captured, before any parse; none when the feature has published no registry.
pub const Capture = struct { bytes: ?[]const u8 };

pub const capture_schema = values.schema(.raw_actor_evidence, Capture, 1, evidence.max_bytes * 2);
pub const registry_schema = values.schema(.actor_evidence_registry, evidence.Registry, 1, evidence.max_bytes * 4);
pub const progress_schema = values.schema(.authentication_progress, authentication.Progress, 1, 2 * 1024 * 1024);
/// Each pass's observation is consumed and invalidated by the step that advances the loop, so its successor keeps its
/// evidence and not its slot: a later pass must not find the progress dependent on an observation that is no longer there.
pub const observation_schema = values.schema(.actor_observation, evidence.Observation, 1, 4096).captured();
pub const schemas = [_]data.Schema{ capture_schema, registry_schema, progress_schema, observation_schema };

fn readInputs(view: *const data.View) operations.Error!*const clarification.Inputs {
    return values.read(view, clarification_values.inputs_schema, clarification.Inputs) catch |operation_error| operation_error;
}

fn readProgress(view: *const data.View) operations.Error!*const authentication.Progress {
    return values.read(view, progress_schema, authentication.Progress) catch |operation_error| operation_error;
}

/// The stage action that reads the feature's actor-evidence registry.
pub const PrepareActorEvidence = struct {
    pub const Action = prepare.Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        // The registry is read after feature logging activates, so its directory is the activated one (the log's own).
        const directory = values.read(&input.step.data, logging.directory, feature.Directory) catch |operation_error| return operation_error;
        const paths = values.read(&input.step.data, clarification_values.paths_schema, artifacts.FeaturePaths) catch |operation_error| return operation_error;
        const inputs = try readInputs(&input.step.data);
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        var diagnostic: prepare.Diagnostic = .{};
        const outputs = self.action.execute(scratch.allocator(), input.step.runtime, &diagnostic, directory.*, paths.*, inputs.*) catch |operation_error| {
            // The stage-owned slot is read before the unchanged error propagates; the runner records the step in the
            // failed action's event (ADR 0031).
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        var delta: pipeline.NodeDelta = .{};
        errdefer for (delta.data_writes) |slot| if (slot) |written| values.destroy(written);
        delta.data_writes[@intFromEnum(capture_schema.key)] = values.create(self.allocator, capture_schema, Capture, .{ .bytes = outputs.capture }) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(registry_schema.key)] = values.create(self.allocator, registry_schema, evidence.Registry, outputs.registry) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};

/// Plans the loop: its iteration is the closed forms that await an account, one pass for each.
pub const Plan = struct {
    pub const Action = @import("../actions/clarification/plan_clarification_authentication.zig").Action;
    pub const iteration: workflow_iteration.Descriptor = .{ .kind = .initialize, .scope = .clarification_inputs, .progress = .authentication_progress };
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const progress = self.action.execute(scratch.allocator(), (try readInputs(&input.step.data)).*) catch |operation_error| return operation_error;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(progress_schema.key)] = values.create(self.allocator, progress_schema, authentication.Progress, progress) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta, .iteration = .{ .limit = progress.pending.len, .before = 0, .after = 0 } };
    }
};

/// `more` while a form awaits its observation, else `ok`.
pub const Check = struct {
    pub const Action = @import("../actions/clarification/check_clarification_authentication.zig").Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .more, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = context.?.action.execute((try readProgress(&input.step.data)).*), .delta = .{} };
    }
};

/// Observes the invoking account once, under the lease the runner issued for this pass.
pub const Authenticate = struct {
    pub const Action = @import("../actions/clarification/authenticate_actor.zig").Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .failed };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const granted = input.step.actor_authentication orelse return error.AuthenticationDenied;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const observation = self.action.execute(scratch.allocator(), input.step.runtime, granted) catch |operation_error| return operation_error;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(observation_schema.key)] = values.create(self.allocator, observation_schema, evidence.Observation, observation) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};

/// Joins the observation of the form just authenticated to the progress and advances the loop.
pub const Advance = struct {
    pub const Action = @import("../actions/clarification/advance_clarification_authentication.zig").Action;
    pub const iteration: workflow_iteration.Descriptor = .{ .kind = .advance, .scope = .clarification_inputs, .progress = .authentication_progress };
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try readProgress(&input.step.data);
        const observation = values.read(&input.step.data, observation_schema, evidence.Observation) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const next = self.action.execute(scratch.allocator(), current.*, observation.*) catch |operation_error| return operation_error;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(progress_schema.key)] = values.create(self.allocator, progress_schema, authentication.Progress, next) catch |operation_error| return operation_error;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta, .iteration = .{ .limit = current.pending.len, .before = current.observations.len, .after = next.observations.len } };
    }
};

/// The stage action that appends the run's evidence and accepts each authenticated form as a response.
pub const Accept = struct {
    pub const Action = accept.Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captures = values.read(&input.step.data, clarification_values.captures_schema, clarification.Captures) catch |operation_error| return operation_error;
        const prior = values.read(&input.step.data, registry_schema, evidence.Registry) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        var diagnostic: accept.Diagnostic = .{};
        const outputs = self.action.execute(scratch.allocator(), input.step.runtime, &diagnostic, (try readInputs(&input.step.data)).*, captures.*, prior.*, (try readProgress(&input.step.data)).*) catch |operation_error| {
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        var delta: pipeline.NodeDelta = .{};
        errdefer for (delta.data_replacements) |slot| if (slot) |written| values.destroy(written);
        delta.data_replacements[@intFromEnum(clarification_values.inputs_schema.key)] = values.create(self.allocator, clarification_values.inputs_schema, clarification.Inputs, outputs.inputs) catch |operation_error| return operation_error;
        delta.data_replacements[@intFromEnum(registry_schema.key)] = values.create(self.allocator, registry_schema, evidence.Registry, outputs.registry) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};

/// `cancelled` when a form this run accepted cancelled its record, else `ok`. The observation stays with the accepted inputs
/// until the output of the cancelled run is prepared from them, which is what lets the publisher end the run `cancelled`
/// (ADR 0025).
pub const Cancellation = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .clarification, .subject = .clarification_inputs, .evidence = .clarification_inputs } };
    pub const Action = @import("../actions/clarification/check_clarification_cancellation.zig").Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .cancelled, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = context.?.action.execute((try readInputs(&input.step.data)).*, (try readProgress(&input.step.data)).*), .delta = .{} };
    }
};

/// Prepares what the run publishes when the user's `cancel` was accepted: the forms, the registry and the clarification
/// state. The accepted inputs it reads carry the cancellation, so the output is the one the publisher may end `cancelled`.
pub const PrepareCancelled = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .clarification, .subject = .clarification_inputs, .evidence = .clarification_inputs, .result = .prepared_workflow_output } };
    pub const Action = @import("../actions/clarification/prepare_cancelled_clarification_output.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const view = &input.step.data;
        const directory = values.read(view, logging.directory, feature.Directory) catch |operation_error| return operation_error;
        const paths = values.read(view, clarification_values.paths_schema, artifacts.FeaturePaths) catch |operation_error| return operation_error;
        const captures = values.read(view, clarification_values.captures_schema, clarification.Captures) catch |operation_error| return operation_error;
        const prior = values.read(view, capture_schema, Capture) catch |operation_error| return operation_error;
        const registry = values.read(view, registry_schema, evidence.Registry) catch |operation_error| return operation_error;
        const sources = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const prepared = self.action.execute(scratch.allocator(), directory.*, paths.*, captures.*, (try readInputs(view)).*, (try readProgress(view)).*, prior.bytes, registry.*, sources.*) catch |cause| return cause;
        return @import("workflow_candidate.zig").publish(self.allocator, @import("workflow_output_binding.zig").prepared_schema, @import("../domain/workflow_output.zig").Prepared, prepared);
    }
};
