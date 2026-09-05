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
        .config_schema = .empty_object,
        .capabilities = @import("model_contract_test_fixture.zig").capabilities,
        .supported_reasoning_efforts = &.{ "low", "high" },
    },
    .{
        .provider = provider_id,
        .model = identity.ModelId.parse("model-b").?,
        .implementation_id = implementation_id,
        .config_schema = .empty_object,
        .capabilities = @import("model_contract_test_fixture.zig").capabilities,
    },
} };

const valid_provider_document =
    \\{
    \\  "providers": [{
    \\    "provider": "compiled-provider",
    \\    "models": [
    \\      { "model": "model-a", "config": {} },
    \\      { "model": "model-b", "config": {} }
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
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{"extra":true}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[]},{"provider":"compiled-provider","models":[]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{}},{"model":"model-a","config":{}}]}]}
        ,
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{}},{"model":"not-compiled","config":{}}]}]}
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
    \\{"logs":{"level":"info","console":false,"promptCapture":[]},"models":{"slots":
    ;
}

fn toolkitSuffix() []const u8 {
    return
    \\},"paths":{"specs":"specs","references":"references","specsArchive":"specs/archive","workflows":"workflows","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":".sddproviders.json"}}
    ;
}
