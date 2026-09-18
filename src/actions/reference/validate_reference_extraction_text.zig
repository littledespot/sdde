const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const text = @import("../../domain/typed_text.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-extraction-text", .kind = .action, .requires = &.{ .parsed_reference_extraction, .reference_passive_literals, .valid_toolchain, .citable_reference_inputs }, .produces = &.{.text_validated_reference_extraction}, .side_effect = .none };
    validator: text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, registry: @import("../../domain/passive_literals.zig").Registry, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextResult {
        return @import("../../domain/reference_extraction_text.zig").validate(self.validator, allocator, registry, current, inputs, parsed);
    }
};
