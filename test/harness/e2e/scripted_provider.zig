//! The E2E substitution is confined to the provider boundary. Selection,
//! bootstrap, YAML transitions, validation and filesystem operations stay real.
const std = @import("std");
const api = @import("../../../src/ports/llm_provider_interface.zig");
const operation = @import("../../../src/domain/llm_provider_operation.zig");
const binding = @import("../../../src/domain/llm_provider_binding.zig");
const fake = @import("../../../src/adapters/provider/fake_llm_provider.zig");
const scripted = @import("../../../src/test_fixtures/spec_generation_responses.zig");

pub const Provider = struct {
    allocator: std.mem.Allocator,
    invocation: *@import("../../../src/composition/engine_invocation.zig").Assembly,
    calls: usize = 0,

    pub fn port(self: *Provider) api.LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .invoke = invoke, .count_input_tokens = count } };
    }

    fn invoke(context: *api.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, authorization: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) api.Error!operation.ProviderInvocationObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        self.calls += 1;
        var base = self.makeFake() orelse return .{ .failed = rejected(invoked.id) };
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const runner = &self.invocation.pipeline_runner.?;
        const body = scripted.build(arena.allocator(), .{ .slots = runner.envelope.slots }, .{}) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => .{ .failed = rejected(invoked.id) },
        };
        base.invocation_plan.complete.content = body;
        return base.interface().invoke(selected, request, authorization, invoked);
    }

    fn count(context: *api.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, authorization: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) api.Error!operation.ProviderTokenCountObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        var base = self.makeFake() orelse return .{ .failed = rejected(invoked.id) };
        return base.interface().countInputTokens(selected, request, authorization, invoked);
    }

    fn makeFake(self: *Provider) ?fake.FakeLLMProvider {
        const runner = if (self.invocation.pipeline_runner) |*value| value else return null;
        const accounting = if (runner.model_accounting) |*value| value else return null;
        return .{
            .allocator = self.allocator,
            .authorization_leases = accounting.authorization_leases.port(runner.provider_clock.?, runner.runtime),
            .count_plan = .{ .counted = 0 },
            .invocation_plan = .{ .complete = .{ .content = "", .input_tokens = 5, .output_tokens = 2 } },
        };
    }
};

fn rejected(id: operation.ProviderOperationId) operation.ProviderFailure {
    return .{ .operation_id = id, .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent };
}
