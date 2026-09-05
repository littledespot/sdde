const std = @import("std");
const validation = @import("domain/provider_invocation_validation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const preparation = @import("domain/model_request_preparation.zig");
const compilation = @import("domain/workflow_compilation.zig");
const build_request = @import("actions/model/build_model_request.zig");
const preflight = @import("actions/model/validate_static_model_request_capacity.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const invoke_model = @import("actions/model/invoke_model.zig");
const authorization_fixture = @import("provider_authorization_test_fixture.zig");

pub const Fixture = struct {
    base: authorization_fixture.Fixture,
    resource: compilation.CompiledResource,
    prepared: preparation.Owned,
    authorized: authorization_fixture.Authorized,
    call: validation.Call,
    fake: fake_provider.FakeLLMProvider,

    pub fn init(self: *Fixture, maximum_output_bytes: u32) !void {
        return self.initWithSchema(maximum_output_bytes, null);
    }

    pub fn initWithSchema(self: *Fixture, maximum_output_bytes: u32, schema_bytes: ?[]const u8) !void {
        try self.base.init(std.testing.allocator);
        errdefer self.base.deinit();
        if (schema_bytes) |bytes| {
            var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
            self.base.request.response_schema = try adapter.compiler().compile(self.base.schema_arena.allocator(), bytes);
            self.base.provider_binding.capacity.canonical.maximum_input_bytes = @import("model_contract_test_fixture.zig").capacity.canonical.maximum_input_bytes;
        }
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
        return (invoke_model.Action{ .provider = self.fake.interface() }).execute(&self.base.provider_binding, self.prepared.request, self.authorized.reference, self.authorized.invoked);
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
