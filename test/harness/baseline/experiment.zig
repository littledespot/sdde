//! One-shot experiment admission. A claim is consumed before credentials or
//! dispatch; failed and interrupted acquisitions cannot restart the same freeze.
//! This diagnostic artifact supplies no workflow recovery or engine authority.
const std = @import("std");
const dispatch = @import("dispatch.zig");
const feasibility = @import("feasibility.zig");
const contracts = @import("../contracts.zig");

pub const claim_root = "zig-out/baseline/claims";
pub const Claim = struct {
    schema: enum { @"baseline-experiment-claim/v1" },
    experiment_sha256: []const u8,
    freeze_sha256: []const u8,
    execution_id: []const u8,
    limits: dispatch.Limits,
    phases: []const feasibility.Phase,
    acquisition: enum { baseline_once_no_resume } = .baseline_once_no_resume,
};
pub const FuturePhase = struct {
    phase: feasibility.Phase,
    state: enum { reserved_unexecuted } = .reserved_unexecuted,
};
pub const Allowance = struct {
    limits: dispatch.Limits,
    consumed_physical_sends: u64,
    known_consumed_actual_tokens: u128,
    consumed_actual_tokens: ?u128,
    unspent_physical_sends: u64,
    unspent_actual_tokens: ?u128,
    future_phases: []const FuturePhase,
    /// Unspent allowance is arithmetic evidence, never permission to restart
    /// this baseline or dispatch a later phase without its shared accounting.
    future_phase_dispatch: enum { unavailable } = .unavailable,
    baseline_restart: enum { prohibited } = .prohibited,
};

fn digest(bytes: []const u8) bool {
    if (bytes.len != 64) return false;
    for (bytes) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

fn validateFields(claim: Claim) !void {
    if (!digest(claim.experiment_sha256) or !digest(claim.freeze_sha256) or !contracts.id(claim.execution_id) or claim.phases.len == 0) return error.InvalidExperimentClaim;
    _ = dispatch.Gate.init(claim.limits) catch return error.InvalidExperimentClaim;
    var baseline = false;
    for (claim.phases, 0..) |phase, index| {
        baseline = baseline or phase == .baseline;
        for (claim.phases[0..index]) |prior| if (prior == phase) return error.InvalidExperimentClaim;
    }
    if (!baseline) return error.InvalidExperimentClaim;
}

pub fn validate(claim: Claim, experiment_sha256: []const u8, freeze_sha256: []const u8, execution_id: []const u8, phases: []const feasibility.Phase, limits: dispatch.Limits) !void {
    try validateFields(claim);
    if (!std.mem.eql(u8, claim.experiment_sha256, experiment_sha256) or !std.mem.eql(u8, claim.freeze_sha256, freeze_sha256) or !std.mem.eql(u8, claim.execution_id, execution_id) or
        !std.meta.eql(claim.limits, limits) or !std.mem.eql(feasibility.Phase, claim.phases, phases)) return error.InvalidExperimentClaim;
}

fn name(a: std.mem.Allocator, experiment_sha256: []const u8) ![]const u8 {
    if (!digest(experiment_sha256)) return error.InvalidExperimentClaim;
    return std.fmt.allocPrint(a, "{s}.json", .{experiment_sha256});
}

/// The exclusive filename derives from the canonical closed freeze value. A
/// renamed/copied/reformatted freeze cannot create a second allowance. Never unlink a
/// partial claim on failure: uncertain admission must remain consumed.
pub fn consume(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, claim: Claim) !void {
    try validateFields(claim);
    const directory = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, repository, claim_root);
    defer directory.close(io);
    const filename = try name(a, claim.experiment_sha256);
    defer a.free(filename);
    const bytes = try std.json.Stringify.valueAlloc(a, claim, .{});
    defer a.free(bytes);
    const file = directory.createFile(io, filename, .{ .exclusive = true, .permissions = .fromMode(0o600) }) catch |err| switch (err) {
        error.PathAlreadyExists => return error.BaselineAlreadyClaimed,
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}

pub fn verify(io: std.Io, a: std.mem.Allocator, repository: std.Io.Dir, expected: Claim) !void {
    try validateFields(expected);
    const filename = try name(a, expected.experiment_sha256);
    defer a.free(filename);
    const path = try std.fs.path.join(a, &.{ claim_root, filename });
    defer a.free(path);
    const bytes = try @import("../files.zig").read(io, a, repository, path);
    defer a.free(bytes);
    const captured = try contracts.decode(Claim, a, bytes);
    try validate(captured, expected.experiment_sha256, expected.freeze_sha256, expected.execution_id, expected.phases, expected.limits);
}

pub fn remaining(a: std.mem.Allocator, phases: []const feasibility.Phase, budget: dispatch.Snapshot) !Allowance {
    var future: std.ArrayList(FuturePhase) = .empty;
    errdefer future.deinit(a);
    for (phases) |phase| if (phase != .baseline) try future.append(a, .{ .phase = phase });
    return .{
        .limits = budget.limits,
        .consumed_physical_sends = budget.physical_sends,
        .known_consumed_actual_tokens = budget.total_accounted_tokens,
        .consumed_actual_tokens = budget.total_actual_tokens,
        .unspent_physical_sends = budget.limits.maximum_sends -| budget.physical_sends,
        .unspent_actual_tokens = if (budget.total_actual_tokens) |actual| @as(u128, budget.limits.maximum_actual_tokens) -| actual else null,
        .future_phases = try future.toOwnedSlice(a),
    };
}

test "one-shot claim rejects a second run even for copied freeze bytes and retains its identity" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    const claim: Claim = .{ .schema = .@"baseline-experiment-claim/v1", .experiment_sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", .freeze_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", .execution_id = "first-run", .limits = .{ .maximum_sends = 10, .maximum_actual_tokens = 100 }, .phases = &.{ .baseline, .selection, .qualification } };
    try consume(std.testing.io, a, repository.dir, claim);
    try verify(std.testing.io, a, repository.dir, claim);
    var retry = claim;
    retry.execution_id = "retry-run";
    retry.freeze_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    try std.testing.expectError(error.BaselineAlreadyClaimed, consume(std.testing.io, a, repository.dir, retry));
    try std.testing.expectError(error.InvalidExperimentClaim, verify(std.testing.io, a, repository.dir, retry));
    try verify(std.testing.io, a, repository.dir, claim);
}

test "partial claims remain consumed and invalid external identities cannot select a path" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    var claim: Claim = .{ .schema = .@"baseline-experiment-claim/v1", .experiment_sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", .freeze_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", .execution_id = "failed-run", .limits = .{ .maximum_sends = 10, .maximum_actual_tokens = 100 }, .phases = &.{.baseline} };
    const directory = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(std.testing.io, repository.dir, claim_root);
    defer directory.close(std.testing.io);
    try directory.writeFile(std.testing.io, .{ .sub_path = try name(a, claim.experiment_sha256), .data = "{" });
    try std.testing.expectError(error.BaselineAlreadyClaimed, consume(std.testing.io, a, repository.dir, claim));
    claim.freeze_sha256 = "../outside";
    try std.testing.expectError(error.InvalidExperimentClaim, consume(std.testing.io, a, repository.dir, claim));
}

test "baseline allowance retains overshoot unknown usage and unexecuted future phase reservations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var gate = try dispatch.Gate.init(.{ .maximum_sends = 3, .maximum_actual_tokens = 10 });
    try gate.reconcile(try gate.beforeSend(), dispatch.ProviderUsage.init(4, 3, 7).?, false);
    const known = try remaining(a, &.{ .baseline, .selection, .qualification }, gate.snapshot());
    try std.testing.expectEqual(@as(u64, 1), known.consumed_physical_sends);
    try std.testing.expectEqual(@as(u64, 2), known.unspent_physical_sends);
    try std.testing.expectEqual(@as(?u128, 3), known.unspent_actual_tokens);
    try std.testing.expectEqual(@as(usize, 2), known.future_phases.len);
    try std.testing.expectEqual(.reserved_unexecuted, known.future_phases[0].state);
    try gate.reconcile(try gate.beforeSend(), null, true);
    const unknown = try remaining(a, &.{.baseline}, gate.snapshot());
    try std.testing.expect(unknown.consumed_actual_tokens == null and unknown.unspent_actual_tokens == null);
    try std.testing.expectEqual(@as(u128, 7), unknown.known_consumed_actual_tokens);
    var exceeded = try dispatch.Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 10 });
    try exceeded.reconcile(try exceeded.beforeSend(), dispatch.ProviderUsage.init(10, 2, 12).?, false);
    const overshot = try remaining(a, &.{.baseline}, exceeded.snapshot());
    try std.testing.expectEqual(@as(?u128, 0), overshot.unspent_actual_tokens);
    try std.testing.expectEqual(@as(?u128, 12), overshot.consumed_actual_tokens);
}
