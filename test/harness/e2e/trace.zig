//! Observes production execution and HTTPS exchanges; supplies no model answers.
const std = @import("std");
const bindings = @import("../../../src/application/workflow_engine_child_bindings.zig");
const execution = @import("../../../src/domain/workflow_execution.zig");
const workflow = @import("../../../src/domain/workflow.zig");
const compilation = @import("../../../src/domain/workflow_compilation.zig");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const transport = @import("../../../src/adapters/provider/bedrock_transport.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const requests = @import("../../../src/application/model_request_workflow.zig");
const evidence = @import("../evidence.zig");
const c = @import("contracts.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;

pub const TransportOutcome = union(enum) {
    transport_error: enum { cancelled, allocation_failed },
    received: struct { status: u16, exception: ?[]const u8, request_id: ?[]const u8 },
    failed: transport.Failure,
};

pub const Trace = struct {
    pub const Purpose = enum { whole_workflow, single_exchange };
    pub const Boundary = enum {
        open,
        exchange_in_flight,
        exchange_finished,
        unsupported_operation,
        binding_rejected,
        publication_prohibited,
        send_limit,
        capture_failed,
    };

    store: evidence.Store,
    invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly,
    events: std.Io.File,
    purpose: Purpose,
    boundary: Boundary = .open,
    /// Count conservatively before dispatch, including failed/uncertain delivery.
    physical_sends: usize = 0,
    /// Transport-observed byte identities for diagnostic readback only. These
    /// never create workflow, predecessor or model-candidate authority.
    request_sha256: ?[32]u8 = null,
    response_sha256: ?[32]u8 = null,
    /// Offline tests may replace only the infrastructure-private transport seam.
    /// A live executable rejects this field rather than ignoring the override.
    transport_override: ?transport.Port = null,
    inner_transport: ?transport.Port = null,
    failure: ?anyerror = null,
    calls: usize = 0,
    call_records: std.ArrayList(Call) = .empty,
    last_rejection: @import("observation.zig").LastModelRejection = .{},
    progress: @import("progress.zig").Progress,
    sequence: usize = 0,
    current: ?operation.ProviderOperationId = null,
    last_step: ?workflow.WorkflowStepId = null,

    const Call = @import("observation.zig").Call;

    pub fn init(store: evidence.Store, invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly, purpose: Purpose) !Trace {
        try store.run.createDirPath(store.io, "evidence");
        return .{ .store = store, .invocation = invocation, .purpose = purpose, .progress = .init(store.allocator), .events = try store.run.createFile(store.io, "events.jsonl", .{ .exclusive = true, .permissions = .fromMode(0o600) }) };
    }
    pub fn close(self: *Trace) void {
        self.last_rejection.deinit(self.store.allocator);
        self.progress.deinit();
        for (self.call_records.items) |call| {
            self.store.allocator.free(call.step);
            if (call.exception) |bytes| self.store.allocator.free(bytes);
            if (call.request_id) |bytes| self.store.allocator.free(bytes);
        }
        self.call_records.deinit(self.store.allocator);
        self.events.close(self.store.io);
    }
    pub fn port(self: *Trace) bindings.ChildBindings {
        return .{ .context = self, .vtable = &.{
            .validate_operation_registry = validate,
            .parse_invocation = parse,
            .select_workflow = select,
            .prepare_workflow = prepare,
            .selected_graph = graph,
            .invoke_invocation = invoke,
            .invoke_step = step,
            .finalize = finalize,
        } };
    }
    fn cast(context: *anyopaque) *Trace {
        return @ptrCast(@alignCast(context));
    }
    fn validate(context: *anyopaque) bindings.SelectionStepOutcome {
        return cast(context).invocation.bindings().invokeValidateOperationRegistry();
    }
    fn parse(context: *anyopaque) bindings.SelectionStepOutcome {
        return cast(context).invocation.bindings().invokeParseInvocation();
    }
    fn select(context: *anyopaque) bindings.SelectionStepOutcome {
        return cast(context).invocation.bindings().invokeSelectWorkflow();
    }
    fn prepare(context: *anyopaque) bindings.PreparationOutcome {
        const self = cast(context);
        if (!@import("builtin").is_test and self.transport_override != null) return .cancelled;
        const result = self.invocation.bindings().invokePrepareWorkflow();
        if (result == .ok) if (self.invocation.provider_runtime) |runtime| {
            if (runtime.provider) |*provider| {
                self.inner_transport = self.transport_override orelse provider.aws_bedrock.transport;
                provider.aws_bedrock.transport = .{ .context = @ptrCast(self), .exchange_fn = exchange };
            }
        };
        return result;
    }
    fn graph(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const Trace = @ptrCast(@alignCast(context));
        return self.invocation.bindings().selectedGraph();
    }
    fn invoke(context: *anyopaque) execution.Applied {
        const self = cast(context);
        const authority = &self.invocation.bindings().selectedGraph().authority;
        if (self.purpose == .single_exchange) {
            if (beforeChild(self.purpose, self.boundary, self.failure)) |stopped| return stopped;
            if (publicationGuard(self.purpose, &self.boundary, authority.invocation_outputs, &.{}, .none)) |stopped| return stopped;
        }
        const result = self.invocation.bindings().invokeInvocation();
        // The compiled invocation operation is observable before the first graph
        // step. Reuse the same native projection; it is not a model-call identity.
        self.recordStep(.{ .bytes = self.invocation.bindings().selectedGraph().authority.invocation_operation_id.bytes }, result) catch |cause| self.fail(cause);
        return result;
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self = cast(context);
        // A failed evidence sink aborts the test; it cannot create a passing run.
        if (beforeChild(self.purpose, self.boundary, self.failure)) |stopped| return stopped;
        if (self.purpose == .single_exchange) {
            for (self.invocation.bindings().selectedGraph().authority.steps) |compiled| {
                if (!std.mem.eql(u8, compiled.id.bytes, id.bytes)) continue;
                if (publicationGuard(self.purpose, &self.boundary, compiled.produces, compiled.replaces, compiled.side_effect)) |stopped| return stopped;
                break;
            }
        }
        const result = self.invocation.bindings().invokeStep(id);
        self.last_step = id;
        self.recordStep(id, result) catch |err| {
            self.fail(err);
        };
        return afterChild(self.purpose, self.boundary, self.failure, result);
    }

    fn finalize(context: *anyopaque, outcome: @import("../../../src/domain/run_outcome.zig").Outcome) @import("../../../src/domain/run_outcome.zig").Outcome {
        return cast(context).invocation.bindings().finalizeOutcome(outcome);
    }

    fn exchange(context: *transport.Context, a: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Trace = @ptrCast(@alignCast(context));
        if (self.failure != null) return error.Cancelled;
        try permitDispatch(a, self.purpose, &self.boundary, self.physical_sends, request);
        self.calls += 1;
        self.captureRequest(request) catch |err| {
            if (self.purpose == .single_exchange) self.boundary = if (err == error.ProbeBindingRejected) .binding_rejected else .capture_failed;
            self.fail(err);
            return error.Cancelled;
        };
        self.request_sha256 = digest(request.body);
        self.response_sha256 = null;
        const response = forwardCaptured(a, self.purpose, &self.boundary, &self.physical_sends, self.inner_transport.?, request) catch |err| {
            if (request.response_body_on_error) |slot| if (slot.*) |partial| {
                if (retainResponse(self.store, self.calls, &self.call_records.items[self.calls - 1], partial.bytes)) |hash| {
                    self.response_sha256 = hash;
                } else |save_error| self.fail(save_error);
            };
            self.saveOutcome(.{ .transport_error = if (err == error.Cancelled) .cancelled else .allocation_failed }) catch |save_error| {
                self.fail(save_error);
            };
            return err;
        };
        switch (response) {
            .received => |received| {
                if (retainResponse(self.store, self.calls, &self.call_records.items[self.calls - 1], received.body)) |hash| {
                    self.response_sha256 = hash;
                } else |err| {
                    self.fail(err);
                }
                self.saveOutcome(.{ .received = .{ .status = received.status, .exception = received.exception, .request_id = received.request_id } }) catch |err| {
                    self.fail(err);
                };
            },
            .failed => |failure| {
                if (failure.body) |partial| {
                    if (retainResponse(self.store, self.calls, &self.call_records.items[self.calls - 1], partial.bytes)) |hash| {
                        self.response_sha256 = hash;
                    } else |err| self.fail(err);
                }
                self.saveOutcome(.{ .failed = failure }) catch |err| self.fail(err);
            },
        }
        return response;
    }

    fn fail(self: *Trace, err: anyerror) void {
        if (self.failure == null) self.failure = err;
    }

    fn digest(bytes: []const u8) [32]u8 {
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
        return hash;
    }

    fn retainResponse(store: evidence.Store, ordinal: usize, call: *Call, bytes: []const u8) ![32]u8 {
        // Availability records retained bytes only. A partial/error body never
        // gains candidate eligibility, status, usage or publication authority.
        const hash = digest(bytes);
        try store.write(.generation, ordinal, .response, bytes);
        call.raw_response_available = true;
        return hash;
    }

    fn saveOutcome(self: *Trace, value: TransportOutcome) !void {
        const call = &self.call_records.items[self.calls - 1];
        switch (value) {
            .received => |received| {
                call.status = received.status;
                if (received.exception) |bytes| call.exception = try self.store.redact(self.store.allocator, bytes);
                if (received.request_id) |bytes| call.request_id = try self.store.redact(self.store.allocator, bytes);
            },
            .failed => |failure| call.transport = failure.diagnostic,
            .transport_error => {},
        }
        const bytes = try std.json.Stringify.valueAlloc(self.store.allocator, value, .{});
        defer self.store.allocator.free(bytes);
        try self.store.write(.generation, self.calls, .outcome, bytes);
    }

    fn captureRequest(self: *Trace, wire: transport.Request) !void {
        const runner = &self.invocation.pipeline_runner.?;
        const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
        const handoff = try requests.readCurrent(&view, requests.prepared_schema);
        const request = handoff.prepared() orelse return error.MissingRequestEvidence;
        if (self.purpose == .single_exchange) {
            const description = @import("../../../src/domain/model_request_description.zig").Description.from(request, handoff.binding(), wire.kind);
            try validateProbeDescription(self.store.allocator, description, wire);
        }
        const accounting = @import("../../../src/application/workflow_model_accounting.zig");
        self.current = (try values.read(&view, accounting.invoked_schema, @import("../../../src/domain/provider_operation_lifecycle.zig").InvokedOperation)).operation().id;
        const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
        const origin = Origin.from(identities, self.current.?) orelse return error.MissingRequestEvidence;
        {
            const request_step = try self.store.allocator.dupe(u8, request.binding_id.operation_id.workflow_step_id.bytes);
            errdefer self.store.allocator.free(request_step);
            try self.call_records.append(self.store.allocator, .{ .origin = origin, .step = request_step });
        }
        const context = try std.json.Stringify.valueAlloc(self.store.allocator, @import("call_context.zig").CallContext{
            .schema = .@"model-call-evidence/v1",
            .call = self.calls,
            .origin = origin,
            .request_step = request.binding_id.operation_id.workflow_step_id.bytes,
            .slot = request.binding_id.slot_id.bytes,
            .attempt = self.current.?.model_attempt_ordinal.value,
            .model = wire.model.bytes,
            .region = wire.region,
            .kind = wire.kind,
            .reasoning_effort = request.binding_id.reasoning_effort,
            .content = request.content,
            .response_schema = request.response_schema.modelBytes(),
            .response_mode = request.response_guidance_mode,
        }, .{ .whitespace = .indent_2 });
        defer self.store.allocator.free(context);
        try self.store.write(.generation, self.calls, .context, context);
        try self.store.write(.generation, self.calls, .request, wire.body);
    }

    fn probeProtocol(a: std.mem.Allocator) !@import("../generation_comparison.zig").Protocol {
        return @import("../generation_comparison.zig").parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    }

    fn validateProbeWire(a: std.mem.Allocator, wire: transport.Request) !void {
        try @import("../model_cost_policy.zig").require(.{ .bytes = "aws-bedrock" }, wire.model);
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        const protocol = try probeProtocol(arena.allocator());
        if (!std.mem.eql(u8, @tagName(wire.region), protocol.region) or !std.mem.eql(u8, wire.model.bytes, protocol.model)) return error.ProbeBindingRejected;
    }

    fn validateProbeDescription(a: std.mem.Allocator, description: @import("../../../src/domain/model_request_description.zig").Description, wire: transport.Request) !void {
        @import("../diagnostic_binding.zig").validateBinding(description) catch return error.ProbeBindingRejected;
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        const protocol = try probeProtocol(arena.allocator());
        const temperature = if (description.controls.temperature) |value| value.wireValue() else null;
        if (description.response_mode != .native_schema or description.reasoning_effort == null or
            !std.mem.eql(u8, description.reasoning_effort.?, @tagName(protocol.reasoning_effort)) or
            !std.meta.eql(temperature, @as(?f64, protocol.temperature)) or description.controls.max_output_tokens == null or
            description.controls.max_output_tokens.?.value != protocol.max_output_tokens or
            description.provider_config != .aws_bedrock or description.provider_config.aws_bedrock.region != wire.region or
            !std.mem.eql(u8, description.model, wire.model.bytes)) return error.ProbeBindingRejected;
    }

    fn permitDispatch(a: std.mem.Allocator, purpose: Purpose, boundary: *Boundary, physical_sends: usize, wire: transport.Request) transport.Error!void {
        if (purpose == .whole_workflow) return;
        if (wire.kind != .inference) {
            boundary.* = .unsupported_operation;
            return error.Cancelled;
        }
        if (physical_sends != 0 or boundary.* != .open) {
            boundary.* = .send_limit;
            return error.Cancelled;
        }
        validateProbeWire(a, wire) catch |err| {
            boundary.* = .binding_rejected;
            return if (err == error.OutOfMemory) error.OutOfMemory else error.Cancelled;
        };
    }

    fn forwardCaptured(a: std.mem.Allocator, purpose: Purpose, boundary: *Boundary, physical_sends: *usize, inner: transport.Port, wire: transport.Request) transport.Error!transport.Response {
        try permitDispatch(a, purpose, boundary, physical_sends.*, wire);
        // Capture has completed. Count before forwarding, including transport
        // cancellation or uncertain delivery; permission is never restored.
        physical_sends.* += 1;
        if (purpose == .single_exchange) boundary.* = .exchange_in_flight;
        defer if (purpose == .single_exchange and boundary.* == .exchange_in_flight) {
            boundary.* = .exchange_finished;
        };
        return inner.exchange(a, wire);
    }

    fn beforeChild(purpose: Purpose, boundary: Boundary, failure: ?anyerror) ?execution.Applied {
        if (failure != null) return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        if (purpose == .single_exchange and boundary != .open) return .{ .rejected = .cancelled };
        return null;
    }

    fn publicationGuard(purpose: Purpose, boundary: *Boundary, produces: []const @import("../../../src/domain/pipeline.zig").DataKey, replaces: []const @import("../../../src/domain/pipeline.zig").DataKey, effect: @import("../../../src/domain/pipeline.zig").SideEffect) ?execution.Applied {
        if (purpose == .whole_workflow) return null;
        const DataKey = @import("../../../src/domain/pipeline.zig").DataKey;
        if (effect == .workflow_publication or std.mem.indexOfScalar(DataKey, produces, .published_workflow_output) != null or
            std.mem.indexOfScalar(DataKey, replaces, .published_workflow_output) != null)
        {
            boundary.* = .publication_prohibited;
            return .{ .rejected = .cancelled };
        }
        return null;
    }

    fn afterChild(purpose: Purpose, boundary: Boundary, failure: ?anyerror, result: execution.Applied) execution.Applied {
        if (purpose == .whole_workflow or boundary == .open) return result;
        // The provider-owning child has reconciled actual usage and retained
        // its native result. Stop before validation, correction or publication.
        // Preserve an existing runner rejection rather than discard its failure.
        if (failure != null) return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        if (result == .rejected) return result;
        return .{ .rejected = .cancelled };
    }

    fn recordStep(self: *Trace, id: workflow.WorkflowStepId, result: execution.Applied) !void {
        const runner = &self.invocation.pipeline_runner.?;
        var arena: std.heap.ArenaAllocator = .init(self.store.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = result.status(), .terminal_rejection = if (result == .rejected) c.TerminalRejection.fromNative(result.rejected) else null };
        try @import("observation.zig").capture(a, runner, &report);
        try self.last_rejection.observe(self.store.allocator, self.calls, report);
        try self.last_rejection.project(a, self.calls, &report);
        const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
        const invocation = @import("../../../src/application/model_invocation_workflow.zig");
        if (view.slots[@intFromEnum(invocation.schema.key)] != null) {
            const raw = try values.read(&view, invocation.schema, @import("../../../src/domain/model_invocation_result.zig").For(.inference).Result);
            if (self.current) |current| if (current.eql(raw.operationId())) {
                if (self.call_records.items[self.calls - 1].output != .available) if (raw.outcome()) |outcome| {
                    if (outcome.* == .observation and outcome.observation == .completed and outcome.observation.completed.raw_result == .complete) {
                        self.store.write(.generation, self.calls, .model_output, outcome.observation.completed.raw_result.complete.content.bytes) catch |err| {
                            self.call_records.items[self.calls - 1].output = .capture_failed;
                            return err;
                        };
                        self.call_records.items[self.calls - 1].output = .available;
                    }
                };
            };
        }
        try self.correlate(a, &report);
        self.sequence += 1;
        try self.progress.observe(self.sequence, id.bytes, report, runner.last_effects);
        try self.progress.project(a, &report);
        const event = try stepEvent(a, self.sequence, id, result, report);
        try self.events.writeStreamingAll(self.store.io, event);
        try self.events.writeStreamingAll(self.store.io, "\n");
        try self.events.sync(self.store.io);
    }

    pub fn stepEvent(a: std.mem.Allocator, sequence: usize, id: workflow.WorkflowStepId, result: execution.Applied, report: c.Report) ![]const u8 {
        return std.json.Stringify.valueAlloc(a, .{
            .schema = "e2e-step-event/v1",
            .sequence = sequence,
            .step = id.bytes,
            .outcome = result.status(),
            .rejection = if (result == .rejected) c.TerminalRejection.fromNative(result.rejected) else null,
            .exchange = if (report.last_model_call) |call| .{ .call = call, .origin = report.last_model_origin, .request_step = report.last_model_step, .usage = report.last_model_usage, .output = report.last_model_output } else null,
            .candidate_source = if (report.candidate_model_call) |call| .{ .call = call, .origin = report.candidate_error.?.origin(), .request_step = report.candidate_model_step, .output = report.candidate_model_output } else null,
            .provider_error = report.provider_diagnostic,
            .provider_origin = report.provider_origin,
            .provider_content_diagnostic = report.provider_content_diagnostic,
            .model_error = report.model_diagnostic,
            .json_error = report.json_error,
            .schema_error = report.schema_error,
            .last_protocol_rejection = report.last_protocol_rejection,
            .last_provider_rejection = report.last_provider_rejection,
            .first_observed_defect = report.first_observed_defect,
            .correction = if (report.corrections.len != 0 and report.corrections[report.corrections.len - 1].sequence == sequence) report.corrections[report.corrections.len - 1] else null,
            .outstanding_work = report.outstanding_work,
            .exchange_evidence = report.exchange_evidence,
            .retry_error = if (result == .rejected and result.rejected == .retry_limit) try result.rejected.retry_limit.describe(a) else null,
            .candidate_error = report.candidate_error,
            .last_operation_rejection = report.last_operation_rejection,
            .repairs = report.repairs,
        }, .{});
    }

    /// Join a retained native origin to the actual captured exchange. No guess
    /// based on the latest call, step name or model response contents.
    pub fn correlate(self: *Trace, a: std.mem.Allocator, report: *c.Report) !void {
        if (self.call_records.items.len != self.calls) return error.MissingRequestEvidence;
        try @import("observation.zig").correlate(a, self.call_records.items, report);
    }
};

const ProbeWire = struct {
    mode: enum { received, http_error, uncertain_delivery, cancelled } = .received,
    calls: usize = 0,
    physical_sends: *const usize,
    boundary: *const Trace.Boundary,
    sends_seen_inside_transport: usize = 0,
    boundary_seen_inside_transport: Trace.Boundary = .open,

    fn port(self: *ProbeWire) transport.Port {
        return .{ .context = @ptrCast(self), .exchange_fn = exchange };
    }
    fn exchange(context: *transport.Context, _: std.mem.Allocator, _: transport.Request) transport.Error!transport.Response {
        const self: *ProbeWire = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.sends_seen_inside_transport = self.physical_sends.*;
        self.boundary_seen_inside_transport = self.boundary.*;
        return switch (self.mode) {
            .received => .{ .received = .{ .status = 200, .body = "{}" } },
            .http_error => .{ .received = .{ .status = 403, .body = "{}" } },
            .uncertain_delivery => .{ .failed = .{ .cause = .transport_failed, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown } },
            .cancelled => error.Cancelled,
        };
    }
};

fn probeWireRequest() transport.Request {
    return .{ .region = .@"ap-southeast-2", .model = .{ .bytes = "openai.gpt-oss-20b-1:0" }, .kind = .inference, .body = "{}", .api_key = "unit-credential", .deadline_monotonic_ms = 1 };
}

test "single-exchange guard consumes its only send before transport and never retries any delivery" {
    for ([_]@FieldType(ProbeWire, "mode"){ .received, .http_error, .uncertain_delivery, .cancelled }) |mode| {
        var boundary: Trace.Boundary = .open;
        var sends: usize = 0;
        var wire: ProbeWire = .{ .mode = mode, .physical_sends = &sends, .boundary = &boundary };
        const request = probeWireRequest();
        if (mode == .cancelled) {
            try std.testing.expectError(error.Cancelled, Trace.forwardCaptured(std.testing.allocator, .single_exchange, &boundary, &sends, wire.port(), request));
        } else _ = try Trace.forwardCaptured(std.testing.allocator, .single_exchange, &boundary, &sends, wire.port(), request);
        try std.testing.expectEqual(@as(usize, 1), wire.calls);
        try std.testing.expectEqual(@as(usize, 1), wire.sends_seen_inside_transport);
        try std.testing.expectEqual(.exchange_in_flight, wire.boundary_seen_inside_transport);
        try std.testing.expectEqual(.exchange_finished, boundary);
        try std.testing.expectEqual(@as(usize, 1), sends);
        try std.testing.expectError(error.Cancelled, Trace.forwardCaptured(std.testing.allocator, .single_exchange, &boundary, &sends, wire.port(), request));
        try std.testing.expectEqual(.send_limit, boundary);
        try std.testing.expectEqual(@as(usize, 1), wire.calls);
        try std.testing.expectEqual(@as(usize, 1), sends);
    }
}

test "single-exchange guard refuses counts foreign tuples and failed capture without a send" {
    for (0..5) |fault| {
        var boundary: Trace.Boundary = if (fault == 4) .capture_failed else .open;
        var sends: usize = 0;
        var wire: ProbeWire = .{ .physical_sends = &sends, .boundary = &boundary };
        var request = probeWireRequest();
        switch (fault) {
            0 => request.kind = .input_token_count,
            1 => request.model = .{ .bytes = "global.openai.gpt-6-luna" },
            2 => request.model = .{ .bytes = "us.openai.gpt-6-luna" },
            3 => request.region = .@"us-west-2",
            4 => {},
            else => unreachable,
        }
        try std.testing.expectError(error.Cancelled, Trace.forwardCaptured(std.testing.allocator, .single_exchange, &boundary, &sends, wire.port(), request));
        try std.testing.expectEqual(@as(usize, 0), sends);
        try std.testing.expectEqual(@as(usize, 0), wire.calls);
        try std.testing.expectEqual(if (fault == 0) Trace.Boundary.unsupported_operation else if (fault == 4) Trace.Boundary.send_limit else Trace.Boundary.binding_rejected, boundary);
        try std.testing.expect(Trace.beforeChild(.single_exchange, boundary, null) != null);
    }
}

test "single-exchange capture requires the frozen native response settings and exact wire association" {
    const Description = @import("../../../src/domain/model_request_description.zig").Description;
    const description: Description = .{
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
        .model_slot = "unit-generation",
        .workflow_id = "unit-workflow",
        .workflow_version = 1,
        .request_step = "unit-request",
        .content = &.{.{ .user = "unit source input" }},
        .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
        .schema = "{}",
        .response_mode = .native_schema,
        .controls = .{ .temperature = .fixed, .max_output_tokens = .{ .value = 16384 } },
        .reasoning_effort = "low",
        .operation_kind = .inference,
    };
    const request = probeWireRequest();
    try Trace.validateProbeDescription(std.testing.allocator, description, request);
    for (0..9) |fault| {
        var invalid = description;
        switch (fault) {
            0 => invalid.response_mode = .prompt_only,
            1 => invalid.reasoning_effort = "medium",
            2 => invalid.controls.temperature = null,
            3 => invalid.controls.max_output_tokens = null,
            4 => invalid.controls.max_output_tokens = .{ .value = 4096 },
            5 => invalid.model = "us.openai.gpt-6-luna",
            6 => invalid.provider_config.aws_bedrock.region = .@"us-west-2",
            7 => invalid.operation_kind = .input_token_count,
            8 => invalid.reasoning_effort = null,
            else => unreachable,
        }
        try std.testing.expectError(error.ProbeBindingRejected, Trace.validateProbeDescription(std.testing.allocator, invalid, request));
    }
}

test "single-exchange child boundary terminates before successors while retaining runner failures" {
    try std.testing.expect(Trace.beforeChild(.single_exchange, .open, null) == null);
    for ([_]Trace.Boundary{ .exchange_in_flight, .exchange_finished, .unsupported_operation, .binding_rejected, .publication_prohibited, .send_limit, .capture_failed }) |boundary| {
        const before = Trace.beforeChild(.single_exchange, boundary, null).?;
        try std.testing.expectEqual(.cancelled, std.meta.activeTag(before.rejected));
        const after = Trace.afterChild(.single_exchange, boundary, null, .{ .outcome = .ok });
        try std.testing.expectEqual(.cancelled, std.meta.activeTag(after.rejected));
    }
    for ([_]execution.Rejection{ .authority, .cancelled, .deadline_exhausted, .{ .operation_failed = error.OperationExecutionFailed } }) |failure| {
        const retained: execution.Applied = .{ .rejected = failure };
        try std.testing.expectEqualDeep(retained, Trace.afterChild(.single_exchange, .exchange_finished, null, retained));
    }
    const failed = Trace.afterChild(.single_exchange, .exchange_finished, error.MissingRequestEvidence, .{ .outcome = .ok });
    try std.testing.expectEqual(.operation_failed, std.meta.activeTag(failed.rejected));
}

test "single-exchange publication guard rejects invocation outputs replacements and typed publication effects" {
    const DataKey = @import("../../../src/domain/pipeline.zig").DataKey;
    const SideEffect = @import("../../../src/domain/pipeline.zig").SideEffect;
    for ([_]struct { produces: []const DataKey, replaces: []const DataKey, effect: SideEffect }{
        .{ .produces = &.{.published_workflow_output}, .replaces = &.{}, .effect = .none },
        .{ .produces = &.{}, .replaces = &.{.published_workflow_output}, .effect = .none },
        .{ .produces = &.{.workflow_invocation}, .replaces = &.{}, .effect = .workflow_publication },
    }) |entry| {
        var boundary: Trace.Boundary = .open;
        const stopped = Trace.publicationGuard(.single_exchange, &boundary, entry.produces, entry.replaces, entry.effect).?;
        try std.testing.expectEqual(.cancelled, std.meta.activeTag(stopped.rejected));
        try std.testing.expectEqual(.publication_prohibited, boundary);
        try std.testing.expect(Trace.publicationGuard(.whole_workflow, &boundary, entry.produces, entry.replaces, entry.effect) == null);
    }
    var boundary: Trace.Boundary = .open;
    try std.testing.expect(Trace.publicationGuard(.single_exchange, &boundary, &.{ .workflow_invocation, .prepared_model_request }, &.{.validated_model_request}, .none) == null);
    try std.testing.expectEqual(.open, boundary);
    try std.testing.expect(Trace.publicationGuard(.single_exchange, &boundary, &.{}, &.{}, .model_call) == null);
    try std.testing.expectEqual(.open, boundary);
}

test "whole-workflow trace leaves native outcomes and multiple inference or count sends unchanged" {
    var boundary: Trace.Boundary = .open;
    var sends: usize = 0;
    var wire: ProbeWire = .{ .physical_sends = &sends, .boundary = &boundary };
    var request = probeWireRequest();
    _ = try Trace.forwardCaptured(std.testing.allocator, .whole_workflow, &boundary, &sends, wire.port(), request);
    request.kind = .input_token_count;
    _ = try Trace.forwardCaptured(std.testing.allocator, .whole_workflow, &boundary, &sends, wire.port(), request);
    try std.testing.expectEqual(@as(usize, 2), sends);
    try std.testing.expectEqual(@as(usize, 2), wire.calls);
    try std.testing.expectEqual(.open, boundary);
    try std.testing.expect(Trace.beforeChild(.whole_workflow, boundary, null) == null);
    inline for (std.meta.tags(workflow.OutcomeTag)) |outcome| {
        const native: execution.Applied = .{ .outcome = outcome };
        try std.testing.expectEqualDeep(native, Trace.afterChild(.whole_workflow, boundary, null, native));
    }
}

test "trace retains partial error response bytes without inventing candidate or usage" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const store: evidence.Store = .{ .io = io, .allocator = std.testing.allocator, .run = directory.dir, .secrets = &.{"unit-secret"} };
    var call: @import("observation.zig").Call = .{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .step = "unit-step" };
    const hash = try Trace.retainResponse(store, 1, &call, "{\"partial\":\"unit-secret");
    try std.testing.expect(call.raw_response_available);
    try std.testing.expectEqual(.not_projected, call.output);
    try std.testing.expect(call.status == null and call.usage == null);
    const path = try evidence.Store.path(std.testing.allocator, .generation, 1, .response);
    defer std.testing.allocator.free(path);
    const bytes = try @import("../files.zig").read(io, std.testing.allocator, directory.dir, path);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("{\"partial\":\"[REDACTED_CREDENTIAL]", bytes);
    try std.testing.expectEqualDeep(Trace.digest("{\"partial\":\"unit-secret"), hash);
    const retained_hash = Trace.digest(bytes);
    try std.testing.expect(!std.mem.eql(u8, &retained_hash, &hash));
}

test "trace response capture failure cannot claim retained bytes or erase the original response" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const store: evidence.Store = .{ .io = io, .allocator = std.testing.allocator, .run = directory.dir, .secrets = &.{} };
    var first: @import("observation.zig").Call = .{ .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .step = "unit-step" };
    const original_hash = try Trace.retainResponse(store, 1, &first, "original partial bytes");
    var rejected = first;
    rejected.raw_response_available = false;
    try std.testing.expectError(error.PathAlreadyExists, Trace.retainResponse(store, 1, &rejected, "replacement bytes"));
    try std.testing.expect(!rejected.raw_response_available);
    const path = try evidence.Store.path(std.testing.allocator, .generation, 1, .response);
    defer std.testing.allocator.free(path);
    const bytes = try @import("../files.zig").read(io, std.testing.allocator, directory.dir, path);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("original partial bytes", bytes);
    try std.testing.expectEqualDeep(Trace.digest(bytes), original_hash);
}
