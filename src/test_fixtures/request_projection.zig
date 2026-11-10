//! The request projection. Every request the fake provider receives is
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

/// One frozen invocation, read strictly: the description's members less `omitted`.
/// The freeze carries no version, so none is checked.
pub const Projection = struct {
    provider: Member("provider"),
    model: Member("model"),
    provider_config: Member("provider_config"),
    model_slot: Member("model_slot"),
    workflow_id: Member("workflow_id"),
    content: Member("content"),
    protocol_prompt: Member("protocol_prompt"),
    schema: Member("schema"),
    response_mode: Member("response_mode"),
    controls: Member("controls"),
    sampling: Member("sampling"),
    reasoning_effort: Member("reasoning_effort"),
    operation_kind: Member("operation_kind"),
    original_sources: Member("original_sources"),
    prose_fields: Member("prose_fields"),
    field_policies: Member("field_policies"),
    exact_scope: Member("exact_scope"),
    members: Member("members"),
    coverages: Member("coverages"),

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) @import("../domain/strict_json.zig").Error!Projection {
        return @import("../domain/strict_json.zig").decode(Projection, a, bytes, .{ .maximum_depth = 64 });
    }
};

fn Member(comptime name: []const u8) type {
    return @FieldType(description.Description, name);
}

comptime {
    const kept = @typeInfo(Projection).@"struct".fields;
    if (kept.len + omitted.len != @typeInfo(description.Description).@"struct".fields.len) @compileError("Projection must hold every description member except the omitted ones");
    for (omitted) |member| if (@hasField(Projection, member)) @compileError("Projection holds an omitted member");
}

/// The freeze's `manifest.json`: the groups, scenarios and calls its directory holds.
pub const Manifest = struct {
    groups: usize,
    scenarios: usize,
    calls: usize,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) @import("../domain/strict_json.zig").Error!Manifest {
        return @import("../domain/strict_json.zig").decode(Manifest, a, bytes, .{ .maximum_depth = 8 });
    }
};

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
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const listing = try calls(arena.allocator(), self.io, root);
        const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), listing.manifest, .{ .whitespace = .indent_1 });
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

/// The call files a freeze directory holds, as `<group>/scenario-NNN/call-NNNN.json`
/// paths relative to it, with the counts its manifest records.
pub const Listing = struct { manifest: Manifest, paths: []const []const u8 };

/// Lists the freeze layout `Sink` writes. Returned storage belongs to `a`.
pub fn calls(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Listing {
    var manifest: Manifest = .{ .groups = 0, .scenarios = 0, .calls = 0 };
    var paths: std.ArrayList([]const u8) = .empty;
    var groups = root.iterate();
    while (try groups.next(io)) |group| {
        if (group.kind != .directory) continue;
        manifest.groups += 1;
        var group_directory = try root.openDir(io, group.name, .{ .iterate = true });
        defer group_directory.close(io);
        var scenarios = group_directory.iterate();
        while (try scenarios.next(io)) |scenario| {
            if (scenario.kind != .directory or !std.mem.startsWith(u8, scenario.name, "scenario-")) continue;
            manifest.scenarios += 1;
            var directory = try group_directory.openDir(io, scenario.name, .{ .iterate = true });
            defer directory.close(io);
            var files = directory.iterate();
            while (try files.next(io)) |call| {
                if (call.kind != .file or !std.mem.startsWith(u8, call.name, "call-")) continue;
                manifest.calls += 1;
                try paths.append(a, try std.fs.path.join(a, &.{ group.name, scenario.name, call.name }));
            }
        }
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return .{ .manifest = manifest, .paths = try paths.toOwnedSlice(a) };
}

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
