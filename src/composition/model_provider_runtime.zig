const std = @import("std");
const runner_module = @import("../application/workflow_pipeline_runner.zig");
const bindings = @import("model_request_operations.zig");
const auth = @import("../adapters/provider/api_key_authorization.zig");
const source = @import("../adapters/system/provider_api_key_source.zig");
const api_key = @import("../adapters/provider/provider_api_key.zig");
const http = @import("../adapters/provider/model_http_exchange.zig");
const model_provider = @import("../adapters/provider/model_provider.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const binding = @import("../domain/llm_provider_binding.zig");

pub const Assembly = struct {
    environment: ?*const std.process.Environ.Map,
    operations: *bindings.Assembly,
    authorization: auth.Adapter,
    transport: http.Adapter,
    provider: ?model_provider.Provider = null,

    pub fn deinit(self: *Assembly) void {
        self.operations.prepare_authorization.action = null;
        self.operations.invoke_model.action = null;
        self.authorization.deinit();
    }

    pub fn bind(self: *Assembly, runner: *runner_module.Runner) error{ProviderModelBindingInvalid}!void {
        // Validate selected model bindings through their existing runner/action
        // owner before reading any permitted environment variable.
        try runner.validateModelBindings();
        var required = false;
        for (runner.selected.graph.authority.steps) |step| {
            for (step.produces) |key| if (key == .provider_authorization_result) {
                required = true;
            };
        }
        if (!required) return;
        std.debug.assert(self.provider == null);
        // One exact variable per family the selected slots bind (ADR 0028). A
        // missing key fails that family's authorization; nothing else checks it.
        const families = try runner.selectedProviderFamilies();
        if (self.environment) |environment| for (std.enums.values(api_key.Family)) |family| {
            if (families.contains(family.configSchema())) self.authorization.materials.set(family, source.read(self.authorization.allocator, environment, family));
        };
        self.provider = .{
            .allocator = self.authorization.allocator,
            .authorization_leases = .{ .context = @ptrCast(runner), .clock = self.transport.clock, .runtime = runner.runtime, .consume_fn = consume },
            .transport = self.transport.port(),
            .capture = runner.model_capture.port(),
        };
        self.operations.prepare_authorization.action = .{ .authorization = self.authorization.port() };
        self.operations.invoke_model.action = .{ .provider = self.provider.?.port() };
    }
};

fn consume(context: *lease.Context, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, invoked: *const operation.InvokedProviderOperation, now: lease.Error!u64) lease.Error!lease.Capability {
    const runner: *runner_module.Runner = @ptrCast(@alignCast(context));
    const state = if (runner.model_accounting) |*value| value else return error.AuthorizationDenied;
    const port = state.authorization_leases.port(runner.provider_clock.?, runner.runtime);
    return port.consume_fn(port.context, reference, selected, request, invoked, now);
}
