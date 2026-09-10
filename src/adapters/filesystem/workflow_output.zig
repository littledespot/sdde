//! Sequential registered-file replacement. Failures retain written files and
//! never fabricate completion; no journal, rollback or recovery directory.
const std = @import("std");
const output = @import("../../domain/workflow_output.zig");
const c = @import("../../domain/clarification_inputs.zig");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const directories = @import("directory_access.zig");
const files = @import("file_access.zig");
const source = @import("feature_input_source.zig");
pub const Adapter = Writer(files.replace);

/// The test seam has exactly the registered-file replacement signature. It
/// changes no path, precondition, ordering or completion policy.
pub fn Writer(comptime replace_file: @TypeOf(files.replace)) type {
    return struct {
        const Self = @This();
        io: std.Io,
        project_root: std.Io.Dir,
        pub fn port(self: *Self) @import("../../ports/workflow_output.zig").Port {
            return .{ .context = self, .publish_fn = publish };
        }
        fn publish(context: *anyopaque, capability: *const roots.FeatureOutputWriteCapability, allocator: std.mem.Allocator, prepared: output.Prepared) output.Error!void {
            const self: *Self = @ptrCast(@alignCast(context));
            try output.validateShape(prepared);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var binding = roots.bindFeatureOutputAdapter(capability);
            var reader: source.Adapter = .{ .io = self.io, .project_root = self.project_root };
            const initial = reader.captureBound(binding, a, prepared.feature, prepared.paths) catch return error.OutputChanged;
            if (!output.sameCapture(prepared.prior, initial)) return error.OutputChanged;
            if (prepared.prior_workflow_state == .captured) {
                const current = reader.captureWorkflowStateBound(binding, a, prepared.feature, prepared.paths) catch return error.OutputChanged;
                if (!output.sameBytes(prepared.prior_workflow_state.captured, current)) return error.OutputChanged;
            }
            var observed = prepared.feature;
            const specs = (directories.openObserved(self.io, self.project_root, binding.paths.specs, binding.specs_observation) catch return error.OutputChanged) orelse
                (directories.ensure(self.io, self.project_root, binding.paths.specs) catch return error.OutputWriteFailed);
            defer specs.close(self.io);
            binding.specs_observation = .{ .directory = directories.inspectReadable(self.io, specs) catch return error.OutputWriteFailed };
            observed.root_observation = binding.specs_observation;
            const feature = (directories.openObserved(self.io, specs, observed.selector.feature_id.bytes, observed.observation) catch return error.OutputChanged) orelse
                (directories.ensure(self.io, specs, observed.selector.feature_id.bytes) catch return error.OutputWriteFailed);
            defer feature.close(self.io);
            observed.observation = .{ .directory = directories.inspectReadable(self.io, feature) catch return error.OutputWriteFailed };
            var expected = prepared.prior;
            for (prepared.files) |file| {
                // Whole controlled-input set, not just the file being replaced.
                const current = reader.captureBound(binding, a, observed, prepared.paths) catch return error.OutputChanged;
                if (!output.sameCapture(expected, current)) return error.OutputChanged;
                const path = try output.path(a, prepared.paths, file.target);
                const root = (directories.openObserved(self.io, self.project_root, if (path.root == .specs) binding.paths.specs else binding.paths.workflows, if (path.root == .specs) binding.specs_observation else .{ .directory = binding.workflows_identity }) catch return error.OutputChanged) orelse return error.OutputChanged;
                defer root.close(self.io);
                const parent = directories.ensure(self.io, root, std.fs.path.dirname(path.root_relative).?) catch return error.OutputWriteFailed;
                defer parent.close(self.io);
                // Recheck after directory preparation, immediately before replacement.
                const fresh = reader.captureBound(binding, a, observed, prepared.paths) catch return error.OutputChanged;
                if (!output.sameCapture(expected, fresh)) return error.OutputChanged;
                if (prepared.prior_workflow_state == .captured) {
                    const current_state = reader.captureWorkflowStateBound(binding, a, observed, prepared.paths) catch return error.OutputChanged;
                    if (!output.sameBytes(prepared.prior_workflow_state.captured, current_state)) return error.OutputChanged;
                }
                var condition: files.Expected = .any;
                if (file.target == .form) {
                    condition = .absent;
                    for (fresh.forms) |capture| if (std.meta.eql(capture.id, file.target.form)) {
                        // Even an invalid concurrent closure is a protected input.
                        // Full equality above rejects every concurrent edit; the
                        // validated producer excludes already protected forms.
                        if (@import("../../domain/clarification_form.zig").isClosed(capture.bytes)) return error.OutputChanged;
                        condition = .{ .exact = capture.bytes };
                    };
                } else if (file.target.artifact == .clarification_state) {
                    condition = if (fresh.state) |bytes| .{ .exact = bytes } else .absent;
                } else if (file.target.artifact == .workflow_state) {
                    condition = if (prepared.prior_workflow_state.captured) |bytes| .{ .exact = bytes } else .absent;
                }
                replace_file(self.io, a, parent, std.fs.path.basename(path.root_relative), condition, file.bytes) catch return error.OutputWriteFailed;
                switch (file.target) {
                    .artifact => |kind| if (kind == .clarification_state) {
                        expected.state = file.bytes;
                    },
                    .form => |id| {
                        var next: std.ArrayList(c.FormCapture) = .empty;
                        var found = false;
                        for (expected.forms) |capture| {
                            if (std.meta.eql(capture.id, id)) {
                                try next.append(a, .{ .id = id, .bytes = file.bytes });
                                found = true;
                            } else try next.append(a, capture);
                        }
                        if (!found) try next.append(a, .{ .id = id, .bytes = file.bytes });
                        std.mem.sort(c.FormCapture, next.items, {}, lessForm);
                        expected.forms = next.items;
                    },
                }
            }
        }
    };
}
fn lessForm(_: void, a: c.FormCapture, b: c.FormCapture) bool {
    return a.id.index() < b.id.index();
}
