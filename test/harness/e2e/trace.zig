//! Observes production execution and HTTPS exchanges; supplies no model answers.
const std = @import("std");
const bindings = @import("../../../src/application/workflow_engine_child_bindings.zig");
const execution = @import("../../../src/domain/workflow_execution.zig");
const workflow = @import("../../../src/domain/workflow.zig");
const compilation = @import("../../../src/domain/workflow_compilation.zig");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const transport = @import("../../../src/adapters/provider/model_http_transport.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const requests = @import("../../../src/application/model_request_workflow.zig");
const evidence = @import("../evidence.zig");
const c = @import("contracts.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
const dispatch = @import("../baseline/dispatch.zig");
const frozen_binding = @import("../frozen_binding.zig");
const request_identity = @import("../../../src/domain/model_request_identity.zig");
const stages = @import("../baseline/stages.zig");
const admission = @import("../baseline/admission.zig");

pub const MechanicalRejection = union(enum) {
    protocol: c.ProtocolRejection,
    provider: c.ProviderRejection,

    fn copy(self: MechanicalRejection, a: std.mem.Allocator) !MechanicalRejection {
        return switch (self) {
            .protocol => |value| blk: {
                var result = value;
                result.reason = try a.dupe(u8, value.reason);
                errdefer a.free(result.reason);
                result.json_error = if (value.json_error) |diagnostic| try diagnostic.copy(a) else null;
                errdefer if (result.json_error) |diagnostic| diagnostic.deinit(a);
                result.composition_error = if (value.composition_error) |diagnostic| try diagnostic.copy(a) else null;
                errdefer if (result.composition_error) |diagnostic| diagnostic.deinit(a);
                if (value.schema_error) |diagnostic| result.schema_error.?.path = try a.dupe(u8, diagnostic.path);
                break :blk .{ .protocol = result };
            },
            .provider => |value| blk: {
                var result = value;
                result.reason = try a.dupe(u8, value.reason);
                break :blk .{ .provider = result };
            },
        };
    }

    fn deinit(self: MechanicalRejection, a: std.mem.Allocator) void {
        switch (self) {
            .protocol => |value| {
                a.free(value.reason);
                if (value.json_error) |diagnostic| diagnostic.deinit(a);
                if (value.composition_error) |diagnostic| diagnostic.deinit(a);
                if (value.schema_error) |diagnostic| a.free(diagnostic.path);
            },
            .provider => |value| a.free(value.reason),
        }
    }
};

pub const Receipt = struct {
    call: usize,
    origin: Origin,
    purpose: request_identity.RequestPurposeKind,
    owner_kind: stages.OwnerKind,
    /// Native out-of-band repair lineage, never inferred from prompt content.
    repair_origin: ?Origin = null,
    experiment_send: ?dispatch.Send,
    request_step: []const u8,
    result_definition: ?@import("../../../src/domain/model_result_schema.zig").DefinitionId = null,
    context_sha256: [32]u8,
    request_sha256: [32]u8,
    response_sha256: ?[32]u8 = null,
    model_output_sha256: ?[32]u8 = null,
    raw_response_available: bool = false,
    model_output_available: bool = false,
    status: ?u16 = null,
    usage: ?operation.ProviderUsage = null,
    uncertain_delivery: bool = false,
    /// First exact origin-joined native failure survives subsequent successes
    /// and later rejections in other calls. It supplies no semantic verdict.
    mechanical_rejection: ?MechanicalRejection = null,

    pub fn jsonStringify(self: Receipt, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.beginObject();
        inline for (std.meta.fields(Receipt)) |field| {
            try writer.objectField(field.name);
            if (field.type == [32]u8) {
                try @import("../../../src/domain/canonical_json.zig").writeByteArray(writer, &@field(self, field.name));
            } else if (field.type == ?[32]u8) {
                if (@field(self, field.name)) |bytes| try @import("../../../src/domain/canonical_json.zig").writeByteArray(writer, &bytes) else try writer.write(null);
            } else try writer.write(@field(self, field.name));
        }
        try writer.endObject();
    }
};

/// Root-owned copies survive the trace and native invocation. A receipt is
/// appended only for a charged physical send; source bytes stay in evidence.
pub const CaptureLog = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(Receipt) = .empty,
    candidates: @import("../baseline/candidates.zig").Tracker = .{},
    reviews: @import("../baseline/reviews.zig").Tracker,

    pub fn init(allocator: std.mem.Allocator) CaptureLog {
        return .{ .allocator = allocator, .reviews = .init(allocator) };
    }
    pub fn deinit(self: *CaptureLog) void {
        self.candidates.deinit(self.allocator);
        self.reviews.deinit();
        for (self.records.items) |record| {
            self.allocator.free(record.request_step);
            if (record.result_definition) |definition| self.allocator.free(definition.bytes);
            if (record.mechanical_rejection) |rejection| rejection.deinit(self.allocator);
        }
        self.records.deinit(self.allocator);
    }

    pub fn observeRejections(self: *CaptureLog, report: c.Report) !void {
        if (report.last_protocol_rejection) |rejection| for (self.records.items) |*receipt| {
            if (!std.meta.eql(receipt.origin, rejection.origin) or receipt.mechanical_rejection != null) continue;
            var joined = rejection;
            joined.call = receipt.call;
            receipt.mechanical_rejection = try (MechanicalRejection{ .protocol = joined }).copy(self.allocator);
        };
        if (report.last_provider_rejection) |rejection| if (rejection.origin) |origin| for (self.records.items) |*receipt| {
            if (!std.meta.eql(receipt.origin, origin) or receipt.mechanical_rejection != null) continue;
            var joined = rejection;
            joined.call = receipt.call;
            receipt.mechanical_rejection = try (MechanicalRejection{ .provider = joined }).copy(self.allocator);
        };
    }
};

fn reconcileExperiment(gate: *dispatch.Gate, send: dispatch.Send, origin: Origin, attempts: []const c.Attempt, uncertain_delivery: bool) !?operation.ProviderUsage {
    const usage = try @import("observation.zig").usageFor(attempts, origin);
    try gate.reconcile(send, usage, uncertain_delivery);
    return usage;
}

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
    experiment: ?*dispatch.Gate = null,
    capture: ?*CaptureLog = null,
    expected_models: ?*const @import("../../../src/domain/config.zig").ModelsConfig = null,
    capture_index: ?usize = null,
    context_sha256: ?[32]u8 = null,
    request_purpose: ?request_identity.RequestPurposeKind = null,
    request_owner_kind: ?stages.OwnerKind = null,
    request_repair_origin: ?Origin = null,
    request_result_definition: ?@import("../../../src/domain/model_result_schema.zig").DefinitionId = null,
    pending: ?struct { send: dispatch.Send, origin: Origin, uncertain_delivery: bool = false } = null,
    inner_transport: ?transport.Port = null,
    failure: ?anyerror = null,
    calls: usize = 0,
    call_records: std.ArrayList(Call) = .empty,
    last_rejection: @import("observation.zig").LastModelRejection = .{},
    progress: @import("progress.zig").Progress,
    admission_audit: admission.Tracker,
    sequence: usize = 0,
    current: ?operation.ProviderOperationId = null,
    last_step: ?workflow.WorkflowStepId = null,

    const Call = @import("observation.zig").Call;

    pub fn init(store: evidence.Store, invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly, purpose: Purpose) !Trace {
        try store.run.createDirPath(store.io, "evidence");
        return .{ .store = store, .invocation = invocation, .purpose = purpose, .progress = .init(store.allocator), .admission_audit = .init(store.allocator), .events = try store.run.createFile(store.io, "events.jsonl", .{ .exclusive = true, .permissions = .fromMode(0o600) }) };
    }
    pub fn close(self: *Trace) void {
        if (self.pending) |pending| if (self.experiment) |gate| {
            // An evidence/operational exit must still charge the unresolved
            // attempt and prevent a subsequent workflow from dispatching.
            gate.reconcile(pending.send, null, pending.uncertain_delivery) catch gate.stop(.evidence_failure);
        };
        self.last_rejection.deinit(self.store.allocator);
        self.progress.deinit();
        self.admission_audit.deinit();
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
                self.inner_transport = self.transport_override orelse provider.transport;
                provider.transport = .{ .context = @ptrCast(self), .exchange_fn = exchange };
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
        if (self.experimentStopped()) return .{ .rejected = .cancelled };
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
        if (self.experimentStopped()) return .{ .rejected = .cancelled };
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
        if (self.experiment != null and self.failure != null) return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        if (self.experimentStopped() and result != .rejected) return .{ .rejected = .cancelled };
        return afterChild(self.purpose, self.boundary, self.failure, result);
    }

    fn experimentStopped(self: *const Trace) bool {
        return if (self.experiment) |gate| if (gate.snapshot().halt_reason) |reason| stopsChildren(reason) else false else false;
    }

    fn stopsChildren(reason: dispatch.Reason) bool {
        return switch (reason) {
            // Consuming the final allowed send/token does not discard the
            // deterministic validation or publication that follows it.
            .send_limit, .token_limit => false,
            .usage_unavailable, .uncertain_delivery, .configuration_drift, .evidence_failure, .scoring_disputed, .operator_stop => true,
        };
    }

    fn finalize(context: *anyopaque, outcome: @import("../../../src/domain/run_outcome.zig").Outcome) @import("../../../src/domain/run_outcome.zig").Outcome {
        return cast(context).invocation.bindings().finalizeOutcome(outcome);
    }

    fn exchange(context: *transport.Context, a: std.mem.Allocator, request: transport.Request) transport.Error!transport.Response {
        const self: *Trace = @ptrCast(@alignCast(context));
        if (self.failure != null) return error.Cancelled;
        if (self.experiment) |gate| if (gate.snapshot().halt_reason != null) return error.Cancelled;
        if (self.experiment != null) frozen_binding.validateWire(a, request) catch |err| {
            self.experiment.?.stop(.configuration_drift);
            return if (err == error.OutOfMemory) error.OutOfMemory else error.Cancelled;
        };
        try permitDispatch(a, self.purpose, &self.boundary, self.physical_sends, request);
        self.calls += 1;
        self.captureRequest(request) catch |err| {
            if (self.purpose == .single_exchange) self.boundary = if (err == error.FrozenBindingRejected) .binding_rejected else .capture_failed;
            if (self.experiment) |gate| gate.stop(if (err == error.FrozenBindingRejected) .configuration_drift else .evidence_failure);
            self.fail(err);
            return error.Cancelled;
        };
        self.request_sha256 = digest(request.body);
        self.response_sha256 = null;
        self.capture_index = null;
        var retained_step: ?[]const u8 = null;
        var retained_definition: ?@import("../../../src/domain/model_result_schema.zig").DefinitionId = null;
        defer if (retained_step) |step_bytes| if (self.capture) |log| log.allocator.free(step_bytes);
        defer if (retained_definition) |definition| if (self.capture) |log| log.allocator.free(definition.bytes);
        if (self.capture) |log| {
            log.records.ensureUnusedCapacity(log.allocator, 1) catch |err| {
                self.fail(err);
                if (self.experiment) |gate| gate.stop(.evidence_failure);
                return error.OutOfMemory;
            };
            retained_step = log.allocator.dupe(u8, self.call_records.items[self.calls - 1].step) catch |err| {
                self.fail(err);
                if (self.experiment) |gate| gate.stop(.evidence_failure);
                return error.OutOfMemory;
            };
            if (self.request_result_definition) |definition| retained_definition = .{ .bytes = log.allocator.dupe(u8, definition.bytes) catch |err| {
                self.fail(err);
                return error.OutOfMemory;
            } };
        }
        const send = if (self.experiment) |gate| gate.beforeSend() catch |err| {
            if (err == error.ExchangeInFlight) gate.stop(.evidence_failure);
            return error.Cancelled;
        } else null;
        if (send) |charged| self.pending = .{ .send = charged, .origin = self.call_records.items[self.calls - 1].origin };
        if (self.capture) |log| {
            self.capture_index = log.records.items.len;
            log.records.appendAssumeCapacity(.{
                .call = self.calls,
                .origin = self.call_records.items[self.calls - 1].origin,
                .purpose = self.request_purpose.?,
                .owner_kind = self.request_owner_kind.?,
                .repair_origin = self.request_repair_origin,
                .experiment_send = send,
                .request_step = retained_step.?,
                .result_definition = retained_definition,
                .context_sha256 = self.context_sha256.?,
                .request_sha256 = self.request_sha256.?,
            });
            retained_step = null;
            retained_definition = null;
        }
        const response = forwardCaptured(a, self.purpose, &self.boundary, &self.physical_sends, self.inner_transport.?, request) catch |err| {
            self.call_records.items[self.calls - 1].uncertain_delivery = true;
            if (self.pending) |*pending| pending.uncertain_delivery = true;
            if (self.receipt()) |retained| retained.uncertain_delivery = true;
            if (request.response_body_on_error) |slot| if (slot.*) |partial| {
                if (retainResponse(self.store, self.calls, &self.call_records.items[self.calls - 1], partial.bytes)) |hash| {
                    self.response_sha256 = hash;
                } else |save_error| self.fail(save_error);
            };
            self.saveOutcome(.{ .transport_error = if (err == error.Cancelled) .cancelled else .allocation_failed }) catch |save_error| {
                self.fail(save_error);
            };
            self.updateReceipt();
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
                if (failure.delivery == .accepted_or_unknown) {
                    self.call_records.items[self.calls - 1].uncertain_delivery = true;
                    if (self.pending) |*pending| pending.uncertain_delivery = true;
                    if (self.receipt()) |retained| retained.uncertain_delivery = true;
                }
                if (failure.body) |partial| {
                    if (retainResponse(self.store, self.calls, &self.call_records.items[self.calls - 1], partial.bytes)) |hash| {
                        self.response_sha256 = hash;
                    } else |err| self.fail(err);
                }
                self.saveOutcome(.{ .failed = failure }) catch |err| self.fail(err);
            },
        }
        self.updateReceipt();
        return response;
    }

    fn receipt(self: *Trace) ?*Receipt {
        const log = self.capture orelse return null;
        return if (self.capture_index) |index| &log.records.items[index] else null;
    }

    fn updateReceipt(self: *Trace) void {
        if (self.receipt()) |retained| {
            const call = self.call_records.items[self.calls - 1];
            retained.response_sha256 = self.response_sha256;
            retained.raw_response_available = call.raw_response_available;
            retained.status = call.status;
            retained.usage = call.usage;
        }
    }

    fn fail(self: *Trace, err: anyerror) void {
        if (self.failure == null) self.failure = err;
        if (self.experiment) |gate| gate.stop(.evidence_failure);
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
        // The request identity carries its packet's purpose and owner (a composed
        // request's, its base packet's), as the E2E report's attempts read them.
        self.request_purpose = std.meta.activeTag(handoff.id().purpose);
        self.request_owner_kind = std.meta.activeTag(handoff.id().immutable_unit_owner_id);
        const packet = handoff.packet() orelse if (handoff.part()) |part| part.base else null;
        self.request_repair_origin = if (packet) |value| value.repairOrigin() else null;
        self.request_result_definition = handoff.selectedResultDefinition();
        if (self.purpose == .single_exchange or self.experiment != null) {
            const description = @import("../../../src/domain/model_request_description.zig").Description.from(request, handoff.binding(), .inference);
            try frozen_binding.validateDescription(self.store.allocator, description, wire, self.expected_models orelse return error.MissingFrozenModels);
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
        const selected = handoff.binding().registry_entry;
        const context = try std.json.Stringify.valueAlloc(self.store.allocator, @import("call_context.zig").CallContext{
            .schema = .@"model-call-evidence/v3",
            .call = self.calls,
            .origin = origin,
            .request_step = request.binding_id.operation_id.workflow_step_id.bytes,
            .slot = request.binding_id.slot_id.bytes,
            .attempt = self.current.?.model_attempt_ordinal.value,
            .provider = selected.provider.bytes,
            .model = selected.model.bytes,
            .provider_config = selected.config,
            .kind = .inference,
            .reasoning_effort = request.binding_id.reasoning_effort,
            .content = request.content,
            .response_schema = request.response_schema.modelBytes(),
            .response_mode = request.response_guidance_mode,
        }, .{ .whitespace = .indent_2 });
        defer self.store.allocator.free(context);
        try self.store.write(.generation, self.calls, .context, context);
        self.context_sha256 = digest(context);
        try self.store.write(.generation, self.calls, .request, wire.body);
    }

    fn permitDispatch(a: std.mem.Allocator, purpose: Purpose, boundary: *Boundary, physical_sends: usize, wire: transport.Request) transport.Error!void {
        if (purpose == .whole_workflow) return;
        if (physical_sends != 0 or boundary.* != .open) {
            boundary.* = .send_limit;
            return error.Cancelled;
        }
        frozen_binding.validateWire(a, wire) catch |err| {
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
        var report: c.Report = .{ .schema = .@"spec-e2e-report/v11", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = result.status(), .terminal_rejection = if (result == .rejected) c.TerminalRejection.fromNative(result.rejected) else null };
        try @import("observation.zig").capture(a, runner, &report);
        if (self.pending) |pending| {
            const usage = try reconcileExperiment(self.experiment.?, pending.send, pending.origin, report.attempts, pending.uncertain_delivery);
            self.pending = null;
            if (self.receipt()) |retained| retained.usage = usage;
        }
        try self.last_rejection.observe(self.store.allocator, self.calls, report);
        try self.last_rejection.project(a, self.calls, &report);
        const view: @import("../../../src/domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
        try self.admission_audit.observe(&view, self.sequence + 1, self.physical_sends);
        if (self.capture) |log| {
            try log.observeRejections(report);
            try log.candidates.observe(log.allocator, &view);
            try log.reviews.observe(&view);
        }
        const invocation = @import("../../../src/application/model_invocation_workflow.zig");
        if (view.slots[@intFromEnum(invocation.schema.key)] != null) {
            const raw = try values.read(&view, invocation.schema, @import("../../../src/domain/model_invocation_result.zig").Result);
            if (self.current) |current| if (current.eql(raw.operationId())) {
                if (self.call_records.items[self.calls - 1].output != .available) if (raw.outcome()) |outcome| {
                    if (outcome.* == .observation and outcome.observation == .completed and outcome.observation.completed.raw_result == .complete) {
                        self.store.write(.generation, self.calls, .model_output, outcome.observation.completed.raw_result.complete.content.bytes) catch |err| {
                            self.call_records.items[self.calls - 1].output = .capture_failed;
                            return err;
                        };
                        self.call_records.items[self.calls - 1].output = .available;
                        if (self.receipt()) |retained| {
                            retained.model_output_available = true;
                            retained.model_output_sha256 = digest(outcome.observation.completed.raw_result.complete.content.bytes);
                        }
                    }
                };
            };
        }
        try self.correlate(a, &report);
        self.updateReceipt();
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
            .schema = "e2e-step-event/v2",
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
            .composition_error = report.composition_error,
            .schema_error = report.schema_error,
            .last_protocol_rejection = report.last_protocol_rejection,
            .last_provider_rejection = report.last_provider_rejection,
            .first_native_rejection = report.first_native_rejection,
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

    pub fn projectAdmission(self: *Trace, a: std.mem.Allocator, report: *c.Report) !void {
        if (self.physical_sends > self.call_records.items.len) return error.MissingRequestEvidence;
        const exchanges = try a.alloc(admission.Exchange, self.physical_sends);
        defer a.free(exchanges);
        for (self.call_records.items[0..self.physical_sends], exchanges, 0..) |call, *observed_exchange, index| observed_exchange.* = .{
            .call = index + 1,
            .origin = call.origin,
            .usage = try @import("observation.zig").usageFor(report.attempts, call.origin),
            .uncertain_delivery = call.uncertain_delivery,
        };
        self.admission_audit.reconcile(exchanges);
        const audit = self.admission_audit.snapshot(self.failure == null);
        try admission.validate(a, audit, exchanges);
        report.admission_audit = try @import("../contracts.zig").decode(admission.Audit, a, try std.json.Stringify.valueAlloc(a, audit, .{}));
        report.admission_escape = try admission.measure(audit, exchanges);
        report.admission_exchanges = try a.dupe(admission.Exchange, exchanges);
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
    return .{ .target = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .model = .{ .bytes = "openai.gpt-oss-20b-1:0" } } }, .body = "{\"inferenceConfig\":{\"temperature\":0.1,\"maxTokens\":16384}}", .api_key = "unit-credential", .deadline_monotonic_ms = 1 };
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

test "single-exchange guard refuses foreign tuples and failed capture without a send" {
    for (1..5) |fault| {
        var boundary: Trace.Boundary = if (fault == 4) .capture_failed else .open;
        var sends: usize = 0;
        var wire: ProbeWire = .{ .physical_sends = &sends, .boundary = &boundary };
        var request = probeWireRequest();
        switch (fault) {
            1 => request.target.aws_bedrock.model = .{ .bytes = "global.openai.gpt-6-luna" },
            2 => request.target.aws_bedrock.model = .{ .bytes = "us.openai.gpt-6-luna" },
            3 => request.target.aws_bedrock.region = .@"us-west-2",
            4 => {},
            else => unreachable,
        }
        try std.testing.expectError(error.Cancelled, Trace.forwardCaptured(std.testing.allocator, .single_exchange, &boundary, &sends, wire.port(), request));
        try std.testing.expectEqual(@as(usize, 0), sends);
        try std.testing.expectEqual(@as(usize, 0), wire.calls);
        try std.testing.expectEqual(if (fault == 4) Trace.Boundary.send_limit else Trace.Boundary.binding_rejected, boundary);
        try std.testing.expect(Trace.beforeChild(.single_exchange, boundary, null) != null);
    }
}

test "single-exchange capture requires the frozen native response settings and exact wire association" {
    const Description = @import("../../../src/domain/model_request_description.zig").Description;
    const description: Description = .{
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16384 }, .request_timeout = .{ .milliseconds = 180000 } } },
        .model_slot = "spec_generation",
        .workflow_id = "unit-workflow",
        .workflow_version = 1,
        .request_step = "unit-request",
        .content = &.{.{ .user = "unit source input" }},
        .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
        .schema = "{}",
        .response_mode = .native_schema,
        .controls = .{ .temperatures = @import("../../../src/test_fixtures/model_temperatures.zig").temperatures },
        .reasoning_effort = "low",
        .operation_kind = .inference,
    };
    var models: @import("../../../src/domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(std.testing.allocator);
    try models.slots.map.put(std.testing.allocator, description.model_slot, .{ .provider = description.provider, .model = description.model, .reasoningEffort = "low" });
    const request = probeWireRequest();
    try frozen_binding.validateDescription(std.testing.allocator, description, request, &models);
    for (0..6) |fault| {
        var invalid = description;
        switch (fault) {
            0 => invalid.response_mode = .prompt_only,
            1 => invalid.reasoning_effort = "medium",
            2 => invalid.controls.temperatures = null,
            3 => invalid.model = "us.openai.gpt-6-luna",
            4 => invalid.provider_config.aws_bedrock.region = .@"us-west-2",
            5 => invalid.reasoning_effort = null,
            else => unreachable,
        }
        try std.testing.expectError(error.FrozenBindingRejected, frozen_binding.validateDescription(std.testing.allocator, invalid, request, &models));
    }
}

test "single-exchange child boundary terminates before successors while retaining runner failures" {
    try std.testing.expect(Trace.beforeChild(.single_exchange, .open, null) == null);
    for ([_]Trace.Boundary{ .exchange_in_flight, .exchange_finished, .binding_rejected, .publication_prohibited, .send_limit, .capture_failed }) |boundary| {
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

test "whole-workflow trace leaves native outcomes and multiple inference sends unchanged" {
    var boundary: Trace.Boundary = .open;
    var sends: usize = 0;
    var wire: ProbeWire = .{ .physical_sends = &sends, .boundary = &boundary };
    const request = probeWireRequest();
    _ = try Trace.forwardCaptured(std.testing.allocator, .whole_workflow, &boundary, &sends, wire.port(), request);
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

test "experiment trace charges only current native usage across serial workflow origins" {
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const current: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } };
    const known = operation.ProviderUsage.init(9, 4, 13).?;
    const records = [_]c.Attempt{
        .{ .origin = first, .step = "unit-first", .purpose = .initial_generation, .owner_kind = .specification_unit, .accounting = .exact_usage, .usage = operation.ProviderUsage.init(1, 1, 2).? },
        .{ .origin = current, .step = "unit-current", .purpose = .initial_generation, .owner_kind = .specification_unit, .accounting = .exact_usage, .usage = known },
    };
    var gate = try dispatch.Gate.init(.{ .maximum_sends = 4, .maximum_actual_tokens = 100 });
    const send = try gate.beforeSend();
    try std.testing.expectEqual(@as(?operation.ProviderUsage, known), try reconcileExperiment(&gate, send, current, &records, false));
    try std.testing.expectEqual(@as(?u128, 13), gate.snapshot().total_actual_tokens);
    // New native invocations may restart their local request identities, but
    // globally charged sends remain distinct and never replay old usage.
    const next_send = try gate.beforeSend();
    try std.testing.expectEqual(@as(u64, 2), next_send.ordinal);
    _ = try reconcileExperiment(&gate, next_send, first, records[0..1], false);
    try std.testing.expectEqual(@as(?u128, 15), gate.snapshot().total_actual_tokens);
}

test "experiment trace cannot substitute older native usage for an unknown exchange" {
    const previous: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const current: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const records = [_]c.Attempt{.{ .origin = previous, .step = "unit-previous", .purpose = .initial_generation, .owner_kind = .specification_unit, .accounting = .exact_usage, .usage = operation.ProviderUsage.init(10, 5, 15).? }};
    for ([_]bool{ false, true }) |uncertain| {
        var gate = try dispatch.Gate.init(.{ .maximum_sends = 4, .maximum_actual_tokens = 100 });
        const retained = try reconcileExperiment(&gate, try gate.beforeSend(), current, &records, uncertain);
        try std.testing.expect(retained == null);
        try std.testing.expectEqual(@as(u128, 0), gate.snapshot().total_accounted_tokens);
        try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
        try std.testing.expect(!gate.snapshot().usage_complete);
        try std.testing.expectEqual(@as(?dispatch.Reason, .usage_unavailable), gate.snapshot().halt_reason);
        try std.testing.expectEqual(uncertain, gate.snapshot().uncertain_delivery);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    }
}

test "experiment trace rejects ambiguous native origin and preserves send accounting" {
    const origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const record: c.Attempt = .{ .origin = origin, .step = "unit-ambiguous", .purpose = .initial_generation, .owner_kind = .specification_unit, .accounting = .exact_usage, .usage = operation.ProviderUsage.init(10, 5, 15).? };
    var gate = try dispatch.Gate.init(.{ .maximum_sends = 4, .maximum_actual_tokens = 100 });
    const send = try gate.beforeSend();
    try std.testing.expectError(error.MissingRequestEvidence, reconcileExperiment(&gate, send, origin, &.{ record, record }, false));
    try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
    try std.testing.expectEqual(@as(u128, 0), gate.snapshot().total_accounted_tokens);
    // The trace's operational cleanup reconciles unknown rather than refunding.
    gate.stop(.evidence_failure);
    try gate.reconcile(send, null, false);
    try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
}

test "experiment equality limits permit deterministic successors while every other stop aborts them" {
    for (std.meta.tags(dispatch.Reason)) |reason| {
        const intrinsic_limit = reason == .send_limit or reason == .token_limit;
        try std.testing.expectEqual(!intrinsic_limit, Trace.stopsChildren(reason));
    }
    var gate = try dispatch.Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 13 });
    try gate.reconcile(try gate.beforeSend(), operation.ProviderUsage.init(9, 4, 13).?, false);
    try std.testing.expect(!Trace.stopsChildren(gate.snapshot().halt_reason.?));
    try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    try std.testing.expectEqual(@as(?u128, 13), gate.snapshot().total_actual_tokens);
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

fn receiptFixture(call: usize, byte: u8) Receipt {
    return .{
        .call = call,
        .origin = .{ .request = .{ .value = call }, .attempt = .{ .value = 1 } },
        .purpose = .initial_generation,
        .owner_kind = .reference_chunk,
        .experiment_send = .{ .ordinal = call },
        .request_step = "native-upstream-request",
        .context_sha256 = @splat(byte),
        .request_sha256 = @splat(byte),
        .response_sha256 = @splat(byte),
        .model_output_sha256 = @splat(byte),
        .raw_response_available = true,
        .model_output_available = true,
    };
}

test "capture receipt hash serialization always emits exact closed byte arrays" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const strict = @import("../../../src/domain/strict_json.zig");
    for ([_]u8{ 0, 1, 'a', 127, 255 }) |byte| {
        const original = receiptFixture(1, byte);
        const bytes = try std.json.Stringify.valueAlloc(a, original, .{});
        const decoded = try strict.decode(Receipt, a, bytes, .{ .maximum_depth = 32 });
        try std.testing.expectEqualSlices(u8, &original.context_sha256, &decoded.context_sha256);
        try std.testing.expectEqualSlices(u8, &original.request_sha256, &decoded.request_sha256);
        try std.testing.expectEqualSlices(u8, &original.response_sha256.?, &decoded.response_sha256.?);
        try std.testing.expectEqualSlices(u8, &original.model_output_sha256.?, &decoded.model_output_sha256.?);
        var parsed = try strict.parse(a, bytes, .{ .maximum_depth = 32 }, false, null);
        defer parsed.deinit();
        inline for (.{ "context_sha256", "request_sha256", "response_sha256", "model_output_sha256" }) |field| {
            try std.testing.expect(parsed.value.object.get(field).? == .array);
        }
        parsed.value.object.getPtr("context_sha256").?.* = .{ .string = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" };
        try std.testing.expectError(error.InvalidJsonDocument, strict.decode(Receipt, a, try std.json.Stringify.valueAlloc(a, parsed.value, .{}), .{ .maximum_depth = 32 }));
    }
}

fn appendReceiptFixture(log: *CaptureLog, call: usize) !void {
    try log.records.ensureUnusedCapacity(log.allocator, 1);
    var receipt = receiptFixture(call, 'a');
    receipt.request_step = try log.allocator.dupe(u8, receipt.request_step);
    log.records.appendAssumeCapacity(receipt);
}

test "native receipt failure proofs preserve intermediate upstream rejections after later summaries change" {
    var log: CaptureLog = .init(std.testing.allocator);
    defer log.deinit();
    for (1..4) |call| try appendReceiptFixture(&log, call);
    var report: c.Report = .{ .schema = .@"spec-e2e-report/v11", .started_at_utc = "", .status = .workflow_failed };
    report.last_protocol_rejection = .{ .call = 1, .origin = log.records.items[0].origin, .reason = "MOCK initial schema rejection", .json_error = null, .schema_error = .{ .reason = .missing_required_property, .path = "/claims" } };
    try log.observeRejections(report);
    report.last_protocol_rejection = null;
    report.last_provider_rejection = .{ .call = 2, .origin = log.records.items[1].origin, .reason = "MOCK middle provider rejection", .content = .missing_final_text };
    try log.observeRejections(report);
    report.last_provider_rejection = null;
    report.last_protocol_rejection = .{ .call = 3, .origin = log.records.items[2].origin, .reason = "MOCK final JSON rejection", .json_error = .{ .reason = .UnexpectedToken }, .schema_error = null };
    try log.observeRejections(report);
    try std.testing.expect(log.records.items[0].mechanical_rejection.? == .protocol);
    try std.testing.expect(log.records.items[1].mechanical_rejection.? == .provider);
    try std.testing.expect(log.records.items[2].mechanical_rejection.? == .protocol);
    try std.testing.expectEqualStrings("MOCK middle provider rejection", log.records.items[1].mechanical_rejection.?.provider.reason);
    try std.testing.expectEqualStrings("/claims", log.records.items[0].mechanical_rejection.?.protocol.schema_error.?.path);
    // A later projection may reference a pre-send failure with no physical
    // receipt; it must not attach that rejection to another actual exchange.
    report.last_protocol_rejection.?.origin.request.value = 99;
    try log.observeRejections(report);
    try std.testing.expectEqual(@as(usize, 3), log.records.items.len);
    try std.testing.expectEqual(@as(usize, 3), log.records.items[2].mechanical_rejection.?.protocol.call);
}

fn rejectionAllocationScenario(a: std.mem.Allocator) !void {
    var log: CaptureLog = .init(a);
    defer log.deinit();
    try appendReceiptFixture(&log, 1);
    const report: c.Report = .{ .schema = .@"spec-e2e-report/v11", .started_at_utc = "", .status = .workflow_failed, .last_protocol_rejection = .{
        .call = 1,
        .origin = log.records.items[0].origin,
        .reason = "MOCK malformed JSON",
        .json_error = .{ .reason = .DuplicateField, .context = .{ .path = "/claims", .key = "kind", .first_occurrence = null, .repeated_occurrence = null } },
        .composition_error = .{ .fields = &.{
            .{ .field = .ac_given, .path = "/records/0/given", .issue = .{ .reason = .reference_only, .first_node = 0, .last_node = 0, .field = .ac_given } },
            .{ .field = .spec_goal, .path = "/goal", .issue = .{ .reason = .prohibited_exact, .first_node = 1, .last_node = 1, .field = .spec_goal } },
        } },
        .schema_error = .{ .reason = .unknown_property, .path = "/unknown" },
    } };
    try log.observeRejections(report);
}

test "native receipt failure proof ownership cleans up every allocation failure" {
    try @import("../../../src/test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(rejectionAllocationScenario, .{});
}
