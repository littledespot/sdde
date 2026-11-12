//! The specification title (ADR 0048): the text of the reference sources' first level-1
//! heading, as written. No model writes it, and it carries no claim, group or provenance.
const std = @import("std");
const spec = @import("specification.zig");
const evidence = @import("reference_evidence.zig");

/// Why a corpus yields no title. Peer sources have no precedence (design.md §2), so
/// different headings are never resolved by choosing one (invariant 20).
pub const Gap = enum { no_title_heading, conflicting_title_headings };
pub const Derivation = union(enum) { title: spec.DisplayName, gap: Gap };

/// Each source contributes its first level-1 heading with text, and one distinct text across
/// the corpus is the title.
pub fn derive(a: std.mem.Allocator, inputs: evidence.Inputs) std.mem.Allocator.Error!Derivation {
    var title: ?[]u8 = null;
    errdefer if (title) |found| a.free(found);
    for (inputs.corpus.sources) |source| {
        const heading = switch (source.reader) {
            .markdown_source_v1 => try @import("markdown_code_spans.zig").levelOneHeading(a, source.bytes),
        } orelse continue;
        const found = title orelse {
            title = heading;
            continue;
        };
        defer a.free(heading);
        if (!std.mem.eql(u8, found, heading)) {
            a.free(found);
            return .{ .gap = .conflicting_title_headings };
        }
    }
    return if (title) |found| .{ .title = .{ .bytes = found } } else .{ .gap = .no_title_heading };
}

/// Readback derives the title again from the captured sources, as it checks every other
/// engine-derived value: a stored title that differs, or a corpus that no longer yields one,
/// is not a stored specification.
pub fn validateStored(a: std.mem.Allocator, inputs: evidence.Inputs, stored: spec.DisplayName) (std.mem.Allocator.Error || spec.Error)!void {
    const title = switch (try derive(a, inputs)) {
        .title => |value| value,
        .gap => return error.InvalidSpecification,
    };
    defer a.free(title.bytes);
    if (!std.mem.eql(u8, title.bytes, stored.bytes)) return error.InvalidSpecification;
}
