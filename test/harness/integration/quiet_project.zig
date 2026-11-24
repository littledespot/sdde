//! A case's configuration mirrors every feature-log row to the real stderr. The tests that run a case read the
//! rows from the feature log, and the mirror would bury the result of a passing run in thousands of them. The
//! captured sources, which the tests verify against the repository, stay as they were.
const std = @import("std");
const fixture = @import("../e2e/fixture.zig");

pub fn materialize(io: std.Io, project: std.Io.Dir, captured: fixture.Capture) !void {
    try fixture.materialize(io, project, captured);
    const quiet = try std.mem.replaceOwned(u8, std.testing.allocator, captured.config, "\"console\": true", "\"console\": false");
    defer std.testing.allocator.free(quiet);
    try project.writeFile(io, .{ .sub_path = ".sddtoolkit.json", .data = quiet });
}
