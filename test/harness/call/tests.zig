const std = @import("std");
const options = @import("options.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const ports = @import("../../../src/ports/request_replay.zig");
const trial = @import("trial.zig");
const binding = @import("../diagnostic_binding.zig");

const args = [_][]const u8{ "--run", "zig-out/e2e-spec/MOCK-run", "--workflow", "sample-workflow", "--call", "12", "--model", "openai.gpt-oss-20b-1:0", "--reasoning-effort", "high" };

test "call selectors require an explicit run workflow physical ordinal model and effort" {
    const parsed = try options.parse(&args);
    try std.testing.expectEqual(@as(u32, 12), parsed.call);
    try std.testing.expectEqual(@as(u16, 1), parsed.repeats);
    try std.testing.expectEqualStrings("high", parsed.reasoning_effort.?);
    try std.testing.expectEqual(@as(u16, 3), (try options.parse(&(args ++ .{ "--repeats", "3" }))).repeats);
    var omitted_effort = args;
    omitted_effort[9] = "none";
    try std.testing.expect((try options.parse(&omitted_effort)).reasoning_effort == null);
    for (0..args.len / 2) |index| {
        var missing: [args.len - 2][]const u8 = undefined;
        @memcpy(missing[0 .. index * 2], args[0 .. index * 2]);
        @memcpy(missing[index * 2 ..], args[index * 2 + 2 ..]);
        try std.testing.expectError(error.InvalidArguments, options.parse(&missing));
    }
    try std.testing.expectError(error.InvalidArguments, options.parse(&(args ++ .{ "--call", "3" })));
    try std.testing.expectError(error.InvalidArguments, options.parse(&(args ++ .{ "--unknown", "3" })));
    try std.testing.expectError(error.InvalidArguments, options.parse(&(args ++ .{"--repeats"})));
    try std.testing.expectError(error.InvalidArguments, options.parse(&(args ++ .{ "--repeats", "0" })));
    for ([_][]const u8{ "0", "-1", "not-a-number", "4294967296" }) |invalid| {
        var bad = args;
        bad[5] = invalid;
        if (options.parse(&bad)) |_| return error.TestExpectedError else |_| {}
    }
    var unsafe = args;
    unsafe[1] = "../outside";
    try std.testing.expectError(error.InvalidEvaluationContract, options.parse(&unsafe));
}

const description: debug.Description = .{
    .provider = "aws-bedrock",
    .model = "openai.gpt-oss-20b-1:0",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
    .model_slot = "sample-slot",
    .workflow_id = "sample-workflow",
    .workflow_version = 1,
    .request_step = "prepare-sample",
    .content = &.{ .{ .guidance = "MOCK guidance" }, .{ .user = "MOCK request" } },
    .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\",\"maxLength\":256}},\"required\":[\"answer\"],\"additionalProperties\":false}",
    .response_mode = .native_schema,
    .controls = .{ .temperature = .zero, .max_output_tokens = .{ .value = 16384 } },
    .reasoning_effort = "high",
    .operation_kind = .inference,
};
const parent: debug.Call = .{
    .run = "MOCK-original-run",
    .sequence = 79,
    .id = "request-2-inference-1",
    .workflow = description.workflow_id,
    .action = "invoke-model",
    .node = "invoke-sample",
    .request_step = description.request_step,
    .slot = description.model_slot,
    .kind = "initial",
    .original = "request-2-inference-1",
    .parent = null,
    .description = description,
    .request = "MOCK original immutable request",
    .request_complete = true,
};
const identity: debug.ReplayIdentity = .{ .id = "trial-1", .run = .{ .bytes = "MOCK-diagnostic-run" }, .sequence = 1 };

const response_body = "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"answer\\\":\\\"MOCK answer\\\"}\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}";

const Fixture = struct {
    wire: @import("../../../src/bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = response_body },
    authority: binding.Authorization = .{ .binding = description },
    environment: std.process.Environ.Map,
    parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{},
    provider: @import("../../../src/adapters/provider/request_replay.zig").Adapter = undefined,
    fail_request: bool = false,
    fail_response: bool = false,
    request: ?debug.RequestRecord = null,
    response: ?debug.ResponseRecord = null,

    fn init(self: *Fixture, a: std.mem.Allocator) !void {
        self.* = .{ .environment = .init(a) };
        try self.environment.put("AWS_BEARER_TOKEN_BEDROCK", "MOCK-secret-never-log");
        self.provider = .{
            .authorization = .{ .context = @ptrCast(&self.authority), .authorize_fn = binding.Authorization.authorize },
            .environment = &self.environment,
            .transport = self.wire.port(),
            .clock = .{ .context = @ptrCast(self), .now_fn = now },
            .compiler = self.parser.compiler(),
        };
    }
    fn now(_: *@import("../../../src/ports/provider_authorization_lease.zig").Context) error{ClockUnavailable}!u64 {
        return 100;
    }
    fn saveRequest(context: *ports.Context, _: std.mem.Allocator, value: debug.RequestRecord) ports.Error!void {
        const self: *Fixture = @ptrCast(@alignCast(context));
        if (self.fail_request) return error.ReplayStorageFailure;
        self.request = value;
    }
    fn saveResponse(context: *ports.Context, _: std.mem.Allocator, value: debug.ResponseRecord) ports.Error!void {
        const self: *Fixture = @ptrCast(@alignCast(context));
        if (self.fail_response) return error.ReplayStorageFailure;
        self.response = value;
    }
    fn service(self: *Fixture) @import("../../../src/application/request_replay.zig").Service {
        return .{ .provider = self.provider.provider(), .store = .{ .context = @ptrCast(self), .request_fn = saveRequest, .response_fn = saveResponse } };
    }
};

test "call trial uses canonical serializer and validation with one send and immutable parent" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    const result = trial.execute(a, std.testing.io, fixture.service(), parent, identity);
    try std.testing.expectEqual(.completed, result.outcome);
    try std.testing.expect(result.canContinue());
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    try std.testing.expectEqualStrings("{\"answer\":\"MOCK answer\"}", result.validation.model_text.?);
    try std.testing.expectEqual(@as(?u64, 2), result.validation.output_tokens);
    try std.testing.expectEqualStrings(parent.id, fixture.request.?.parent_call);
    try std.testing.expectEqualStrings(parent.run, fixture.request.?.parent_run);
    try std.testing.expectEqualDeep(description.content, fixture.request.?.description.content);
    try std.testing.expectEqualStrings(description.schema, fixture.request.?.description.schema);
    try std.testing.expectEqualStrings("MOCK original immutable request", parent.request.?);
    const body = try @import("../contracts.zig").decode(std.json.Value, a, fixture.request.?.body);
    try std.testing.expectEqualStrings("high", body.object.get("reasoning_effort").?.string);
    try std.testing.expectEqual(@as(i64, 16384), body.object.get("max_completion_tokens").?.integer);
    try std.testing.expect(body.object.contains("response_format"));
}

test "call trial retains output limits and transport failure without retry or false success" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    fixture.wire.inference_body = try std.mem.replaceOwned(u8, a, response_body, "\"stop\"", "\"length\"");
    const limited = trial.execute(a, std.testing.io, fixture.service(), parent, identity);
    try std.testing.expectEqual(.protocol_invalid, limited.outcome);
    try std.testing.expectEqualStrings("output_limit", limited.diagnostic.?);
    try std.testing.expectEqual(@as(?u64, 2), limited.validation.output_tokens);
    try std.testing.expect(limited.canContinue());
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
    fixture.wire.cancelled = true;
    const cancelled = trial.execute(a, std.testing.io, fixture.service(), parent, identity);
    try std.testing.expectEqual(.transport_failed, cancelled.outcome);
    try std.testing.expect(!cancelled.canContinue());
    try std.testing.expectEqual(@as(usize, 2), fixture.wire.calls);
    try std.testing.expectEqual(.cancelled, fixture.response.?.outcome);
}

test "call trial stops on durable request or response storage failure" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    fixture.fail_request = true;
    const before = trial.execute(a, std.testing.io, fixture.service(), parent, identity);
    try std.testing.expectEqual(.operation_failed, before.outcome);
    try std.testing.expect(!before.canContinue());
    try std.testing.expectEqual(@as(usize, 0), fixture.wire.calls);
    fixture.fail_request = false;
    fixture.fail_response = true;
    const after = trial.execute(a, std.testing.io, fixture.service(), parent, identity);
    try std.testing.expectEqual(.operation_failed, after.outcome);
    try std.testing.expect(!after.canContinue());
    try std.testing.expectEqualStrings("ReplayStorageFailure", after.diagnostic.?);
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
}

test "call diagnostic uses the immutable archive store and rejects HTTP errors without continuation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture: Fixture = undefined;
    try fixture.init(a);
    defer fixture.environment.deinit();
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var store: @import("../../../src/adapters/filesystem/request_debugger_store.zig").Store = .{ .io = std.testing.io, .feature = temp.dir };
    const service: @import("../../../src/application/request_replay.zig").Service = .{ .provider = fixture.provider.provider(), .store = store.port() };
    const id: debug.ReplayIdentity = .{ .id = "a" ** 32, .run = identity.run, .sequence = 1 };
    fixture.wire.result = .{ .received = .{ .status = 429, .body = "MOCK rate limited" } };
    const result = trial.execute(a, std.testing.io, service, parent, id);
    try std.testing.expectEqual(.transport_failed, result.outcome);
    try std.testing.expectEqualStrings("http_error", result.diagnostic.?);
    try std.testing.expect(!result.canContinue());
    const calls = try store.load(a);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqualStrings(parent.run, calls[0].parent_run.?);
    try std.testing.expectEqualStrings(parent.id, calls[0].parent.?);
    try std.testing.expectEqual(@as(?u16, 429), calls[0].response_status);
    try std.testing.expectEqualStrings("high", calls[0].description.?.reasoning_effort.?);
    const reused = trial.execute(a, std.testing.io, service, parent, id);
    try std.testing.expectEqual(.operation_failed, reused.outcome);
    try std.testing.expectEqualStrings("ReplayStorageFailure", reused.diagnostic.?);
    try std.testing.expectEqual(@as(usize, 1), fixture.wire.calls);
}

test "call report distinguishes protocol success from semantic and workflow acceptance" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const reports = @import("report.zig");
    var report: reports.Report = .{
        .started_at_utc = "2026-10-10T00:00:00Z",
        .options = try options.parse(&args),
        .parent_run = parent.run,
        .parent_call = parent.id,
        .original_binding = description,
        .effective_binding = description,
        .context_path = "MOCK/context.json",
        .request_path = "MOCK/request.json",
    };
    try std.testing.expect(!report.succeeded());
    report.trials = &.{.{ .ordinal = 1, .request_id = "trial-1", .outcome = .completed }};
    try std.testing.expect(report.succeeded());
    const markdown = try reports.markdown(a, report);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "Semantic quality is not assessed") != null);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "publication and rubric evaluation did not run") != null);
    report.options.repeats = 2;
    try std.testing.expect(!report.succeeded());
    report.options.repeats = 1;
    report.trials = &.{.{ .ordinal = 1, .request_id = "trial-1", .outcome = .protocol_invalid, .diagnostic = "MOCK failure" }};
    try std.testing.expect(!report.succeeded());
}
