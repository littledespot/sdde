//! Private bounded YAML 1.2 syntax adapter.
//!
//! This adapter owns YAML loading only. Its generic document may be consumed
//! only inside the toolchain parser/action boundary and must never be exported
//! from the SDDE root module or returned by a service. It does not map fields,
//! validate a domain schema, resolve inheritance, log, or perform filesystem
//! I/O.

const std = @import("std");
const yaml = @import("yaml");

pub const Diagnostic = yaml.Diagnostic;
pub const Document = yaml.LoadedDocument;
pub const Error = yaml.Error;

pub const Limits = struct {
    max_input_bytes: usize,
    max_event_count: usize,
    max_token_count: usize,
    max_nesting_depth: usize,
    max_scalar_bytes: usize,
};

pub fn parse(
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
    diagnostic: *Diagnostic,
) Error!Document {
    diagnostic.* = .{};

    return yaml.loadWithOptions(allocator, input, .{
        .schema = .core,
        .duplicate_key_behavior = .reject,
        .unknown_tag_behavior = .reject,
        .max_input_bytes = limits.max_input_bytes,
        .max_alias_count = 0,
        .max_alias_expansion = 0,
        .max_document_count = 1,
        .max_event_count = limits.max_event_count,
        .max_token_count = limits.max_token_count,
        .max_nesting_depth = limits.max_nesting_depth,
        .max_scalar_bytes = limits.max_scalar_bytes,
        .diagnostic = diagnostic,
    });
}

const test_limits: Limits = .{
    .max_input_bytes = 4096,
    .max_event_count = 256,
    .max_token_count = 256,
    .max_nesting_depth = 16,
    .max_scalar_bytes = 256,
};

fn expectRejected(input: []const u8, limits: Limits) !void {
    var diagnostic: Diagnostic = .{};
    if (parse(std.testing.allocator, input, limits, &diagnostic)) |loaded| {
        var document = loaded;
        document.deinit();
        return error.ExpectedYamlRejection;
    } else |err| switch (err) {
        error.InvalidSyntax, error.Unsupported => {},
        error.OutOfMemory => return err,
    }
    try std.testing.expect(diagnostic.message.len != 0);
}

test "loads one bounded YAML 1.2 document without schema filtering" {
    var diagnostic: Diagnostic = .{};
    var document = try parse(
        std.testing.allocator,
        "unknown_field: no\n",
        test_limits,
        &diagnostic,
    );
    defer document.deinit();

    const mapping = switch (document.root.*) {
        .mapping => |value| value,
        else => return error.ExpectedMapping,
    };
    try std.testing.expectEqual(@as(usize, 1), mapping.pairs.len);

    switch (mapping.pairs[0].key.*) {
        .scalar => |value| try std.testing.expectEqualStrings("unknown_field", value.value),
        else => return error.ExpectedScalarKey,
    }

    switch (mapping.pairs[0].value.*) {
        .scalar => |value| try std.testing.expectEqualStrings("no", value.value),
        else => return error.ExpectedYaml12String,
    }
}

test "rejects unsafe YAML document features" {
    const inputs = [_][]const u8{
        "name: first\nname: second\n",
        "base: &base value\ncopy: *base\n",
        "value: !custom tagged\n",
        "---\nname: first\n---\nname: second\n",
    };

    for (inputs) |input| {
        try expectRejected(input, test_limits);
    }
}

test "enforces caller-supplied limits" {
    var limits = test_limits;
    limits.max_input_bytes = 4;
    try expectRejected("name: value\n", limits);
}
