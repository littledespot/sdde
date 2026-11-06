const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
const session = @import("../../domain/specification_session.zig");
const story = @import("../../domain/specification_story.zig");
const binding = @import("../../domain/specification_source_binding.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "compose-specification-story", .kind = .action, .requires = &.{ .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{}, .replaces = &.{.specification_generation_session}, .side_effect = .none };
    validator: @import("../../domain/typed_text.zig").Validator,
    /// ADR 0047: compose the story, validate it as any unit, then admit and append it.
    /// A story that fails unit validation blocks with its issue; it is never repaired.
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: session.Session, context: @import("../../domain/specification_provenance.zig").Context) story.Error!story.Outcome {
        const composed = switch (try story.compose(allocator, current, context)) {
            .story => |value| value,
            .blocked => |rejection| return .{ .blocked = rejection },
        };
        const checked = switch (try g.validate(allocator, self.validator, context, .primary_user_story, .{ .content = .{ .primary_user_story = composed } })) {
            .valid => |valid| valid,
            .invalid => |issue| return .{ .blocked = try binding.storyRejection(allocator, context.references, .{ .not_admissible = issue }) },
        };
        if (try session.checkConsistency(allocator, current, context, checked, null)) |issue| return .{ .blocked = try binding.storyRejection(allocator, context.references, .{ .not_admissible = issue }) };
        return .{ .composed = try session.appendBound(allocator, current, try session.admit(allocator, current, context, checked)) };
    }
};
