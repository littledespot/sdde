const std = @import("std");
const c = @import("contracts.zig");
const files = @import("../files.zig");
const score = @import("score.zig");
const report = @import("report.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const ports = @import("../../../src/ports/request_replay.zig");
const codec = @import("../../../src/domain/model_candidate_json.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const directory = @import("../../../src/adapters/filesystem/directory_access.zig");
const store_module = @import("../../../src/adapters/filesystem/request_debugger_store.zig");
const provider_module = @import("../../../src/adapters/provider/request_replay.zig");
pub const Options = struct {
    cohort: []const u8,
    output: []const u8,
    binding: c.Capture,
    repeats: u16,
    split: @FieldType(c.Case, "split"),
    guidance: ?[]const u8,
    live: bool,
};
pub fn parse(args: []const []const u8) !Options {
    var values: std.StringHashMap([]const u8) = .init(std.heap.page_allocator);
    defer values.deinit();
    var live = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--live")) {
            if (live) return error.InvalidArguments;
            live = true;
            continue;
        }
        const names = [_][]const u8{ "--cohort", "--output", "--feature", "--run", "--call", "--repeats", "--split", "--guidance" };
        const known = for (names) |name| {
            if (std.mem.eql(u8, args[i], name)) break true;
        } else false;
        if (!known or i + 1 == args.len or values.contains(args[i])) return error.InvalidArguments;
        try values.put(args[i], args[i + 1]);
        i += 1;
    }
    const result: Options = .{
        .cohort = values.get("--cohort") orelse return error.InvalidArguments,
        .output = values.get("--output") orelse return error.InvalidArguments,
        .binding = .{ .feature = values.get("--feature") orelse return error.InvalidArguments, .run = values.get("--run") orelse return error.InvalidArguments, .call = values.get("--call") orelse return error.InvalidArguments },
        .repeats = try std.fmt.parseInt(u16, values.get("--repeats") orelse return error.InvalidArguments, 10),
        .split = std.meta.stringToEnum(@FieldType(c.Case, "split"), values.get("--split") orelse return error.InvalidArguments) orelse return error.InvalidArguments,
        .guidance = values.get("--guidance"),
        .live = live,
    };
    for ([_][]const u8{ result.cohort, result.output, result.binding.feature }) |path| try @import("../contracts.zig").path(path);
    if (result.guidance) |path| try @import("../contracts.zig").path(path);
    if (result.repeats == 0 or !@import("../contracts.zig").id(result.binding.call) or !@import("../contracts.zig").id(result.binding.run)) return error.InvalidArguments;
    return result;
}
pub fn captured(io: std.Io, a: std.mem.Allocator, selected: c.Capture) !debug.Call {
    const feature = try directory.open(io, .cwd(), selected.feature);
    defer feature.close(io);
    var store: store_module.Store = .{ .io = io, .feature = feature };
    const calls = try store.load(a);
    var result: ?debug.Call = null;
    for (calls) |call| if (std.mem.eql(u8, call.run, selected.run) and std.mem.eql(u8, call.id, selected.call)) {
        if (result != null) return error.InvalidEvaluationContract;
        result = call;
    };
    const call = result orelse return error.InvalidEvaluationContract;
    if (call.description == null or !call.request_complete or call.redacted) return error.InvalidEvaluationContract;
    return call;
}
pub fn roleInput(a: std.mem.Allocator, description: debug.Description) !@import("../../../src/domain/reference_model_input.zig").RoleInput {
    var body: ?[]const u8 = null;
    var guidance_count: usize = 0;
    for (description.content) |part| switch (part) {
        .user => |bytes| {
            if (body != null) return error.InvalidEvaluationContract;
            body = bytes;
        },
        .guidance => guidance_count += 1,
        .system, .evidence => return error.InvalidEvaluationContract,
    };
    if (guidance_count != 1) return error.InvalidEvaluationContract;
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, body orelse return error.InvalidEvaluationContract);
    const Role = @import("../../../src/domain/reference_reconciliation.zig").GenerationRole;
    if (input.assignment.role_definitions.len != std.meta.tags(Role).len) return error.InvalidEvaluationContract;
    var defined: std.enums.EnumSet(Role) = .initEmpty();
    for (input.assignment.role_definitions) |definition| {
        if (defined.contains(definition.role) or !@import("../contracts.zig").text(definition.purpose)) return error.InvalidEvaluationContract;
        defined.insert(definition.role);
    }
    return input;
}
const Authorization = struct {
    binding: debug.Description,
    fn authorize(context: *ports.Context, value: debug.Description) ports.Error!void {
        const self: *Authorization = @ptrCast(@alignCast(context));
        const expected = self.binding;
        // Explicit diagnostic binding, not an imported workflow capability.
        if (!std.mem.eql(u8, value.provider, expected.provider) or !std.mem.eql(u8, value.model, expected.model) or !std.meta.eql(value.provider_config, expected.provider_config) or
            !std.meta.eql(value.controls, expected.controls) or !debug.sameOptional(value.reasoning_effort, expected.reasoning_effort) or value.response_mode != expected.response_mode or value.operation_kind != .inference) return error.ReplayUnauthorized;
    }
};
pub fn responseFailure(a: std.mem.Allocator, response: debug.ResponseRecord) !?[]const u8 {
    if (response.outcome != .received) return response.diagnostic orelse @tagName(response.outcome);
    if (response.status != 200) return try std.fmt.allocPrint(a, "HTTP-{d}", .{response.status orelse 0});
    return null;
}
pub fn controlledDescription(a: std.mem.Allocator, binding: debug.Description, packet: *packets.Packet, guidance: []const u8, canonical: *const @import("../../../src/domain/model_result_schema.zig").Schema) !debug.Description {
    var description = binding;
    // Descriptions outlive the preparation loop and its temporary content array.
    description.content = try a.dupe(@import("../../../src/domain/llm_provider_operation.zig").ModelVisibleContent, &.{ .{ .guidance = guidance }, .{ .user = try a.dupe(u8, packet.body()) } });
    const restricted = try @import("../../../src/domain/model_result_schema.zig").restrict(a, canonical, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    description.schema = try a.dupe(u8, restricted.selected().modelBytes());
    return description;
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
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build calibrate-roles -- --cohort <json> --output <existing-directory> --feature <captured-feature-directory> --run <captured-run-id> --call <role-call-id> --split development|held_out --repeats <positive-count> [--guidance <candidate-prompt>] [--live]\nWithout --live, prepare packets and report the declared allowance without API calls. Live runs require reviewed labels and TEST_AWS_BEARER_TOKEN_BEDROCK; no .env file is loaded. One physical call per case/repeat/variant, no correction or repair. This is diagnostic calibration, not E2E.\n");
        return;
    }
    const options = parse(args.items) catch return fail(io, "Invalid arguments; use --help. No API call made.");
    const cohort = try c.parse(a, try files.read(io, a, .cwd(), options.cohort));
    if (options.live and cohort.label_status != .reviewed) return fail(io, "Human-reviewed labels are required for live calibration. No API call made.");
    const binding_call = try captured(io, a, options.binding);
    const binding = binding_call.description.?;
    _ = try roleInput(a, binding);
    if (binding.provider_config != .aws_bedrock) return error.InvalidEvaluationContract;
    const identities = @import("../../../src/domain/llm_provider_identity.zig");
    const supported = @import("../../../src/composition/provider_model_contracts.zig").registry.resolve(identities.ProviderId.parse(binding.provider).?, identities.ModelId.parse(binding.model).?) orelse return error.InvalidEvaluationContract;
    if (!supported.acceptsConfig(binding.provider_config) or !supported.capabilities.supports(binding.response_mode, binding.controls) or
        !std.meta.eql(supported.capabilities.inferenceControls(), binding.controls) or
        !@import("../../../src/domain/llm_provider_contracts.zig").supportsReasoningEffort(supported.supported_reasoning_efforts, binding.reasoning_effort)) return error.InvalidEvaluationContract;
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try parser.compiler().compile(a, try files.read(io, a, .cwd(), "design/workflows/spec/reconciliation.schema.json"));
    const canonical = compiled.select(.{ .bytes = "roles_assignment" }) orelse return error.InvalidEvaluationContract;
    const prompt = try files.read(io, a, .cwd(), "design/workflows/spec/reconciliation-roles.prompt.md");
    const candidate = if (options.guidance) |path| try files.read(io, a, .cwd(), path) else null;
    var parents: std.ArrayList(debug.Call) = .empty;
    var cases: std.ArrayList(c.Case) = .empty;
    // Validate every case and label before the first dispatch.
    for (cohort.cases) |entry| {
        if (entry.split != options.split) continue;
        var parent = switch (entry.input) {
            .captured => |selected| try captured(io, a, selected),
            .controlled => |sources| controlled: {
                const packet = try @import("input.zig").packet(io, a, sources);
                defer packets.release(packet);
                var call = binding_call;
                call.description = try controlledDescription(a, binding, packet, prompt, canonical);
                break :controlled call;
            },
        };
        const body = try roleInput(a, parent.description.?);
        try score.validateLabels(body.accepted, entry.labels);
        var description = parent.description.?;
        // All trials retain the same explicit model/settings binding.
        description.provider = binding.provider;
        description.model = binding.model;
        description.provider_config = binding.provider_config;
        description.controls = binding.controls;
        description.reasoning_effort = binding.reasoning_effort;
        description.response_mode = binding.response_mode;
        _ = try parser.compiler().compileSelected(a, description.schema);
        parent.description = description;
        try parents.append(a, parent);
        try cases.append(a, entry);
    }
    if (cases.items.len == 0) return error.InvalidEvaluationContract;
    const output = try directory.open(io, .cwd(), options.output);
    defer output.close(io);
    const run = try @import("../e2e/run_directory.zig").Run.create(io, output);
    defer run.close(io);
    var store: store_module.Store = .{ .io = io, .feature = run.dir };
    var authority: Authorization = .{ .binding = binding };
    var clock: @import("../../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var transport: @import("../../../src/adapters/provider/bedrock_http.zig").Adapter = .{ .io = io, .clock = clock.clock(), .runtime = .{} };
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    if (options.live) try environment.put("AWS_BEARER_TOKEN_BEDROCK", try @import("../environment.zig").credential(init.environ_map, .bedrock_invoke));
    var provider: provider_module.Adapter = .{ .authorization = .{ .context = @ptrCast(&authority), .authorize_fn = Authorization.authorize }, .environment = &environment, .transport = transport.port(), .clock = clock.clock(), .compiler = parser.compiler() };
    const service: @import("../../../src/application/request_replay.zig").Service = .{ .provider = provider.provider(), .store = store.port() };
    const variants: usize = if (candidate != null) 2 else 1;
    const allowance = try std.math.mul(u64, try std.math.mul(u64, cases.items.len, options.repeats), variants);
    const plan = try std.json.Stringify.valueAlloc(a, .{ .cohort = cohort, .options = options, .binding = binding, .maximum_physical_calls = allowance, .correction = "not_run", .repair = "not_run" }, .{ .whitespace = .indent_2 });
    if (environment.get("AWS_BEARER_TOKEN_BEDROCK")) |secret| {
        var sanitized = try @import("../../../src/domain/model_log_redaction.zig").sanitize(a, plan, &.{secret});
        defer sanitized.deinit(a);
        if (sanitized.redacted) return error.InvalidEvaluationContract;
    }
    try @import("../output.zig").write(io, run.dir, "plan.json", plan);
    var trials: std.ArrayList(report.Trial) = .empty;
    var sequence: u64 = 0;
    for (cases.items, parents.items) |entry, parent| for (0..options.repeats) |repeat| for (0..variants) |variant| {
        sequence += 1;
        var description = parent.description.?;
        if (variant == 1) {
            const parts = try a.dupe(@import("../../../src/domain/llm_provider_operation.zig").ModelVisibleContent, description.content);
            for (parts) |*part| if (part.* == .guidance) {
                part.* = .{ .guidance = candidate.? };
            };
            description.content = parts;
        }
        const body = try roleInput(a, description);
        var trial: report.Trial = .{ .case_id = entry.id, .family = entry.family, .split = entry.split, .input_origin = std.meta.activeTag(entry.input), .repeat = @intCast(repeat + 1), .variant = if (variant == 0) .baseline else .candidate, .guidance_bytes = 0, .input_bytes = 0, .schema_bytes = description.schema.len };
        for (description.content) |part| switch (part) {
            .guidance => |bytes| trial.guidance_bytes += bytes.len,
            .user => |bytes| trial.input_bytes += bytes.len,
            .system, .evidence => return error.InvalidEvaluationContract,
        };
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        const id = try a.dupe(u8, &std.fmt.bytesToHex(random, .lower));
        trial.request = id;
        // Diagnostic modifications still go through the existing one-send service.
        if (options.live) {
            const started: std.Io.Clock.Timestamp = .now(io, .awake);
            const result = service.replay(a, .{ .id = id, .run = .{ .bytes = &run.name }, .sequence = sequence }, parent, .{ .call = 0, .mode = .modified, .edit = .{ .content = description.content, .schema = description.schema } }) catch |err| {
                trial.elapsed_ns = started.durationTo(.now(io, .awake)).raw.toNanoseconds();
                trial.failure = @errorName(err);
                try trials.append(a, trial);
                continue;
            };
            trial.elapsed_ns = started.durationTo(.now(io, .awake)).raw.toNanoseconds();
            trial.request_bytes = result.request.body.len;
            trial.response_bytes = if (result.response.body) |bytes| bytes.len else null;
            trial.validation = result.validation;
            trial.failure = try responseFailure(a, result.response);
            if (trial.failure == null) trial.outcome = try score.assess(a, body.accepted, entry.labels, result.validation);
        } else {
            const request = try provider.provider().prepare(a, description);
            trial.request_bytes = request.len;
            try store.port().request(a, .{ .id = id, .run = &run.name, .sequence = sequence, .parent_run = parent.run, .parent_call = parent.id, .original_run = parent.original_run orelse parent.run, .original_call = parent.original, .node = parent.node, .mode = .modified, .description = description, .source_overrides = true, .body = request });
        }
        try trials.append(a, trial);
    };
    try @import("../output.zig").write(io, run.dir, "report.json", try std.json.Stringify.valueAlloc(a, .{ .schema = "role-calibration-report/v1", .label_status = cohort.label_status, .live = options.live, .maximum_physical_calls = allowance, .trials = trials.items, .totals = report.totals(trials.items) }, .{ .whitespace = .indent_2 }));
    try @import("../output.zig").write(io, run.dir, "report.md", try report.markdown(a, options.live, cohort.label_status == .reviewed, trials.items));
    try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(a, "Role calibration report: {s}/{s}/report.json\n", .{ options.output, &run.name }));
}
fn fail(io: std.Io, message: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, message);
    try std.Io.File.stderr().writeStreamingAll(io, "\n");
    std.process.exit(1);
}
