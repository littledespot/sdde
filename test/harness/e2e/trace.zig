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

test "production tracing retains aggregate coverage diagnostics and permits existing bounded repair" {
    // Offline integration: only the transport returns scripted data. The real
    // workflow, provider admission, trace, runner and publication path execute.
    const io = std.testing.io;
    const samples = @import("../../../src/test_fixtures/spec_generation_responses.zig");
    const Wire = struct {
        invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly,
        omitted: bool,
        calls: usize = 0,

        fn exchange(context: *transport.Context, a: std.mem.Allocator, _: transport.Request) transport.Error!transport.Response {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            const runner = &self.invocation.pipeline_runner.?;
            const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            const body = samples.build(a, view, .{ .normalize_exact = true, .omit_exact = self.omitted }) catch |err| std.debug.panic("scripted response: {s}", .{@errorName(err)});
            return .{ .received = .{ .status = 200, .body = try std.fmt.allocPrint(
                a,
                "{{\"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":{s}}},\"finish_reason\":\"stop\"}}],\"usage\":{{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}}}",
                .{try std.json.Stringify.valueAlloc(a, body, .{})},
            ) } };
        }
        fn selected(_: *anyopaque) bindings.SelectionStepOutcome {
            return .ok;
        }
        fn ready(_: *anyopaque) bindings.PreparationOutcome {
            return .ok;
        }
    };
    const Mode = enum { repair, blocked, capture_failure };
    for ([_][]const u8{ "Display `Hello, World!`.", "Display `Loan renewed!`." }) |source| for (std.meta.tags(Mode)) |mode| {
        const omitted = mode == .blocked;
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const choice = try c.parse(a, @embedFile("../../e2e/wf-001-hello-world/node-vitest/workflow.case.json"));
        const fixture = @import("fixture.zig");
        const captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        var run = std.testing.tmpDir(.{});
        defer run.cleanup();
        try fixture.materialize(io, project.dir, captured);
        try project.dir.writeFile(io, .{ .sub_path = "references/hello-world/stories.md", .data = source });
        var runtime: @import("../../../src/composition/root.zig").Runtime = undefined;
        runtime.init(io, std.testing.allocator, project.dir, .{});
        defer runtime.deinit();
        try std.testing.expect(runtime.boot == .ready);
        var invocation = runtime.invocation(&.{ choice.workflow_id, "--feature", choice.feature, "--reference", choice.reference }, .{
            .snapshot = try @import("../../../src/adapters/provider/bedrock_api_key.zig").Snapshot.capture(std.testing.allocator, "isolated-credential"),
        });
        defer invocation.deinit();
        const initial = invocation.bindings();
        try std.testing.expectEqual(.ok, initial.invokeValidateOperationRegistry());
        try std.testing.expectEqual(.ok, initial.invokeParseInvocation());
        try std.testing.expectEqual(.ok, initial.invokeSelectWorkflow());
        try std.testing.expectEqual(.ok, initial.invokePrepareWorkflow());
        var trace = try Trace.init(.{ .io = io, .allocator = std.testing.allocator, .run = run.dir, .secrets = &.{"isolated-credential"} }, &invocation);
        defer trace.close();
        if (mode == .capture_failure) try run.dir.createDirPath(io, "evidence/generation/call-000001/model_output.txt");
        var wire: Wire = .{ .invocation = &invocation, .omitted = omitted };
        trace.inner_transport = .{ .context = @ptrCast(&wire), .exchange_fn = Wire.exchange };
        runtime.provider_runtime.provider.?.aws_bedrock.transport = .{ .context = @ptrCast(&trace), .exchange_fn = Trace.exchange };
        var prepared = trace.port().vtable.*;
        prepared.validate_operation_registry = Wire.selected;
        prepared.parse_invocation = Wire.selected;
        prepared.select_workflow = Wire.selected;
        prepared.prepare_workflow = Wire.ready;
        const outcome = @import("../../../src/application/workflow_engine_orchestrator.zig").run(.{ .context = &trace, .vtable = &prepared });
        try std.testing.expectEqual(mode == .capture_failure, trace.failure != null);
        try std.testing.expectEqual(switch (mode) {
            .repair => workflow.OutcomeTag.ok,
            .blocked => .blocked,
            .capture_failure => .failed,
        }, outcome.executionStatus().?);
        const runner = &invocation.pipeline_runner.?;
        var report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = outcome.executionStatus() };
        try @import("observation.zig").capture(a, runner, &report);
        try trace.correlate(a, &report);
        try std.testing.expectEqual(wire.calls, trace.calls);
        try std.testing.expectEqual(wire.calls, report.model_calls);
        try std.testing.expectEqual(@as(u128, wire.calls) * 12, report.total_tokens);
        try std.testing.expect(report.usage_complete);
        if (mode == .capture_failure) {
            try std.testing.expectEqual(@as(usize, 1), trace.calls);
            try std.testing.expectEqual(.capture_failed, report.exchange_evidence.?.text);
            try std.testing.expect(report.last_model_output == null);
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/spec.md", .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/clarify/S01.md", .{}));
            continue;
        }
        const events = try run.dir.readFileAlloc(io, "events.jsonl", a, .limited(16 * 1024 * 1024));
        var rows = std.mem.splitScalar(u8, events, '\n');
        var aggregate: usize = 0;
        var selected: usize = 0;
        var merged: usize = 0;
        var coverage_call: ?i64 = null;
        while (rows.next()) |row| {
            if (row.len == 0) continue;
            const event = (try std.json.parseFromSlice(std.json.Value, a, row, .{})).value.object;
            const step = event.get("step").?.string;
            const operation_id = for (runner.selected.graph.authority.steps) |entry| {
                if (std.mem.eql(u8, step, entry.id.bytes)) break entry.operation_id.bytes;
            } else return error.UnknownTracedOperation;
            if (std.mem.eql(u8, operation_id, "validate-specification-coverage") and std.mem.eql(u8, event.get("outcome").?.string, "invalid")) {
                aggregate += 1;
                coverage_call = event.get("exchange").?.object.get("call").?.integer;
                try std.testing.expect(event.get("candidate_source").? == .null);
                try std.testing.expect(event.get("candidate_error").?.object.contains("coverage"));
            }
            if (std.mem.eql(u8, operation_id, "authorize-specification-coverage-repair") and !omitted) {
                selected += 1;
                try std.testing.expect(event.get("candidate_source").? == .object);
                try std.testing.expectEqual(coverage_call.?, event.get("exchange").?.object.get("call").?.integer);
            }
            if (std.mem.eql(u8, operation_id, "merge-specification-coverage-repair")) {
                merged += 1;
                try std.testing.expectEqual(coverage_call.?, event.get("exchange").?.object.get("call").?.integer);
            }
        }
        try std.testing.expectEqual(@as(usize, 1), aggregate);
        try std.testing.expectEqual(@as(usize, if (omitted) 0 else 1), selected);
        try std.testing.expectEqual(selected, merged);
        const spec_path = "specs/hello-world/spec.md";
        const state_path = ".sddtoolkit/workflows/features/hello-world/state/workflow.json";
        if (omitted) {
            try std.testing.expectEqual(.candidate, report.candidate_error.?.attribution());
            try std.testing.expect(report.candidate_model_call == null);
            try std.testing.expect(std.mem.indexOf(u8, try @import("report.zig").renderMarkdown(a, report), "assembled candidate") != null);
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, spec_path, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, state_path, .{}));
            try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/clarify/S01.md", .{}));
        } else {
            try project.dir.access(io, spec_path, .{});
            const state = try project.dir.readFileAlloc(io, state_path, a, .limited(64 * 1024 * 1024));
            _ = (try @import("../../../src/domain/specification_state.zig").parse(a, state, .{ .bytes = choice.feature }, runtime.boot.ready.workflows.registry().contractSource())).specified().?;
            try std.testing.expect(report.candidate_error == null);
        }
    };
}

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
