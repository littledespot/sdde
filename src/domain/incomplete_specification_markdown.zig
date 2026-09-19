//! Incomplete-view renderer. Questions link to controlled forms; this format
//! deliberately cannot parse as the completed editable specification contract.
const std = @import("std");
const draft = @import("incomplete_specification.zig");
const c = @import("clarification_inputs.zig");
pub const Error = draft.Error || @import("reference_markdown.zig").Error;

pub fn render(a: std.mem.Allocator, value: draft.State, clarifications: c.ValidatedState) Error![]const u8 {
    _ = try draft.bindClarifications(value, clarifications);
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    try write(w, "# Feature Specification\n\n**Status: Incomplete — awaiting clarification**\n\nThe requirements below retain current source-supported business content. Resolve the linked questions before planning.\n");
    inline for (.{ .{ @import("reference_extraction.zig").Kind.business, "Supported Requirements" }, .{ @import("reference_extraction.zig").Kind.scope_guard, "Scope Constraints" } }) |section| {
        try write(w, "\n## " ++ section[1] ++ "\n\n");
        var count: usize = 0;
        for (value.reference.extraction.claims, value.reference.dispositions) |claim, disposition| {
            if (!@import("specification_provenance.zig").eligibleClaim(disposition.disposition) or
                claim.content != .model or claim.content.model != section[0]) continue;
            try write(w, "- ");
            try @import("reference_markdown.zig").business(w, value.reference, @field(claim.content.model, @tagName(section[0])).value);
            try write(w, "\n");
            count += 1;
        }
        if (count == 0) try write(w, "No supported content is available for this section yet.\n");
    }
    try write(w, "\n## Open Clarifications\n\n");
    for (value.open_clarifications) |id| {
        const name = id.filename();
        // Filenames and link targets come only from the validated native ID.
        w.print("- [{s}]({s}/{s})\n", .{ name[0..3], @import("workflow_artifact_registry.zig").clarification_directory_name, name }) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice();
}
fn write(w: *std.Io.Writer, bytes: []const u8) Error!void {
    w.writeAll(bytes) catch return error.OutOfMemory;
}
