const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const results = @import("../domain/model_invocation_result.zig");
const data = @import("../domain/pipeline_data.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const identity = @import("../domain/model_request_identity.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
const accounting = @import("workflow_model_accounting.zig");
const authorization = @import("provider_authorization_workflow.zig");
const selection = @import("../domain/workflow_model_invocation.zig");

pub const schema = values.schema(.provider_invocation_result, results.For(.inference).Result, 1, null);
pub const count_schema = values.schema(.provider_token_count_result, results.For(.input_token_count).Result, 1, null);
pub const Invoke = Call(.inference);
pub const Count = Call(.input_token_count);

fn Call(comptime kind: provider.ProviderOperationKind) type {
    const result = results.For(kind);
    const output_schema = if (kind == .inference) schema else count_schema;
    return struct {
        pub const Action = if (kind == .inference) @import("../actions/model/invoke_model.zig").Action else @import("../actions/model/count_model_input_tokens.zig").Action;
        pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
            .id = Action.contract.id,
            .kind = .step,
            .requires = &selection.requires,
            .produces = if (kind == .inference) &selection.produces else &selection.count_produces,
            .outcomes = &.{ .ok, .failed, .cancelled },
            .side_effect = Action.contract.side_effect,
        };
        allocator: std.mem.Allocator,
        // A missing adapter fails closed; production never substitutes a fake.
        action: ?Action = null,

        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            const prepared = request.prepared() orelse return error.OperationExecutionFailed;
            const invoked = (values.read(&input.step.data, accounting.invoked_schema, lifecycle.InvokedOperation) catch return error.OperationExecutionFailed).operation();
            const authorization_result = values.read(&input.step.data, authorization.schema, @import("../domain/provider_authorization_result.zig").Result) catch return error.OperationExecutionFailed;
            const reference = switch (authorization_result.outcome().*) {
                .prepared => |*reference| reference,
                .failed, .cancelled => return error.OperationExecutionFailed,
            };
            const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
            const owner = self.allocator.create(Owner) catch return error.OperationExecutionFailed;
            errdefer self.allocator.destroy(owner);
            const retained = values.retain(input.step.data.slots[@intFromEnum(requests.prepared_schema.key)].?) catch return error.OperationExecutionFailed;
            errdefer values.destroy(retained);
            owner.* = .{ .allocator = self.allocator, .request = retained, .response = result.Owner.init(self.allocator, ledger, invoked.id) catch return error.OperationExecutionFailed };
            const value = values.adopt(self.allocator, output_schema, result.Result, Owner, owner, Owner.view, Owner.destroy, null) catch {
                owner.response.destroy();
                return error.OperationExecutionFailed;
            };
            const outcome: result.Outcome = if (self.action) |action| call: {
                const observed = action.execute(request.binding(), prepared, reference, invoked) catch |err| break :call switch (err) {
                    error.Cancelled => .cancelled,
                    error.OutOfMemory => .allocation_failed,
                };
                break :call .{ .observation = observed };
            } else .{ .observation = .{ .failed = .{ .operation_id = invoked.id, .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } } };
            owner.response.finish(outcome);
            var delta: pipeline.NodeDelta = .{};
            delta.data_writes[@intFromEnum(output_schema.key)] = value;
            return .{ .outcome = statusFor(kind, outcome), .delta = delta };
        }
        const Owner = struct {
            allocator: std.mem.Allocator,
            request: *data.Value,
            response: *result.Owner,
            fn view(self: *const Owner) *const result.Result {
                return self.response.view();
            }
            fn destroy(self: *Owner) void {
                self.response.destroy();
                values.destroy(self.request);
                self.allocator.destroy(self);
            }
        };
    };
}

pub fn status(outcome: results.For(.inference).Outcome) @import("../domain/workflow.zig").OutcomeTag {
    return statusFor(.inference, outcome);
}
pub fn countStatus(outcome: results.For(.input_token_count).Outcome) @import("../domain/workflow.zig").OutcomeTag {
    return statusFor(.input_token_count, outcome);
}
fn statusFor(comptime kind: provider.ProviderOperationKind, outcome: results.For(kind).Outcome) @import("../domain/workflow.zig").OutcomeTag {
    return switch (outcome) {
        .observation => |observation| if (kind == .input_token_count) switch (observation) {
            .counted => .ok,
            .failed => .failed,
        } else switch (observation) {
            .completed => |completed| switch (completed.raw_result) {
                .complete => .ok,
                .stopped => .failed,
            },
            .failed => .failed,
        },
        .cancelled => .cancelled,
        .allocation_failed => .failed,
    };
}
