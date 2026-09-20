//! Composition owns the active log's adapter and authority lifetimes. The
//! selected graph requests activation through one fixed lifecycle operation.
const std = @import("std");
const port = @import("../ports/feature_log_activation.zig");
const feature = @import("../domain/feature_directory.zig");
const active = @import("../domain/active_feature_directory.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const binding = @import("../domain/feature_log_binding.zig");
const runtime = @import("active_feature_log_runtime.zig");
const run = @import("../domain/run_outcome.zig");
const telemetry = @import("../domain/telemetry.zig");
const Failure = @import("../domain/feature_log_stream.zig").FailureCode;

pub const Assembly = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project: std.Io.Dir,
    roots: *const @import("../domain/bootstrap_root_registry.zig").BootstrapRootRegistry,
    logs: *@import("../application/log_service.zig").LogService,
    inputs: *@import("../adapters/filesystem/feature_input_source.zig").Adapter,
    outputs: *@import("../adapters/filesystem/workflow_output.zig").Adapter,
    binding_owner: ?*binding.BindingOwner = null,
    directory_owner: ?*active.Owner = null,
    artifact_owner: ?*artifacts.Owner = null,
    runtime_owner: ?*runtime.Owner = null,
    shortcode: ?telemetry.WorkflowShortcode = null,
    failure: ?Failure = null,
    finalized: bool = false,

    pub fn activator(self: *Assembly) port.Activator {
        return .{ .context = @ptrCast(self), .activate_fn = activate };
    }
    pub fn finalizer(self: *Assembly) port.Finalizer {
        return .{ .context = @ptrCast(self), .finish_fn = finish };
    }

    fn activate(context: *port.Context, prior: feature.Directory, shortcode: telemetry.WorkflowShortcode) port.Outcome {
        const self: *Assembly = @ptrCast(@alignCast(context));
        if (self.binding_owner != null or self.finalized) return self.fail(.LOG_SINK_FAILURE);
        self.shortcode = shortcode;
        const identity: @import("../adapters/system/feature_log_identity.zig").Adapter = .{ .io = self.io };
        self.binding_owner = identity.create(self.allocator, prior.selector.feature_id, self.logs.policy().*) catch |err| return switch (err) {
            error.Canceled => .cancelled,
            else => self.fail(.LOG_SINK_FAILURE),
        };
        const selected_binding = binding.binding(self.binding_owner.?);
        var layout: @import("../adapters/filesystem/feature_log_layout.zig").Adapter = .{ .io = self.io, .project_root = self.project };
        self.directory_owner = layout.port().activate(self.allocator, self.roots.featureOutputWrite(), prior, selected_binding) catch |err| return switch (err) {
            error.Cancelled => .cancelled,
            else => self.fail(.LOG_SINK_FAILURE),
        };
        const directory = active.capability(self.directory_owner.?);
        self.artifact_owner = artifacts.createForActive(self.allocator, self.roots.featureOutputWrite(), selected_binding, directory) catch return self.fail(.LOG_SINK_FAILURE);
        self.runtime_owner = runtime.create(self.allocator, self.io, self.project, self.logs.policy(), artifacts.registry(self.artifact_owner.?), selected_binding) catch return self.fail(.LOG_SINK_FAILURE);
        switch (self.logs.activate(runtime.runner(self.runtime_owner.?).childBindings(), shortcode)) {
            .ok => {},
            .blocked => |failure| return self.fail(failure),
            .invalid => return self.fail(.LOG_SINK_FAILURE),
        }
        self.inputs.active_feature = directory;
        self.outputs.active_feature = directory;
        const events: @import("../application/workflow_event_capture.zig").Capture = .{ .barrier = self.logs.barrier(), .shortcode = shortcode };
        if (events.emit(.{ .event_type = .run_started })) |failure| return self.fail(failure);
        return .{ .ready = active.directory(directory) };
    }

    fn fail(self: *Assembly, failure: Failure) port.Outcome {
        if (self.failure == null and self.runtime_owner == null) if (self.shortcode) |shortcode| {
            // Failures before sink construction still use the same bounded
            // emergency action; no feature stream can exist yet.
            var output: @import("../adapters/system/log_output.zig").Adapter = .{ .io = self.io };
            const emergency: @import("../actions/log/emit_emergency_log_failure_record.zig").Action = .{ .sink = output.emergency() };
            emergency.execute(shortcode, failure);
        };
        self.failure = failure;
        return .{ .blocked = failure };
    }

    fn finish(context: *port.Context, reason: port.Finalizer.Reason) run.Outcome {
        const self: *Assembly = @ptrCast(@alignCast(context));
        const outcome = reason.outcome();
        if (!self.finalized) {
            self.finalized = true;
            if (self.logs.lifecycle.active != null) {
                const events: @import("../application/workflow_event_capture.zig").Capture = .{ .barrier = self.logs.barrier(), .shortcode = self.shortcode.? };
                const event_failure = switch (reason) {
                    .terminal => events.terminal(outcome),
                    .publication => |prepared| events.emit(.{ .event_type = .publication_prepared, .fields = .{ .outcome = if (prepared == .needs_user) .needs_user else .completed } }),
                };
                if (event_failure) |failure| self.failure = failure;
                var finalization: @import("../application/feature_log_finalization_runner.zig").Runner = .{
                    .target = runtime.runner(self.runtime_owner.?),
                    .mode = .active,
                    .shortcode = self.shortcode.?,
                };
                switch (self.logs.finalizeActive(finalization.childBindings())) {
                    .ok => {},
                    .blocked => |failure| self.failure = failure,
                    .invalid => self.failure = .LOG_SINK_FAILURE,
                }
            }
        }
        return if (self.failure) |failure| .{ .execution_rejected = .{ .logging = failure } } else outcome;
    }

    pub fn deinit(self: *Assembly) void {
        // Every engine terminal path finalizes before the reported outcome.
        std.debug.assert(self.logs.lifecycle.active == null);
        self.inputs.active_feature = null;
        self.outputs.active_feature = null;
        if (self.runtime_owner) |owner| runtime.deinit(owner);
        if (self.artifact_owner) |owner| artifacts.deinitOwner(owner);
        if (self.directory_owner) |owner| active.deinitOwner(owner);
        if (self.binding_owner) |owner| binding.deinitOwner(owner);
        self.* = undefined;
    }
};
