//! Diagnostic Bedrock projection using the production encoder, decoder and transport.
const std = @import("std");
const debug = @import("../../domain/request_debugger.zig");
const port = @import("../../ports/request_replay.zig");
const request = @import("bedrock_request.zig");
const strict = @import("../../domain/strict_json.zig");
const envelope = @import("../../domain/model_envelope.zig");
const contracts = @import("../../domain/llm_provider_contracts.zig");
pub const Authorization = struct {
    context: *port.Context,
    authorize_fn: *const fn (*port.Context, debug.Description) port.Error!void,
};
pub const Adapter = struct {
    authorization: Authorization,
    environment: *const std.process.Environ.Map,
    transport: @import("bedrock_transport.zig").Port,
    clock: @import("../../ports/provider_authorization_lease.zig").Clock,
    compiler: @import("../../ports/model_result_schema_compiler.zig").Compiler,

    pub fn provider(self: *Adapter) port.Provider {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare, .send_fn = send, .inspect_fn = inspect };
    }
    fn prepare(context: *port.Context, a: std.mem.Allocator, description: debug.Description) port.Error![]const u8 {
        const self: *Adapter = @ptrCast(@alignCast(context));
        try self.authorization.authorize_fn(self.authorization.context, description);
        if (description.provider_config != .aws_bedrock or description.operation_kind != .inference or !std.mem.eql(u8, description.protocol_prompt, @import("../../domain/model_controls.zig").response_format_guidance)) return error.InvalidReplay;
        const schema = self.compiler.compileSelected(a, description.schema) catch return error.InvalidReplay;
        const body = request.encodeText(a, .{
            .content = description.content,
            .schema = switch (description.response_mode) {
                .prompt_only => .{ .prompt_only = schema.modelBytes() },
                .native_schema => .{ .native = .{ .guidance = schema.modelBytes(), .structure = @import("../../domain/model_schema_projection.zig").render(a, schema, .bedrock) catch return error.InvalidReplay } },
            },
            .schema_name = "sdde_model_envelope_v1",
            .temperature = description.controls.temperature,
            .reasoning_effort = request.reasoningEffort(description.reasoning_effort) catch return error.InvalidReplay,
        }, .inference) catch return error.InvalidReplay;
        // A modified request must not persist an authorization secret as content.
        var material = @import("../system/bedrock_api_key_source.zig").read(a, self.environment);
        defer material.deinit();
        if (material == .allocation_failed) return error.OutOfMemory;
        if (material == .ready) {
            const description_bytes = try std.json.Stringify.valueAlloc(a, description, .{});
            for ([_][]const u8{ body, description_bytes }) |bytes| {
                var sanitized = try @import("../../domain/model_log_redaction.zig").sanitize(a, bytes, &.{material.ready.bytes});
                defer sanitized.deinit(a);
                if (sanitized.redacted) return error.InvalidReplay;
            }
        }
        return body;
    }
    fn send(context: *port.Context, a: std.mem.Allocator, value: debug.RequestRecord) port.Error!debug.ResponseRecord {
        const self: *Adapter = @ptrCast(@alignCast(context));
        // Reauthorize at dispatch; records are not capabilities.
        const rebuilt = try prepare(context, a, value.description);
        if (!std.mem.eql(u8, rebuilt, value.body)) return error.InvalidReplay;
        var material = @import("../system/bedrock_api_key_source.zig").read(a, self.environment);
        defer material.deinit();
        const credential = switch (material) {
            .ready => |key| key.bytes,
            .unavailable => return error.ReplayUnauthorized,
            .allocation_failed => return error.OutOfMemory,
        };
        const now = self.clock.now() catch return error.ReplayProviderFailure;
        const deadline = std.math.add(u64, now, 300_000) catch return error.ReplayProviderFailure;
        var partial: ?@import("bedrock_transport.zig").ResponseBody = null;
        const received = self.transport.exchange(a, .{
            .region = value.description.provider_config.aws_bedrock.region,
            .model = @import("../../domain/llm_provider_identity.zig").ModelId.parse(value.description.model) orelse return error.InvalidReplay,
            .kind = .inference,
            .body = value.body,
            .api_key = credential,
            .deadline_monotonic_ms = deadline,
            .response_body_on_error = &partial,
        }) catch |err| return response(a, value.id, if (err == error.Cancelled) .cancelled else .transport_failed, null, partial, @errorName(err), credential);
        return switch (received) {
            .received => |result| response(a, value.id, .received, result.status, .{ .bytes = result.body, .complete = true }, null, credential),
            .failed => |failure| response(a, value.id, if (failure.body != null and !failure.body.?.complete) .partial else .transport_failed, null, failure.body, @tagName(failure.cause), credential),
        };
    }
    fn response(a: std.mem.Allocator, id: []const u8, outcome: @FieldType(debug.ResponseRecord, "outcome"), status: ?u16, body: ?@import("bedrock_transport.zig").ResponseBody, diagnostic: ?[]const u8, credential: []const u8) port.Error!debug.ResponseRecord {
        var value: debug.ResponseRecord = .{ .id = id, .outcome = outcome, .status = status, .diagnostic = diagnostic };
        if (body) |bytes| {
            const sanitized = try @import("../../domain/model_log_redaction.zig").sanitize(a, bytes.bytes, &.{credential});
            value.body = sanitized.bytes;
            value.encoding = if (sanitized.encoding == .utf8) .utf8 else .base64;
            value.redacted = sanitized.redacted;
        }
        return value;
    }
    fn inspect(context: *port.Context, a: std.mem.Allocator, description: debug.Description, body: []const u8) port.Error!debug.Validation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        var result: debug.Validation = .{};
        // Token-count observations contain no generated candidate to validate.
        if (description.operation_kind != .inference) return result;
        var raw = strict.parse(a, body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch {
            result.extraction = .invalid;
            return result;
        };
        defer raw.deinit();
        const decoded = @import("bedrock_response.zig").decodeConverse(raw.value) catch {
            result.extraction = .invalid;
            return result;
        };
        result.input_tokens = decoded.usage.input_tokens;
        result.output_tokens = decoded.usage.output_tokens;
        result.latency_ms = decoded.latency_ms;
        if (decoded.output != .text) {
            result.extraction = .invalid;
            result.reason = switch (decoded.output) {
                .invalid => |reason| @tagName(reason),
                .stopped => |reason| @tagName(reason),
                .text => unreachable,
            };
            return result;
        }
        result.extraction = .valid;
        result.model_text = try a.dupe(u8, decoded.output.text);
        var document = envelope.parseContent(a, decoded.output.text, null) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.json = .invalid;
            result.reason = "Invalid JSON";
            return result;
        };
        defer document.deinit();
        result.normalization = document.normalization;
        result.parsed = strict.decode(std.json.Value, a, document.content, .{ .maximum_depth = @import("../../domain/model_result_schema.zig").max_json_depth }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReplay;
        result.json = .valid;
        const schema = self.compiler.compileSelected(a, description.schema) catch {
            result.reason = "Captured schema is invalid";
            return result;
        };
        if (@import("../../domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), schema.root())) |diagnostic| {
            result.schema = .invalid;
            const detail = try diagnostic.describe(a);
            result.path = detail.path;
            result.reason = @tagName(detail.reason);
            result.expected = @tagName(diagnostic.expected.*);
            var actual = envelope.value(&document.parsed.value);
            var valid = true;
            for (diagnostic.segments[0..diagnostic.length]) |segment| {
                actual = switch (segment) {
                    .property => |name| if (actual == .object) actual.object.get(name) orelse {
                        valid = false;
                        break;
                    } else {
                        valid = false;
                        break;
                    },
                    .index => |index| if (actual == .array) actual.array.at(index) orelse {
                        valid = false;
                        break;
                    } else {
                        valid = false;
                        break;
                    },
                };
            }
            result.received = if (valid) @tagName(actual) else "missing";
        } else result.schema = .valid;
        return result;
    }
};
