const std = @import("std");
const decode_toolkit = @import("actions/config/decode_sddtoolkit_config.zig");
const build_registry = @import("actions/provider/build_llm_provider_registry.zig");
const decode_provider = @import("actions/provider/decode_llm_provider_config.zig");
const validate_allowlist = @import("actions/provider/validate_repository_model_allowlist.zig");
const validate_registry = @import("actions/provider/validate_llm_provider_registry.zig");
const registry_service = @import("application/llm_provider_registry_service.zig");
const config = @import("domain/config.zig");
const allowlist_contract = @import("domain/repository_model_allowlist.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const document = @import("domain/llm_provider_document.zig");
const identity = @import("domain/llm_provider_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const registry_contract = @import("domain/llm_provider_registry.zig");

comptime {
    pipeline.validateLinear(
        &.{ .raw_llm_provider_config, .engine_config },
        &.{
            decode_provider.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
            validate_allowlist.Action.contract,
        },
    );
}

const provider_id = identity.ProviderId.parse("compiled-provider").?;
const implementation_id = contracts.RegisteredProviderImplementationId.init(1).?;
const compiled_contracts: contracts.Registry = .{ .entries = &.{
    .{
        .provider = provider_id,
        .model = identity.ModelId.parse("model-a").?,
        .implementation_id = implementation_id,
        .facts = .deadline_only,
        .capabilities = @import("model_contract_test_fixture.zig").capabilities,
        .supported_reasoning_efforts = &.{ "low", "high" },
    },
    .{
        .provider = provider_id,
        .model = identity.ModelId.parse("model-b").?,
        .implementation_id = implementation_id,
        .facts = .deadline_only,
        .capabilities = @import("model_contract_test_fixture.zig").capabilities,
    },
} };

const valid_provider_document =
    \\{
    \\  "providers": [{
    \\    "provider": "compiled-provider",
    \\    "models": [
    \\      { "model": "model-a", "json": false, "config": { "requestTimeoutMs": 1000 } },
    \\      { "model": "model-b", "json": false, "config": { "requestTimeoutMs": 2000 } }
    \\    ]
    \\  }]
    \\}
;

test "registry service owns the complete immutable sorted catalogue" {
    var fixture = try Fixture.init(std.testing.allocator, valid_provider_document);
    defer fixture.deinit();

    const provider_registry = fixture.service.registry();
    try std.testing.expectEqual(@as(usize, 2), provider_registry.count());
    const first = provider_registry.resolve(
        provider_id,
        identity.ModelId.parse("model-a").?,
    ).?;
    try std.testing.expectEqual(@as(u16, 1), first.id.ordinal);
    try std.testing.expect(provider_registry.resolveId(first.id) == first);
    // Each entry keeps its own catalogue deadline.
    try std.testing.expectEqual(@as(u32, 1000), first.config.requestTimeout().milliseconds);
    try std.testing.expectEqual(@as(u32, 2000), provider_registry.resolve(provider_id, identity.ModelId.parse("model-b").?).?.config.requestTimeout().milliseconds);
    try std.testing.expect(provider_registry.resolve(
        provider_id,
        identity.ModelId.parse("not-configured").?,
    ) == null);
}

test "repository allowlist accepts all catalogue models" {
    var fixture = try Fixture.init(std.testing.allocator, valid_provider_document);
    defer fixture.deinit();
    var toolkit = try decodeToolkit(all_slots_config);
    defer toolkit.deinit();

    const owner = try (validate_allowlist.Action{}).execute(
        std.testing.allocator,
        &toolkit.value().models,
        fixture.service.registry(),
    );
    defer allowlist_contract.deinitOwner(owner);
    const allowed = allowlist_contract.allowlist(owner);
    try std.testing.expectEqual(@as(usize, 2), allowed.count());
    try std.testing.expectEqualStrings("low", allowed.resolveSlot(identity.ModelSlotId.parse("first").?).?.reasoning_effort.?);
    try std.testing.expect(allowed.resolveSlot(identity.ModelSlotId.parse("second").?) != null);
}

test "repository allowlist accepts a strict subset and leaves unused catalogue entries unauthorized" {
    var fixture = try Fixture.init(std.testing.allocator, valid_provider_document);
    defer fixture.deinit();
    var toolkit = try decodeToolkit(subset_slots_config);
    defer toolkit.deinit();

    const owner = try (validate_allowlist.Action{}).execute(
        std.testing.allocator,
        &toolkit.value().models,
        fixture.service.registry(),
    );
    defer allowlist_contract.deinitOwner(owner);
    const allowed = allowlist_contract.allowlist(owner);
    try std.testing.expectEqual(@as(usize, 1), allowed.count());
    const selected = allowed.resolveSlot(identity.ModelSlotId.parse("first").?).?;
    const unused = fixture.service.registry().resolve(
        provider_id,
        identity.ModelId.parse("model-b").?,
    ).?;
    try std.testing.expect(!selected.registry_entry_id.eql(unused.id));
    try std.testing.expect(allowed.resolveSlot(identity.ModelSlotId.parse("second").?) == null);
}

test "multiple slots may reference one catalogue model without duplicating authority" {
    var fixture = try Fixture.init(std.testing.allocator, valid_provider_document);
    defer fixture.deinit();
    var toolkit = try decodeToolkit(repeated_model_slots_config);
    defer toolkit.deinit();

    const owner = try (validate_allowlist.Action{}).execute(
        std.testing.allocator,
        &toolkit.value().models,
        fixture.service.registry(),
    );
    defer allowlist_contract.deinitOwner(owner);
    const allowed = allowlist_contract.allowlist(owner);
    try std.testing.expectEqual(@as(usize, 2), allowed.count());
    try std.testing.expect(allowed.resolveSlot(identity.ModelSlotId.parse("first").?).?.registry_entry_id.eql(
        allowed.resolveSlot(identity.ModelSlotId.parse("second").?).?.registry_entry_id,
    ));
}

test "one absent or option-incompatible slot rejects the complete allowlist" {
    var fixture = try Fixture.init(std.testing.allocator, valid_provider_document);
    defer fixture.deinit();

    inline for (.{ missing_model_slots_config, unsupported_option_slots_config }) |bytes| {
        var toolkit = try decodeToolkit(bytes);
        defer toolkit.deinit();
        try std.testing.expectError(
            error.LLMProviderModelBindingInvalid,
            (validate_allowlist.Action{}).execute(
                std.testing.allocator,
                &toolkit.value().models,
                fixture.service.registry(),
            ),
        );
    }
}

test "unsupported duplicate invalid-config and partially valid catalogues publish no registry" {
    const invalid = [_][]const u8{
        \\{"providers":[{"provider":"unknown-provider","models":[]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000,"extra":true}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":0}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":4294967296}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[]},{"provider":"compiled-provider","models":[]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000}},{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{"requestTimeoutMs":1000}},{"model":"not-compiled","json": false, "config":{"requestTimeoutMs":1000}}]}]}
        ,
    };

    for (invalid) |bytes| {
        var raw = try (decode_provider.Action{}).execute(std.testing.allocator, bytes);
        defer raw.deinit();
        try std.testing.expectError(
            error.LLMProviderRegistryInvalid,
            (build_registry.Action{ .contracts = &compiled_contracts }).execute(
                std.testing.allocator,
                raw.value(),
            ),
        );
    }
}

test "registry validator independently rejects facts not supplied by compiler contracts" {
    var raw = try (decode_provider.Action{}).execute(
        std.testing.allocator,
        valid_provider_document,
    );
    defer raw.deinit();
    var candidate = try (build_registry.Action{ .contracts = &compiled_contracts }).execute(
        std.testing.allocator,
        raw.value(),
    );
    defer candidate.deinit();
    candidate.entries[0].implementation_id =
        contracts.RegisteredProviderImplementationId.init(2).?;

    try std.testing.expectError(
        error.LLMProviderRegistryInvalid,
        (validate_registry.Action{ .contracts = &compiled_contracts }).execute(
            std.testing.allocator,
            candidate,
        ),
    );
}

test "production-empty contract registry activates no project provider" {
    var raw = try (decode_provider.Action{}).execute(
        std.testing.allocator,
        valid_provider_document,
    );
    defer raw.deinit();
    try std.testing.expectError(
        error.LLMProviderRegistryInvalid,
        (build_registry.Action{ .contracts = &contracts.Registry.empty }).execute(
            std.testing.allocator,
            raw.value(),
        ),
    );
}

const Fixture = struct {
    raw: document.Owned,
    candidate: registry_contract.Candidate,
    service: registry_service.LLMProviderRegistryService,

    fn init(allocator: std.mem.Allocator, bytes: []const u8) !Fixture {
        var raw = try (decode_provider.Action{}).execute(allocator, bytes);
        errdefer raw.deinit();
        var candidate = try (build_registry.Action{ .contracts = &compiled_contracts }).execute(
            allocator,
            raw.value(),
        );
        errdefer candidate.deinit();
        const owner = try (validate_registry.Action{ .contracts = &compiled_contracts }).execute(
            allocator,
            candidate,
        );
        return .{
            .raw = raw,
            .candidate = candidate,
            .service = .init(owner),
        };
    }

    fn deinit(self: *Fixture) void {
        self.service.deinit();
        self.candidate.deinit();
        self.raw.deinit();
        self.* = undefined;
    }
};

fn decodeToolkit(bytes: []const u8) !config.Owned {
    return (decode_toolkit.Action{}).execute(std.testing.allocator, bytes);
}

const all_slots_config = toolkitPrefix() ++
    \\{"first":{"provider":"compiled-provider","model":"model-a","reasoningEffort":"low"},"second":{"provider":"compiled-provider","model":"model-b"}}
++ toolkitSuffix();

const subset_slots_config = toolkitPrefix() ++
    \\{"first":{"provider":"compiled-provider","model":"model-a"}}
++ toolkitSuffix();

const repeated_model_slots_config = toolkitPrefix() ++
    \\{"first":{"provider":"compiled-provider","model":"model-a"},"second":{"provider":"compiled-provider","model":"model-a"}}
++ toolkitSuffix();

const missing_model_slots_config = toolkitPrefix() ++
    \\{"first":{"provider":"compiled-provider","model":"model-a"},"missing":{"provider":"compiled-provider","model":"model-c"}}
++ toolkitSuffix();

const unsupported_option_slots_config = toolkitPrefix() ++
    \\{"first":{"provider":"compiled-provider","model":"model-a","reasoningEffort":"medium"}}
++ toolkitSuffix();

fn toolkitPrefix() []const u8 {
    return
    \\{"logs":{"level":"info","console":false},"models":{"slots":
    ;
}

fn toolkitSuffix() []const u8 {
    return
    \\},"paths":{"specs":"specs","references":"references","specsArchive":"specs/archive","workflows":"workflows","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":".sddproviders.json"}}
    ;
}

test "catalogue JSON selection retains per-model choices and rejects unsupported siblings" {
    const a = std.testing.allocator;
    var registered_entries = compiled_contracts.entries[0..2].*;
    registered_entries[0].capabilities.structured_response = .native_json_schema;
    const registered: contracts.Registry = .{ .entries = &registered_entries };
    const bytes =
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json":true,"config":{"requestTimeoutMs":1000}},{"model":"model-b","json":false,"config":{"requestTimeoutMs":1000}}]}]}
    ;
    var decoded = try (decode_provider.Action{}).execute(a, bytes);
    defer decoded.deinit();
    var candidate = try (build_registry.Action{ .contracts = &registered }).execute(a, decoded.value());
    defer candidate.deinit();
    try std.testing.expect(candidate.entries[0].json);
    try std.testing.expect(!candidate.entries[1].json);
    const owner = try registry_contract.createValidated(a, candidate, registered);
    defer registry_contract.deinitOwner(owner);
    const captured = registry_contract.registry(owner);
    try std.testing.expectEqual(.native_schema, captured.resolveId(.{ .ordinal = 1 }).?.responseMode());
    try std.testing.expectEqual(.prompt_only, captured.resolveId(.{ .ordinal = 2 }).?.responseMode());
    candidate.entries[0].json = false;
    // The owned invocation snapshot does not reread mutable candidate configuration.
    try std.testing.expect(captured.resolveId(.{ .ordinal = 1 }).?.json);
    candidate.entries[1].json = true;
    try std.testing.expectError(error.InvalidLLMProviderRegistry, registry_contract.createValidated(a, candidate, registered));
}

test "Bedrock catalogue entries take every compiled control from the family they name" {
    const registered = @import("composition/provider_model_contracts.zig").registry;
    const model_ids = @import("model_contract_test_fixture.zig").bedrock_model_ids;
    const Entry = struct { model: []const u8, json: bool, config: struct { region: []const u8, family: []const u8, maxOutputTokens: u32, requestTimeoutMs: u32 } };
    const Provider = struct { provider: []const u8, models: []const Entry };
    for (std.enums.values(contracts.BedrockFamily)) |family| {
        const contract = for (registered.entries) |*entry| {
            if (entry.facts.bedrockFamily() == family) break entry;
        } else return error.TestUnexpectedResult;
        for (std.enums.values(contracts.BedrockRegion)) |region| for ([_]bool{ false, true }) |json| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var models: [model_ids.len]Entry = undefined;
            for (&models, model_ids) |*model, id| model.* = .{ .model = id, .json = json, .config = .{ .region = @tagName(region), .family = @tagName(family), .maxOutputTokens = 16000, .requestTimeoutMs = 180000 } };
            const bytes = try std.json.Stringify.valueAlloc(a, .{ .providers = &[_]Provider{.{ .provider = "aws-bedrock", .models = &models }} }, .{});
            var raw = try (decode_provider.Action{}).execute(a, bytes);
            defer raw.deinit();
            var candidate = try (build_registry.Action{ .contracts = &registered }).execute(a, raw.value());
            defer candidate.deinit();
            const owner = try registry_contract.createValidated(a, candidate, registered);
            defer registry_contract.deinitOwner(owner);
            for (model_ids) |id| {
                const entry = registry_contract.registry(owner).resolve(identity.ProviderId.parse("aws-bedrock").?, identity.ModelId.parse(id).?).?;
                try std.testing.expectEqual(family, entry.facts.bedrockFamily().?);
                try std.testing.expectEqualDeep(contracts.ValidatedProviderConfig{ .aws_bedrock = .{ .region = region, .family = family, .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }, entry.config);
                try std.testing.expectEqualDeep(contract.capabilities, entry.capabilities);
                try std.testing.expectEqual(contract.supported_reasoning_efforts.len, entry.supported_reasoning_efforts.len);
                for (contract.supported_reasoning_efforts, entry.supported_reasoning_efforts) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
                try std.testing.expectEqual(@as(@TypeOf(entry.responseMode()), if (json) .native_schema else .prompt_only), entry.responseMode());
            }
        };
    }
    // The catalogue names a compiled family exactly; it never supplies an encoding.
    const a = std.testing.allocator;
    const valid = try std.json.Stringify.valueAlloc(a, .{ .providers = &[_]Provider{.{ .provider = "aws-bedrock", .models = &.{Entry{ .model = model_ids[0], .json = true, .config = .{
        .region = @tagName(std.enums.values(contracts.BedrockRegion)[0]),
        .family = @tagName(std.enums.values(contracts.BedrockFamily)[0]),
        .maxOutputTokens = 16000,
        .requestTimeoutMs = 180000,
    } }} }} }, .{});
    defer a.free(valid);
    const family_field = try std.fmt.allocPrint(a, "\"family\":\"{s}\",", .{@tagName(std.enums.values(contracts.BedrockFamily)[0])});
    defer a.free(family_field);
    for ([_][2][]const u8{
        .{ family_field, "" },
        .{ family_field, "\"family\":\"unknown\"," },
        .{ family_field, "\"family\":null," },
        .{ family_field, "\"family\":\"CONVERSE\"," },
        .{ family_field, "\"family\":[\"converse\"]," },
        .{ "\"config\":{", "\"config\":{\"profile\":\"converse\"," },
    }) |replacement| {
        const changed = try std.mem.replaceOwned(u8, a, valid, replacement[0], replacement[1]);
        defer a.free(changed);
        try std.testing.expect(!std.mem.eql(u8, valid, changed));
        var raw = try (decode_provider.Action{}).execute(a, changed);
        defer raw.deinit();
        try std.testing.expectError(error.LLMProviderRegistryInvalid, (build_registry.Action{ .contracts = &registered }).execute(a, raw.value()));
    }
    try std.testing.expect(!@hasField(registry_contract.CandidateEntry, "bedrock_request_profile"));
    const injected = try std.mem.replaceOwned(u8, a, valid, "\"json\":true", "\"json\":true,\"family\":\"converse\"");
    defer a.free(injected);
    try std.testing.expectError(error.LLMProviderConfigParseError, (decode_provider.Action{}).execute(a, injected));
}
