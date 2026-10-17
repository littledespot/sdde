//! Apply a human's bound rubric judgment to one retained native E2E report.
const std = @import("std");
const files = @import("files.zig");
const human = @import("human_adjudication.zig");
const directories = @import("../../src/adapters/filesystem/directory_access.zig");
const output = @import("output.zig");

pub const Options = struct { report: []const u8, review: []const u8, output: []const u8 };
pub fn parse(args: []const []const u8) error{InvalidArguments}!Options {
    var report: ?[]const u8 = null;
    var review: ?[]const u8 = null;
    var destination: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return error.InvalidArguments;
        @import("contracts.zig").path(args[i + 1]) catch return error.InvalidArguments;
        const slot = if (std.mem.eql(u8, args[i], "--report")) &report else if (std.mem.eql(u8, args[i], "--review")) &review else if (std.mem.eql(u8, args[i], "--output")) &destination else return error.InvalidArguments;
        if (slot.* != null) return error.InvalidArguments;
        slot.* = args[i + 1];
    }
    return .{ .report = report orelse return error.InvalidArguments, .review = review orelse return error.InvalidArguments, .output = destination orelse return error.InvalidArguments };
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, a);
    defer it.deinit();
    _ = it.skip();
    var args: std.ArrayList([]const u8) = .empty;
    while (it.next()) |arg| try args.append(a, arg);
    if (args.items.len == 1 and std.mem.eql(u8, args.items[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build adjudicate-spec -- --report <relative-e2e-report.json> --review <relative-human-review.json> --output <existing-relative-directory>\nOffline only. Validates a human rubric judgment bound to the exact retained report. Creates a new adjudication directory; never changes the workflow or original report. Exit 0 accepted, 1 rejected/error, 2 unresolved.\n");
        return;
    }
    const options = parse(args.items) catch return fail(io, "Invalid arguments; use --help. No API call is possible.");
    const original = files.read(io, a, .cwd(), options.report) catch return fail(io, "Original report unavailable.");
    const review = files.read(io, a, .cwd(), options.review) catch return fail(io, "Human review unavailable.");
    const result = human.evaluate(a, review, original) catch |err| return fail(io, try std.fmt.allocPrint(a, "Adjudication rejected: {s}.", .{@errorName(err)}));
    const parent = directories.open(io, .cwd(), options.output) catch return fail(io, "Output must be an existing safe directory.");
    defer parent.close(io);
    var random: [16]u8 = undefined;
    try io.randomSecure(&random);
    const name = try std.fmt.allocPrint(a, "adjudication-{s}", .{std.fmt.bytesToHex(random, .lower)});
    try parent.createDir(io, name, .default_dir);
    const dir = try directories.open(io, parent, name);
    defer dir.close(io);
    // Retain the exact authority inputs alongside their deterministic projection.
    try output.write(io, dir, "original-report.json", original);
    try output.write(io, dir, "human-review.json", review);
    try output.write(io, dir, "report.json", try std.json.Stringify.valueAlloc(a, result, .{ .whitespace = .indent_2 }));
    try output.write(io, dir, "report.md", try markdown(a, result));
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Human acceptance: {s}\nAdjudication: {s}/{s}/report.md\n", .{ @tagName(result.acceptance), options.output, name }));
    switch (result.acceptance) {
        .passed => {},
        .failed => std.process.exit(1),
        .unresolved => std.process.exit(2),
    }
}
fn markdown(a: std.mem.Allocator, result: human.Adjudication) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try out.writer.print("# Human specification adjudication\n\nAcceptance: **{s}**", .{@tagName(result.acceptance)});
    switch (result.acceptance) {
        .passed => {},
        .failed => |reason| try out.writer.print(" ({s})", .{@tagName(reason)}),
        .unresolved => |reason| try out.writer.print(" ({s})", .{@tagName(reason)}),
    }
    try out.writer.print("\n\nOriginal report SHA-256: `{s}`\n\nHuman review SHA-256: `{s}`\n\nReviewer: ", .{ result.original_report_sha256, result.review_sha256 });
    try @import("report.zig").escape(&out.writer, result.reviewer orelse "pending");
    try out.writer.writeAll("\n\nReviewed UTC: ");
    try @import("report.zig").escape(&out.writer, result.reviewed_at_utc orelse "pending");
    if (result.human_judgment) |judgment| {
        if (judgment.score_percent) |score| try out.writer.print("\n\nHuman rubric score: {d:.2}%", .{score});
        for (judgment.results) |criterion| {
            try out.writer.writeAll("\n\n- ");
            try @import("report.zig").escape(&out.writer, criterion.criterion_id);
            try out.writer.print(": {s}", .{@tagName(criterion.disposition)});
            if (criterion.score) |score| try out.writer.print(" ({d})", .{score});
        }
    }
    try out.writer.writeAll("\n\nThis is development acceptance. It does not change production workflow authority.\n");
    return out.toOwnedSlice();
}
fn fail(io: std.Io, message: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, message);
    try std.Io.File.stderr().writeStreamingAll(io, "\n");
    std.process.exit(1);
}

test "adjudication command requires exact safe explicit inputs and has no live option" {
    const options = try parse(&.{ "--report", "run/report.json", "--review", "review.json", "--output", "results" });
    try std.testing.expectEqualStrings("run/report.json", options.report);
    for ([_][]const []const u8{
        &.{},
        &.{"--live"},
        &.{ "--report", "../report.json", "--review", "review.json", "--output", "results" },
        &.{ "--report", "report.json", "--report", "other.json", "--review", "review.json", "--output", "results" },
    }) |args| try std.testing.expectError(error.InvalidArguments, parse(args));
}
