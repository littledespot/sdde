//! Authored model observations for reference chunks. Test data only;
//! matching source bytes binds the example, it does not infer business meaning.
const std = @import("std");
const spec = @import("../domain/specification.zig");
pub const Script = struct {
    schema: []const u8,
    extractions: []const Extraction,
    description: []const u8,
    primary_goal: []const u8,
    entity_basis: []const u8,
    document: spec.CapturedDocument,
};
pub const Extraction = struct { source: []const u8, claim: []const u8 };

pub fn extraction(script: Script, source: []const u8) !Extraction {
    for (script.extractions) |entry| if (std.mem.eql(u8, source, entry.source)) return entry;
    return error.InvalidSpecificationScript;
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Script {
    const value = try @import("../domain/strict_json.zig").decode(Script, allocator, bytes, .{ .maximum_depth = 32 });
    if (!std.mem.eql(u8, value.schema, "specification-script/v1")) return error.InvalidSpecificationScript;
    if (value.extractions.len == 0) return error.InvalidSpecificationScript;
    for (value.extractions, 0..) |entry, index| {
        for ([_][]const u8{ entry.source, entry.claim }) |field| try text(field);
        for (value.extractions[0..index]) |prior| if (std.mem.eql(u8, entry.source, prior.source)) return error.InvalidSpecificationScript;
    }
    for ([_][]const u8{ value.description, value.primary_goal, value.entity_basis }) |field| try text(field);
    try spec.validateDocument(value.document, false);
    for (value.document.records) |record| if (record.id != null) return error.InvalidSpecificationScript;
    return value;
}

fn text(field: []const u8) !void {
    if (std.mem.trim(u8, field, " \t\r\n").len == 0 or !@import("../domain/typed_text.zig").validScalar(field)) return error.InvalidSpecificationScript;
}
