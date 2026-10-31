//! FIX06 T5(e): the request projection. Every request the fake provider receives is
//! projected at the provider port, so an engine change that must leave model input
//! unchanged is proved by a byte diff of two freezes. It is an observation, never
//! asserted against expected content.
const std = @import("std");
const binding = @import("../domain/llm_provider_binding.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const identity = @import("../domain/model_request_identity.zig");
const description = @import("../domain/model_request_description.zig");
const provider_interface = @import("../ports/llm_provider_interface.zig");

/// Names the freeze root; unset, projections are kept in memory only.
pub const environment_variable = "SDDE_REQUEST_PROJECTION";

/// Description members that engine refactors change by design (E1, E4).
const omitted = [_][]const u8{ "version", "workflow_version", "request_step" };

/// The description of one invocation without the omitted members, member order and
/// number spellings preserved.
pub fn project(
    a: std.mem.Allocator,
    request: *const operation.IdentifiedProviderNeutralModelRequest,
    selected: *const binding.ValidatedProviderModelBinding,
    kind: operation.ProviderOperationKind,
) ![]u8 {
    const full = try std.json.Stringify.valueAlloc(a, description.Description.from(request, selected, kind), .{});
    var value = try std.json.parseFromSliceLeaky(std.json.Value, a, full, .{ .parse_numbers = false });
    for (omitted) |member| if (!value.object.orderedRemove(member)) return error.MissingDescriptionMember;
    return std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_1 });
}

pub const Sink = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: ?std.Io.Dir = null,
    /// The scenario group, so groups that share a freeze never overwrite each other's
    /// scenario numbers: `<group>/scenario-NNN/call-NNNN.json`.
    group: []const u8 = "",
    entries: std.ArrayList(Entry) = .empty,

    /// One recorded invocation, keyed by its provider-call order in the scenario (the
    /// E2E evidence's `call-NNNN` numbering): a request ordinal restarts for each unit,
    /// and the run's ledger position isn't visible at the provider port. The request,
    /// attempt, kind and digest serve the projection's own tests; the freeze holds the
    /// bytes.
    pub const Entry = struct {
        scenario: usize,
        call: usize,
        request: u32,
        attempt: u32,
        owner: std.meta.Tag(identity.ImmutableUnitOwnerId),
        purpose: identity.RequestPurposeKind,
        digest: [32]u8,
    };

    /// Writes `<group>/scenario-NNN/call-NNNN.json` under the directory the environment names,
    /// creating it when missing; without one, records in memory. A named directory that
    /// can't be used ends the test process, so a freeze is never silently empty.
    pub fn fromEnvironment(allocator: std.mem.Allocator, io: std.Io) !Sink {
        const path = std.testing.environ.getAlloc(allocator, environment_variable) catch |err| switch (err) {
            error.EnvironmentVariableMissing => return .{ .allocator = allocator, .io = io },
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidWtf8 => unusable("", err),
        };
        defer allocator.free(path);
        if (path.len == 0) unusable(path, error.EmptyPath);
        const root = std.Io.Dir.cwd().createDirPathOpen(io, path, .{ .open_options = .{ .iterate = true } }) catch |err| unusable(path, err);
        return .{ .allocator = allocator, .io = io, .root = root };
    }

    fn unusable(path: []const u8, err: anyerror) noreturn {
        std.debug.panic("{s}=\"{s}\" is unusable: {s}", .{ environment_variable, path, @errorName(err) });
    }

    pub fn deinit(self: *Sink) void {
        if (self.root) |root| {
            self.writeManifest(root) catch |err| std.debug.panic("request projection manifest failed: {s}", .{@errorName(err)});
            root.close(self.io);
        }
        self.entries.deinit(self.allocator);
    }

    /// `manifest.json` counts the groups, scenarios and calls the whole directory holds,
    /// so a missing or partial freeze never diffs clean. Each sink sharing the directory
    /// rewrites it as it closes.
    pub fn writeManifest(self: *Sink, root: std.Io.Dir) !void {
        var manifest: struct { groups: usize = 0, scenarios: usize = 0, calls: usize = 0 } = .{};
        var groups = root.iterate();
        while (try groups.next(self.io)) |group| {
            if (group.kind != .directory) continue;
            manifest.groups += 1;
            var group_directory = try root.openDir(self.io, group.name, .{ .iterate = true });
            defer group_directory.close(self.io);
            var scenarios = group_directory.iterate();
            while (try scenarios.next(self.io)) |scenario| {
                if (scenario.kind != .directory or !std.mem.startsWith(u8, scenario.name, "scenario-")) continue;
                manifest.scenarios += 1;
                var directory = try group_directory.openDir(self.io, scenario.name, .{ .iterate = true });
                defer directory.close(self.io);
                var calls = directory.iterate();
                while (try calls.next(self.io)) |call| manifest.calls += @intFromBool(call.kind == .file and std.mem.startsWith(u8, call.name, "call-"));
            }
        }
        const bytes = try std.json.Stringify.valueAlloc(self.allocator, manifest, .{ .whitespace = .indent_1 });
        defer self.allocator.free(bytes);
        try root.writeFile(self.io, .{ .sub_path = "manifest.json", .data = bytes });
    }

    fn record(
        self: *Sink,
        scenario: usize,
        call: usize,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        selected: *const binding.ValidatedProviderModelBinding,
        invoked: *const operation.InvokedProviderOperation,
    ) !void {
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const bytes = try project(a, request, selected, invoked.id.kind);
        var entry: Entry = .{
            .scenario = scenario,
            .call = call,
            .request = request.model_request_id.request_ordinal.value,
            .attempt = invoked.id.model_attempt_ordinal.value,
            .owner = std.meta.activeTag(request.model_request_id.immutable_unit_owner_id),
            .purpose = std.meta.activeTag(request.model_request_id.purpose),
            .digest = undefined,
        };
        std.crypto.hash.sha2.Sha256.hash(bytes, &entry.digest, .{});
        try self.entries.append(self.allocator, entry);
        const root = self.root orelse return;
        if (self.group.len == 0) return error.UngroupedProjection;
        var directory = try root.createDirPathOpen(self.io, try std.fmt.allocPrint(a, "{s}/scenario-{d:0>3}", .{ self.group, scenario }), .{});
        defer directory.close(self.io);
        try directory.writeFile(self.io, .{ .sub_path = try std.fmt.allocPrint(a, "call-{d:0>4}.json", .{call}), .data = bytes });
    }
};

/// A provider port that records each invocation in its sink, then delegates.
pub const Recorder = struct {
    sink: *Sink,
    scenario: usize,
    inner: provider_interface.LLMProviderInterface,
    recorded: usize = 0,

    pub fn interface(self: *Recorder) provider_interface.LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &vtable };
    }

    const vtable: provider_interface.LLMProviderInterface.VTable = .{ .invoke = invoke };

    fn invoke(
        context: *provider_interface.Context,
        selected: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        authorization: *const operation.ValidatedProviderAuthorizationLeaseRef,
        invoked: *const operation.InvokedProviderOperation,
    ) provider_interface.Error!operation.ProviderInvocationObservation {
        const self: *Recorder = @ptrCast(@alignCast(context));
        self.recorded += 1;
        self.sink.record(self.scenario, self.recorded, request, selected, invoked) catch |err| std.debug.panic("request projection failed: {s}", .{@errorName(err)});
        return self.inner.invoke(selected, request, authorization, invoked);
    }
};
