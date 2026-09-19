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

const TransportOutcome = union(enum) {
    transport_error: enum { cancelled, allocation_failed },
    received: struct { status: u16, exception: ?[]const u8, request_id: ?[]const u8 },
    failed: transport.Failure,
};

pub const Trace = struct {
    store: evidence.Store,
    invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly,
    events: std.Io.File,
    inner_transport: ?transport.Port = null,
    failure: ?anyerror = null,
    calls: usize = 0,
    call_records: std.ArrayList(Call) = .empty,
    last_rejection: @import("observation.zig").LastModelRejection = .{},
    sequence: usize = 0,
    current: ?operation.ProviderOperationId = null,
    output_written: bool = false,
    last_step: ?workflow.WorkflowStepId = null,

    const Call = @import("observation.zig").Call;

    pub fn init(store: evidence.Store, invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly) !Trace {
        try store.run.createDirPath(store.io, "evidence");
        return .{ .store = store, .invocation = invocation, .events = try store.run.createFile(store.io, "events.jsonl", .{ .exclusive = true, .permissions = .fromMode(0o600) }) };
    }
    pub fn close(self: *Trace) void {
        self.last_rejection.deinit(self.store.allocator);
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
        const result = self.invocation.bindings().invokePrepareWorkflow();
        if (result == .ok) if (self.invocation.provider_runtime) |runtime| {
            if (runtime.provider) |*provider| {
                self.inner_transport = provider.aws_bedrock.transport;
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
        return cast(context).invocation.bindings().invokeInvocation();
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self = cast(context);
        // A failed evidence sink aborts the test; it cannot create a passing run.
        if (self.failure != null) return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        const result = self.invocation.bindings().invokeStep(id);
        self.last_step = id;
        self.recordStep(id, result) catch |err| {
            self.fail(err);
        };
        return result;
    }

    fn finalize(context: *anyopaque, outcome: @import("../../../src/domain/run_outcome.zig").Outcome) @import("../../../src/domain/run_outcome.zig").Outcome {
        return cast(context).invocation.bindings().finalizeOutcome(outcome);
    }

    fn exchange(context: *transport.Context, a: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Trace = @ptrCast(@alignCast(context));
        if (self.failure != null) return error.Cancelled;
        self.calls += 1;
        self.output_written = false;
        self.captureRequest(request) catch |err| {
            self.fail(err);
            return error.Cancelled;
        };
        const response = self.inner_transport.?.exchange(a, request) catch |err| {
            self.saveOutcome(.{ .transport_error = if (err == error.Cancelled) .cancelled else .allocation_failed }) catch |save_error| {
                self.fail(save_error);
            };
            return err;
        };
        switch (response) {
            .received => |received| {
                if (self.store.write(.generation, self.calls, .response, received.body)) {
                    self.call_records.items[self.calls - 1].raw_response_available = true;
                } else |err| {
                    self.fail(err);
                }
                self.saveOutcome(.{ .received = .{ .status = received.status, .exception = received.exception, .request_id = received.request_id } }) catch |err| {
                    self.fail(err);
                };
            },
            .failed => |failure| self.saveOutcome(.{ .failed = failure }) catch |err| {
                self.fail(err);
            },
        }
        return response;
    }

    fn fail(self: *Trace, err: anyerror) void {
        if (self.failure == null) self.failure = err;
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
        const request = (try requests.readCurrent(&view, requests.prepared_schema)).prepared() orelse return error.MissingRequestEvidence;
        const accounting = @import("../../../src/application/workflow_model_accounting.zig");
        self.current = (try values.read(&view, accounting.invoked_schema, @import("../../../src/domain/provider_operation_lifecycle.zig").InvokedOperation)).operation().id;
        const identities = try values.read(&view, requests.ledger_schema, @import("../../../src/domain/model_request_identity.zig").ModelRequestIdentityLedger);
        const origin = Origin.from(identities, self.current.?) orelse return error.MissingRequestEvidence;
        {
            const request_step = try self.store.allocator.dupe(u8, request.binding_id.operation_id.workflow_step_id.bytes);
            errdefer self.store.allocator.free(request_step);
            try self.call_records.append(self.store.allocator, .{ .origin = origin, .step = request_step });
        }
        const context = try std.json.Stringify.valueAlloc(self.store.allocator, .{
            .schema = "model-call-evidence/v1",
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
                if (!self.output_written) if (raw.outcome()) |outcome| {
                    if (outcome.* == .observation and outcome.observation == .completed and outcome.observation.completed.raw_result == .complete) {
                        try self.store.write(.generation, self.calls, .model_output, outcome.observation.completed.raw_result.complete.content.bytes);
                        self.output_written = true;
                        self.call_records.items[self.calls - 1].output_available = true;
                    }
                };
            };
        }
        try self.correlate(a, &report);
        self.sequence += 1;
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
            .model_error = report.model_diagnostic,
            .json_error = report.json_error,
            .schema_error = report.schema_error,
            .last_protocol_rejection = report.last_protocol_rejection,
            .exchange_evidence = report.exchange_evidence,
            .retry_error = if (result == .rejected and result.rejected == .retry_limit) try result.rejected.retry_limit.describe(a) else null,
            .candidate_error = report.candidate_error,
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
