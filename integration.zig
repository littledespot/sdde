//! Offline workflow and Spec harness integration tests.
test {
    _ = @import("test/integration/workflow_tests.zig");
    _ = @import("test/integration/generation_protocol_tests.zig");
    _ = @import("test/integration/provider_compatibility_tests.zig");
    _ = @import("test/integration/baseline_tests.zig");
    _ = @import("test/integration/representation_admission_tests.zig");
    _ = @import("test/integration/insertion_presentation_tests.zig");
    _ = @import("test/integration/exact_value_recognition_tests.zig");
    _ = @import("test/harness/integration/tests.zig");
}
