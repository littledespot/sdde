//! Full repository test discovery. Import shared sources in one module so their
//! tests execute once even when both the engine and harness depend on them.
test {
    _ = @import("src/root.zig");
    _ = @import("src/architecture_test.zig");
    _ = @import("harness.zig");
    _ = @import("e2e.zig");
    _ = @import("build/zig_version.zig");
    _ = @import("build/provenance.zig");
    _ = @import("src/workflow_repair_retry_test.zig");
    _ = @import("src/adapters/provider/native_model_http.zig");
}
