//! Offline inspection of frozen historical evidence; never sends model requests.
const std = @import("std");
const p = @import("preparation.zig");
const score = @import("scoring.zig");
const strict = @import("../../../src/domain/strict_json.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const files = @import("../files.zig");
const path = @import("../contracts.zig").path;
pub const Options = union(enum) {
    prepare: []const u8,
    validate: []const u8,
    dispatch_request: struct { bundle: []const u8, trial: []const u8, calls: []const u8, output: []const u8 },
    score: struct { bundle: []const u8, receipts: []const u8, output: []const u8 },
};
pub fn parse(args: []const []const u8) !Options {
    if (args.len == 2) {
        try path(args[1]);
        if (std.mem.eql(u8, args[0], "prepare")) return .{ .prepare = args[1] };
        if (std.mem.eql(u8, args[0], "validate")) return .{ .validate = args[1] };
    }
    if (args.len == 5 and std.mem.eql(u8, args[0], "dispatch-request")) {
        inline for (.{ 1, 3, 4 }) |index| try path(args[index]);
        if (args[2].len == 0) return error.InvalidArguments;
        return .{ .dispatch_request = .{ .bundle = args[1], .trial = args[2], .calls = args[3], .output = args[4] } };
    }
    if (args.len == 4 and std.mem.eql(u8, args[0], "score")) {
        inline for (.{ 1, 2, 3 }) |index| try path(args[index]);
        return .{ .score = .{ .bundle = args[1], .receipts = args[2], .output = args[3] } };
    }
    return error.InvalidArguments;
}
const help =
    \\Usage: zig build attribution-replay -- prepare <bundle-directory>
    \\       zig build attribution-replay -- validate <bundle-directory>
    \\       zig build attribution-replay -- dispatch-request <bundle-directory> <trial-id> <debugger-calls.json> <output.json>
    \\       zig build attribution-replay -- score <bundle-directory> <receipts.json> <output.json>
    \\All modes are offline: no credential, HTTP, process or model dispatch capability.
    \\prepare materializes seven frozen debugger edits/provider bodies and 21 ordered trials. Existing files must match exactly. validate proves pins and exact deterministic regeneration.
    \\dispatch-request fails HistoricalDispatchUnsupported: these v5 captures cannot become current requests. A new experiment needs current v6 captures and separate approval.
    \\score retains historical unattempted and rejected denominators and checks immutable records and mechanical composition. It does not assess current B3 admission, semantics or workflow authority.
    \\
;
pub fn main(init: std.process.Init) !void {
    command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Offline attribution command failed: {s}. No model call made.\n", .{@errorName(err)}));
        std.process.exit(1);
    };
}
fn command(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) return std.Io.File.stdout().writeStreamingAll(init.io, help);
    const options = try parse(args[1..]);
    const bundle = try p.prepare(a);
    switch (options) {
        .prepare => |directory| {
            try std.Io.Dir.cwd().createDirPath(init.io, directory);
            for (bundle.artifacts) |artifact| try writeOrCompare(init.io, a, try join(a, directory, artifact.name), artifact.bytes);
        },
        .validate => |directory| try validate(init.io, a, bundle, directory),
        .dispatch_request => |selected| {
            try validate(init.io, a, bundle, selected.bundle);
            const trial = try p.trial(bundle, selected.trial);
            const calls = try p.decodeCalls(a, try files.read(init.io, a, .cwd(), selected.calls));
            const input = try p.dispatchRequest(a, trial, calls);
            try writeOrCompare(init.io, a, selected.output, try p.json(a, input));
        },
        .score => |selected| {
            try validate(init.io, a, bundle, selected.bundle);
            const receipts = try strict.decode(score.Receipts, a, try files.read(init.io, a, .cwd(), selected.receipts), .{ .maximum_depth = 64 });
            try score.validateReceiptSet(bundle, receipts);
            const results = try a.alloc(score.TrialResult, bundle.manifest.trials.len);
            var ids: std.StringHashMap(void) = .init(a);
            for (bundle.manifest.trials, results, 0..) |trial, *result, index| {
                result.* = .{ .trial = trial, .measurement = .{ .state = .not_attempted } };
                if (index >= receipts.trials.len) continue;
                const receipt = receipts.trials[index];
                const request_bytes = try files.read(init.io, a, .cwd(), receipt.request_record);
                const request = try score.decodeRequest(a, request_bytes);
                const response_bytes = try files.read(init.io, a, .cwd(), receipt.response_record);
                const response = try strict.decode(debug.ResponseRecord, a, response_bytes, .{ .maximum_depth = 64 });
                try score.validateRequest(a, trial, request);
                if (!std.mem.eql(u8, request.id, response.id) or ids.contains(request.id)) return error.DuplicateReplay;
                try ids.put(request.id, {});
                result.request_sha256 = try p.hash(a, request_bytes);
                result.response_record_sha256 = try p.hash(a, response_bytes);
                result.measurement = try score.measure(a, request.description, response);
            }
            const report: score.Report = .{ .attempted = receipts.trials.len, .trials = results, .arms = try score.summarize(a, results) };
            try writeOrCompare(init.io, a, selected.output, try p.json(a, report));
        },
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, "Offline attribution command completed; zero model calls.\n");
}
fn join(a: std.mem.Allocator, directory: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}/{s}", .{ directory, name });
}
fn validate(io: std.Io, a: std.mem.Allocator, bundle: p.Bundle, directory: []const u8) !void {
    for (bundle.artifacts) |artifact| {
        const actual = try files.read(io, a, .cwd(), try join(a, directory, artifact.name));
        if (!std.mem.eql(u8, actual, artifact.bytes)) return error.BundleDrift;
    }
    for (p.source_artifacts) |artifact| {
        const actual = try files.read(io, a, .cwd(), try std.fmt.allocPrint(a, "{s}/sources/{s}", .{ p.calibration, artifact.name }));
        if (!std.mem.eql(u8, actual, artifact.bytes)) return error.CaptureDrift;
    }
}
fn writeOrCompare(io: std.Io, a: std.mem.Allocator, name: []const u8, bytes: []const u8) !void {
    try path(name);
    const file = std.Io.Dir.cwd().createFile(io, name, .{ .exclusive = true, .permissions = .fromMode(0o600) }) catch |err| {
        if (err != error.PathAlreadyExists) return err;
        if (!std.mem.eql(u8, try files.read(io, a, .cwd(), name), bytes)) return error.ExistingArtifactDrift;
        return;
    };
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}
