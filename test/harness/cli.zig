//! Explicit development invocation. Supplied artifacts never imply engine success.
const std = @import("std");
const c = @import("contracts.zig");
const files = @import("files.zig");
const wire = @import("openai.zig");
const http = @import("http.zig");
const reports = @import("report.zig");
const directories = @import("../../src/adapters/filesystem/directory_access.zig");
pub const Options = struct { case: []const u8, spec: []const u8, config: []const u8, output: []const u8 };
pub fn parse(args: []const []const u8) error{InvalidArguments}!Options {
    var selected: ?[]const u8 = null;
    var spec: ?[]const u8 = null;
    var config: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var live = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const name = args[index];
        if (std.mem.eql(u8, name, "--live")) {
            if (live) return error.InvalidArguments;
            live = true;
            continue;
        }
        if (index + 1 == args.len) return error.InvalidArguments;
        const value = args[index + 1];
        c.path(value) catch return error.InvalidArguments;
        const slot = if (std.mem.eql(u8, name, "--case")) &selected else if (std.mem.eql(u8, name, "--spec")) &spec else if (std.mem.eql(u8, name, "--config")) &config else if (std.mem.eql(u8, name, "--output")) &output else return error.InvalidArguments;
        if (slot.* != null) return error.InvalidArguments;
        slot.* = value;
        index += 1;
    }
    if (!live) return error.InvalidArguments;
    return .{ .case = selected orelse return error.InvalidArguments, .spec = spec orelse return error.InvalidArguments, .config = config orelse return error.InvalidArguments, .output = output orelse return error.InvalidArguments };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const a = init.arena.allocator();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, a);
    defer iterator.deinit();
    _ = iterator.skip();
    var args: std.ArrayList([]const u8) = .empty;
    while (iterator.next()) |arg| try args.append(a, arg);
    if (args.items.len == 1 and std.mem.eql(u8, args.items[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build evaluate-spec -- --case <relative-json> --spec <relative-md> --config <relative-json> --output <existing-relative-directory> --live\nAll paths are relative to the current directory. Live execution sends source/spec/rubric to OpenAI and may incur charges. OPENAI_API_KEY is required.\n");
        return;
    }
    const options = parse(args.items) catch return fail(io, "Invalid arguments; use --help. No API call made.");
    const config_bytes = files.read(io, a, .cwd(), options.config) catch return fail(io, "Evaluator configuration is unavailable. No API call made.");
    const config = wire.parseConfig(a, config_bytes) catch return fail(io, "Invalid evaluator configuration. No API call made.");
    const key = init.environ_map.get("OPENAI_API_KEY") orelse return fail(io, "OPENAI_API_KEY is missing. No API call made.");
    if (!http.validKey(key)) return fail(io, "OPENAI_API_KEY is invalid. No API call made.");
    var random: [16]u8 = undefined;
    try io.randomSecure(&random);
    const id = try std.fmt.allocPrint(a, "eval-{s}", .{std.fmt.bytesToHex(random, .lower)});
    const inputs = files.capture(io, a, .cwd(), options.case, options.spec, id, .{
        .origin = .supplied,
        .workflow_status = .not_run,
        .execution_id = null,
        .provider = null,
        .model = null,
    }) catch return fail(io, "Invalid or unavailable case, rubric, source or specification. No API call made.");
    const output = directories.open(io, .cwd(), options.output) catch return fail(io, "Output must be an existing safe directory. No API call made.");
    defer output.close(io);
    // Exclusive new reports cannot overwrite source/spec/clarification files.
    const json_name = try std.fmt.allocPrint(a, "{s}.json", .{id});
    const md_name = try std.fmt.allocPrint(a, "{s}.md", .{id});
    const json_file = output.createFile(io, json_name, .{ .exclusive = true, .permissions = .fromMode(0o600) }) catch return fail(io, "Cannot create a new report. No API call made.");
    defer json_file.close(io);
    const md_file = output.createFile(io, md_name, .{ .exclusive = true, .permissions = .fromMode(0o600) }) catch return fail(io, "Cannot create the report view. No API call made; an empty JSON report may remain.");
    defer md_file.close(io);
    var adapter: http.Adapter = .{ .io = io, .api_key = key };
    const result = @import("evaluate.zig").run(io, a, adapter.port(), config, inputs) catch return fail(io, "Evaluator aborted; reserved report files may be incomplete. No quality result is available.");
    try json_file.writeStreamingAll(io, try reports.json(a, result));
    try json_file.sync(io);
    try md_file.writeStreamingAll(io, try reports.markdown(a, result));
    try md_file.sync(io);
    const message = try std.fmt.allocPrint(a, "Evaluation report: {s}/{s}\n", .{ options.output, md_name });
    try std.Io.File.stdout().writeStreamingAll(io, message);
    switch (result.outcome) {
        .evaluator_error => std.process.exit(1),
        .evaluated => |value| if (value.assessment != .scored) std.process.exit(2),
    }
}
fn fail(io: std.Io, message: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, message);
    try std.Io.File.stderr().writeStreamingAll(io, "\n");
    std.process.exit(1);
}
