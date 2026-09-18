const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const text = @import("typed_text.zig");
pub fn validate(validator: text.Validator, allocator: std.mem.Allocator, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextResult {
    // Even empty/blocked candidate sets must bind current source/policy data.
    try @import("path_token_grammar.zig").validateBinding(allocator, registry.grammar, current, inputs, validator.normalizer, validator.folder);
    if (parsed.revision == 0) return error.InvalidReferenceExtraction;
    const entries = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
    for (parsed.entries, entries) |candidate, *entry| {
        const context: text.ScopeSetContext = .{ .registry = registry, .current = current, .inputs = inputs, .scopes = &.{candidate.scope} };
        _ = try evidence.resolve(inputs, candidate.scope);
        entry.scope = candidate.scope;
        entry.origin = candidate.origin;
        entry.classification_origin = candidate.origin;
        entry.token_classifications = candidate.token_classifications;
        entry.outcome = switch (candidate.outcome) {
            .blocked => |reason| .{ .blocked = reason },
            .no_feature_claim => |reason| .{ .no_feature_claim = switch (try validator.checkReferenceIn(allocator, context, reason)) {
                .valid => |value| value,
                .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .reason, issue, .{ .reason = reason }),
            } },
            .claims => |proposals| claims: {
                const checked = try allocator.alloc(extraction.TextValidatedProposal, proposals.len);
                for (proposals, checked, 0..) |proposal, *value, index| {
                    value.citations = proposal.citations;
                    value.origin = extraction.textOrigin(candidate, .{ .claim = index });
                    const origins = try allocator.alloc(?@import("model_candidate_origin.zig").Origin, proposal.citations.len);
                    @memset(origins, candidate.origin);
                    value.citation_origins = origins;
                    value.content = switch (try checkContent(validator, allocator, context, proposal.content)) {
                        .valid => |accepted| accepted,
                        .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .{ .claim = index }, issue, .{ .content = proposal.content }),
                    };
                }
                break :claims .{ .claims = checked };
            },
        };
    }
    return .{ .valid = .{ .revision = parsed.revision, .last_repair = parsed.last_repair, .entries = entries } };
}

fn checkContent(validator: text.Validator, a: std.mem.Allocator, context: text.ScopeSetContext, content: extraction.ProposalContent) extraction.Error!text.Result(extraction.Content) {
    return switch (content) {
        inline .business, .scope_guard => |value, tag| switch (try validator.checkBusinessIn(a, context, value)) {
            .valid => |accepted| .{ .valid = @unionInit(extraction.Content, @tagName(tag), accepted) },
            .invalid => |issue| .{ .invalid = issue },
        },
        inline else => |value, tag| switch (try validator.checkReferenceIn(a, context, value)) {
            .valid => |accepted| .{ .valid = @unionInit(extraction.Content, @tagName(tag), accepted) },
            .invalid => |issue| .{ .invalid = issue },
        },
    };
}

/// Observe the authorized field with the same text rules as complete extraction.
/// Unrelated invalid claims cannot conceal this field's validation result.
pub fn validTarget(validator: text.Validator, a: std.mem.Allocator, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed, scope: evidence.Scope, target: extraction.TextTarget) extraction.Error!bool {
    try @import("path_token_grammar.zig").validateBinding(a, registry.grammar, current, inputs, validator.normalizer, validator.folder);
    _ = try evidence.resolve(inputs, scope);
    for (parsed.entries) |entry| if (entry.scope.chunk_id.eql(scope.chunk_id)) {
        if (!entry.scope.state_id.eql(scope.state_id)) return error.InvalidReferenceExtraction;
        const context: text.ScopeSetContext = .{ .registry = registry, .current = current, .inputs = inputs, .scopes = &.{scope} };
        return switch (target) {
            .reason => if (entry.outcome == .no_feature_claim)
                (try validator.checkReferenceIn(a, context, entry.outcome.no_feature_claim)) == .valid
            else
                error.InvalidReferenceExtraction,
            .claim => |index| if (entry.outcome == .claims and index < entry.outcome.claims.len)
                (try checkContent(validator, a, context, entry.outcome.claims[index].content)) == .valid
            else
                error.InvalidReferenceExtraction,
        };
    };
    return error.InvalidReferenceExtraction;
}

fn reject(a: std.mem.Allocator, inputs: evidence.Inputs, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, parsed: extraction.Parsed, entry: extraction.ParsedResult, target: extraction.TextTarget, issue: text.Issue, observed: @FieldType(extraction.TextRejection, "observed")) extraction.Error!extraction.TextResult {
    const context = @import("reference_extraction_context.zig");
    return .{ .invalid = .{ .scope = entry.scope, .revision = parsed.revision, .target = target, .origin = extraction.textOrigin(entry, target), .issue = issue, .observed = observed, .dependencies = try @import("atomic_repair.zig").snapshot(context.TextFacts, a, try context.textFacts(inputs, registry, current, parsed)) } };
}
