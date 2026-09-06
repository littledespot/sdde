const std = @import("std");
const runner_module = @import("../application/workflow_pipeline_runner.zig");
const bindings = @import("model_request_operations.zig");
const auth = @import("../adapters/provider/bedrock_authorization.zig");
const source = @import("../adapters/system/bedrock_api_key_source.zig");
const http = @import("../adapters/provider/bedrock_http.zig");
const dispatch = @import("../adapters/provider/provider_dispatch.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const binding = @import("../domain/llm_provider_binding.zig");

pub const Assembly = struct {
    environment: ?*const std.process.Environ.Map,
    operations: *bindings.Assembly,
    authorization: auth.Adapter,
    transport: http.Adapter,
    provider: ?dispatch.Dispatch = null,

    pub fn deinit(self: *Assembly) void {
        self.operations.prepare_authorization.action = null;
        self.operations.invoke_model.action = null;
        self.operations.count_model_input.action = null;
        self.authorization.deinit();
    }

    pub fn bind(self: *Assembly, runner: *runner_module.Runner) error{ProviderModelBindingInvalid}!void {
        // Validate selected model bindings through their existing runner/action
        // owner before reading the one permitted environment variable.
        try runner.validateModelBindings();
        var required = false;
        for (runner.selected.graph.authority.steps) |step| {
            for (step.produces) |key| if (key == .provider_authorization_result) {
                required = true;
            };
        }
        if (!required) return;
        std.debug.assert(self.provider == null);
        if (self.environment) |environment| self.authorization.material = source.read(self.authorization.allocator, environment);
        self.provider = .{ .aws_bedrock = .{
            .allocator = self.authorization.allocator,
            .authorization_leases = .{ .context = @ptrCast(runner), .clock = self.transport.clock, .runtime = runner.runtime, .consume_fn = consume },
            .transport = self.transport.port(),
        } };
        self.operations.prepare_authorization.action = .{ .authorization = self.authorization.port() };
        self.operations.invoke_model.action = .{ .provider = self.provider.?.port() };
        self.operations.count_model_input.action = .{ .provider = self.provider.?.port() };
    }
};

fn consume(context: *lease.Context, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, invoked: *const operation.InvokedProviderOperation, now: lease.Error!u64) lease.Error!lease.Capability {
    const runner: *runner_module.Runner = @ptrCast(@alignCast(context));
    const state = if (runner.model_accounting) |*value| value else return error.AuthorizationDenied;
    const port = state.authorization_leases.port(runner.provider_clock.?, runner.runtime);
    return port.consume_fn(port.context, reference, selected, request, invoked, now);
}
