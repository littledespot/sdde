const std = @import("std");
const inspection = @import("inspection.zig");
const reports = @import("report.zig");
const c = @import("../e2e/contracts.zig");
const description: @import("../../../src/domain/request_debugger.zig").Description = .{
    .provider = "aws-bedrock",
    .model = "global.openai.gpt-6-luna",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } },
    .model_slot = "slot",
    .workflow_id = "sample-workflow",
    .workflow_version = 1,
    .request_step = "request-step",
    .content = &.{.{ .user = "source" }},
    .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}",
    .response_mode = .native_schema,
    .controls = .{ .temperature = null },
    .reasoning_effort = null,
    .operation_kind = .inference,
};

test "compatibility requires an explicit case and live opt-in without replay or extra controls" {
    const parse = @import("cli.zig").parse;
    try std.testing.expectEqualStrings("case with spaces.json", try parse(&.{ "--case", "case with spaces.json", "--live" }));
    for ([_][]const []const u8{ &.{}, &.{ "--case", "case.json" }, &.{ "--live", "--case", "case.json" }, &.{ "--case", "../case.json", "--live" }, &.{ "--case", "/case.json", "--live" }, &.{ "--case", "case.json", "--live", "--repeats", "2" }, &.{ "--case", "case.json", "--live", "--model", "another-model" }, &.{ "--run", "historical-capture", "--live" } }) |args| {
        if (parse(args)) |_| return error.AcceptedInvalidCompatibilityArguments else |err| switch (err) {
            error.InvalidArguments, error.InvalidEvaluationContract => {},
            else => return err,
        }
    }
}

test "compatibility classification requires exact usage capture and an incomplete workflow" {
    const probe: @import("../e2e/invoke.zig").Probe = .{ .physical_sends = 1, .boundary = .exchange_finished };
    const workflow: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-10-15T00:00:00Z", .status = .workflow_cancelled, .workflow_outcome = .cancelled };
    const valid: inspection.Inspection = .{
        .request_identity = .{ .run = "run", .call = "call", .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } } },
        .description = description,
        .request_file = "evidence/generation/call-000001/request.json",
        .response_file = "evidence/generation/call-000001/response.json",
        .response_complete = true,
        .http_status = 200,
        .usage = .{ .input_tokens = 10, .output_tokens = 2, .total_tokens = 12 },
        .validation = .{ .extraction = .valid, .json = .valid, .schema = .valid },
    };
    var result = valid;
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.compatible, result.status);
    for (0..8) |fault| {
        var broken_probe = probe;
        var broken_workflow = workflow;
        result = valid;
        switch (fault) {
            0 => broken_probe.physical_sends = 0,
            1 => broken_probe.physical_sends = 2,
            2 => result.request_identity = null,
            3 => result.response_file = null,
            4 => result.usage = null,
            5 => broken_workflow.usage_complete = false,
            6 => broken_workflow.workflow_outcome = .ok,
            7 => broken_workflow.publication_check = .passed,
            else => unreachable,
        }
        inspection.classify(broken_probe, broken_workflow, &result);
        try std.testing.expectEqual(.inconclusive, result.status);
    }
    result = valid;
    result.validation.schema = .invalid;
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.incompatible, result.status);
    result = valid;
    result.validation.extraction = .invalid;
    result.validation.reason = "output_limit";
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.incompatible, result.status);
    for ([_]u16{ 401, 403, 429, 503 }) |status| {
        result = valid;
        result.http_status = status;
        inspection.classify(probe, workflow, &result);
        try std.testing.expectEqual(.inconclusive, result.status);
    }
    result = valid;
    result.response_complete = false;
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.inconclusive, result.status);
}

test "compatibility missing trusted usage retains precise extraction rejection and stays inconclusive" {
    const probe: @import("../e2e/invoke.zig").Probe = .{ .physical_sends = 1, .boundary = .exchange_finished };
    const workflow: c.Report = .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = "2026-10-15T00:00:00Z", .status = .workflow_failed, .workflow_outcome = .failed, .usage_complete = false };
    const missing_usage: inspection.Inspection = .{
        .request_identity = .{ .run = "run", .call = "call", .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } } },
        .description = description,
        .request_file = "evidence/generation/call-000001/request.json",
        .response_file = "evidence/generation/call-000001/response.json",
        .response_complete = true,
        .http_status = 200,
    };
    var result = missing_usage;
    result.validation = .{ .extraction = .invalid, .reason = "Unknown provider response field", .path = "/usage/serverToolUsage/unknown" };
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.inconclusive, result.status);
    try std.testing.expectEqualStrings("Unknown provider response field", result.reason.?);
    try std.testing.expectEqualStrings("/usage/serverToolUsage/unknown", result.validation.path.?);
    try std.testing.expect(result.usage == null);

    for ([_]@TypeOf(result.validation.extraction){ .unavailable, .valid }) |extraction| {
        result = missing_usage;
        result.validation = .{ .extraction = extraction, .reason = "Untrusted unrelated diagnostic" };
        inspection.classify(probe, workflow, &result);
        try std.testing.expectEqual(.inconclusive, result.status);
        try std.testing.expectEqualStrings("ProviderUsageUnavailable", result.reason.?);
    }
    result = missing_usage;
    result.validation.extraction = .invalid;
    inspection.classify(probe, workflow, &result);
    try std.testing.expectEqual(.inconclusive, result.status);
    try std.testing.expectEqualStrings("ProviderUsageUnavailable", result.reason.?);
}

test "compatibility report keeps unknown usage separate from accounted tokens" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var report: reports.Report = .{ .origin = .offline, .started_at_utc = "2026-10-15T00:00:00Z", .case_source = "case.json", .execution_id = "run", .status = .inconclusive };
    reports.applyExecution(&report, .{ .physical_sends = 1, .boundary = .exchange_finished }, .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = report.started_at_utc, .status = .workflow_cancelled, .workflow_outcome = .cancelled, .usage_complete = false });
    const bytes = try std.json.Stringify.valueAlloc(a, report, .{});
    const raw = try @import("../contracts.zig").decode(std.json.Value, a, bytes);
    try std.testing.expect(raw.object.get("total_actual_tokens").? == .null);
    try std.testing.expect(!raw.object.get("usage_complete").?.bool);
    try std.testing.expectEqual(@as(i64, 0), raw.object.get("total_accounted_tokens").?.integer);
    reports.applyExecution(&report, .{ .physical_sends = 1, .boundary = .exchange_finished }, .{ .schema = .@"spec-e2e-report/v9", .started_at_utc = report.started_at_utc, .status = .workflow_cancelled, .workflow_outcome = .cancelled, .usage_complete = true, .total_tokens = 12 });
    try std.testing.expectEqual(@as(?u128, 12), report.total_actual_tokens);
    try std.testing.expectEqual(@as(u128, 12), report.total_accounted_tokens);
}

test "compatibility preflight rejects unpermitted slots and incomplete capture settings before credentials" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const config = @embedFile("../../integration/fixtures/baseline/protocol.sddtoolkit.json");
    const preflight = @import("cli.zig").preflight;
    try preflight(a, config);
    // The shipped cases select Claude Haiku 5.5 (ADR 0029): a permitted generation
    // model, but not the frozen GPT-OSS protocol this probe is bound to.
    try std.testing.expectError(error.FrozenBindingRejected, preflight(a, @embedFile("../../e2e/wf-001-hello-world/.sddtoolkit.json")));
    try std.testing.expectError(error.FrozenBindingRejected, preflight(a, @embedFile("../../integration/fixtures/baseline/mock-bad-input-drifted-effort.sddtoolkit.json")));
    const disallowed = try std.mem.replaceOwned(u8, a, config, "openai.gpt-oss-20b-1:0", "unpermitted-model");
    try std.testing.expectError(error.DisallowedTestModel, preflight(a, disallowed));
    const metadata_only = try std.mem.replaceOwned(u8, a, config, "\"level\": \"debug\"", "\"level\": \"info\"");
    try std.testing.expectError(error.CompleteCaptureRequired, preflight(a, metadata_only));
}

test "compatibility wire identity rejects missing proof and consistent external byte substitution" {
    var digest: [32]u8 = undefined;
    const actual = "actual provider bytes";
    std.crypto.hash.sha2.Sha256.hash(actual, &digest, .{});
    const hex = try inspection.verifyWire(digest, actual);
    try std.testing.expectEqualSlices(u8, &std.fmt.bytesToHex(digest, .lower), &hex);
    try std.testing.expectError(error.CaptureIncomplete, inspection.verifyWire(null, actual));
    // Identical substituted file/archive copies still differ from the digest
    // retained by the trusted transport observer during the actual exchange.
    const substituted_file = "substituted provider bytes";
    const substituted_archive = substituted_file;
    try std.testing.expectEqualStrings(substituted_file, substituted_archive);
    try std.testing.expectError(error.CaptureMismatch, inspection.verifyWire(digest, substituted_file));
}

test "compatibility report preserves diagnostic reasoning and rejects every finalization fault" {
    const io = std.testing.io;
    const Fault = enum { none, json_write, markdown_write, sync };
    for (std.meta.tags(Fault)) |fault| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var temp = std.testing.tmpDir(.{});
        defer temp.cleanup();
        var output = try @import("../e2e/report.zig").Output.reserve(io, temp.dir);
        defer output.close(io);
        switch (fault) {
            .json_write => {
                output.json.close(io);
                output.json = try temp.dir.openFile(io, "report.json", .{ .mode = .read_only });
            },
            .markdown_write => {
                output.markdown.close(io);
                output.markdown = try temp.dir.openFile(io, "report.md", .{ .mode = .read_only });
            },
            .none, .sync => {},
        }
        const stdout = try temp.dir.createFile(io, "stdout.txt", .{});
        defer stdout.close(io);
        const stderr = try temp.dir.createFile(io, "stderr.txt", .{});
        defer stderr.close(io);
        var vtable = io.vtable.*;
        if (fault == .sync) vtable.fileSync = struct {
            fn fail(_: ?*anyopaque, _: std.Io.File) std.Io.File.SyncError!void {
                return error.NoSpaceLeft;
            }
        }.fail;
        const selected_io: std.Io = .{ .userdata = io.userdata, .vtable = &vtable };
        const report: reports.Report = .{ .origin = .offline, .started_at_utc = "2026-10-15T00:00:00Z", .case_source = "case.json", .execution_id = "run", .status = .compatible, .physical_sends = 1, .boundary = .exchange_finished, .workflow_outcome = .cancelled, .inspection = .{ .validation = .{ .reasoning = &.{ .{ .text = .{ .text = "provider diagnostic", .signature = "opaque" } }, .{ .redacted = .{ .base64 = "AQI=" } } } } } };
        const success = try @import("cli.zig").finish(selected_io, a, output, report, "run", stdout, stderr);
        try std.testing.expectEqual(fault == .none, success);
        try std.testing.expectEqual(.cancelled, report.workflow_outcome.?);
        if (fault == .none) {
            const bytes = try @import("../files.zig").read(io, a, temp.dir, "report.json");
            const decoded = try @import("../contracts.zig").decode(std.json.Value, a, bytes);
            try std.testing.expectEqualStrings("none", decoded.object.get("authority").?.string);
            try std.testing.expectEqualStrings("not_assessed", decoded.object.get("semantic_quality").?.string);
            const reasoning = decoded.object.get("inspection").?.object.get("validation").?.object.get("reasoning").?.array.items;
            try std.testing.expectEqual(@as(usize, 2), reasoning.len);
            try std.testing.expectEqualStrings("opaque", reasoning[0].object.get("text").?.object.get("signature").?.string);
        }
    }
}
