const std = @import("std");
const identity = @import("domain/feature_identity.zig");
const reference = @import("domain/reference_selector.zig");
const derive = @import("actions/specify/derive_feature_identity.zig");
const normalize = @import("actions/reference/normalize_reference_selector.zig");
const unicode = @import("unicode_normalization");
const normalizer: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc, .fold_fn = unicode.fold };
const action: derive.Action = .{ .normalizer = normalizer };
const policy = identity.NamingPolicy.init(64).?;
const runners = @import("application/feature_identity_workflow.zig");
const values = @import("application/pipeline_values.zig");
const selector_schema = @import("application/reference_workflow_values.zig").selector;
const pipeline = @import("domain/pipeline.zig");
const Envelope = @import("application/pipeline_envelope.zig").PipelineEnvelope;

test "identity uses complete selector and pinned folding with repeatable results" {
    const cases = .{
        .{ "Hello_World", "hello-world" },
        .{ "Products/Orders/Checkout", "products-orders-checkout" },
        .{ "Café/Straße", "cafe-strasse" },
        .{ "①Ｆｏｏ/ﬃ", "1foo-ffi" },
        .{ "Ångström/İstanbul", "angstrom-istanbul" },
        .{ "Café/日本語/Orders", "cafe-orders" },
        .{ "--Alpha__Beta--", "alpha-beta" },
        .{ "123", "123" },
    };
    inline for (cases) |case| {
        for (0..2) |_| {
            const seed = try action.execute(std.testing.allocator, .{ .bytes = case[0] }, policy);
            defer std.testing.allocator.free(seed.feature_id.bytes);
            try std.testing.expectEqualStrings(case[1], seed.feature_id.bytes);
            try std.testing.expectEqualStrings(case[0], seed.reference_selector.bytes);
            try std.testing.expect(std.meta.eql(policy, seed.naming_policy));
        }
    }
}

test "canonically equivalent Unicode and normalized nesting derive identical seeds" {
    for ([_][]const u8{ "Café/Orders", "./Cafe\u{301}\\Orders" }) |raw| {
        const normalized = try (normalize.Action{ .normalizer = normalizer }).execute(std.testing.allocator, .{ .raw_reference = raw });
        defer std.testing.allocator.free(normalized.bytes);
        const seed = try action.execute(std.testing.allocator, try reference.validate(normalized), policy);
        defer std.testing.allocator.free(seed.feature_id.bytes);
        try std.testing.expectEqualStrings("Café/Orders", seed.reference_selector.bytes);
        try std.testing.expectEqualStrings("cafe-orders", seed.feature_id.bytes);
    }
}

test "maximum length is explicit and truncation cannot leave a partial scalar or hyphen" {
    for ([_]i64{ -1, 0, 256, std.math.maxInt(i64) }) |maximum| try std.testing.expect(identity.NamingPolicy.init(maximum) == null);
    const cases = .{
        .{ "Éclair/Orders", 1, "e" },
        .{ "alpha/beta", 5, "alpha" },
        .{ "alpha/beta", 6, "alpha" },
        .{ "alpha/beta", 7, "alpha-b" },
        .{ "Straße", 5, "stras" },
    };
    inline for (cases) |case| {
        const seed = try action.execute(std.testing.allocator, .{ .bytes = case[0] }, identity.NamingPolicy.init(case[1]).?);
        defer std.testing.allocator.free(seed.feature_id.bytes);
        try std.testing.expectEqualStrings(case[2], seed.feature_id.bytes);
    }
    const longest = [_]u8{'a'} ** identity.maximum_id_bytes;
    const seed = try action.execute(std.testing.allocator, .{ .bytes = &longest }, identity.NamingPolicy.init(255).?);
    defer std.testing.allocator.free(seed.feature_id.bytes);
    try std.testing.expectEqualStrings(&longest, seed.feature_id.bytes);
}

test "empty folding portable-invalid results and malformed selectors fail closed" {
    for ([_][]const u8{ "日本語", "Ελλάδα", "---", "\u{301}", "ＣＯＮ", "ＡＵＸ", "ＬＰＴ１" }) |selector| {
        try std.testing.expectError(error.InvalidFeatureId, action.execute(std.testing.allocator, .{ .bytes = selector }, policy));
    }
    try std.testing.expectError(error.InvalidFeatureId, action.execute(std.testing.allocator, .{ .bytes = "console" }, identity.NamingPolicy.init(3).?));
    for ([_][]const u8{ "", "../hello", "one//two", "one/", "bad\x00name", "\xff" }) |selector| {
        try std.testing.expectError(error.InvalidReferenceSelector, action.execute(std.testing.allocator, .{ .bytes = selector }, policy));
    }
    try std.testing.expectError(error.InvalidFeatureNamingPolicy, action.execute(std.testing.allocator, .{ .bytes = "hello" }, .{ .version = .unicode17_ascii_v1, .maximum_length = 0 }));
    for ([_][]const u8{ "", "-hello", "hello-", "a--b", "Hello", "a/b", "con", "é", "a_b" }) |id| try std.testing.expect(identity.FeatureId.parse(id) == null);
}

test "colliding names preserve distinct selectors and do not invent a suffix" {
    const first = try action.execute(std.testing.allocator, .{ .bytes = "a/b" }, policy);
    defer std.testing.allocator.free(first.feature_id.bytes);
    const second = try action.execute(std.testing.allocator, .{ .bytes = "a-b" }, policy);
    defer std.testing.allocator.free(second.feature_id.bytes);
    try std.testing.expectEqualStrings(first.feature_id.bytes, second.feature_id.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.reference_selector.bytes, second.reference_selector.bytes));
}

test "all allowed lengths produce bounded canonical IDs stable under re-derivation" {
    const selector = "Alpha__Beta-" ** 20 ++ "/" ++ "Éclair__Z9-" ** 20;
    for (1..identity.maximum_id_bytes + 1) |maximum| {
        const selected_policy = identity.NamingPolicy.init(@intCast(maximum)).?;
        const first = try action.execute(std.testing.allocator, .{ .bytes = selector }, selected_policy);
        defer std.testing.allocator.free(first.feature_id.bytes);
        try std.testing.expect(first.feature_id.bytes.len <= maximum);
        try std.testing.expect(identity.FeatureId.parse(first.feature_id.bytes) != null);
        const repeated = try action.execute(std.testing.allocator, .{ .bytes = first.feature_id.bytes }, selected_policy);
        defer std.testing.allocator.free(repeated.feature_id.bytes);
        try std.testing.expectEqualStrings(first.feature_id.bytes, repeated.feature_id.bytes);
    }
}

test "bounded folding rejects expansion without publishing a shortened identity" {
    // Each selector segment fits, but the pinned compatibility expansion exceeds
    // the explicit output ceiling. Truncating the final ID must not bypass it.
    const selector = ("\u{fdfa}" ** 80 ++ "/") ** 15 ++ "name";
    try std.testing.expectError(error.NormalizationLimitExceeded, action.execute(std.testing.allocator, .{ .bytes = selector }, policy));
    try std.testing.expectError(error.InvalidFeatureId, identity.fromFolded(std.testing.allocator, "\xff", policy));
}

test "identity action uses only the bounded pure folding port and propagates its failure" {
    const Fake = struct {
        fn fold(_: std.mem.Allocator, input: []const u8, maximum: usize) @import("ports/unicode_normalizer.zig").Error![]u8 {
            std.debug.assert(std.mem.eql(u8, input, "Some/Selector"));
            std.debug.assert(maximum == identity.maximum_folded_bytes);
            return error.NormalizationFailed;
        }
    };
    const failed: derive.Action = .{ .normalizer = .{ .normalize_fn = unicode.nfc, .fold_fn = Fake.fold } };
    try std.testing.expectError(error.NormalizationFailed, failed.execute(std.testing.allocator, .{ .bytes = "Some/Selector" }, policy));
    const binding = comptime @import("application/workflow_operation_binding.zig").inspect(runners.Derive, &.{});
    try std.testing.expect(binding.valid and !binding.model_provider and !binding.reference_read and !binding.toolchain_read and !binding.toolchain_parser);
}

fn derivationAllocationCase(allocator: std.mem.Allocator) !void {
    const seed = try action.execute(allocator, .{ .bytes = "Café/Orders" }, policy);
    defer allocator.free(seed.feature_id.bytes);
    try std.testing.expectEqualStrings("cafe-orders", seed.feature_id.bytes);
}

test "identity derivation releases every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, derivationAllocationCase, .{});
}

const step: @import("domain/workflow_compilation.zig").CompiledStep = .{
    .id = .{ .bytes = "identity" },
    .operation_id = .{ .bytes = derive.Action.contract.id },
    .parameters = &.{.{ .id = .{ .bytes = "max-length" }, .value = .{ .integer = 64 } }},
    .requires = derive.Action.contract.requires,
    .produces = derive.Action.contract.produces,
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = &.{ .ok, .failed },
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{},
    .retry_authority = null,
};

fn publishAllocationCase(allocator: std.mem.Allocator, selector: *@import("domain/pipeline_data.zig").Value) !void {
    var runner: runners.Derive = .{ .allocator = allocator, .action = action };
    var view: @import("domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(selector_schema.key)] = selector;
    var candidate = runners.Derive.invoke(&runner, .{ .step = .{
        .data = view,
        .step = &step,
        .resources = &.{},
        .model_binding = null,
        .log = pipeline.WorkflowLog.init(.{ .bytes = "TEST".* }),
    } }) catch return error.OutOfMemory;
    var store: Envelope = .init(&.{ selector_schema, runners.seed_schema });
    defer store.deinit();
    defer store.discard(&candidate.delta);
    // Only the runner applies the candidate. A private input copy establishes
    // its required-data precondition without transferring the caller's value.
    var input_delta: pipeline.NodeDelta = .{};
    input_delta.data_writes[@intFromEnum(selector_schema.key)] = try values.create(allocator, selector_schema, reference.RelativeSelector, .{ .bytes = "Café/Orders" });
    defer store.discard(&input_delta);
    try store.apply(.{ .id = "selector@1", .kind = .action, .requires = &.{}, .produces = &.{selector_schema.key}, .side_effect = .none }, &input_delta, .ok);
    try store.apply(derive.Action.contract, &candidate.delta, candidate.outcome);
    const result_view = try store.view(.{ .id = "consumer@1", .kind = .action, .requires = &.{.feature_identity_seed}, .produces = &.{}, .side_effect = .none });
    const seed = try values.read(&result_view, runners.seed_schema, identity.FeatureIdentitySeed);
    try std.testing.expectEqualStrings("cafe-orders", seed.feature_id.bytes);
    try std.testing.expectEqualStrings("Café/Orders", seed.reference_selector.bytes);
    try std.testing.expect(std.meta.eql(policy, seed.naming_policy));
}

test "runner publishes an owned closed seed after scratch cleanup and frees every failed allocation" {
    const selector = try values.create(std.testing.allocator, selector_schema, reference.RelativeSelector, .{ .bytes = "Café/Orders" });
    defer values.destroy(selector);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishAllocationCase, .{selector});
}
