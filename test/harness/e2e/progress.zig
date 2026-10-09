//! Read-only links between observed defects and accepted native repair effects.
//! Event order is chronology, never a claim of the initiating semantic cause.
const std = @import("std");
const c = @import("contracts.zig");
const execution = @import("../../../src/domain/workflow_execution.zig");
const pipeline = @import("../../../src/domain/pipeline.zig");

pub const Progress = struct {
    arena: std.heap.ArenaAllocator,
    first: ?c.ObservedDefect = null,
    corrections: std.ArrayList(c.Correction) = .empty,
    outstanding: [@import("../../../src/domain/pipeline_data.zig").key_count]?usize = @splat(null),

    pub fn init(a: std.mem.Allocator) Progress {
        return .{ .arena = .init(a) };
    }
    pub fn deinit(self: *Progress) void {
        self.arena.deinit();
    }
    pub fn observe(self: *Progress, sequence: usize, step: []const u8, report: c.Report, effects: ?execution.AppliedEffects) !void {
        const a = self.arena.allocator();
        if (self.first == null) {
            const evidence: ?@FieldType(c.ObservedDefect, "evidence") = if (report.candidate_error) |value|
                .{ .candidate = value }
            else if (report.model_diagnostic) |reason|
                .{ .protocol = .{ .call = report.last_model_call orelse return error.MissingRequestEvidence, .origin = report.last_model_origin orelse return error.MissingRequestEvidence, .reason = reason, .json_error = report.json_error, .schema_error = report.schema_error } }
            else if (report.provider_diagnostic) |reason|
                .{ .provider = .{ .call = if (report.provider_origin != null) report.last_model_call else null, .origin = report.provider_origin, .reason = reason, .content = report.provider_content_diagnostic } }
            else if (report.last_operation_rejection) |value|
                .{ .operation = value }
            else if (report.terminal_rejection) |value|
                .{ .runner = value }
            else
                null;
            if (evidence) |value| self.first = try copy(c.ObservedDefect, a, .{ .sequence = sequence, .step = step, .evidence = value });
        }
        const applied = effects orelse return;
        var invalidated: std.ArrayList(pipeline.DataKey) = .empty;
        var rebuilt: std.ArrayList(c.WorkLink) = .empty;
        var it = applied.invalidations.iterator();
        while (it.next()) |key| {
            self.outstanding[@intFromEnum(key)] = sequence;
            try invalidated.append(a, key);
        }
        var produced = applied.writes;
        produced.setUnion(applied.replacements);
        it = produced.iterator();
        while (it.next()) |key| {
            const slot = &self.outstanding[@intFromEnum(key)];
            if (slot.*) |prior| try rebuilt.append(a, .{ .key = key, .invalidated_at = prior });
            slot.* = null;
        }
        if (applied.repair != null or applied.diagnostic != null or invalidated.items.len != 0 or rebuilt.items.len != 0) try self.corrections.append(a, .{
            .sequence = sequence,
            .step = try a.dupe(u8, step),
            .repair = applied.repair,
            .rejection = if (applied.diagnostic) |cause| @import("../../../src/domain/operation_error.zig").code(execution.OperationError, cause) else null,
            .invalidated = try invalidated.toOwnedSlice(a),
            .rebuilt = try rebuilt.toOwnedSlice(a),
        });
    }
    pub fn project(self: *const Progress, a: std.mem.Allocator, report: *c.Report) !void {
        report.first_observed_defect = if (self.first) |first| try copy(c.ObservedDefect, a, first) else null;
        report.corrections = try copy([]const c.Correction, a, self.corrections.items);
        var outstanding: std.ArrayList(c.WorkLink) = .empty;
        for (self.outstanding, 0..) |sequence, index| if (sequence) |value| {
            try outstanding.append(a, .{ .key = @enumFromInt(index), .invalidated_at = value });
        };
        report.outstanding_work = try outstanding.toOwnedSlice(a);
    }
};

fn copy(comptime T: type, a: std.mem.Allocator, value: T) !T {
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    defer a.free(bytes);
    return @import("../contracts.zig").decode(T, a, bytes);
}
