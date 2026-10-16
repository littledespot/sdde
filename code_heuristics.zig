//! Development-only code heuristics report entry point.
pub const main = @import("build/code_heuristics/main.zig").main;

test {
    _ = @import("build/code_heuristics/model.zig");
    _ = @import("build/code_heuristics/analyze.zig");
    _ = @import("build/code_heuristics/report.zig");
    _ = @import("build/code_heuristics/inventory.zig");
    _ = @import("build/code_heuristics/main.zig");
}
