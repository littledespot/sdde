const std = @import("std");
const document = @import("llm_provider_document.zig");
const identity = @import("llm_provider_identity.zig");
const strict_json = @import("strict_json.zig");

pub const Error = error{LLMProviderConfigParseError};

/// Decodes the captured provider document through the closed strict shape and checks its bounded
/// common shape. The caller owns the result.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!document.Owned {
    var owned = document.Owned.init(allocator);
    errdefer owned.deinit();
    owned.document = strict_json.decode(
        document.RawLLMProviderDocument,
        owned.allocator(),
        bytes,
        .{ .maximum_bytes = document.max_bytes, .maximum_depth = document.max_nesting_depth },
    ) catch return error.LLMProviderConfigParseError;

    try validateIntegers(allocator, bytes);
    try validateCommonShape(owned.value());
    return owned;
}

/// The catalogue holds integers only, wherever they stand, a model's `config` included.
fn validateIntegers(allocator: std.mem.Allocator, bytes: []const u8) Error!void {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    while (true) switch (scanner.next() catch return error.LLMProviderConfigParseError) {
        .number, .partial_number => |number| {
            if (!isIntegerLexeme(number)) return error.LLMProviderConfigParseError;
        },
        .allocated_number => |number| {
            defer allocator.free(number);
            if (!isIntegerLexeme(number)) return error.LLMProviderConfigParseError;
        },
        .end_of_document => return,
        else => {},
    };
}

fn validateCommonShape(raw: *const document.RawLLMProviderDocument) Error!void {
    if (raw.providers.len > document.max_providers) {
        return error.LLMProviderConfigParseError;
    }
    var model_total: usize = 0;
    for (raw.providers) |provider| {
        if (identity.ProviderId.parse(provider.provider) == null or
            provider.models.len > document.max_models_per_provider)
        {
            return error.LLMProviderConfigParseError;
        }
        model_total = std.math.add(usize, model_total, provider.models.len) catch {
            return error.LLMProviderConfigParseError;
        };
        if (model_total > document.max_models_total) {
            return error.LLMProviderConfigParseError;
        }
        for (provider.models) |model| {
            if (identity.ModelId.parse(model.model) == null or model.config != .object) {
                return error.LLMProviderConfigParseError;
            }
        }
    }
}

fn isIntegerLexeme(bytes: []const u8) bool {
    return std.mem.indexOfAny(u8, bytes, ".eE") == null;
}

test "strict decoder accepts the exact bounded common shape" {
    const bytes =
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","json": false, "config":{}}]}]}
    ;
    var decoded = try decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(usize, 1), decoded.value().providers.len);
    try std.testing.expectEqualStrings("model-a", decoded.value().providers[0].models[0].model);
}

test "strict decoder rejects malformed closed-shape and transport violations" {
    const invalid = [_][]const u8{
        "{",
        "{}",
        "\xef\xbb\xbf{\"providers\":[]}",
        "{\"providers\":[]} true",
        "{\"providers\":[],\"extra\":true}",
        "{\"providers\":[],\"providers\":[]}",
        "{\"providers\":{}}",
        "{\"providers\":[{\"models\":[]}]}",
        "{\"providers\":[{\"provider\":\"compiled\"}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"config\":{}}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\"}]}]}",
        "{\"providers\":[{\"provider\":\"Compiled\",\"models\":[]}]}",
        "{\"providers\":[{\"provider\":[99],\"models\":[]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":[109],\"json\":false,\"config\":{}}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[],\"extra\":true}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"json\":false,\"config\":[],\"extra\":true}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"json\":false,\"config\":{\"weight\":1.5}}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"json\":false,\"config\":{\"key\":true,\"key\":false}}]}]}",
    };
    for (invalid) |bytes| {
        try std.testing.expectError(
            error.LLMProviderConfigParseError,
            decode(std.testing.allocator, bytes),
        );
    }
}

test "strict decoder enforces nesting and collection totals" {
    const allocator = std.testing.allocator;

    var too_deep: std.array_list.Managed(u8) = .init(allocator);
    defer too_deep.deinit();
    try too_deep.appendSlice("{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"m\",\"json\":false,\"config\":");
    try too_deep.appendNTimes('[', document.max_nesting_depth);
    try too_deep.appendSlice("0");
    try too_deep.appendNTimes(']', document.max_nesting_depth);
    try too_deep.appendSlice("}]}]}");
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        decode(allocator, too_deep.items),
    );

    var at_model_limit: std.array_list.Managed(u8) = .init(allocator);
    defer at_model_limit.deinit();
    try appendModelDocument(&at_model_limit, document.max_models_total);
    var decoded = try decode(allocator, at_model_limit.items);
    decoded.deinit();

    var too_many: std.array_list.Managed(u8) = .init(allocator);
    defer too_many.deinit();
    try appendModelDocument(&too_many, document.max_models_total + 1);
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        decode(allocator, too_many.items),
    );

    var at_provider_limit: std.array_list.Managed(u8) = .init(allocator);
    defer at_provider_limit.deinit();
    try appendProviderDocument(&at_provider_limit, document.max_providers);
    decoded = try decode(allocator, at_provider_limit.items);
    decoded.deinit();

    var too_many_providers: std.array_list.Managed(u8) = .init(allocator);
    defer too_many_providers.deinit();
    try appendProviderDocument(&too_many_providers, document.max_providers + 1);
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        decode(allocator, too_many_providers.items),
    );
}

fn appendModelDocument(output: *std.array_list.Managed(u8), count: usize) !void {
    try output.appendSlice("{\"providers\":[{\"provider\":\"compiled\",\"models\":[");
    for (0..count) |index| {
        if (index != 0) try output.append(',');
        try output.print("{{\"model\":\"m{d}\",\"json\":false,\"config\":{{}}}}", .{index});
    }
    try output.appendSlice("]}]}");
}

fn appendProviderDocument(output: *std.array_list.Managed(u8), count: usize) !void {
    try output.appendSlice("{\"providers\":[");
    for (0..count) |index| {
        if (index != 0) try output.append(',');
        try output.print("{{\"provider\":\"p{d}\",\"models\":[]}}", .{index});
    }
    try output.appendSlice("]}");
}

test "model JSON selection is an explicit closed boolean" {
    const a = std.testing.allocator;
    const prefix = "{\"providers\":[{\"provider\":\"compiled-provider\",\"models\":[{\"model\":\"model-a\",\"config\":{}";
    for ([_][]const u8{ "", ",\"json\":null", ",\"json\":1", ",\"json\":\"true\"", ",\"json\":true,\"json\":false", ",\"json\":true,\"extra\":false" }) |field| {
        const bytes = try std.mem.concat(a, u8, &.{ prefix, field, "}]}]}" });
        defer a.free(bytes);
        try std.testing.expectError(error.LLMProviderConfigParseError, decode(a, bytes));
    }
    for ([_]bool{ false, true }) |json| {
        const bytes = try std.mem.concat(a, u8, &.{ prefix, ",\"json\":", if (json) "true" else "false", "}]}]}" });
        defer a.free(bytes);
        var decoded = try decode(a, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(json, decoded.value().providers[0].models[0].json);
    }
}
