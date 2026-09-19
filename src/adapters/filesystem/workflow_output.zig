//! Sequential registered-file replacement. Failures retain written files and
//! never fabricate completion; no journal, rollback or recovery directory.
const std = @import("std");
const output = @import("../../domain/workflow_output.zig");
const c = @import("../../domain/clarification_inputs.zig");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const active_directory = @import("../../domain/active_feature_directory.zig");
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
        active_feature: ?*const active_directory.Capability = null,
        pub fn port(self: *Self) @import("../../ports/workflow_output.zig").Port {
            return .{ .context = self, .publish_fn = publish };
        }
        fn publish(context: *anyopaque, capability: *const roots.FeatureOutputWriteCapability, allocator: std.mem.Allocator, prepared: output.Prepared) output.Error!void {
            const self: *Self = @ptrCast(@alignCast(context));
            return self.publishBound(roots.bindFeatureOutputAdapter(capability), allocator, prepared);
        }
        fn publishBound(self: *Self, bootstrap_binding: roots.FeatureInputAdapterBinding, allocator: std.mem.Allocator, prepared: output.Prepared) output.Error!void {
            try output.validateShape(prepared);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const effective: active_directory.BoundInput = if (self.active_feature) |active|
                active_directory.bindInput(active, bootstrap_binding, prepared.feature) orelse return error.OutputChanged
            else
                .{ .binding = bootstrap_binding, .directory = prepared.feature };
            var binding = effective.binding;
            var observed = effective.directory;
            var reader: source.Adapter = .{ .io = self.io, .project_root = self.project_root, .active_feature = self.active_feature };
            const initial = reader.captureBound(binding, a, observed, prepared.paths) catch return error.OutputChanged;
            if (!output.sameCapture(prepared.prior, initial)) return error.OutputChanged;
            if (prepared.prior_workflow_state == .captured) {
                const current = reader.captureWorkflowStateBound(binding, a, observed, prepared.paths) catch return error.OutputChanged;
                if (!output.sameBytes(prepared.prior_workflow_state.captured, current)) return error.OutputChanged;
            }
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

const ActivatedFixture = struct {
    binding: roots.FeatureInputAdapterBinding,
    before: @import("../../domain/feature_directory.zig").Directory,
    current: @import("../../domain/feature_directory.zig").Directory,
    paths: @import("../../domain/workflow_artifact_registry.zig").FeaturePaths,
    prior: c.Captures,
    owner: *active_directory.Owner,

    fn init(allocator: std.mem.Allocator, io: std.Io, project: std.Io.Dir, specs_path: []const u8, feature_name: []const u8, present: enum { neither, root, both }) !ActivatedFixture {
        const feature_directory = @import("../../domain/feature_directory.zig");
        const artifacts = @import("../../domain/workflow_artifact_registry.zig");
        const workflows = try directories.ensure(io, project, "engine/workflows");
        defer workflows.close(io);
        var binding: roots.FeatureInputAdapterBinding = .{
            .paths = .{ .specs = specs_path, .archive = "retired", .workflows = "engine/workflows" },
            .specs_observation = .absent,
            .workflows_identity = try directories.inspectReadable(io, workflows),
        };
        const selected = try feature_directory.validate(allocator, .{ .bytes = feature_name }, .{ .specs = specs_path, .archive = "retired" });
        var before: feature_directory.Directory = .{ .selector = selected, .root_observation = .absent, .observation = .absent };
        if (present != .neither) {
            const specs = try directories.ensure(io, project, specs_path);
            defer specs.close(io);
            binding.specs_observation = .{ .directory = try directories.inspectReadable(io, specs) };
            before.root_observation = binding.specs_observation;
            if (present == .both) {
                const feature = try directories.ensure(io, specs, feature_name);
                defer feature.close(io);
                before.observation = .{ .directory = try directories.inspectReadable(io, feature) };
            }
        }
        const paths = try artifacts.resolveFeaturePaths(allocator, binding.paths, selected);
        var reader: source.Adapter = .{ .io = io, .project_root = project };
        const prior = try reader.captureBound(binding, allocator, before, paths);
        try std.testing.expect((try reader.captureWorkflowStateBound(binding, allocator, before, paths)) == null);
        const specs = try directories.ensure(io, project, specs_path);
        defer specs.close(io);
        const feature = try directories.ensure(io, specs, feature_name);
        defer feature.close(io);
        const current: feature_directory.Directory = .{
            .selector = selected,
            .root_observation = .{ .directory = try directories.inspectReadable(io, specs) },
            .observation = .{ .directory = try directories.inspectReadable(io, feature) },
        };
        return .{ .binding = binding, .before = before, .current = current, .paths = paths, .prior = prior, .owner = try active_directory.createValidated(allocator, binding, before, current) };
    }

    fn prepared(self: ActivatedFixture) output.Prepared {
        return .{
            .terminal_outcome = .ok,
            .feature = self.current,
            .paths = self.paths,
            .prior = self.prior,
            .prior_workflow_state = .{ .captured = null },
            .files = &.{
                .{ .target = .{ .artifact = .specification }, .bytes = "# Supported specification\n" },
                .{ .target = .{ .artifact = .reference_context }, .bytes = "# Reference context\n" },
                .{ .target = .{ .form = .{ .stage = .spec, .ordinal = 1 } }, .bytes = "Open clarification\n" },
                .{ .target = .{ .artifact = .workflow_state }, .bytes = "Validated state\n" },
            },
        };
    }
};

test "registered output and input readers consume only the activated feature identities" {
    const io = std.testing.io;
    for ([_]struct { specs: []const u8, feature: []const u8 }{
        .{ .specs = "requirements/current", .feature = "Chosen/Café" },
        .{ .specs = "custom/specifications", .feature = "Other/日本語" },
    }) |configuration| {
        inline for (.{ .neither, .root, .both }) |present| {
            var project = std.testing.tmpDir(.{});
            defer project.cleanup();
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const fixture = try ActivatedFixture.init(a, io, project.dir, configuration.specs, configuration.feature, present);
            defer active_directory.deinitOwner(fixture.owner);
            const active = active_directory.capability(fixture.owner);
            var reader: source.Adapter = .{ .io = io, .project_root = project.dir, .active_feature = active };
            try std.testing.expect(output.sameCapture(fixture.prior, try reader.captureBound(fixture.binding, a, fixture.current, fixture.paths)));
            try std.testing.expect((try reader.captureWorkflowStateBound(fixture.binding, a, fixture.current, fixture.paths)) == null);
            var writer: Adapter = .{ .io = io, .project_root = project.dir, .active_feature = active };
            var prepared = fixture.prepared();
            if (present != .both) {
                try std.testing.expectError(error.FeatureInputUnavailable, reader.captureBound(fixture.binding, a, fixture.before, fixture.paths));
                try std.testing.expectError(error.FeatureInputUnavailable, reader.captureWorkflowStateBound(fixture.binding, a, fixture.before, fixture.paths));
                prepared.feature = fixture.before;
                try std.testing.expectError(error.OutputChanged, writer.publishBound(fixture.binding, a, prepared));
                prepared.feature = fixture.current;
            }
            try writer.publishBound(fixture.binding, a, prepared);
            for (prepared.files) |file| {
                const path = try output.path(a, fixture.paths, file.target);
                try std.testing.expectEqualStrings(file.bytes, try project.dir.readFileAlloc(io, path.project_relative, a, .limited(128)));
            }
        }
    }
}

test "activated publication rejects changed roots features and physical directories" {
    const io = std.testing.io;
    for ([_]enum { binding_root, workflows, observation, feature, physical_root, physical_feature }{
        .binding_root, .workflows, .observation, .feature, .physical_root, .physical_feature,
    }) |change| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try ActivatedFixture.init(a, io, project.dir, "custom/specs", "Chosen/nested", .neither);
        defer active_directory.deinitOwner(fixture.owner);
        const active = active_directory.capability(fixture.owner);
        var binding = fixture.binding;
        var prepared = fixture.prepared();
        switch (change) {
            .binding_root => binding.paths.specs = "other/specs",
            .workflows => binding.workflows_identity.file_id += 1,
            .observation => prepared.feature.observation.directory.file_id += 1,
            .feature => {
                const selected = try @import("../../domain/feature_directory.zig").validate(a, .{ .bytes = "Other/nested" }, .{ .specs = binding.paths.specs, .archive = binding.paths.archive });
                prepared.feature.selector = selected;
                prepared.paths = try @import("../../domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, binding.paths, selected);
            },
            .physical_root, .physical_feature => {
                const changed = if (change == .physical_root) binding.paths.specs else prepared.feature.selector.project_relative_path;
                try project.dir.rename(changed, project.dir, "previous-directory", io);
                try project.dir.createDirPath(io, fixture.current.selector.project_relative_path);
            },
        }
        var reader: source.Adapter = .{ .io = io, .project_root = project.dir, .active_feature = active };
        try std.testing.expectError(error.FeatureInputUnavailable, reader.captureBound(binding, a, prepared.feature, prepared.paths));
        var writer: Adapter = .{ .io = io, .project_root = project.dir, .active_feature = active };
        try std.testing.expectError(error.OutputChanged, writer.publishBound(binding, a, prepared));
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, fixture.paths.get(.specification).project_relative, .{}));
        try std.testing.expectError(error.FileNotFound, project.dir.openFile(io, fixture.paths.get(.workflow_state).project_relative, .{}));
    }
}
