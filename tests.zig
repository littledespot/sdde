//! Unit test discovery. Import shared sources in one module so their
//! tests execute once even when both the engine and harness depend on them.
test {
    _ = @import("src/root.zig");
    _ = @import("src/architecture_test.zig");
    _ = @import("harness.zig");
    _ = @import("build/zig_version.zig");
    _ = @import("build/provenance.zig");
    _ = @import("code_heuristics.zig");
    _ = @import("src/workflow_repair_retry_test.zig");
    _ = @import("src/test_fixtures/scenario_timing.zig");
    _ = @import("src/adapters/provider/native_model_http.zig");
    _ = @import("test/harness/attribution/tests.zig");
    _ = @import("test/harness/exact_value/recognition.zig");
    _ = @import("test/harness/exact_value/recognition_tests.zig");
    _ = @import("test/harness/exact_value/control_tests.zig");
    _ = @import("test/harness/exact_value/corpus_tests.zig");
    _ = @import("test/harness/exact_value/prompt_capture.zig");
    _ = @import("test/harness/exact_value/binding_experiment.zig");
    _ = @import("test/harness/exact_value/boundary_experiment_tests.zig");
}
