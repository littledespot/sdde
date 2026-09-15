//! Read retained native merge facts; never infer progress or revalidate output.
//! Results and copied native slices belong to the caller's arena.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
const Merge = @import("../domain/atomic_repair.zig").Merge;

pub fn read(a: std.mem.Allocator, view: *const data.View) (values.Error || @import("../domain/strict_json.zig").Error)![]const Merge {
    var result: std.ArrayList(Merge) = .empty;
    const extraction = @import("reference_extraction_workflow.zig");
    const reconciliation = @import("reference_reconciliation_workflow.zig");
    for ([_]data.Schema{ extraction.parsed_schema, extraction.text_schema, reconciliation.parsed_schema }) |schema| {
        if (!view.contains(schema.key)) continue;
        const value = try values.read(view, schema, @import("../domain/reference_candidate_value.zig").Value);
        try append(a, &result, switch (value.payload().*) {
            .parsed => |candidate| candidate.last_repair,
            .text_validated => |candidate| candidate.last_repair,
            .reconciliation_parsed => |candidate| candidate.source.last_repair,
            else => null,
        });
    }
    const spec = @import("specification_workflow.zig");
    const storage = @import("specification_values.zig").storage;
    for ([_]data.Schema{ spec.parsed_schema, spec.checked_schema, spec.session_schema }) |schema| {
        if (!view.contains(schema.key)) continue;
        switch (storage.payload(try values.read(view, schema, storage.Value)).*) {
            .parsed => |candidate| try append(a, &result, candidate.last_repair),
            .checked => |candidate| try append(a, &result, candidate.last_repair),
            .unit_rejected => |candidate| try append(a, &result, candidate.last_repair),
            .session => |session| for (session.units) |unit| {
                if (unit) |candidate| try append(a, &result, candidate.last_repair);
            },
            else => {},
        }
    }
    const support = @import("specification_support_workflow.zig");
    if (view.contains(support.schema.key)) {
        const owned = @import("required_authority_values.zig");
        const value = owned.payload(try values.read(view, support.schema, owned.Value));
        if (value.* == .support) try append(a, &result, switch (value.support) {
            .accepted => |accepted| accepted.candidate.last_repair,
            .rejected => |rejected| if (rejected.candidate) |candidate| candidate.last_repair else null,
        });
    }
    return result.toOwnedSlice(a);
}

fn append(a: std.mem.Allocator, result: *std.ArrayList(Merge), observation: ?Merge) !void {
    const value = observation orelse return;
    // The same immutable merge may be retained by several derived candidates.
    for (result.items) |prior| if (std.mem.eql(u8, prior.authorization.bytes, value.authorization.bytes)) return;
    try result.append(a, try value.copy(a));
}
