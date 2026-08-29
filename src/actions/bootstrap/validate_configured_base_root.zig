const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const pipeline = @import("../../domain/pipeline.zig");
const root_inspector = @import("../../ports/bootstrap_root_inspector.zig");

pub const Error = error{ BootstrapRootResolutionError, Cancelled };

pub const Action = struct {
    inspector: root_inspector.Inspector,

    pub const contract: pipeline.NodeContract = .{
        .id = "validate-configured-base-root@1",
        .kind = .action,
        .requires = &.{.configured_root_candidate_set},
        .produces = &.{.configured_root_capability_set},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        candidate: bootstrap_roots.ConfiguredRootCandidate,
    ) Error!bootstrap_roots.ValidatedConfiguredRoot {
        if (candidate.path.root_role != candidate.path.path_key.role()) {
            return error.BootstrapRootResolutionError;
        }
        const observation = self.inspector.inspect(candidate.path.relative_path) catch |inspection_error| {
            return switch (inspection_error) {
                error.Cancelled => error.Cancelled,
                error.BootstrapRootInspectionFailure => error.BootstrapRootResolutionError,
            };
        };
        if (candidate.path.path_key.existencePolicy() == .required_directory and
            observation == .absent)
        {
            return error.BootstrapRootResolutionError;
        }

        return .{
            .path_key = candidate.path.path_key,
            .root_role = candidate.path.root_role,
            .canonical_project_root = candidate.canonical_project_root,
            .configured_relative_path = candidate.path.relative_path,
            .canonical_path = candidate.canonical_path,
            .access_class = candidate.path.path_key.accessClass(),
            .existence_policy = candidate.path.path_key.existencePolicy(),
            .observation = observation,
        };
    }
};

const FakeInspector = struct {
    observation: bootstrap_roots.RootObservation,
    calls: usize = 0,

    fn port(self: *FakeInspector) root_inspector.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(context: *anyopaque, _: []const u8) root_inspector.Error!bootstrap_roots.RootObservation {
        const self: *FakeInspector = @ptrCast(@alignCast(context));
        self.calls += 1;
        return self.observation;
    }
};

fn testCandidate(key: bootstrap_roots.PathKey) bootstrap_roots.ConfiguredRootCandidate {
    return .{
        .path = .{ .path_key = key, .root_role = key.role(), .relative_path = "root" },
        .canonical_project_root = "/project",
        .canonical_path = "/project/root",
    };
}

test "admits an absent optional root without granting creation authority" {
    var fake: FakeInspector = .{ .observation = .absent };
    const capability = try (Action{ .inspector = fake.port() }).execute(testCandidate(.specs));
    try std.testing.expect(!capability.isPresent());
    try std.testing.expectEqual(bootstrap_roots.ExistencePolicy.optional_directory, capability.existence_policy);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "requires the workflow authority directory at preselection" {
    var fake: FakeInspector = .{ .observation = .absent };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        (Action{ .inspector = fake.port() }).execute(testCandidate(.workflows)),
    );
}

test "maps an unreadable workflow directory to root resolution failure" {
    var rejecting = RejectingInspector{};
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        (Action{ .inspector = rejecting.port() }).execute(testCandidate(.workflows)),
    );
    try std.testing.expectEqual(@as(usize, 1), rejecting.calls);
}

const RejectingInspector = struct {
    calls: usize = 0,

    fn port(self: *RejectingInspector) root_inspector.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(context: *anyopaque, _: []const u8) root_inspector.Error!bootstrap_roots.RootObservation {
        const self: *RejectingInspector = @ptrCast(@alignCast(context));
        self.calls += 1;
        return error.BootstrapRootInspectionFailure;
    }
};

test "preserves an explicit inspection cancellation" {
    var cancelling = CancellingInspector{};
    try std.testing.expectError(
        error.Cancelled,
        (Action{ .inspector = cancelling.port() }).execute(testCandidate(.principles)),
    );
}

const CancellingInspector = struct {
    fn port(self: *CancellingInspector) root_inspector.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(_: *anyopaque, _: []const u8) root_inspector.Error!bootstrap_roots.RootObservation {
        return error.Cancelled;
    }
};
