//! Read-only compatibility assessment through canonical capture and schema owners.
const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");
const invoke = @import("../e2e/invoke.zig");
const workflow_report = @import("../e2e/contracts.zig");

pub const Status = enum { compatible, incompatible, inconclusive };
pub const Inspection = struct {
    status: Status = .inconclusive,
    reason: ?[]const u8 = null,
    request_identity: ?struct { run: []const u8, call: []const u8, origin: @import("../../../src/domain/model_candidate_origin.zig").Origin } = null,
    description: ?debug.Description = null,
    request_file: ?[]const u8 = null,
    response_file: ?[]const u8 = null,
    response_complete: bool = false,
    outcome_file: ?[]const u8 = null,
    transport_outcome: ?@import("../e2e/trace.zig").TransportOutcome = null,
    request_sha256: ?[]const u8 = null,
    response_sha256: ?[]const u8 = null,
    provider_request_id: ?[]const u8 = null,
    http_status: ?u16 = null,
    candidate_diagnostic: ?[]const u8 = null,
    /// Inert provider-reported wire text, distinct from candidate/schema diagnostics.
    reported_stop: ?[]const u8 = null,
    usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage = null,
    validation: debug.Validation = .{},
};

/// Compare external readback with the byte identity retained from the observed
/// transport. These digests confer no workflow or predecessor authority.
pub fn verifyWire(expected: ?[32]u8, bytes: []const u8) ![64]u8 {
    const observed = expected orelse return error.CaptureIncomplete;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    if (!std.mem.eql(u8, &observed, &digest)) return error.CaptureMismatch;
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn classify(probe: invoke.Probe, report: workflow_report.Report, value: *Inspection) void {
    if (probe.physical_sends != 1 or probe.boundary != .exchange_finished) {
        value.status = .inconclusive;
        value.reason = "NoCompleteSingleExchange";
    } else if (report.evidence_error != null or value.request_identity == null or value.description == null or value.response_file == null) {
        value.status = .inconclusive;
        value.reason = "IncompleteExchangeEvidence";
    } else if (value.http_status == null) {
        value.status = .inconclusive;
        value.reason = "ProviderDeliveryIncomplete";
    } else if (value.http_status != 200) {
        // HTTP rejection alone cannot establish model/codec incompatibility:
        // credentials or service availability may be responsible.
        value.status = .inconclusive;
        value.reason = "ProviderHttpRejection";
    } else if (!value.response_complete) {
        value.status = .inconclusive;
        value.reason = "ProviderBodyIncomplete";
    } else if (value.usage == null or !report.usage_complete) {
        value.status = .inconclusive;
        value.reason = if (value.validation.extraction == .invalid)
            value.validation.reason orelse "ProviderUsageUnavailable"
        else
            "ProviderUsageUnavailable";
    } else if (report.workflow_outcome != .cancelled or report.publication_check != .not_run or report.specification != null or report.evaluation_inputs != null) {
        value.status = .inconclusive;
        value.reason = "UnexpectedWorkflowOutcome";
    } else if (value.validation.extraction != .valid or value.validation.json != .valid or value.validation.schema != .valid) {
        value.status = .incompatible;
        value.reason = value.validation.reason orelse "ProviderOrSchemaInvalid";
    } else {
        value.status = .compatible;
        value.reason = null;
    }
}

/// Returned fields live in the caller's arena; the independently loaded capture
/// is released here. Inspection never calls send(), continues or publishes.
pub fn inspect(io: std.Io, a: std.mem.Allocator, environment: *const std.process.Environ.Map, repository: std.Io.Dir, run_path: []const u8, workflow: []const u8, probe: invoke.Probe, report: workflow_report.Report) !Inspection {
    var result: Inspection = .{};
    if (probe.physical_sends != 1) {
        classify(probe, report, &result);
        return result;
    }
    var captured = try @import("../call/capture.zig").load(io, a, repository, run_path, workflow, 1);
    defer captured.deinit();
    const description = captured.call.description.?;
    const request_digest = try verifyWire(probe.request_sha256, captured.call.request.?);
    result.request_sha256 = try a.dupe(u8, &request_digest);
    try @import("../model_cost_policy.zig").require(.{ .bytes = description.provider }, .{ .bytes = description.model });
    const binding = @import("../diagnostic_binding.zig");
    // Validate unchanged controls against the retained catalogue and compiled registry.
    _ = try binding.rebind(a, description, captured.provider_catalogue, description.model, description.reasoning_effort);
    var authority: binding.Authorization = .{ .binding = description };
    var clock: @import("../../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var transport: @import("../../../src/adapters/provider/bedrock_http.zig").Adapter = .{ .io = io, .clock = clock.clock(), .runtime = .{} };
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var provider: @import("../../../src/adapters/provider/request_replay.zig").Adapter = .{
        .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = binding.Authorization.authorize },
        .environment = environment,
        .transport = transport.port(),
        .clock = clock.clock(),
        .compiler = parser.compiler(),
    };
    const prepared = try provider.provider().prepare(a, description);
    if (!std.mem.eql(u8, prepared, captured.call.request.?)) return error.CaptureMismatch;
    result.request_identity = .{ .run = try a.dupe(u8, captured.call.run), .call = try a.dupe(u8, captured.call.id), .origin = captured.context.origin };
    result.description = try debug.Description.decode(a, try std.json.Stringify.valueAlloc(a, description, .{}));
    result.request_file = try @import("../evidence.zig").Store.path(a, .generation, 1, .request);
    const run = try @import("../../../src/adapters/filesystem/directory_access.zig").open(io, repository, run_path);
    defer run.close(io);
    const outcome_path = try @import("../evidence.zig").Store.path(a, .generation, 1, .outcome);
    const outcome = try @import("../contracts.zig").decode(@import("../e2e/trace.zig").TransportOutcome, a, try @import("../files.zig").read(io, a, run, outcome_path));
    result.outcome_file = outcome_path;
    result.transport_outcome = outcome;
    switch (outcome) {
        .received => |received| {
            result.http_status = received.status;
            result.provider_request_id = received.request_id;
        },
        .failed, .transport_error => {},
    }
    const exchange = report.exchange_evidence orelse return error.CaptureMismatch;
    if (exchange.status != result.http_status or !debug.sameOptional(exchange.request_id, result.provider_request_id)) return error.CaptureMismatch;
    // Production prompt archives carry body identity, while the trace's closed
    // transport record owns HTTP facts. Replay-only status must also agree if present.
    if (captured.call.response_status) |status| if (status != result.http_status) return error.CaptureMismatch;
    if (captured.call.response) |response| {
        const provenance = std.meta.stringToEnum(enum { provider_body, partial_provider_body, transport_outcome, incomplete_capture }, captured.call.response_provenance orelse return error.CaptureIncomplete) orelse return error.CaptureMismatch;
        switch (provenance) {
            .transport_outcome => {
                // The debugger exposes this as a diagnostic response view, not
                // as provider bytes. The closed trace outcome is retained above.
                classify(probe, report, &result);
                return result;
            },
            .incomplete_capture => return error.CaptureIncomplete,
            .provider_body, .partial_provider_body => {},
        }
        if (captured.call.redacted or !std.mem.eql(u8, captured.call.response_encoding, "utf8")) return error.CaptureRedacted;
        const path = try @import("../evidence.zig").Store.path(a, .generation, 1, .response);
        const raw = try @import("../files.zig").read(io, a, run, path);
        if (!std.mem.eql(u8, raw, response)) return error.CaptureMismatch;
        const response_digest = try verifyWire(probe.response_sha256, raw);
        result.response_sha256 = try a.dupe(u8, &response_digest);
        result.response_file = path;
        result.response_complete = provenance == .provider_body;
        // Error/partial prefixes are retained exactly but cannot be interpreted
        // as a completed HTTP-200 model response or acquire candidate eligibility.
        if (result.http_status != 200 or !result.response_complete) {
            classify(probe, report, &result);
            return result;
        }
        result.validation = try provider.provider().inspect(a, description, raw);
        result.candidate_diagnostic = result.validation.reason;
        if (result.validation.input_tokens) |input| if (result.validation.output_tokens) |output| {
            // Canonical inspection already decoded the closed provider response.
            // Read its reported stop for diagnostics; this adds no admission rule.
            var wire = try @import("../../../src/domain/strict_json.zig").parse(a, raw, .{ .maximum_depth = std.math.maxInt(usize) }, false, null);
            defer wire.deinit();
            if (wire.value.object.get("stopReason")) |stop| if (stop == .string) {
                result.reported_stop = try a.dupe(u8, stop.string);
            };
            const total = std.math.add(u64, input, output) catch return error.CaptureMismatch;
            const usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(input, output, total) orelse return error.CaptureMismatch;
            const accounted = report.last_model_usage orelse return error.CaptureMismatch;
            if (!std.meta.eql(usage, accounted) or report.last_model_origin == null or !std.meta.eql(report.last_model_origin.?, captured.context.origin)) return error.CaptureMismatch;
            result.usage = usage;
        };
    }
    classify(probe, report, &result);
    return result;
}
