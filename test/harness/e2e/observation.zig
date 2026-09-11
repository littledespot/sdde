//! Read-only projection of runner-owned provider evidence into a test report.
const std = @import("std");
const c = @import("contracts.zig");
const models = @import("../contracts.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const requests = @import("../../../src/application/model_request_workflow.zig");
const authorization = @import("../../../src/application/provider_authorization_workflow.zig");

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
                    .protocol_rejected => |reason| report.model_diagnostic = @errorName(reason),
                    .decoded, .not_decoded => {},
                };
            }
            const payload = @import("../../../src/application/model_payload_schema_workflow.zig");
            if (view.slots[@intFromEnum(payload.schema.key)] != null) {
                const result = try values.read(&view, payload.schema, payload.Result);
                if (result.source().source().operationId().model_request_id == request.id()) switch (result.outcome()) {
                    .schema_rejected => |reason| report.model_diagnostic = @tagName(reason),
                    .valid, .not_validated => {},
                };
            }
        }
    }
    report.models = try used.toOwnedSlice(allocator);
}
