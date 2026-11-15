//! Apply an adjudication record's rubric judgment to the retained native E2E report
//! --report names.
const std = @import("std");
const files = @import("files.zig");
const adjudication = @import("adjudication.zig");
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
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build adjudicate-spec -- --report <relative-e2e-report.json> --review <relative-adjudication-record.json> --output <existing-relative-directory>\nOffline only. Validates a rubric judgment record against the retained report --report names. Creates a new adjudication directory holding copies of both and the decision; never changes the workflow or original report. Exit 0 accepted, 1 rejected/error, 2 unresolved.\n");
        return;
    }
    const options = parse(args.items) catch return fail(io, "Invalid arguments; use --help. No API call is possible.");
    const original = files.read(io, a, .cwd(), options.report) catch return fail(io, "Original report unavailable.");
    const review = files.read(io, a, .cwd(), options.review) catch return fail(io, "Adjudication record unavailable.");
    var rejection: ?adjudication.Rejection = null;
    const result = adjudication.evaluateReporting(a, review, original, &rejection) catch |err| return fail(io, try std.fmt.allocPrint(a, "Adjudication rejected: {s}{s}.", .{ @errorName(err), try rejectionDetail(a, rejection) }));
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
    try output.write(io, dir, "adjudication-record.json", review);
    try output.write(io, dir, "report.json", try std.json.Stringify.valueAlloc(a, result, .{ .whitespace = .indent_2 }));
    try output.write(io, dir, "report.md", try markdown(a, result));
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Acceptance: {s}\nAdjudication: {s}/{s}/report.md\n", .{ @tagName(result.acceptance), options.output, name }));
    switch (result.acceptance) {
        .passed => {},
        .failed => std.process.exit(1),
        .unresolved => std.process.exit(2),
    }
}
/// " (stage ...)" naming the stage that rejected and, for a judgment, its reason, criterion, evidence
/// entry and document, so a rejected record says what to look at. Empty when no stage was recorded.
fn rejectionDetail(a: std.mem.Allocator, rejection: ?adjudication.Rejection) ![]const u8 {
    const found = rejection orelse return "";
    const diagnostic = found.judgment orelse return std.fmt.allocPrint(a, " (stage {s})", .{@tagName(found.stage)});
    var out: std.Io.Writer.Allocating = .init(a);
    try out.writer.print(" (stage {s}: {s}", .{ @tagName(found.stage), @tagName(diagnostic.reason) });
    if (diagnostic.criterion_id) |criterion| try out.writer.print(", criterion {s}", .{criterion});
    if (diagnostic.evidence_index) |index| try out.writer.print(", evidence {d}", .{index});
    if (diagnostic.document_id) |document| try out.writer.print(", document {s}", .{document});
    try out.writer.writeAll(")");
    return out.toOwnedSlice();
}

fn markdown(a: std.mem.Allocator, result: adjudication.Adjudication) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    defer out.deinit();
    try out.writer.print("# Specification adjudication\n\nAcceptance: **{s}**", .{@tagName(result.acceptance)});
    switch (result.acceptance) {
        .passed => {},
        .failed => |reason| try out.writer.print(" ({s})", .{@tagName(reason)}),
        .unresolved => |reason| try out.writer.print(" ({s})", .{@tagName(reason)}),
    }
    try out.writer.writeAll("\n\nReviewer: ");
    try @import("report.zig").escape(&out.writer, result.reviewer);
    try out.writer.writeAll("\n\nReviewed UTC: ");
    try @import("report.zig").escape(&out.writer, result.reviewed_at_utc);
    if (result.judgment.score_percent) |score| try out.writer.print("\n\nRubric score: {d:.2}%", .{score});
    for (result.judgment.results) |criterion| {
        try out.writer.writeAll("\n\n- ");
        try @import("report.zig").escape(&out.writer, criterion.criterion_id);
        try out.writer.print(": {s}", .{@tagName(criterion.disposition)});
        if (criterion.score) |score| try out.writer.print(" ({d})", .{score});
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
