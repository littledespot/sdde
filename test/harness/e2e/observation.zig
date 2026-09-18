//! Read-only projection of runner-owned provider evidence into a test report.
const std = @import("std");
const c = @import("contracts.zig");
const models = @import("../contracts.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const requests = @import("../../../src/application/model_request_workflow.zig");
const authorization = @import("../../../src/application/provider_authorization_workflow.zig");

/// Diagnostic projection only: retirement may release transport before the
/// runner rejects continuation. Only a newer protocol rejection supersedes it.
pub const LastModelRejection = struct {
    call: usize = 0,
    origin: ?@import("../../../src/domain/model_candidate_origin.zig").Origin = null,
    reason: ?[]const u8 = null,
    json_error: @FieldType(c.Report, "json_error") = null,
    schema_error: @FieldType(c.Report, "schema_error") = null,

    pub fn deinit(self: *LastModelRejection, allocator: std.mem.Allocator) void {
        if (self.reason) |reason| allocator.free(reason);
        if (self.json_error) |diagnostic| diagnostic.deinit(allocator);
        if (self.schema_error) |diagnostic| allocator.free(diagnostic.path);
        self.* = .{};
    }

    pub fn observe(self: *LastModelRejection, allocator: std.mem.Allocator, call: usize, report: c.Report) !void {
        const diagnostic = report.model_diagnostic orelse return;
        const origin = report.last_model_origin orelse return error.MissingRequestEvidence;
        const reason = try allocator.dupe(u8, diagnostic);
        errdefer allocator.free(reason);
        var shape = report.schema_error;
        if (shape) |*value| value.path = try allocator.dupe(u8, value.path);
        errdefer if (shape) |value| allocator.free(value.path);
        const json_error = if (report.json_error) |value| try value.copy(allocator) else null;
        self.deinit(allocator);
        self.* = .{ .call = call, .origin = origin, .reason = reason, .json_error = json_error, .schema_error = shape };
    }

    pub fn project(self: *const LastModelRejection, allocator: std.mem.Allocator, call: usize, report: *c.Report) !void {
        const reason = self.reason orelse return;
        const retained = try allocator.dupe(u8, reason);
        errdefer allocator.free(retained);
        var shape = self.schema_error;
        if (shape) |*diagnostic| diagnostic.path = try allocator.dupe(u8, diagnostic.path);
        errdefer if (shape) |value| allocator.free(value.path);
        const json_error = if (self.json_error) |value| try value.copy(allocator) else null;
        report.last_protocol_rejection = .{ .call = self.call, .origin = self.origin orelse return error.MissingRequestEvidence, .reason = retained, .json_error = json_error, .schema_error = shape };
        if (self.call == call and report.workflow_outcome != .ok and report.model_diagnostic == null) {
            report.model_diagnostic = retained;
            report.json_error = json_error;
            report.schema_error = shape;
        }
    }
};

pub fn capture(allocator: std.mem.Allocator, runner: *const @import("../../../src/application/workflow_pipeline_runner.zig").Runner, report: *c.Report) !void {
    const ledger = runner.tokenLedger();
    report.model_calls = ledger.accounted_operations.items.len;
    report.total_tokens = ledger.committed();
    report.usage_complete = ledger.status() != .usage_unavailable;
    report.total_token_budget = ledger.totalTokenBudget().value;
    report.retry_settings = try runner.retryObservations(allocator);
    const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
    var attempts: std.ArrayList(c.Attempt) = .empty;
    var used: std.ArrayList(models.GenerationModel) = .empty;
    defer used.deinit(allocator);
    if (runner.model_accounting) |accounting| {
        const services = runner.model_provider_services orelse return error.MissingProviderEvidence;
        for (ledger.accounted_operations.items) |accounted| {
            const id = accounted.id;
            const record = accounting.current_operations.record(id) orelse return error.MissingProviderEvidence;
            const entry = services.registry().resolveId(record.binding_id.registry_entry_id) orelse return error.MissingProviderEvidence;
            const slot = record.binding_id.slot_id.bytes;
            const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
            const origin = @import("../../../src/domain/model_candidate_origin.zig").Origin.from(identities, id) orelse return error.MissingProviderEvidence;
            const usage = if (accounted.reconciliation == .exact_usage) accounted.reconciliation.exact_usage else null;
            try attempts.append(allocator, .{ .origin = origin, .step = try allocator.dupe(u8, record.binding_id.operation_id.workflow_step_id.bytes), .accounting = accounted.reconciliation, .usage = usage });
            report.last_model_origin = origin;
            report.last_model_usage = usage;
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
    report.attempts = try attempts.toOwnedSlice(allocator);
    report.candidate_error = if (try @import("../../../src/application/candidate_validation_diagnostics.zig").read(&view)) |diagnostic| try diagnostic.copy(allocator) else null;
    report.repairs = try @import("../../../src/application/candidate_repair_observations.zig").read(allocator, &view);
    if (report.candidate_error) |diagnostic| if (diagnostic.origin()) |origin| {
        const accounting = runner.model_accounting orelse return error.MissingProviderEvidence;
        const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
        var found = false;
        for (ledger.accounted_operations.items) |accounted| if (origin.matches(identities, accounted.id)) {
            const id = accounted.id;
            if (found) return error.MissingProviderEvidence;
            _ = accounting.current_operations.record(id) orelse return error.MissingProviderEvidence;
            found = true;
        };
        if (!found) return error.MissingProviderEvidence;
    };
    const observation = @import("../../../src/application/provider_observation_workflow.zig");
    const information = runner.envelope.latestInformation(observation.schema.key);
    if (information.contains(observation.schema.key)) {
        const result = try values.read(&information, observation.schema, observation.Result);
        if (latest(ledger, result.operationId())) switch (result.outcome()) {
            .validated => |evidence| {
                const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
                report.last_model_origin = @import("../../../src/domain/model_candidate_origin.zig").Origin.from(identities, result.operationId()) orelse return error.MissingProviderEvidence;
                report.last_model_usage = evidence.usage();
                switch (evidence.result()) {
                    .failed => |failure| {
                        report.provider_diagnostic = @tagName(failure.cause);
                        report.provider_content_diagnostic = failure.content;
                    },
                    .stopped => |reason| report.provider_diagnostic = @tagName(reason),
                    .complete => {},
                }
            },
            .rejected => |reason| report.provider_diagnostic = @errorName(reason),
            .cancelled => {},
        };
    }
    if (view.slots[@intFromEnum(requests.prepared_schema.key)] != null) {
        const request = try requests.readCurrent(&view, requests.prepared_schema);
        const binding = request.binding();
        const found = for (used.items) |model| {
            if (std.mem.eql(u8, model.slot, binding.slot_id.bytes)) break true;
        } else false;
        if (!found) try used.append(allocator, .{
            .slot = try allocator.dupe(u8, binding.slot_id.bytes),
            .provider = try allocator.dupe(u8, binding.registry_entry.provider.bytes),
            .model = try allocator.dupe(u8, binding.registry_entry.model.bytes),
        });
        if (report.workflow_outcome != .ok) {
            if (view.slots[@intFromEnum(authorization.schema.key)] != null) {
                const result = try values.read(&view, authorization.schema, @import("../../../src/domain/provider_authorization_result.zig").Result);
                switch (result.outcome().*) {
                    .failed => |failure| if (failure.operation_id.model_request_id == request.id()) {
                        report.provider_diagnostic = @tagName(failure.cause);
                        report.provider_content_diagnostic = failure.content;
                    },
                    .prepared, .cancelled => {},
                }
            }
            const envelope = @import("../../../src/application/model_envelope_workflow.zig");
            if (view.slots[@intFromEnum(envelope.schema.key)] != null) {
                const result = try values.read(&view, envelope.schema, envelope.Result);
                if (latest(ledger, result.source().operationId())) switch (result.outcome()) {
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
                if (latest(ledger, result.source().source().operationId())) switch (result.outcome()) {
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

/// Captured exchange metadata. Trace owns step bytes; projections copy them.
pub const Call = struct {
    origin: @import("../../../src/domain/model_candidate_origin.zig").Origin,
    step: []const u8,
    usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage = null,
    output_available: bool = false,
    raw_response_available: bool = false,
    status: ?u16 = null,
    exception: ?[]const u8 = null,
    request_id: ?[]const u8 = null,
    transport: ?@import("../../../src/domain/llm_provider_operation.zig").TransportDiagnostic = null,
    // capture() emits static native tag/error names, never provider prose.
    provider_diagnostic: ?[]const u8 = null,
    provider_content_diagnostic: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderContentDiagnostic = null,
};

/// Join only exact native associations. A prepared request or a retained older
/// candidate never supplies the latest exchange's identity or token usage.
pub fn correlate(a: std.mem.Allocator, calls: []Call, report: *c.Report) !void {
    if (report.provider_diagnostic) |diagnostic| if (report.last_model_origin) |origin| {
        const call = &calls[try findCall(calls, origin)];
        call.provider_diagnostic = diagnostic;
        call.provider_content_diagnostic = report.provider_content_diagnostic;
    };
    if (report.last_model_usage) |usage| {
        const origin = report.last_model_origin orelse return error.MissingRequestEvidence;
        calls[try findCall(calls, origin)].usage = usage;
    }
    if (calls.len != 0) {
        const last = calls[calls.len - 1];
        _ = try findCall(calls, last.origin);
        report.last_model_call = calls.len;
        report.last_model_step = try a.dupe(u8, last.step);
        report.last_model_origin = last.origin;
        report.last_model_usage = last.usage;
        if (report.provider_diagnostic == null) {
            report.provider_diagnostic = last.provider_diagnostic;
            report.provider_content_diagnostic = last.provider_content_diagnostic;
        }
        report.last_model_output = if (last.output_available) try @import("../evidence.zig").Store.path(a, .generation, calls.len, .model_output) else null;
        report.exchange_evidence = .{
            .raw_response = if (last.raw_response_available) try @import("../evidence.zig").Store.path(a, .generation, calls.len, .response) else null,
            .text = if (report.evidence_error != null) .capture_failed else if (last.output_available) .available else if (!last.raw_response_available) .response_absent else if (report.terminal_rejection != null and report.terminal_rejection.?.kind == .token_budget) .budget_stop else .not_projected,
            .status = last.status,
            .exception = if (last.exception) |bytes| try a.dupe(u8, bytes) else null,
            .request_id = if (last.request_id) |bytes| try a.dupe(u8, bytes) else null,
            .transport = last.transport,
        };
    } else {
        report.last_model_step = null;
        report.last_model_call = null;
        report.last_model_origin = null;
        report.last_model_usage = null;
        report.last_model_output = null;
        report.exchange_evidence = null;
    }
    report.candidate_model_call = null;
    report.candidate_model_step = null;
    report.candidate_model_output = null;
    const diagnostic = report.candidate_error orelse return;
    const origin = diagnostic.origin() orelse return error.MissingRequestEvidence;
    const index = try findCall(calls, origin);
    const source = calls[index];
    if (!source.output_available) return error.MissingRequestEvidence;
    report.candidate_model_call = index + 1;
    report.candidate_model_step = try a.dupe(u8, source.step);
    report.candidate_model_output = try @import("../evidence.zig").Store.path(a, .generation, index + 1, .model_output);
}

fn findCall(calls: []const Call, origin: @import("../../../src/domain/model_candidate_origin.zig").Origin) !usize {
    var found: ?usize = null;
    for (calls, 0..) |candidate, index| if (std.meta.eql(candidate.origin, origin)) {
        if (found != null) return error.MissingRequestEvidence;
        found = index;
    };
    return found orelse error.MissingRequestEvidence;
}

fn latest(ledger: *const @import("../../../src/domain/workflow_token_accounting.zig").Ledger, id: @import("../../../src/domain/llm_provider_operation.zig").ProviderOperationId) bool {
    return ledger.accounted_operations.items.len != 0 and ledger.accounted_operations.items[ledger.accounted_operations.items.len - 1].id.eql(id);
}
