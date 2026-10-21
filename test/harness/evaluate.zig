//! One sequential evaluation. Attempt observations are the sole usage record.
const std = @import("std");
const c = @import("contracts.zig");
const request_encoding = @import("request.zig");
const provider = @import("provider.zig");
const report = @import("report.zig");
const judgment = @import("judgment.zig");
const configuration = @import("configuration.zig");
const correction = @import("correction.zig");
pub const Error = c.Error || error{Cancelled};

/// Caller retains the arena owning inputs, requests, observations and report.
pub fn run(io: std.Io, a: std.mem.Allocator, port: provider.Port, config: configuration.Config, capture: c.Capture) Error!report.Report {
    var request = try request_encoding.encode(a, config, capture, null);
    var purpose: @FieldType(report.Attempt, "purpose") = .judgment;
    var sent: ?correction.Correction = null;
    var unconstrained: ?correction.Unconstrained = null;
    var attempts: std.ArrayList(report.Attempt) = .empty;
    defer attempts.deinit(a);
    var ordinal: u32 = 1;
    var retries: u32 = 0;
    var corrections: usize = 0;
    var outcome: report.Outcome = .{ .evaluator_error = .retries_exhausted };
    while (true) : (ordinal += 1) {
        io.checkCancel() catch {
            outcome = .{ .evaluator_error = .cancelled };
            break;
        };
        try attempts.ensureUnusedCapacity(a, 1);
        var observation = port.invoke(a, request, config.timeout_ms) catch |err| blk: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :blk provider.Observation{ .failure = .cancelled };
        };
        // A narrow adapter is still an untrusted observation producer.
        if (observation.usage) |usage| {
            if (report.Usage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) {
                observation.usage = null;
                observation.failure = .invalid_response;
                observation.payload = null;
            }
        }
        if (observation.request_id) |id| if (!c.id(id)) {
            observation.request_id = null;
            observation.failure = .invalid_response;
            observation.payload = null;
        };
        if (!observation.identity.validFor(config) and (observation.failure == null or observation.identity != .unavailable)) {
            observation.identity = .unavailable;
            observation.failure = .invalid_response;
            observation.payload = null;
        }
        attempts.appendAssumeCapacity(.{
            .ordinal = ordinal,
            .purpose = purpose,
            .unconstrained = unconstrained,
            .request_id = observation.request_id,
            .identity = observation.identity,
            .usage = observation.usage,
            .failure = if (observation.failure) |failure| provider.reported(failure) else null,
        });
        const last = &attempts.items[attempts.items.len - 1];
        var total: u128 = 0;
        for (attempts.items) |attempt| if (attempt.usage) |usage| {
            total += usage.total_tokens;
        };
        if (total > config.total_token_budget) {
            outcome = .{ .evaluator_error = .budget_exceeded };
            break;
        }
        if (observation.failure) |failure| {
            outcome = .{ .evaluator_error = provider.reported(failure) };
            // Unknown consumption blocks further calls. Retry only transient
            // failures with actual usage, never refusals or undesirable scores.
            if (failure != .provider_failed and failure != .rate_limited) break;
            if (observation.usage == null) break;
            if (total >= config.total_token_budget) {
                outcome = .{ .evaluator_error = .budget_exceeded };
                break;
            }
            if (retries >= config.retry_limit) {
                outcome = .{ .evaluator_error = .retries_exhausted };
                break;
            }
            retries += 1;
            io.sleep(.fromMilliseconds(config.retry_delay_ms), .awake) catch {
                outcome = .{ .evaluator_error = .cancelled };
                break;
            };
            continue;
        }
        if (observation.usage == null) {
            last.failure = .usage_unavailable;
            outcome = .{ .evaluator_error = .usage_unavailable };
            break;
        }
        const payload = observation.payload orelse {
            last.failure = .invalid_response;
            outcome = .{ .evaluator_error = .invalid_response };
            break;
        };
        const content = try modelContent(a, payload);
        var diagnostic: ?judgment.Diagnostic = null;
        var result: ?judgment.Result = judgment.validate(a, &diagnostic, capture, content) catch |err| blk: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :blk null;
        };
        if (result != null) if (sent) |prior| if (try correction.preserved(a, prior, content)) |changed| {
            diagnostic = changed;
            result = null;
        };
        if (result) |valid| {
            outcome = .{ .evaluated = valid };
            break;
        }
        // Only an invalid judgment is corrected; a valid low score never is.
        var rejected = diagnostic orelse return error.InvalidEvaluationContract;
        if (correction.correctable(rejected.reason)) if (try correction.blocked(a, content)) |repeated| {
            rejected = repeated;
        };
        last.failure = .invalid_judgment;
        last.diagnostic = rejected;
        outcome = .{ .evaluator_error = .invalid_judgment };
        if (corrections == correction.attempts or !correction.correctable(rejected.reason)) break;
        if (total >= config.total_token_budget) {
            outcome = .{ .evaluator_error = .budget_exceeded };
            break;
        }
        sent = .{ .rejected = content, .diagnostic = rejected };
        unconstrained = try correction.unconstrained(a, content);
        request = try request_encoding.encode(a, config, capture, sent);
        purpose = .correction;
        corrections += 1;
    }
    return .{ .capture = capture, .configuration = config, .attempts = try a.dupe(report.Attempt, attempts.items), .outcome = outcome, .protocol_sha256 = try @import("packet.zig").protocolSha256(a) };
}

/// A judge response is model output: it crosses the engine's one model-envelope
/// decoder, including its approved §22.6 opening-artifact exception. Human
/// adjudication proposals do not. A rejected envelope keeps the original bytes so
/// judgment validation reports the original parser diagnostic.
fn modelContent(a: std.mem.Allocator, payload: []const u8) error{OutOfMemory}![]const u8 {
    var document = @import("../../src/domain/model_envelope.zig").parseContent(a, payload, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else payload;
    defer document.deinit();
    return document.content;
}
