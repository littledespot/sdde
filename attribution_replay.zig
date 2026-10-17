//! Offline preparation and measurement; this executable has no dispatch path.
pub const live_model_connections = false;
pub const main = @import("test/harness/attribution/cli.zig").main;

test {
    _ = @import("test/harness/attribution/tests.zig");
}
