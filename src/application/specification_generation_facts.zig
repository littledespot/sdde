//! The runner's current typed generation facts, independent of review routing.
const data = @import("../domain/pipeline_data.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const generation = @import("specification_workflow.zig");
const authority = @import("required_authority_workflow.zig");
const owned = @import("required_authority_values.zig");
const spec = @import("../domain/specification.zig");

pub const Facts = struct {
    session: ?@import("../domain/specification_session.zig").Session,
    content: ?spec.IdentifiedContent,

    pub fn phase(self: Facts) @import("../domain/specification_generation_phase.zig").Phase {
        return if (self.session != null or self.content != null) .generation_started else .pre_generation;
    }

    pub fn brief(self: Facts) ?spec.Brief {
        const current = self.session orelse return null;
        const checked = current.units[0] orelse return null;
        return switch (checked.response) {
            .clarification, .inconclusive => null,
            .content => |content| switch (content) {
                .brief => |value| value,
                else => null,
            },
        };
    }
};

/// Presence counts only after the canonical typed owner accepts the payload.
/// Retiring or rebuilding review authority cannot erase these generation facts.
pub fn read(view: *const data.View) operations.Error!Facts {
    return .{
        .session = if (view.contains(generation.session_schema.key)) try generation.readSession(view) else null,
        .content = if (view.contains(authority.content_schema.key)) try owned.read(view, authority.content_schema, .content) else null,
    };
}
