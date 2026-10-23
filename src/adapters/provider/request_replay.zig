//! The one diagnostic replay projection for every provider family, using the
//! production encoders, decoders, credential source and shared transport. It
//! dispatches only the family's codec and endpoint target.
const std = @import("std");
const debug = @import("../../domain/request_debugger.zig");
const port = @import("../../ports/request_replay.zig");
const text = @import("model_text_request.zig");
const transport = @import("model_http_transport.zig");
const key = @import("provider_api_key.zig");
const source = @import("../system/provider_api_key_source.zig");
const strict = @import("../../domain/strict_json.zig");
const envelope = @import("../../domain/model_envelope.zig");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const support = @import("provider_response_support.zig");
pub const Authorization = struct {
    context: *port.Context,
    /// The compiled facts of the current binding the description names.
    authorize_fn: *const fn (*port.Context, debug.Description) port.Error!contracts.ProviderFacts,
};
pub const Adapter = struct {
    authorization: Authorization,
    environment: *const std.process.Environ.Map,
    transport: transport.Port,
    clock: @import("../../ports/provider_authorization_lease.zig").Clock,
    compiler: @import("../../ports/model_result_schema_compiler.zig").Compiler,

    pub fn provider(self: *Adapter) port.Provider {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare, .send_fn = send, .inspect_fn = inspect };
    }
    fn prepare(context: *port.Context, a: std.mem.Allocator, description: debug.Description) port.Error![]const u8 {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const facts = try self.authorization.authorize_fn(self.authorization.context, description);
        const family = key.Family.of(description.provider_config) orelse return error.InvalidReplay;
        if (std.meta.activeTag(facts) != family.configSchema() or !std.mem.eql(u8, description.protocol_prompt, @import("../../domain/model_controls.zig").response_format_guidance)) return error.InvalidReplay;
        const schema = self.compiler.compileSelected(a, description.schema) catch return error.InvalidReplay;
        const members = @import("../../domain/model_result_schema.zig").restrictMembers(a, schema, description.members) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReplay;
        members.release();
        const fields = @import("../../domain/model_text_field.zig").inspectSchema(schema.root(), description.field_policies, description.prose_fields);
        if (!fields.valid or (fields.requires_exact_scope and description.exact_scope == null)) return error.InvalidReplay;
        if (description.exact_scope) |scope| if (!@import("../../domain/model_exact_values.zig").valid(scope)) return error.InvalidReplay;
        const text_schema: text.TextSchema = switch (description.response_mode) {
            .prompt_only => .{ .prompt_only = schema.modelBytes() },
            .native_schema => .{ .native = .{ .guidance = schema.modelBytes(), .structure = @import("../../domain/model_schema_projection.zig").render(a, schema, .native) catch return error.InvalidReplay } },
        };
        const effort = text.reasoningEffort(description.reasoning_effort) catch return error.InvalidReplay;
        // The captured family must be the one the authorized binding compiles.
        if (description.provider_config == .aws_bedrock and facts.bedrockFamily() != description.provider_config.aws_bedrock.family) return error.InvalidReplay;
        const body = switch (description.provider_config) {
            .aws_bedrock => |config| @import("bedrock_request.zig").encodeText(a, .{
                .content = description.content,
                .schema = text_schema,
                .schema_name = "sdde_model_envelope_v1",
                .temperature = description.controls.temperature,
                .reasoning_effort = effort,
                .family = config.family,
                .max_output_tokens = config.max_output_tokens,
            }),
            .anthropic => |config| @import("anthropic_request.zig").encodeText(a, .{
                .model = description.model,
                .content = description.content,
                .schema = text_schema,
                .temperature = description.controls.temperature,
                .reasoning_effort = effort,
                .max_output_tokens = config.max_output_tokens,
            }),
            .deadline_only => return error.InvalidReplay,
        } catch return error.InvalidReplay;
        // A modified request must not persist an authorization secret as content.
        var material = source.read(a, self.environment, family);
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
        const family = key.Family.of(value.description.provider_config) orelse return error.InvalidReplay;
        var material = source.read(a, self.environment, family);
        defer material.deinit();
        const credential = switch (material) {
            .ready => |snapshot| snapshot.bytes,
            .unavailable => return error.ReplayUnauthorized,
            .allocation_failed => return error.OutOfMemory,
        };
        // The captured catalogue entry owns the deadline (ADR 0030); replay
        // has no deadline of its own.
        const now = self.clock.now() catch return error.ReplayProviderFailure;
        const deadline = std.math.add(u64, now, value.description.provider_config.requestTimeout().milliseconds) catch return error.ReplayProviderFailure;
        var partial: ?transport.ResponseBody = null;
        const received = self.transport.exchange(a, .{
            .target = switch (value.description.provider_config) {
                .aws_bedrock => |config| .{ .aws_bedrock = .{
                    .region = config.region,
                    .model = @import("../../domain/llm_provider_identity.zig").ModelId.parse(value.description.model) orelse return error.InvalidReplay,
                } },
                .anthropic => .anthropic,
                .deadline_only => return error.InvalidReplay,
            },
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
    fn response(a: std.mem.Allocator, id: []const u8, outcome: @FieldType(debug.ResponseRecord, "outcome"), status: ?u16, body: ?transport.ResponseBody, diagnostic: ?[]const u8, credential: []const u8) port.Error!debug.ResponseRecord {
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
        var syntax: ?strict.Diagnostic = null;
        defer if (syntax) |value| value.deinit(a);
        var raw = strict.parse(a, body, .{ .maximum_depth = std.math.maxInt(usize) }, false, &syntax) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.extraction = .invalid;
            result.reason = "Invalid provider response JSON";
            if (syntax) |value| if (value.context) |context_value| {
                result.path = try a.dupe(u8, context_value.path);
            };
            return result;
        };
        defer raw.deinit();
        var provider_diagnostic: ?support.DecodeDiagnostic = null;
        defer if (provider_diagnostic) |value| value.deinit(a);
        const decoded_result = switch (description.provider_config) {
            .aws_bedrock => @import("bedrock_response.zig").decodeConverse(a, raw.value, &provider_diagnostic),
            .anthropic => @import("anthropic_response.zig").decodeMessages(a, raw.value, description.model, &provider_diagnostic),
            .deadline_only => return error.InvalidReplay,
        };
        var decoded = decoded_result catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.extraction = .invalid;
            if (provider_diagnostic) |value| {
                result.reason = value.explanation();
                result.path = try a.dupe(u8, value.path);
            }
            return result;
        };
        defer decoded.deinit(a);
        result.input_tokens = decoded.usage.input_tokens;
        result.output_tokens = decoded.usage.output_tokens;
        result.latency_ms = decoded.latency_ms;
        result.reasoning = try @import("../../domain/provider_reasoning.zig").clone(a, decoded.reasoning);
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
        const compiled = self.compiler.compileSelected(a, description.schema) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.reason = "Captured schema is invalid";
            return result;
        };
        // Admission validates the restricted schema, including native membership.
        const members = @import("../../domain/model_result_schema.zig").restrictMembers(a, compiled, description.members) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            result.reason = "Captured schema and native membership disagree";
            return result;
        };
        defer members.release();
        const schema = members.selected();
        const fields = @import("../../domain/model_text_field.zig").inspectSchema(schema.root(), description.field_policies, description.prose_fields);
        if (!fields.valid or (fields.requires_exact_scope and description.exact_scope == null) or (description.exact_scope != null and !@import("../../domain/model_exact_values.zig").valid(description.exact_scope.?))) {
            result.reason = "Captured schema and native field policies disagree";
            return result;
        }
        if (try @import("../../domain/model_text_composition.zig").check(a, document.parsed.value, description.field_policies, description.prose_fields, description.original_sources, .{ .exact_scope = description.exact_scope })) |diagnostic| {
            defer diagnostic.deinit(a);
            result.json = .invalid;
            result.reason = "ModelTextComposition";
            result.path = try a.dupe(u8, diagnostic.fields[0].path);
            return result;
        }
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
