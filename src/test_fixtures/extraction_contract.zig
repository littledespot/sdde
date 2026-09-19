//! Small compiled-authority fixture for persisted state tests. Production lookup
//! is supplied by the validated registry, never by persisted metadata.
const std = @import("std");
const c = @import("../domain/workflow_compilation.zig");
const w = @import("../domain/workflow.zig");
const source = @import("../ports/workflow_contract_source.zig");
pub const Fixture = struct {
    authority: c.SemanticAuthority,
    pub fn init(a: std.mem.Allocator) !Fixture {
        var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema = try parser.compiler().compile(a, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\",\"maxLength\":100}},\"required\":[\"value\"],\"additionalProperties\":false}");
        const plan = try parser.compiler().compileComposition(a, "{\"schema\":\"json-composition/v1\",\"result\":\"result\",\"parts\":{\"content\":{\"paths\":[\"/value\"]}}}", schema);
        const resources = try a.dupe(c.CompiledResource, &.{ .{ .id = .{ .bytes = "result" }, .content = .{ .result_schema = schema } }, .{ .id = .{ .bytes = "parts" }, .content = .{ .json_composition = plan } } });
        const steps = try a.alloc(c.CompiledStep, 7);
        const names = [_][]const u8{ "init", "request", "close", "retain", "assemble", "validate", "collect" };
        for (steps, names) |*step, name| step.* = .{ .id = .{ .bytes = name }, .operation_id = .{ .bytes = name }, .parameters = &.{}, .requires = &.{}, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{.ok}, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
        steps[0].parameters = &.{.{ .id = .{ .bytes = "composition" }, .value = .{ .resource = .{ .bytes = "parts" } } }};
        steps[0].produces = &.{.json_composition};
        steps[1].parameters = &.{.{ .id = .{ .bytes = "composition-part" }, .value = .{ .string = "content" } }};
        steps[1].produces = &.{ .assigned_model_request, .prepared_model_request, .terminal_provider_operation, .model_payload_schema_result };
        steps[1].replaces = &.{.model_request_identity_ledger};
        steps[2].requires = &.{.terminal_provider_operation};
        steps[2].replaces = &.{.model_request_identity_ledger};
        steps[3].requires = &.{ .prepared_model_request, .model_payload_schema_result };
        steps[3].replaces = &.{.json_composition};
        steps[4].produces = &.{.assembled_json};
        steps[4].invalidates = &.{.json_composition};
        steps[5].requires = &.{.assembled_json};
        steps[5].produces = &.{.validated_assembled_json};
        steps[6].requires = &.{ .assembled_json, .validated_assembled_json };
        steps[6].replaces = &.{.reference_extraction_progress};
        steps[6].invalidates = &.{ .assembled_json, .validated_assembled_json };
        const edges = try a.alloc(w.Transition, steps.len);
        for (edges, 0..) |*edge, i| edge.* = .{ .from = steps[i].id, .outcome = .ok, .target = if (i + 1 < steps.len) .{ .step = steps[i + 1].id } else .{ .terminal = .ok } };
        return .{ .authority = .{ .workflow_id = .{ .bytes = "fixture-extraction" }, .workflow_version = 1, .invocation_operation_id = .{ .bytes = "fixture-input" }, .policy_profile_id = .{ .bytes = "fixture@1" }, .total_model_token_budget = .{ .value = 1000 }, .start_step_id = steps[0].id, .invocation_outputs = &.{ .model_request_identity_ledger, .reference_extraction_progress }, .resources = resources, .steps = steps, .transitions = edges, .maximum_step_executions = steps.len } };
    }
    pub fn port(self: *const Fixture) source.Source {
        return .{ .context = @ptrCast(self), .resolve_fn = resolve };
    }
    fn resolve(context: *const source.Context, id: w.WorkflowId) ?*const c.SemanticAuthority {
        const self: *const Fixture = @ptrCast(@alignCast(context));
        return if (std.mem.eql(u8, id.bytes, self.authority.workflow_id.bytes)) &self.authority else null;
    }
};
