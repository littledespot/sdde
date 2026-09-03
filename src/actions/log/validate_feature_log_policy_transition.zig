const std = @import("std");
const binding = @import("../../domain/feature_log_binding.zig");
const log_policy = @import("../../domain/log_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{InvalidFeatureLogPolicyTransition};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-feature-log-policy-transition@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .logging_policy },
        .produces = &.{.feature_log_policy_transition_authority},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        current_binding: *const binding.ValidatedFeatureLogBinding,
        current_policy: *const log_policy.CompiledLoggingPolicy,
        next_binding: *const binding.ValidatedFeatureLogBinding,
        next_policy: *const log_policy.CompiledLoggingPolicy,
    ) Error!void {
        if (!std.mem.eql(u8, current_binding.featureId().bytes, next_binding.featureId().bytes) or
            !std.mem.eql(u8, current_binding.runId().bytes, next_binding.runId().bytes) or
            std.mem.eql(u8, current_binding.bindingId().bytes, next_binding.bindingId().bytes) or
            std.mem.eql(u8, current_binding.logPolicyId().bytes, next_binding.logPolicyId().bytes) or
            !log_policy.transitionCompatible(current_policy.*, next_policy.*))
        {
            return error.InvalidFeatureLogPolicyTransition;
        }
    }
};

test "policy transitions require a new compatible binding in the same run" {
    const telemetry = @import("../../domain/telemetry.zig");
    const current_candidate: binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("POLICY-1").?,
        .binding_id = telemetry.Identifier.validate("BINDING-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
    };
    const next_candidate: binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("POLICY-2").?,
        .binding_id = telemetry.Identifier.validate("BINDING-2").?,
        .run_id = current_candidate.run_id,
        .feature_id = current_candidate.feature_id,
    };
    const current_owner = try binding.createValidated(std.testing.allocator, current_candidate);
    defer binding.deinitOwner(current_owner);
    const next_owner = try binding.createValidated(std.testing.allocator, next_candidate);
    defer binding.deinitOwner(next_owner);
    const current_policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .info, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var next_policy = current_policy;
    next_policy.level.threshold = .debug;
    try (Action{}).execute(
        binding.binding(current_owner),
        &current_policy,
        binding.binding(next_owner),
        &next_policy,
    );

    try std.testing.expectError(
        error.InvalidFeatureLogPolicyTransition,
        (Action{}).execute(
            binding.binding(current_owner),
            &current_policy,
            binding.binding(current_owner),
            &next_policy,
        ),
    );
    next_policy.max_segments -= 1;
    try std.testing.expectError(
        error.InvalidFeatureLogPolicyTransition,
        (Action{}).execute(
            binding.binding(current_owner),
            &current_policy,
            binding.binding(next_owner),
            &next_policy,
        ),
    );
}
