test {
    _ = @import("workflow_operation_registry_test.zig");
    _ = @import("pipeline_data_test.zig");
    _ = @import("pipeline_native_value_test.zig");
    _ = @import("toolchain_workflow_test.zig");
    _ = @import("reference_preflight_test.zig");
    _ = @import("feature_directory_test.zig");
    _ = @import("application/specify_invocation_orchestrator.zig");
    _ = @import("workflow_value_flow_test.zig");
    _ = @import("feature_log_runtime_test.zig");
    _ = @import("workflow_registry_test.zig");
    _ = @import("workflow_execution_test.zig");
    _ = @import("workflow_definition_test.zig");
    _ = @import("application/feature_log_policy_transition_coordinator.zig");
    _ = @import("application/feature_log_policy_transition_runner.zig");
    _ = @import("application/feature_log_retention_coordinator.zig");
    _ = @import("application/feature_log_runtime_lifecycle.zig");
    _ = @import("application/feature_log_finalization_coordinator.zig");
    _ = @import("application/feature_log_finalization_runner.zig");
    _ = @import("actions/log/build_feature_log_retention_authorization.zig");
    _ = @import("adapters/system/trusted_log_clock.zig");
    _ = @import("adapters/system/log_output.zig");
}
