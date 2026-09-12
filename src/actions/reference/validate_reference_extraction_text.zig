const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const text = @import("../../domain/typed_text.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-extraction-text", .kind = .action, .requires = &.{ .parsed_reference_extraction, .reference_passive_literals, .valid_toolchain, .citable_reference_inputs }, .produces = &.{.text_validated_reference_extraction}, .side_effect = .none };
    validator: text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, registry: @import("../../domain/passive_literals.zig").Registry, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextValidated {
        // Even empty/blocked candidate sets must bind current source/policy data.
        try @import("../../domain/path_token_grammar.zig").validateBinding(allocator, registry.grammar, current, inputs, self.validator.normalizer, self.validator.folder);
        const entries = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
        for (parsed.entries, entries) |candidate, *entry| {
            const context: text.Context = .{ .registry = registry, .current = current, .inputs = inputs, .scope = candidate.scope };
            _ = try evidence.resolve(inputs, candidate.scope);
            entry.scope = candidate.scope;
            entry.classification_origin = candidate.origin;
            entry.token_classifications = candidate.token_classifications;
            entry.outcome = switch (candidate.outcome) {
                .blocked => |reason| .{ .blocked = reason },
                .no_feature_claim => |reason| .{ .no_feature_claim = try self.validator.reference(allocator, context, reason) },
                .claims => |proposals| claims: {
                    const checked = try allocator.alloc(extraction.TextValidatedProposal, proposals.len);
                    for (proposals, checked) |proposal, *value| {
                        value.citations = proposal.citations;
                        value.origin = candidate.origin;
                        const origins = try allocator.alloc(?@import("../../domain/model_candidate_origin.zig").Origin, proposal.citations.len);
                        @memset(origins, candidate.origin);
                        value.citation_origins = origins;
                        value.content = switch (proposal.content) {
                            inline .business, .scope_guard => |candidate_text, tag| @unionInit(extraction.Content, @tagName(tag), try self.validator.business(allocator, context, candidate_text)),
                            inline else => |candidate_text, tag| @unionInit(extraction.Content, @tagName(tag), try self.validator.reference(allocator, context, candidate_text)),
                        };
                    }
                    break :claims .{ .claims = checked };
                },
            };
        }
        return .{ .entries = entries };
    }
};
