const std = @import("std");
const validation = @import("domain/provider_invocation_validation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const preparation = @import("domain/model_request_preparation.zig");
const compilation = @import("domain/workflow_compilation.zig");
const build_request = @import("actions/model/build_model_request.zig");
const preflight = @import("actions/model/validate_static_model_request_capacity.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const authorization_fixture = @import("provider_authorization_test_fixture.zig");

pub const Fixture = struct {
    base: authorization_fixture.Fixture,
    resource: compilation.CompiledResource,
    prepared: preparation.Owned,
    authorized: authorization_fixture.Authorized,
    call: validation.Call,
    fake: fake_provider.FakeLLMProvider,

    pub fn init(self: *Fixture, maximum_output_bytes: u32) !void {
        try self.base.init(std.testing.allocator);
        errdefer self.base.deinit();
        self.base.provider_binding.capacity.canonical.maximum_output_bytes = maximum_output_bytes;
        self.resource = .{ .id = .{ .bytes = "result" }, .content = .{ .result_schema = self.base.request.response_schema } };
        const source = try self.requestSource();
        self.prepared = try (build_request.Action{}).execute(std.testing.allocator, source, self.base.request.content);
        errdefer self.prepared.deinit();
        const validated = try (preflight.Action{}).execute(source, self.prepared.request);
        self.base.request = self.prepared.request.*;
        self.authorized = try self.base.startInference();
        self.call = .{ .preflight = validated, .provider_binding = &self.base.provider_binding, .operations = self.base.ledger(), .operation_id = self.authorized.invoked.id };
        self.fake = .{
            .allocator = std.testing.allocator,
            .authorization_leases = self.base.leasePort(),
            .count_plan = .{ .counted = 0 },
            .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 2 } },
        };
    }

    pub fn deinit(self: *Fixture) void {
        self.prepared.deinit();
        self.base.deinit();
    }

    pub fn response(self: *Fixture) !provider.ProviderInvocationObservation {
        return self.fake.interface().invoke(&self.base.provider_binding, self.prepared.request, self.authorized.reference, self.authorized.invoked);
    }

    pub fn requestSource(self: *Fixture) !preparation.Source {
        const id = self.base.model_request_id;
        return .{
            .request_binding = try self.base.requests.validate(self.base.requests.ledger().?.revision(), id, id.immutable_unit_owner_id, id.model_operation_id, id.purpose),
            .provider_binding = &self.base.provider_binding,
            .request_schema_id = self.base.request.request_schema_id,
            .model_visible_input_id = self.base.request.model_visible_input_id,
            .result_resource = &self.resource,
        };
    }
};
