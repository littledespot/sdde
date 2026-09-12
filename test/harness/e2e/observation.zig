//! Read-only projection of runner-owned provider evidence into a test report.
const std = @import("std");
const c = @import("contracts.zig");
const models = @import("../contracts.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const requests = @import("../../../src/application/model_request_workflow.zig");
const authorization = @import("../../../src/application/provider_authorization_workflow.zig");

/// Diagnostic projection only: retirement may release transport before the
/// runner rejects continuation. A new actual call supersedes this snapshot.
pub const LastModelRejection = struct {
    call: usize = 0,
    reason: ?[]const u8 = null,
    json_error: @FieldType(c.Report, "json_error") = null,
    schema_error: @FieldType(c.Report, "schema_error") = null,
    usage: @FieldType(c.Report, "last_model_usage") = null,

    pub fn deinit(self: *LastModelRejection, allocator: std.mem.Allocator) void {
        if (self.reason) |reason| allocator.free(reason);
        if (self.json_error) |diagnostic| diagnostic.deinit(allocator);
        if (self.schema_error) |diagnostic| allocator.free(diagnostic.path);
        self.* = .{};
    }

    pub fn observe(self: *LastModelRejection, allocator: std.mem.Allocator, call: usize, report: c.Report) !void {
        if (self.call != call) self.deinit(allocator);
        self.call = call;
        const diagnostic = report.model_diagnostic orelse return;
        const reason = try allocator.dupe(u8, diagnostic);
        errdefer allocator.free(reason);
        var shape = report.schema_error;
        if (shape) |*value| value.path = try allocator.dupe(u8, value.path);
        errdefer if (shape) |value| allocator.free(value.path);
        const json_error = if (report.json_error) |value| try value.copy(allocator) else null;
        self.deinit(allocator);
        self.* = .{ .call = call, .reason = reason, .json_error = json_error, .schema_error = shape, .usage = report.last_model_usage };
    }

    pub fn project(self: *const LastModelRejection, allocator: std.mem.Allocator, call: usize, report: *c.Report) !void {
        if (self.call != call or report.workflow_outcome == .ok or report.model_diagnostic != null) return;
        const reason = self.reason orelse return;
        const retained = try allocator.dupe(u8, reason);
        errdefer allocator.free(retained);
        var shape = self.schema_error;
        if (shape) |*diagnostic| diagnostic.path = try allocator.dupe(u8, diagnostic.path);
        errdefer if (shape) |value| allocator.free(value.path);
        const json_error = if (self.json_error) |value| try value.copy(allocator) else null;
        report.model_diagnostic = retained;
        report.json_error = json_error;
        report.schema_error = shape;
        report.last_model_usage = self.usage;
    }
};

pub fn capture(allocator: std.mem.Allocator, runner: *const @import("../../../src/application/workflow_pipeline_runner.zig").Runner, report: *c.Report) !void {
    const ledger = runner.tokenLedger();
    report.model_calls = ledger.accounted_operations.items.len;
    report.total_tokens = ledger.committed();
    report.usage_complete = ledger.status() != .usage_unavailable;
    var used: std.ArrayList(models.GenerationModel) = .empty;
    defer used.deinit(allocator);
    if (runner.model_accounting) |accounting| {
        const services = runner.model_provider_services orelse return error.MissingProviderEvidence;
        for (ledger.accounted_operations.items) |id| {
            const record = accounting.current_operations.record(id) orelse return error.MissingProviderEvidence;
            report.last_model_step = try allocator.dupe(u8, record.binding_id.operation_id.workflow_step_id.bytes);
            const entry = services.registry().resolveId(record.binding_id.registry_entry_id) orelse return error.MissingProviderEvidence;
            const slot = record.binding_id.slot_id.bytes;
            const found = for (used.items) |model| {
                if (std.mem.eql(u8, model.slot, slot)) break true;
            } else false;
            if (!found) try used.append(allocator, .{
                .slot = try allocator.dupe(u8, slot),
                .provider = try allocator.dupe(u8, entry.provider.bytes),
                .model = try allocator.dupe(u8, entry.model.bytes),
            });
        }
    }
    const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
    report.candidate_error = if (try @import("../../../src/application/candidate_validation_diagnostics.zig").read(&view)) |diagnostic| try diagnostic.copy(allocator) else null;
    if (report.candidate_error) |diagnostic| if (diagnostic.origin()) |origin| {
        const accounting = runner.model_accounting orelse return error.MissingProviderEvidence;
        const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
        var found = false;
        for (ledger.accounted_operations.items) |id| if (origin.matches(identities, id)) {
            if (found) return error.MissingProviderEvidence;
            const record = accounting.current_operations.record(id) orelse return error.MissingProviderEvidence;
            report.candidate_model_step = try allocator.dupe(u8, record.binding_id.operation_id.workflow_step_id.bytes);
            found = true;
        };
        if (!found) return error.MissingProviderEvidence;
    };
    if (view.slots[@intFromEnum(requests.prepared_schema.key)] != null) {
        const request = try requests.readCurrent(&view, requests.prepared_schema);
        report.last_model_step = try allocator.dupe(u8, request.binding().operation_id.workflow_step_id.bytes);
        const binding = request.binding();
        const found = for (used.items) |model| {
            if (std.mem.eql(u8, model.slot, binding.slot_id.bytes)) break true;
        } else false;
        if (!found) try used.append(allocator, .{
            .slot = try allocator.dupe(u8, binding.slot_id.bytes),
            .provider = try allocator.dupe(u8, binding.registry_entry.provider.bytes),
            .model = try allocator.dupe(u8, binding.registry_entry.model.bytes),
        });
        const observation = @import("../../../src/application/provider_observation_workflow.zig");
        if (view.slots[@intFromEnum(observation.schema.key)] != null) {
            const result = try values.read(&view, observation.schema, observation.Result);
            if (result.operationId().model_request_id == request.id()) switch (result.outcome()) {
                .validated => |evidence| {
                    report.last_model_usage = evidence.usage();
                    switch (evidence.result()) {
                        .failed => |failure| report.provider_diagnostic = @tagName(failure.cause),
                        .stopped => |reason| report.provider_diagnostic = @tagName(reason),
                        .complete => {},
                    }
                },
                .rejected => |reason| report.provider_diagnostic = @errorName(reason),
                .cancelled => {},
            };
        }
        if (report.workflow_outcome != .ok) {
            if (view.slots[@intFromEnum(authorization.schema.key)] != null) {
                const result = try values.read(&view, authorization.schema, @import("../../../src/domain/provider_authorization_result.zig").Result);
                switch (result.outcome().*) {
                    .failed => |failure| if (failure.operation_id.model_request_id == request.id()) {
                        report.provider_diagnostic = @tagName(failure.cause);
                    },
                    .prepared, .cancelled => {},
                }
            }
            const envelope = @import("../../../src/application/model_envelope_workflow.zig");
            if (view.slots[@intFromEnum(envelope.schema.key)] != null) {
                const result = try values.read(&view, envelope.schema, envelope.Result);
                if (result.source().operationId().model_request_id == request.id()) switch (result.outcome()) {
                    .protocol_rejected => |rejection| {
                        report.model_diagnostic = @errorName(rejection.reason);
                        report.json_error = try rejection.diagnostic.copy(allocator);
                    },
                    .decoded, .not_decoded => {},
                };
            }
            const payload = @import("../../../src/application/model_payload_schema_workflow.zig");
            if (view.slots[@intFromEnum(payload.schema.key)] != null) {
                const result = try values.read(&view, payload.schema, payload.Result);
                if (result.source().source().operationId().model_request_id == request.id()) switch (result.outcome()) {
                    .schema_rejected => |diagnostic| {
                        report.model_diagnostic = @tagName(diagnostic.reason);
                        report.schema_error = try diagnostic.describe(allocator);
                    },
                    .valid, .not_validated => {},
                };
            }
        }
    }
    report.models = try used.toOwnedSlice(allocator);
}
