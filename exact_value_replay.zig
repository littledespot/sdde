//! Offline prototype only: no provider, workflow continuation or publication.
pub const live_model_connections = false;
pub const main = @import("test/harness/exact_value/cli.zig").main;

test {
    _ = @import("test/harness/exact_value/recognition.zig");
    _ = @import("test/harness/exact_value/recognition_tests.zig");
    _ = @import("test/harness/exact_value/control_tests.zig");
    _ = @import("test/harness/exact_value/corpus_tests.zig");
    _ = @import("test/harness/exact_value/prompt_capture.zig");
}
