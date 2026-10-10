//! Offline workflow and Spec harness integration tests.
test {
    _ = @import("test/integration/workflow_tests.zig");
    _ = @import("test/harness/integration/tests.zig");
}
