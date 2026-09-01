const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootResolutionError};

pub const Action = struct {
    policy: bootstrap_roots.WorkspacePathPolicy,

    pub const contract: pipeline.NodeContract = .{
        .id = "validate-engine-path-policy@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{ .configured_root_path_policy_set, .llm_provider_config_path_policy },
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        path_key: bootstrap_roots.PathKey,
        raw_path: []const u8,
    ) Error!bootstrap_roots.NormalizedConfiguredPath {
        const normalized = try normalize(self.policy, allocator, raw_path, true);
        return .{
            .path_key = path_key,
            .root_role = path_key.role(),
            .relative_path = normalized,
        };
    }

    pub fn executeLLMProviderConfig(
        self: Action,
        allocator: std.mem.Allocator,
        raw_path: []const u8,
    ) Error!bootstrap_roots.NormalizedLLMProviderConfigPath {
        const normalized = try normalize(self.policy, allocator, raw_path, false);
        errdefer allocator.free(normalized);
        if (!std.mem.eql(
            u8,
            std.fs.path.basename(normalized),
            bootstrap_roots.llm_provider_config_basename,
        )) {
            return error.BootstrapRootResolutionError;
        }
        return .{ .relative_path = normalized };
    }
};

fn normalize(
    policy: bootstrap_roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    raw_path: []const u8,
    allow_trailing_separator: bool,
) Error![]u8 {
    if (raw_path.len == 0 or raw_path.len > policy.max_relative_path_bytes) {
        return error.BootstrapRootResolutionError;
    }
    if (!std.unicode.utf8ValidateSlice(raw_path)) {
        return error.BootstrapRootResolutionError;
    }
    if (isAbsoluteOrDrivePath(raw_path)) {
        return error.BootstrapRootResolutionError;
    }

    if (!allow_trailing_separator and raw_path[raw_path.len - 1] == '/') {
        return error.BootstrapRootResolutionError;
    }
    const normalized_length = if (raw_path[raw_path.len - 1] == '/')
        raw_path.len - 1
    else
        raw_path.len;
    if (normalized_length == 0) return error.BootstrapRootResolutionError;
    const normalized = raw_path[0..normalized_length];

    var iterator = std.mem.splitScalar(u8, normalized, '/');
    while (iterator.next()) |component| {
        try validateComponent(policy, component);
    }
    if (hasEncodedDotOrSeparator(normalized)) {
        return error.BootstrapRootResolutionError;
    }

    return allocator.dupe(u8, normalized) catch error.BootstrapRootResolutionError;
}

fn isAbsoluteOrDrivePath(path: []const u8) bool {
    if (path[0] == '/' or path[0] == '\\') return true;
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn validateComponent(
    policy: bootstrap_roots.WorkspacePathPolicy,
    component: []const u8,
) Error!void {
    if (component.len == 0 or component.len > policy.max_component_bytes) {
        return error.BootstrapRootResolutionError;
    }
    if (std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
        return error.BootstrapRootResolutionError;
    }
    if (component[component.len - 1] == '.' or component[component.len - 1] == ' ') {
        return error.BootstrapRootResolutionError;
    }

    for (component) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.BootstrapRootResolutionError;
        if (byte >= 0x80) return error.BootstrapRootResolutionError;
        switch (byte) {
            '\\', '<', '>', ':', '"', '|', '?', '*' => return error.BootstrapRootResolutionError,
            else => {},
        }
    }
    if (isReservedPortableName(component)) {
        return error.BootstrapRootResolutionError;
    }
}

fn isReservedPortableName(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    if (std.ascii.eqlIgnoreCase(stem, "con") or
        std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or
        std.ascii.eqlIgnoreCase(stem, "nul"))
    {
        return true;
    }
    if (stem.len != 4) return false;
    const prefix_is_reserved = std.ascii.eqlIgnoreCase(stem[0..3], "com") or
        std.ascii.eqlIgnoreCase(stem[0..3], "lpt");
    return prefix_is_reserved and stem[3] >= '1' and stem[3] <= '9';
}

fn hasEncodedDotOrSeparator(path: []const u8) bool {
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        if (path[index] != '%') continue;
        var token_index = index + 1;
        while (token_index + 1 < path.len and
            std.ascii.toLower(path[token_index]) == '2' and
            std.ascii.toLower(path[token_index + 1]) == '5')
        {
            token_index += 2;
        }
        if (token_index + 1 >= path.len) continue;
        const first = std.ascii.toLower(path[token_index]);
        const second = std.ascii.toLower(path[token_index + 1]);
        if ((first == '2' and (second == 'e' or second == 'f')) or
            (first == '5' and second == 'c')) return true;
    }
    return false;
}

fn testPolicy() bootstrap_roots.WorkspacePathPolicy {
    return .{
        .max_component_bytes = 16,
        .max_relative_path_bytes = 64,
        .max_absolute_path_bytes = 128,
    };
}

test "normalizes one trailing separator and preserves the configured role" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = testPolicy() };
    const result = try action.execute(allocator, .workflows, ".sddtoolkit/workflows/");
    defer allocator.free(result.relative_path);

    try std.testing.expectEqualStrings(".sddtoolkit/workflows", result.relative_path);
    try std.testing.expectEqual(bootstrap_roots.ConfiguredRootRole.workflow_authority, result.root_role);
}

test "rejects unsafe ambiguous unportable and over-limit paths" {
    const action: Action = .{ .policy = testPolicy() };
    const invalid = [_][]const u8{
        "",
        "/absolute",
        "C:/drive",
        "\\\\server\\share",
        "a//b",
        "a/./b",
        "a/../b",
        "a\\b",
        "a\x00b",
        "a/%2f/b",
        "a/%252E/b",
        "a/%255c/b",
        "a/con",
        "a/trailing.",
        "a/abcdefghijklmnopq",
        "non-ascii-\xc3\xa9",
    };

    for (invalid) |path| {
        try std.testing.expectError(
            error.BootstrapRootResolutionError,
            action.execute(std.testing.allocator, .specs, path),
        );
    }

    const invalid_utf8 = [_]u8{ 0xff, 'a' };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(std.testing.allocator, .specs, &invalid_utf8),
    );
}

test "accepts exact component and relative limits and rejects one byte over" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = testPolicy() };
    const exact_component = "abcdefghijklmnop";
    const exact_relative = "aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb/cccccccccccccccc/ddddddddddddd";

    const component = try action.execute(allocator, .specs, exact_component);
    defer allocator.free(component.relative_path);
    const relative = try action.execute(allocator, .references, exact_relative);
    defer allocator.free(relative.relative_path);

    try std.testing.expectEqual(@as(usize, 16), component.relative_path.len);
    try std.testing.expectEqual(@as(usize, 64), relative.relative_path.len);
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(
            allocator,
            .templates,
            "aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb/cccccccccccccccc/dddddddddddddddd",
        ),
    );
}

test "provider config path requires the exact basename without a directory suffix" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = .{
        .max_component_bytes = 32,
        .max_relative_path_bytes = 128,
        .max_absolute_path_bytes = 256,
    } };
    const exact = try action.executeLLMProviderConfig(
        allocator,
        "configuration/.sddproviders.json",
    );
    defer allocator.free(exact.relative_path);
    try std.testing.expectEqualStrings(
        "configuration/.sddproviders.json",
        exact.relative_path,
    );

    const invalid = [_][]const u8{
        "configuration/providers.json",
        "configuration/.sddproviders.json/",
        "configuration/.SDDPROVIDERS.JSON",
    };
    for (invalid) |path| {
        try std.testing.expectError(
            error.BootstrapRootResolutionError,
            action.executeLLMProviderConfig(allocator, path),
        );
    }
}
