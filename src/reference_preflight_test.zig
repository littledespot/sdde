const std = @import("std");
const reference = @import("domain/reference_selector.zig");
const parse = @import("actions/specify/parse_specify_invocation.zig");
const validate = @import("actions/specify/validate_specify_arguments.zig");
const normalize = @import("actions/reference/normalize_reference_selector.zig");
const lexical = @import("actions/reference/validate_reference_selector.zig");
const runner = @import("application/reference_workflow_runner.zig");
const values = @import("application/pipeline_values.zig");
const schemas = @import("application/reference_workflow_values.zig");
const Envelope = @import("application/pipeline_envelope.zig").PipelineEnvelope;
const unicode = @import("unicode_normalization");
const normalizer: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc, .fold_fn = unicode.fold };

test "Specify grammar accepts one required reference and rejects every removed input form" {
    const result = try (validate.Action{}).execute(try (parse.Action{}).execute(&.{ "--reference", "hello-world" }));
    try std.testing.expectEqualStrings("hello-world", result.raw_reference);
    const rejected = [_][]const []const u8{
        &.{},                                             &.{"--reference"},                   &.{ "--reference", "" },
        &.{ "--reference", "one", "--reference", "two" }, &.{ "--reference", "one", "extra" }, &.{"description"},
        &.{ "--feature", "one" },                         &.{ "--description", "one" },        &.{ "--feature-id", "one" },
        &.{ "-type", "one" },                             &.{ "--ref", "one" },                &.{ "--", "--reference", "one" },
        &.{"--reference=one"},                            &.{ "--reference", "--" },
    };
    for (rejected) |arguments| {
        const parsed = (parse.Action{}).execute(arguments) catch |err| {
            try std.testing.expectEqual(error.InvalidSpecifyArguments, err);
            continue;
        };
        try std.testing.expectError(error.InvalidSpecifyArguments, (validate.Action{}).execute(parsed));
    }
}

test "selector normalization preserves meaning and canonicalizes only NFC separators and literal dots" {
    const cases = .{
        .{ "./Cafe\u{301}/./notes", "Café/notes" },
        .{ "documentation\\日本語", "documentation/日本語" },
        .{ "one/two/.", "one/two" },
        .{ "\u{1100}\u{1161}/reference", "가/reference" },
    };
    inline for (cases) |case| {
        const normalized = try (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_reference = case[0] });
        defer std.testing.allocator.free(normalized.bytes);
        const selector = try (lexical.Action{}).execute(normalized);
        try std.testing.expectEqualStrings(case[1], selector.bytes);
    }
}

test "selector safety rejects escape forms controls ambiguous separators and portable-invalid segments" {
    const rejected = [_][]const u8{
        "",                     ".",              "./.",       "../hello",     "hello/../world",  "/root",           "\\root",            "C:\\root",     "\\\\server\\share",
        "https://example.test", "file:root",      "hello/",    "hello//world", "hello/\x00world", "hello/\x1fworld", "hello/\u{85}world", "hello/%2e%2e", "hello/%252e%252e",
        "hello/%2Fworld",       "hello/%5cworld", "hello/con", "hello/bad.",   "hello/bad ",      "hello/bad?",      "hello/..\\world",
    };
    for (rejected) |raw| {
        const normalized = try (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_reference = raw });
        defer std.testing.allocator.free(normalized.bytes);
        try std.testing.expectError(error.InvalidReferenceSelector, (lexical.Action{}).execute(normalized));
    }
    try std.testing.expectError(error.InvalidUtf8, (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_reference = "\xed\xa0\x80" }));
    const long_segment = [_]u8{'a'} ** (reference.max_segment_bytes + 1);
    try std.testing.expectError(error.InvalidReferenceSelector, (lexical.Action{}).execute(.{ .bytes = &long_segment }));
    const long_path = [_]u8{'a'} ** (reference.max_bytes + 1);
    try std.testing.expectError(error.NormalizationLimitExceeded, (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_reference = &long_path }));
}

test "Unicode reference paths do not weaken the distinct ASCII configured-root contract" {
    const policy: @import("domain/bootstrap_roots.zig").WorkspacePathPolicy = .{ .max_component_bytes = 255, .max_relative_path_bytes = 4096, .max_absolute_path_bytes = 4096 };
    try std.testing.expectError(error.InvalidConfiguredPath, @import("domain/configured_path_policy.zig").normalize(policy, std.testing.allocator, "Café", false));
    _ = try (lexical.Action{}).execute(.{ .bytes = "Café" });
}

fn normalizationAllocationCase(allocator: std.mem.Allocator) !void {
    const result = try (normalize.Action{ .normalizer = normalizer }).execute(allocator, .{ .raw_reference = "./Cafe\u{301}/notes" });
    defer allocator.free(result.bytes);
    try std.testing.expectEqualStrings("Café/notes", result.bytes);
}

test "selector normalization cleans up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, normalizationAllocationCase, .{});
}

test "invocation publishes only validated owned context and rejects without output" {
    var binding: runner.Invocation = .{ .allocator = std.testing.allocator };
    var candidate = try runner.Invocation.invoke(&binding, .{ .invocation = .{ .arguments = &.{ "--reference", "hello" } } });
    var envelope: Envelope = .init(&schemas.schemas);
    defer envelope.deinit();
    defer envelope.discard(&candidate.delta);
    const contract: @import("domain/pipeline.zig").NodeContract = .{ .id = runner.Invocation.contract.id, .kind = .orchestrator, .requires = &.{}, .produces = runner.Invocation.contract.produces, .side_effect = .none };
    try envelope.apply(contract, &candidate.delta, .ok);
    try std.testing.expect(envelope.slots[@intFromEnum(schemas.parsed.key)] == null);
    const read_contract: @import("domain/pipeline.zig").NodeContract = .{ .id = "read@1", .kind = .action, .requires = &.{.specify_invocation}, .produces = &.{}, .side_effect = .none };
    const view = try envelope.view(read_contract);
    try std.testing.expectEqualStrings("hello", (try values.read(&view, schemas.invocation, reference.Invocation)).raw_reference);
    try std.testing.expectError(error.OperationExecutionFailed, runner.Invocation.invoke(&binding, .{ .invocation = .{ .arguments = &.{} } }));
}

test "registered bindings derive only their narrow operational capabilities" {
    const binding = @import("application/workflow_operation_binding.zig");
    const normalization = comptime binding.inspect(runner.NormalizeSelector, &.{});
    const inspection = comptime binding.inspect(runner.InspectDirectory, &.{});
    try std.testing.expect(normalization.valid and !normalization.reference_read and !normalization.model_provider);
    try std.testing.expect(inspection.valid and inspection.reference_read and !inspection.model_provider and !inspection.toolchain_read);
    try std.testing.expect((comptime binding.inspect(runner.Invocation, &.{})).valid);
}

fn invocationAllocationCase(allocator: std.mem.Allocator) !void {
    var binding: runner.Invocation = .{ .allocator = allocator };
    var candidate = runner.Invocation.invoke(&binding, .{ .invocation = .{ .arguments = &.{ "--reference", "hello" } } }) catch return error.OutOfMemory;
    var envelope: Envelope = .init(&schemas.schemas);
    defer envelope.deinit();
    defer envelope.discard(&candidate.delta);
    try std.testing.expect(candidate.delta.data_writes[@intFromEnum(schemas.invocation.key)] != null);
}

test "invocation cleans up every failed allocation without leaking parsed context" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, invocationAllocationCase, .{});
}

test "reference directory action exposes only inspection and propagates source failure" {
    // Missing bound authority must stop before the adapter callback is reached.
    const Fake = struct {
        calls: usize = 0,
        fn inspect(context: *anyopaque, _: *const @import("domain/bootstrap_root_registry.zig").ConfiguredBaseRootCapability, _: std.mem.Allocator, _: reference.RelativeSelector) @import("ports/reference_directory_inspector.zig").Error!reference.Directory {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            return error.ReferenceDirectoryUnavailable;
        }
    };
    var fake: Fake = .{};
    const action: @import("actions/reference/inspect_reference_directory.zig").Action = .{ .inspector = .{ .context = &fake, .inspect_fn = Fake.inspect } };
    try std.testing.expectError(error.ReferenceDirectoryUnavailable, action.execute(std.testing.allocator, .{ .bytes = "hello" }));
    try std.testing.expectEqual(@as(usize, 0), fake.calls);
}
