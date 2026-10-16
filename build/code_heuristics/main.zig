//! Offline development tool. No workflow execution or provider capability.
const std = @import("std");
const inventory = @import("inventory.zig");
const report = @import("report.zig");
const files = @import("../../src/adapters/filesystem/file_access.zig");

const help =
    \\Usage: zig build code-heuristics
    \\Write an advisory repository-wide Zig code report to zig-out/code-heuristics/report.md and report.json (under --prefix when supplied).
    \\The development executable takes one output directory; --help prints this text.
    \\
;

pub fn main(init: std.process.Init) !void {
    command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Code heuristics report failed: {s}.\n", .{@errorName(err)}));
        std.process.exit(1);
    };
}

fn command(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const output = try parse(args[1..]);
    if (output == null) return std.Io.File.stdout().writeStreamingAll(init.io, help);
    const measurements = try inventory.capture(a, init.io, .cwd());
    const result = try report.build(a, measurements);
    const markdown = try report.markdown(a, result);
    const json = try std.json.Stringify.valueAlloc(a, result, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().createDirPath(init.io, output.?);
    const directory = try std.Io.Dir.cwd().openDir(init.io, output.?, .{ .follow_symlinks = false });
    defer directory.close(init.io);
    try files.replace(init.io, a, directory, "report.md", .any, markdown);
    try files.replace(init.io, a, directory, "report.json", .any, json);
    try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Code heuristics: {d} Zig files; {s}/report.md and {s}/report.json\n", .{ measurements.len, output.?, output.? }));
}

fn parse(args: []const []const u8) !?[]const u8 {
    if (args.len != 1) return error.InvalidArguments;
    if (std.mem.eql(u8, args[0], "--help")) return null;
    if (args[0].len == 0 or std.mem.startsWith(u8, args[0], "-") or std.mem.indexOfScalar(u8, args[0], 0) != null) return error.InvalidArguments;
    return args[0];
}

test "report CLI requires one output directory or help" {
    try std.testing.expectEqualStrings("zig-out/code-heuristics", (try parse(&.{"zig-out/code-heuristics"})).?);
    try std.testing.expectEqualStrings("/tmp/report", (try parse(&.{"/tmp/report"})).?);
    try std.testing.expectEqual(null, try parse(&.{"--help"}));
    for ([_][]const []const u8{ &.{}, &.{ "zig-out", "extra" }, &.{"--unknown"}, &.{""}, &.{"out\x00put"} }) |args| {
        try std.testing.expect(if (parse(args)) |_| false else |_| true);
    }
}

test {
    _ = @import("inventory.zig");
    _ = @import("analyze.zig");
    _ = @import("model.zig");
    _ = @import("report.zig");
}
