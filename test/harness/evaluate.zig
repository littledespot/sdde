//! One sequential evaluation. Attempt observations are the sole usage record.
const std = @import("std");
const c = @import("contracts.zig");
const wire = @import("openai.zig");
const provider = @import("provider.zig");
const report = @import("report.zig");
const judgment = @import("judgment.zig");
const configuration = @import("configuration.zig");
pub const Error = c.Error || error{Cancelled};

/// Caller retains the arena owning inputs, requests, observations and report.
pub fn run(io: std.Io, a: std.mem.Allocator, port: provider.Port, config: configuration.Config, capture: c.Capture) Error!report.Report {
    const request = try wire.request(a, config, capture);
    var attempts: std.ArrayList(report.Attempt) = .empty;
    defer attempts.deinit(a);
    var ordinal: u32 = 1;
    var outcome: report.Outcome = .{ .evaluator_error = .retries_exhausted };
    while (true) : (ordinal += 1) {
        io.checkCancel() catch {
            outcome = .{ .evaluator_error = .cancelled };
            break;
        };
        try attempts.ensureUnusedCapacity(a, 1);
        var observation = port.invoke(a, request, config.timeout_ms) catch |err| blk: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :blk wire.Observation{ .failure = .cancelled };
        };
        // A narrow adapter is still an untrusted observation producer.
        if (observation.usage) |usage| {
            if (report.Usage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) {
                observation.usage = null;
                observation.failure = .invalid_response;
                observation.payload = null;
            }
        }
        inline for (.{ "request_id", "response_id" }) |field| {
            if (@field(observation, field)) |value| if (!c.id(value)) {
                @field(observation, field) = null;
                observation.failure = .invalid_response;
                observation.payload = null;
            };
        }
        if (observation.actual_model) |model| if (c.ModelId.parse(model) == null) {
            observation.actual_model = null;
            observation.failure = .invalid_response;
            observation.payload = null;
        };
        if (observation.failure == null and (observation.response_id == null or observation.actual_model == null)) {
            observation.failure = .invalid_response;
            observation.payload = null;
        }
        attempts.appendAssumeCapacity(.{
            .ordinal = ordinal,
            .request_id = observation.request_id,
            .response_id = observation.response_id,
            .actual_model = observation.actual_model,
            .usage = observation.usage,
            .failure = observation.failure,
        });
        var total: u128 = 0;
        for (attempts.items) |attempt| if (attempt.usage) |usage| {
            total += usage.total_tokens;
        };
        if (total > config.total_token_budget) {
            outcome = .{ .evaluator_error = .budget_exceeded };
            break;
        }
        if (observation.failure) |failure| {
            outcome = .{ .evaluator_error = failure };
            // Unknown consumption blocks further calls. Retry only transient
            // failures with actual usage, never refusals or undesirable scores.
            if (failure != .provider_failed and failure != .rate_limited) break;
            if (observation.usage == null) break;
            if (total >= config.total_token_budget) {
                outcome = .{ .evaluator_error = .budget_exceeded };
                break;
            }
            if (ordinal > config.retry_limit) {
                outcome = .{ .evaluator_error = .retries_exhausted };
                break;
            }
            io.sleep(.fromMilliseconds(config.retry_delay_ms), .awake) catch {
                outcome = .{ .evaluator_error = .cancelled };
                break;
            };
            continue;
        }
        if (observation.usage == null) {
            outcome = .{ .evaluator_error = .usage_unavailable };
            break;
        }
        const payload = observation.payload orelse {
            outcome = .{ .evaluator_error = .invalid_response };
            break;
        };
        const result = judgment.validate(a, capture, payload) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            outcome = .{ .evaluator_error = .invalid_judgment };
            break;
        };
        outcome = .{ .evaluated = result };
        break;
    }
    return .{ .capture = capture, .configuration = config, .attempts = try a.dupe(report.Attempt, attempts.items), .outcome = outcome };
}
