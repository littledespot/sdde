const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const identity = @import("model_request_identity.zig");

pub fn For(comptime kind: provider.ProviderOperationKind) type {
    return struct {
        pub const Outcome = union(enum) {
            observation: switch (kind) {
                .inference => provider.ProviderInvocationObservation,
                .input_token_count => provider.ProviderTokenCountObservation,
            },
            cancelled,
            allocation_failed,
        };

        /// Owns the untrusted response, not validation evidence or workflow authority.
        pub const Result = opaque {
            pub fn operationId(self: *const Result) provider.ProviderOperationId {
                return storage(self).operation_id;
            }

            pub fn outcome(self: *const Result) ?*const Outcome {
                return if (storage(self).outcome) |*value| value else null;
            }
        };

        pub const Owner = struct {
            allocator: std.mem.Allocator,
            requests: *identity.Owner,
            operation_id: provider.ProviderOperationId,
            outcome: ?Outcome = null,

            /// Prepared before the call so retaining its result cannot allocate afterward.
            pub fn init(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger, operation_id: provider.ProviderOperationId) (std.mem.Allocator.Error || identity.Error || error{InvalidInvocationResult})!*Owner {
                if (operation_id.kind != kind or operation_id.model_attempt_ordinal.value == 0 or
                    requests.canonicalRequestId(operation_id.model_request_id) != operation_id.model_request_id) return error.InvalidInvocationResult;
                const retained = try identity.retainLedger(requests);
                errdefer identity.deinitOwner(retained);
                const owner = try allocator.create(Owner);
                owner.* = .{ .allocator = allocator, .requests = retained, .operation_id = operation_id };
                return owner;
            }

            pub fn finish(self: *Owner, outcome: Outcome) void {
                std.debug.assert(self.outcome == null);
                self.outcome = outcome;
            }

            pub fn view(self: *const Owner) *const Result {
                return @ptrCast(self);
            }

            pub fn destroy(self: *Owner) void {
                if (self.outcome) |*outcome| switch (outcome.*) {
                    .observation => |*observation| if (kind == .inference) observation.deinit(),
                    .cancelled, .allocation_failed => {},
                };
                identity.deinitOwner(self.requests);
                self.allocator.destroy(self);
            }
        };

        fn storage(result: *const Result) *const Owner {
            return @ptrCast(@alignCast(result));
        }
    };
}
