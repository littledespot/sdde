const std = @import("std");
const document = @import("../../domain/llm_provider_document.zig");
const identity = @import("../../domain/llm_provider_identity.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LLMProviderConfigParseError};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "decode-llm-provider-config@1",
        .kind = .action,
        .requires = &.{.raw_llm_provider_config},
        .produces = &.{.raw_llm_provider_document},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        bytes: []const u8,
    ) Error!document.Owned {
        try validateTransport(allocator, bytes);

        var owned = document.Owned.init(allocator);
        errdefer owned.deinit();
        owned.document = std.json.parseFromSliceLeaky(
            document.RawLLMProviderDocument,
            owned.allocator(),
            bytes,
            .{
                .duplicate_field_behavior = .@"error",
                .ignore_unknown_fields = false,
                .max_value_len = document.max_bytes,
                .allocate = .alloc_always,
            },
        ) catch return error.LLMProviderConfigParseError;

        try validateCommonShape(owned.value());
        return owned;
    }
};

fn validateTransport(allocator: std.mem.Allocator, bytes: []const u8) Error!void {
    if (bytes.len > document.max_bytes or !std.unicode.utf8ValidateSlice(bytes) or
        std.mem.startsWith(u8, bytes, "\xef\xbb\xbf"))
    {
        return error.LLMProviderConfigParseError;
    }

    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var depth: usize = 0;
    while (true) {
        const token = scanner.next() catch return error.LLMProviderConfigParseError;
        switch (token) {
            .object_begin, .array_begin => {
                depth += 1;
                if (depth > document.max_nesting_depth) {
                    return error.LLMProviderConfigParseError;
                }
            },
            .object_end, .array_end => {
                if (depth == 0) return error.LLMProviderConfigParseError;
                depth -= 1;
            },
            .number, .partial_number => |number| {
                if (!isIntegerLexeme(number)) return error.LLMProviderConfigParseError;
            },
            .allocated_number => |number| {
                defer allocator.free(number);
                if (!isIntegerLexeme(number)) return error.LLMProviderConfigParseError;
            },
            .end_of_document => {
                if (depth != 0) return error.LLMProviderConfigParseError;
                break;
            },
            else => {},
        }
    }
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
        \\{"providers":[{"provider":"compiled-provider","models":[{"model":"model-a","config":{}}]}]}
    ;
    var decoded = try (Action{}).execute(std.testing.allocator, bytes);
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
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[],\"extra\":true}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"config\":[],\"extra\":true}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"config\":{\"weight\":1.5}}]}]}",
        "{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"model-a\",\"config\":{\"key\":true,\"key\":false}}]}]}",
    };
    for (invalid) |bytes| {
        try std.testing.expectError(
            error.LLMProviderConfigParseError,
            (Action{}).execute(std.testing.allocator, bytes),
        );
    }
}

test "strict decoder enforces nesting and collection totals" {
    const allocator = std.testing.allocator;

    var too_deep: std.array_list.Managed(u8) = .init(allocator);
    defer too_deep.deinit();
    try too_deep.appendSlice("{\"providers\":[{\"provider\":\"compiled\",\"models\":[{\"model\":\"m\",\"config\":");
    try too_deep.appendNTimes('[', document.max_nesting_depth);
    try too_deep.appendSlice("0");
    try too_deep.appendNTimes(']', document.max_nesting_depth);
    try too_deep.appendSlice("}]}]}");
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        (Action{}).execute(allocator, too_deep.items),
    );

    var at_model_limit: std.array_list.Managed(u8) = .init(allocator);
    defer at_model_limit.deinit();
    try appendModelDocument(&at_model_limit, document.max_models_total);
    var decoded = try (Action{}).execute(allocator, at_model_limit.items);
    decoded.deinit();

    var too_many: std.array_list.Managed(u8) = .init(allocator);
    defer too_many.deinit();
    try appendModelDocument(&too_many, document.max_models_total + 1);
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        (Action{}).execute(allocator, too_many.items),
    );

    var at_provider_limit: std.array_list.Managed(u8) = .init(allocator);
    defer at_provider_limit.deinit();
    try appendProviderDocument(&at_provider_limit, document.max_providers);
    decoded = try (Action{}).execute(allocator, at_provider_limit.items);
    decoded.deinit();

    var too_many_providers: std.array_list.Managed(u8) = .init(allocator);
    defer too_many_providers.deinit();
    try appendProviderDocument(&too_many_providers, document.max_providers + 1);
    try std.testing.expectError(
        error.LLMProviderConfigParseError,
        (Action{}).execute(allocator, too_many_providers.items),
    );
}

fn appendModelDocument(output: *std.array_list.Managed(u8), count: usize) !void {
    try output.appendSlice("{\"providers\":[{\"provider\":\"compiled\",\"models\":[");
    for (0..count) |index| {
        if (index != 0) try output.append(',');
        try output.print("{{\"model\":\"m{d}\",\"config\":{{}}}}", .{index});
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
