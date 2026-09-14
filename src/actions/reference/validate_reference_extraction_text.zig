const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
const evidence = @import("../../domain/reference_evidence.zig");
const text = @import("../../domain/typed_text.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-extraction-text", .kind = .action, .requires = &.{ .parsed_reference_extraction, .reference_passive_literals, .valid_toolchain, .citable_reference_inputs }, .produces = &.{.text_validated_reference_extraction}, .side_effect = .none };
    validator: text.Validator,
    pub fn execute(self: Action, allocator: std.mem.Allocator, registry: @import("../../domain/passive_literals.zig").Registry, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextResult {
        // Even empty/blocked candidate sets must bind current source/policy data.
        try @import("../../domain/path_token_grammar.zig").validateBinding(allocator, registry.grammar, current, inputs, self.validator.normalizer, self.validator.folder);
        if (parsed.revision == 0) return error.InvalidReferenceExtraction;
        const entries = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
        for (parsed.entries, entries) |candidate, *entry| {
            const context: text.ScopeSetContext = .{ .registry = registry, .current = current, .inputs = inputs, .scopes = &.{candidate.scope} };
            _ = try evidence.resolve(inputs, candidate.scope);
            entry.scope = candidate.scope;
            entry.classification_origin = candidate.origin;
            entry.token_classifications = candidate.token_classifications;
            entry.outcome = switch (candidate.outcome) {
                .blocked => |reason| .{ .blocked = reason },
                .no_feature_claim => |reason| .{ .no_feature_claim = switch (try self.validator.checkReferenceIn(allocator, context, reason)) {
                    .valid => |value| value,
                    .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .reason, issue, .{ .reason = reason }),
                } },
                .claims => |proposals| claims: {
                    const checked = try allocator.alloc(extraction.TextValidatedProposal, proposals.len);
                    for (proposals, checked, 0..) |proposal, *value, index| {
                        value.citations = proposal.citations;
                        value.origin = extraction.textOrigin(candidate, .{ .claim = index });
                        const origins = try allocator.alloc(?@import("../../domain/model_candidate_origin.zig").Origin, proposal.citations.len);
                        @memset(origins, candidate.origin);
                        value.citation_origins = origins;
                        value.content = switch (proposal.content) {
                            inline .business, .scope_guard => |candidate_text, tag| @unionInit(extraction.Content, @tagName(tag), switch (try self.validator.checkBusinessIn(allocator, context, candidate_text)) {
                                .valid => |accepted| accepted,
                                .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .{ .claim = index }, issue, .{ .content = proposal.content }),
                            }),
                            inline else => |candidate_text, tag| @unionInit(extraction.Content, @tagName(tag), switch (try self.validator.checkReferenceIn(allocator, context, candidate_text)) {
                                .valid => |accepted| accepted,
                                .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .{ .claim = index }, issue, .{ .content = proposal.content }),
                            }),
                        };
                    }
                    break :claims .{ .claims = checked };
                },
            };
        }
        return .{ .valid = .{ .revision = parsed.revision, .last_repair = parsed.last_repair, .entries = entries } };
    }
};

fn reject(a: std.mem.Allocator, inputs: evidence.Inputs, registry: @import("../../domain/passive_literals.zig").Registry, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain, parsed: extraction.Parsed, entry: extraction.ParsedResult, target: extraction.TextTarget, issue: text.Issue, observed: @FieldType(extraction.TextRejection, "observed")) extraction.Error!extraction.TextResult {
    const context = @import("../../domain/reference_extraction_context.zig");
    return .{ .invalid = .{ .scope = entry.scope, .revision = parsed.revision, .target = target, .origin = extraction.textOrigin(entry, target), .issue = issue, .observed = observed, .dependencies = try @import("../../domain/atomic_repair.zig").snapshot(context.TextFacts, a, try context.textFacts(inputs, registry, current, parsed)) } };
}
