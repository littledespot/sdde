const std = @import("std");
const definitions = @import("domain/specification_result_definitions.zig");
const model_result_schema = @import("domain/model_result_schema.zig");
const schema_adapter = @import("adapters/parsers/model_result_schemas.zig");

fn compileShipped(a: std.mem.Allocator, name: []const u8) !*const model_result_schema.Schema {
    var adapter: schema_adapter.Adapter = .{};
    const path = try std.fmt.allocPrint(a, "design/workflows/spec/{s}.schema.json", .{name});
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(model_result_schema.max_bytes));
    return adapter.compiler().compile(a, bytes);
}

fn expectEverySelectable(comptime Enum: type, a: std.mem.Allocator, name: []const u8) !void {
    const compiled = try compileShipped(a, name);
    inline for (@typeInfo(Enum).@"enum".fields) |field| {
        const member: Enum = @enumFromInt(field.value);
        // The name satisfies the definition grammar and the shipped schema declares it as a selectable result.
        try std.testing.expect(model_result_schema.DefinitionId.parse(@tagName(member)) != null);
        try std.testing.expect(compiled.select(member.id()) != null);
    }
}

test "every definition a Spec builder can select is declared by its shipped schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectEverySelectable(definitions.Extraction, a, "extraction");
    try expectEverySelectable(definitions.Reconciliation, a, "reconciliation");
    try expectEverySelectable(definitions.Generation, a, "generation");
    try expectEverySelectable(definitions.Links, a, "links");
    try expectEverySelectable(definitions.Support, a, "support");
}

test "no definition name belongs to two schemas' enums" {
    // `parse` is per schema, so a name shared by two enums would make a fixture or a builder
    // resolve another schema's request to its own member.
    @setEvalBranchQuota(20_000);
    const enums = .{ definitions.Extraction, definitions.Reconciliation, definitions.Generation, definitions.Links, definitions.Support };
    inline for (enums, 0..) |left, left_index| {
        inline for (enums, 0..) |right, right_index| {
            if (left_index >= right_index) continue;
            inline for (@typeInfo(left).@"enum".fields) |left_field| {
                inline for (@typeInfo(right).@"enum".fields) |right_field| {
                    comptime std.debug.assert(!std.mem.eql(u8, left_field.name, right_field.name));
                }
            }
        }
    }
}

test "a selected definition resolves to its own member and to no member of another schema" {
    inline for (@typeInfo(definitions.Support).@"enum".fields) |field| {
        const member: definitions.Support = @enumFromInt(field.value);
        try std.testing.expectEqual(@as(?definitions.Support, member), definitions.Support.parse(member.id()));
    }
    try std.testing.expectEqual(@as(?definitions.Links, .scenario_link), definitions.Links.parse(definitions.Links.scenario_link.id()));
    try std.testing.expect(definitions.Support.parse(definitions.Links.scenario_link.id()) == null);
    try std.testing.expect(definitions.Reconciliation.parse(definitions.Extraction.claim.id()) == null);
}

test "a definition the schema does not declare is not selectable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compileShipped(arena.allocator(), "links");
    try std.testing.expect(compiled.select(.{ .bytes = "scenario_link" }) != null);
    try std.testing.expect(compiled.select(.{ .bytes = "finding" }) == null);
}
