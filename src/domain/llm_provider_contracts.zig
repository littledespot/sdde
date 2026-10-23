const std = @import("std");
const identity = @import("llm_provider_identity.zig");

pub const max_contracts: usize = 256;
pub const max_reasoning_efforts: usize = 16;

pub const RegisteredProviderImplementationId = struct {
    ordinal: u16,

    pub fn init(ordinal: u16) ?RegisteredProviderImplementationId {
        if (ordinal == 0) return null;
        return .{ .ordinal = ordinal };
    }

    pub fn eql(
        left: RegisteredProviderImplementationId,
        right: RegisteredProviderImplementationId,
    ) bool {
        return left.ordinal == right.ordinal;
    }
};

/// Closed provider families. Each tag names its catalogue configuration schema.
pub const ProviderConfigSchema = enum {
    /// Test-only family whose configuration records nothing but the deadline.
    deadline_only,
    aws_bedrock,
    anthropic,

    /// The provider ID a family's compiled entries must carry. The test-only
    /// deadline-only family may not borrow a production family's identity.
    pub fn providerId(self: ProviderConfigSchema) ?[]const u8 {
        return switch (self) {
            .deadline_only => null,
            .aws_bedrock => "aws-bedrock",
            .anthropic => "anthropic",
        };
    }
};

// Closed deployment facts; neither endpoints nor credentials are project data. These
// are the Bedrock runtime source Regions AWS documented on 22 October 2026 (ADR 0029).
pub const BedrockRegion = enum {
    @"us-east-1",
    @"us-east-2",
    @"us-west-1",
    @"us-west-2",
    @"ca-central-1",
    @"ca-west-1",
    @"us-gov-west-1",
    @"us-gov-east-1",
    @"eu-central-1",
    @"eu-central-2",
    @"eu-north-1",
    @"eu-south-1",
    @"eu-south-2",
    @"eu-west-1",
    @"eu-west-2",
    @"eu-west-3",
    @"ap-east-2",
    @"ap-northeast-1",
    @"ap-northeast-2",
    @"ap-northeast-3",
    @"ap-south-1",
    @"ap-south-2",
    @"ap-southeast-1",
    @"ap-southeast-2",
    @"ap-southeast-3",
    @"ap-southeast-4",
    @"ap-southeast-5",
    @"ap-southeast-6",
    @"ap-southeast-7",
    @"il-central-1",
    @"me-central-1",
    @"me-south-1",
    @"af-south-1",
    @"sa-east-1",
    @"mx-central-1",
};
// A Bedrock family is compiled request-field knowledge. A catalogue entry selects one
// for its model; it never supplies an encoding, and no model-name text selects one
// (ADR 0029).
pub const BedrockFamily = enum { converse, @"gpt-oss", luna, claude };

/// The one rule for a catalogue's integer limits: a positive value in the u32
/// range. No limit is zero, and every value fits the transport's u32 fields.
fn positiveU32(value: i64) ?u32 {
    const narrowed = std.math.cast(u32, value) orelse return null;
    return if (narrowed == 0) null else narrowed;
}

/// A catalogue limit on the wire: one integer-written JSON number admitted by
/// `positiveU32`. No quoted, fractional or exponent form names a limit,
/// whichever JSON decoder runs.
fn jsonPositiveU32(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!u32 {
    const token = try source.nextAllocMax(a, .alloc_if_needed, options.max_value_len orelse std.json.default_max_value_len);
    const written = switch (token) {
        .number => |bytes| bytes,
        .allocated_number => |bytes| bytes,
        else => return error.UnexpectedToken,
    };
    if (!std.json.isNumberFormattedLikeAnInteger(written)) return error.InvalidNumber;
    return positiveU32(try std.fmt.parseInt(i64, written, 10)) orelse error.InvalidNumber;
}

/// A model's documented maximum output, recorded in the catalogue and sent as
/// every inference request's ceiling, so no provider default or required field
/// can cut output short (ADR 0011, ADR 0028). It is never zero.
/// Every decoder admits it through `parse`; on the wire it is one integer-written
/// JSON number, as the catalogue decoder requires.
pub const ModelMaximumOutput = struct {
    tokens: u32,

    /// The closed wire kind `strict_json` checks before `jsonParse` runs.
    pub const ClosedJsonWire = u32;

    pub fn parse(tokens: i64) ?ModelMaximumOutput {
        return .{ .tokens = positiveU32(tokens) orelse return null };
    }

    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!ModelMaximumOutput {
        return .{ .tokens = try jsonPositiveU32(a, source, options) };
    }

    pub fn jsonStringify(self: ModelMaximumOutput, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.write(self.tokens);
    }
};

/// A model's provider-operation deadline, recorded in its catalogue entry and
/// bound to every provider operation of a request that selects the entry,
/// including protocol corrections (ADR 0030). It is never zero, and it fits
/// the u32 range so a monotonic deadline can always be formed from it; the
/// catalogue is its one owner.
/// Every decoder admits it through `parse`; on the wire it is one integer-written
/// JSON number, as the catalogue decoder requires.
pub const RequestTimeout = struct {
    milliseconds: u32,

    /// The closed wire kind `strict_json` checks before `jsonParse` runs.
    pub const ClosedJsonWire = u32;

    pub fn parse(milliseconds: i64) ?RequestTimeout {
        return .{ .milliseconds = positiveU32(milliseconds) orelse return null };
    }

    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!RequestTimeout {
        return .{ .milliseconds = try jsonPositiveU32(a, source, options) };
    }

    pub fn jsonStringify(self: RequestTimeout, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.write(self.milliseconds);
    }
};

pub const ValidatedProviderConfig = union(ProviderConfigSchema) {
    deadline_only: struct { request_timeout: RequestTimeout },
    aws_bedrock: struct { region: BedrockRegion, family: BedrockFamily, max_output_tokens: ModelMaximumOutput, request_timeout: RequestTimeout },
    anthropic: struct { max_output_tokens: ModelMaximumOutput, request_timeout: RequestTimeout },

    /// The entry's provider-operation deadline, which every family records.
    pub fn requestTimeout(self: ValidatedProviderConfig) RequestTimeout {
        return switch (self) {
            inline else => |config| config.request_timeout,
        };
    }
};

/// Compiled facts of one provider family; the tag is its configuration schema,
/// so a family's facts cannot accompany another family's catalogue entry.
pub const ProviderFacts = union(ProviderConfigSchema) {
    deadline_only,
    /// The Bedrock family the contract encodes.
    aws_bedrock: BedrockFamily,
    anthropic,

    /// The Bedrock family, or null for another provider family.
    pub fn bedrockFamily(self: ProviderFacts) ?BedrockFamily {
        return switch (self) {
            .aws_bedrock => |family| family,
            .deadline_only, .anthropic => null,
        };
    }
};

pub const ProviderModelContract = struct {
    provider: identity.ProviderId,
    /// The one model an exact contract covers. A Bedrock family contract covers
    /// every catalogue model that names its family, so it has none (ADR 0029).
    model: ?identity.ModelId,
    implementation_id: RegisteredProviderImplementationId,
    facts: ProviderFacts,
    capabilities: @import("model_capabilities.zig").Capabilities,
    supported_reasoning_efforts: []const []const u8 = &.{},

    pub fn configSchema(self: ProviderModelContract) ProviderConfigSchema {
        return std.meta.activeTag(self.facts);
    }

    /// Whether this contract covers a catalogue model with its validated configuration.
    pub fn covers(self: ProviderModelContract, model: identity.ModelId, config: ValidatedProviderConfig) bool {
        if (!@import("llm_provider_config_schema.zig").matches(self.configSchema(), config)) return false;
        return switch (self.facts) {
            .aws_bedrock => |family| config.aws_bedrock.family == family,
            .deadline_only, .anthropic => if (self.model) |registered| registered.eql(model) else false,
        };
    }
};

pub const Registry = struct {
    entries: []const ProviderModelContract,

    pub const empty: Registry = .{ .entries = &.{} };

    pub fn validate(self: Registry) Error!void {
        if (self.entries.len > max_contracts) return error.InvalidProviderModelContracts;
        for (self.entries, 0..) |entry, index| {
            // Only a Bedrock family contract covers models it does not name.
            if ((entry.model == null) != (entry.facts == .aws_bedrock)) return error.InvalidProviderModelContracts;
            if (entry.model) |model| if (identity.ModelId.parse(model.bytes) == null) return error.InvalidProviderModelContracts;
            // A family's entries carry its provider identity, and no other
            // provider may claim a production family's identity.
            const family = entry.configSchema();
            if (family.providerId()) |expected| {
                if (!std.mem.eql(u8, entry.provider.bytes, expected)) return error.InvalidProviderModelContracts;
            } else for ([_]ProviderConfigSchema{ .aws_bedrock, .anthropic }) |production| {
                if (std.mem.eql(u8, entry.provider.bytes, production.providerId().?)) return error.InvalidProviderModelContracts;
            }
            if (identity.ProviderId.parse(entry.provider.bytes) == null or
                RegisteredProviderImplementationId.init(entry.implementation_id.ordinal) == null or
                entry.supported_reasoning_efforts.len > max_reasoning_efforts or !entry.capabilities.isValid())
            {
                return error.InvalidProviderModelContracts;
            }
            for (entry.supported_reasoning_efforts, 0..) |effort, effort_index| {
                if (effort.len == 0) return error.InvalidProviderModelContracts;
                for (entry.supported_reasoning_efforts[0..effort_index]) |previous| {
                    if (std.mem.eql(u8, effort, previous)) return error.InvalidProviderModelContracts;
                }
            }
            for (self.entries[0..index]) |previous| {
                // One contract per exact model, and one per Bedrock family.
                const same_coverage = if (entry.model) |model|
                    previous.model != null and model.eql(previous.model.?)
                else
                    std.meta.eql(entry.facts, previous.facts);
                if (entry.provider.eql(previous.provider) and same_coverage) {
                    return error.InvalidProviderModelContracts;
                }
                // One implementation per provider, and one family per
                // implementation: different families never alias an ID.
                if ((entry.provider.eql(previous.provider) and !entry.implementation_id.eql(previous.implementation_id)) or
                    (entry.implementation_id.eql(previous.implementation_id) and family != previous.configSchema()))
                {
                    return error.InvalidProviderModelContracts;
                }
            }
        }
    }

    pub fn containsProvider(self: Registry, provider: identity.ProviderId) bool {
        for (self.entries) |entry| {
            if (entry.provider.eql(provider)) return true;
        }
        return false;
    }

    /// The configuration schema of a registered provider's family. Every contract
    /// of one provider shares it, so a catalogue entry decodes before its join.
    pub fn configSchema(self: Registry, provider: identity.ProviderId) ?ProviderConfigSchema {
        for (self.entries) |entry| {
            if (entry.provider.eql(provider)) return entry.configSchema();
        }
        return null;
    }

    pub fn resolve(
        self: Registry,
        provider: identity.ProviderId,
        model: identity.ModelId,
        config: ValidatedProviderConfig,
    ) ?*const ProviderModelContract {
        for (self.entries) |*entry| {
            if (entry.provider.eql(provider) and entry.covers(model, config)) return entry;
        }
        return null;
    }
};

pub const Error = error{InvalidProviderModelContracts};

pub fn supportsReasoningEffort(
    supported_values: []const []const u8,
    selected: ?[]const u8,
) bool {
    const value = selected orelse return true;
    for (supported_values) |supported| {
        if (std.mem.eql(u8, value, supported)) return true;
    }
    return false;
}

test "contract registry is exact unique and provider consistent" {
    const capabilities: @import("model_capabilities.zig").Capabilities = .{
        .inference = true,
        .structured_response = .prompt_only,
        .temperature = false,
    };
    const provider = identity.ProviderId.parse("compiled-provider").?;
    const first = ProviderModelContract{
        .provider = provider,
        .model = identity.ModelId.parse("model-a").?,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .facts = .deadline_only,
        .capabilities = capabilities,
        .supported_reasoning_efforts = &.{ "low", "high" },
    };
    const second = ProviderModelContract{
        .provider = provider,
        .model = identity.ModelId.parse("model-b").?,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .facts = .deadline_only,
        .capabilities = capabilities,
    };
    const registry: Registry = .{ .entries = &.{ first, second } };
    try registry.validate();
    const deadline_only: ValidatedProviderConfig = .{ .deadline_only = .{ .request_timeout = .{ .milliseconds = 1000 } } };
    try std.testing.expect(registry.resolve(provider, first.model.?, deadline_only) != null);
    try std.testing.expect(registry.resolve(provider, identity.ModelId.parse("model-c").?, deadline_only) == null);
    try std.testing.expect(supportsReasoningEffort(first.supported_reasoning_efforts, "low"));
    try std.testing.expect(!supportsReasoningEffort(first.supported_reasoning_efforts, "medium"));

    const duplicate: Registry = .{ .entries = &.{ first, first } };
    try std.testing.expectError(error.InvalidProviderModelContracts, duplicate.validate());
    var conflicting = second;
    conflicting.implementation_id = RegisteredProviderImplementationId.init(2).?;
    const inconsistent: Registry = .{ .entries = &.{ first, conflicting } };
    try std.testing.expectError(error.InvalidProviderModelContracts, inconsistent.validate());
    // An exact contract always names its model.
    var unnamed = first;
    unnamed.model = null;
    try std.testing.expectError(error.InvalidProviderModelContracts, (Registry{ .entries = &.{unnamed} }).validate());
}

test "Bedrock family contracts cover every model and Region that names their family, once each" {
    const capabilities: @import("model_capabilities.zig").Capabilities = .{ .inference = true, .structured_response = .prompt_only, .temperature = false };
    const provider = identity.ProviderId.parse("aws-bedrock").?;
    var contracts: [std.enums.values(BedrockFamily).len]ProviderModelContract = undefined;
    for (&contracts, std.enums.values(BedrockFamily)) |*contract, family| contract.* = .{
        .provider = provider,
        .model = null,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .facts = .{ .aws_bedrock = family },
        .capabilities = capabilities,
    };
    const registry: Registry = .{ .entries = &contracts };
    try registry.validate();
    try std.testing.expectEqual(ProviderConfigSchema.aws_bedrock, registry.configSchema(provider).?);
    for (std.enums.values(BedrockFamily)) |family| {
        for (std.enums.values(BedrockRegion)) |region| {
            for ([_][]const u8{ "MOCK-model", "MOCK.vendor.model-v1:0", "arn:aws:bedrock:MOCK:application-inference-profile/x" }) |raw| {
                const model = identity.ModelId.parse(raw).?;
                const config: ValidatedProviderConfig = .{ .aws_bedrock = .{ .region = region, .family = family, .max_output_tokens = .{ .tokens = 1 }, .request_timeout = .{ .milliseconds = 1 } } };
                const resolved = registry.resolve(provider, model, config).?;
                try std.testing.expectEqual(family, resolved.facts.bedrockFamily().?);
                // No other family covers it, and no other provider's configuration does.
                for (contracts) |other| if (other.facts.aws_bedrock != family) try std.testing.expect(!other.covers(model, config));
                try std.testing.expect(registry.resolve(provider, model, .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 1 }, .request_timeout = .{ .milliseconds = 1 } } }) == null);
            }
        }
    }
    // A family registers once, and a family contract never names one model.
    const repeated: Registry = .{ .entries = &.{ contracts[0], contracts[0] } };
    try std.testing.expectError(error.InvalidProviderModelContracts, repeated.validate());
    var named = contracts[0];
    named.model = identity.ModelId.parse("MOCK-model").?;
    try std.testing.expectError(error.InvalidProviderModelContracts, (Registry{ .entries = &.{named} }).validate());
}

test "contract registry binds each provider family to its identity and implementation" {
    const capabilities: @import("model_capabilities.zig").Capabilities = .{ .inference = true, .structured_response = .prompt_only, .temperature = false };
    const bedrock: ProviderModelContract = .{
        .provider = identity.ProviderId.parse("aws-bedrock").?,
        .model = null,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .facts = .{ .aws_bedrock = .converse },
        .capabilities = capabilities,
    };
    const anthropic: ProviderModelContract = .{
        .provider = identity.ProviderId.parse("anthropic").?,
        .model = identity.ModelId.parse("model-b").?,
        .implementation_id = RegisteredProviderImplementationId.init(2).?,
        .facts = .anthropic,
        .capabilities = capabilities,
    };
    try (Registry{ .entries = &.{ bedrock, anthropic } }).validate();
    try std.testing.expect(anthropic.covers(anthropic.model.?, .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!anthropic.covers(anthropic.model.?, .{ .aws_bedrock = .{ .region = .@"us-west-2", .family = .converse, .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } }));
    try std.testing.expect(!bedrock.covers(anthropic.model.?, .{ .anthropic = .{ .max_output_tokens = .{ .tokens = 128000 }, .request_timeout = .{ .milliseconds = 180000 } } }));

    // Two families never share an implementation ID.
    var aliased = anthropic;
    aliased.implementation_id = bedrock.implementation_id;
    try std.testing.expectError(error.InvalidProviderModelContracts, (Registry{ .entries = &.{ bedrock, aliased } }).validate());
    // A family's facts cannot accompany another provider's identity.
    var foreign_identity = anthropic;
    foreign_identity.provider = bedrock.provider;
    try std.testing.expectError(error.InvalidProviderModelContracts, (Registry{ .entries = &.{foreign_identity} }).validate());
    var borrowed_identity = anthropic;
    borrowed_identity.facts = .deadline_only;
    try std.testing.expectError(error.InvalidProviderModelContracts, (Registry{ .entries = &.{borrowed_identity} }).validate());
    try std.testing.expect(anthropic.facts.bedrockFamily() == null);
}
