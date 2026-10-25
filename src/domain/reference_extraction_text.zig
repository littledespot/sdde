const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const text = @import("typed_text.zig");
pub fn validate(validator: text.Validator, allocator: std.mem.Allocator, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextResult {
    // Even empty/blocked candidate sets must bind current source/policy data.
    try @import("path_token_grammar.zig").validateBinding(allocator, registry.grammar, current, inputs, validator.normalizer, validator.folder);
    if (parsed.revision == 0) return error.InvalidReferenceExtraction;
    const entries = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
    var blocks: CodeBlocks = try .init(allocator, inputs);
    for (parsed.entries, entries) |candidate, *entry| {
        const context: text.ScopeSetContext = .{ .registry = registry, .current = current, .inputs = inputs, .scopes = &.{candidate.scope}, .field = .extraction_reason };
        _ = try evidence.resolve(inputs, candidate.scope);
        entry.scope = candidate.scope;
        entry.origin = candidate.origin;
        const classification_origins = try allocator.alloc(?@import("model_candidate_origin.zig").Origin, candidate.token_classifications.len);
        @memset(classification_origins, if (candidate.producers) |producers| producers.classifications else candidate.origin);
        entry.classification_origins = classification_origins;
        entry.producers = candidate.producers;
        entry.token_classifications = candidate.token_classifications;
        entry.outcome = switch (candidate.outcome) {
            .blocked => |reason| .{ .blocked = reason },
            .no_feature_claim => |reason| .{ .no_feature_claim = switch (try validator.checkReferenceIn(allocator, context, reason)) {
                .valid => |value| value,
                .invalid => |issue| return reject(allocator, inputs, registry, current, parsed, candidate, .reason, issue, .{ .reason = reason }),
            } },
            .claims => |proposals| claims: {
                const origin = if (candidate.producers) |producers| producers.content else candidate.origin;
                const layout = try Layout.init(allocator, inputs, candidate.scope, &blocks);
                var checked: std.ArrayList(extraction.TextValidatedProposal) = .empty;
                for (proposals) |proposal| {
                    const quoted = try layout.quote(allocator, proposal);
                    // Quoted source text has no model wording to repair (ADR 0036).
                    const content = switch (try checkContent(validator, allocator, context, quoted.content)) {
                        .valid => |accepted| accepted,
                        .invalid => return error.InvalidReferenceExtraction,
                    };
                    try checked.append(allocator, .{ .content = content, .citations = quoted.citations, .origin = origin });
                }
                break :claims .{ .claims = try checked.toOwnedSlice(allocator) };
            },
        };
    }
    return .{ .valid = .{ .revision = parsed.revision, .last_repair = parsed.last_repair, .entries = entries } };
}

fn checkContent(validator: text.Validator, a: std.mem.Allocator, context: text.ScopeSetContext, content: extraction.ProposalContent) extraction.Error!text.Result(extraction.Content) {
    var selected = context;
    return switch (content) {
        inline .business, .scope_guard => |value, tag| checked: {
            selected.field = text.field_policy.referenceField(.extraction, @tagName(tag));
            break :checked switch (try validator.checkBusinessIn(a, selected, value)) {
                .valid => |accepted| .{ .valid = @unionInit(extraction.Content, @tagName(tag), accepted) },
                .invalid => |issue| .{ .invalid = issue },
            };
        },
        inline else => |value, tag| checked: {
            selected.field = text.field_policy.referenceField(.extraction, @tagName(tag));
            break :checked switch (try validator.checkReferenceIn(a, selected, value)) {
                .valid => |accepted| .{ .valid = @unionInit(extraction.Content, @tagName(tag), accepted) },
                .invalid => |issue| .{ .invalid = issue },
            };
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
        const context: text.ScopeSetContext = .{ .registry = registry, .current = current, .inputs = inputs, .scopes = &.{scope}, .field = .extraction_reason };
        return switch (target) {
            .reason => if (entry.outcome == .no_feature_claim)
                (try validator.checkReferenceIn(a, context, entry.outcome.no_feature_claim)) == .valid
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

const selections = @import("source_selections.zig");
const markdown = @import("markdown_code_spans.zig");
const Quote = struct { content: extraction.ProposalContent, citations: []const selections.Selection };

/// Each source's fenced code blocks from its reader, scanned once per validation
/// and only for sources whose claims are quoted.
const CodeBlocks = struct {
    inputs: evidence.Inputs,
    sources: []?[]const markdown.Range,

    fn init(a: std.mem.Allocator, inputs: evidence.Inputs) std.mem.Allocator.Error!CodeBlocks {
        const sources = try a.alloc(?[]const markdown.Range, inputs.corpus.sources.len);
        @memset(sources, null);
        return .{ .inputs = inputs, .sources = sources };
    }
    fn of(self: *CodeBlocks, a: std.mem.Allocator, source: evidence.Source) extraction.Error![]const markdown.Range {
        const index = for (self.inputs.corpus.sources, 0..) |candidate, index| {
            if (candidate.id.ordinal == source.id.ordinal) break index;
        } else return error.InvalidReferenceExtraction;
        if (self.sources[index] == null) {
            const ranges = switch (source.reader) {
                .markdown_source_v1 => try markdown.scanAll(a, source.bytes),
            };
            var blocks: std.ArrayList(markdown.Range) = .empty;
            for (ranges) |range| if (range.form == .code_block) try blocks.append(a, range);
            self.sources[index] = try blocks.toOwnedSlice(a);
        }
        return self.sources[index].?;
    }
};

/// ADR 0036: one chunk's supplied lines, each marked when it is fenced code.
const Layout = struct {
    bytes: []const u8,
    lines: []const selections.Line,
    code: []const bool,

    fn init(a: std.mem.Allocator, inputs: evidence.Inputs, scope: evidence.Scope, blocks: *CodeBlocks) extraction.Error!Layout {
        const view = try evidence.resolve(inputs, scope);
        const lines = try selections.lines(a, inputs, scope);
        const ranges = try blocks.of(a, view.source);
        const code = try a.alloc(bool, lines.len);
        // The first block that can hold the chunk's first line, then a forward walk.
        var low: usize = 0;
        var high = ranges.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (lines.len != 0 and ranges[middle].end <= lines[0].span.start.byte) low = middle + 1 else high = middle;
        }
        var index = low;
        for (lines, code) |line, *fenced| {
            while (index < ranges.len and ranges[index].end <= line.span.start.byte) index += 1;
            fenced.* = index < ranges.len and ranges[index].start <= line.span.start.byte;
        }
        return .{ .bytes = view.source.bytes, .lines = lines, .code = code };
    }

    /// A claim quotes the source bytes of the lines it cites, as written. A run
    /// of cited lines continues across uncited blank lines and is trimmed at its
    /// ends, except where a fenced code line keeps every byte. Runs are joined by
    /// an ellipsis line, which marks uncited text and can't complete a JSON value
    /// across the gap.
    fn quote(self: Layout, a: std.mem.Allocator, proposal: extraction.Proposal) extraction.Error!Quote {
        const cited = try a.alloc(bool, self.lines.len);
        @memset(cited, false);
        for (proposal.citations) |id| {
            const index = for (self.lines, 0..) |line, index| {
                if (line.id.ordinal == id.ordinal) break index;
            } else return error.InvalidReferenceExtraction;
            // Admission offers only citable lines.
            if (!selections.citable(self.lines[index].text)) return error.InvalidReferenceExtraction;
            cited[index] = true;
        }
        var words: std.ArrayList(u8) = .empty;
        var citations: std.ArrayList(selections.Selection) = .empty;
        var index: usize = 0;
        while (index < self.lines.len) {
            if (!cited[index]) {
                index += 1;
                continue;
            }
            var last = index;
            var next = index + 1;
            while (next < self.lines.len and (cited[next] or !selections.citable(self.lines[next].text))) : (next += 1) {
                if (cited[next]) last = next;
            }
            var run = self.bytes[self.lines[index].span.start.byte..self.lines[last].span.end.byte];
            if (!self.code[index]) run = std.mem.trimStart(u8, run, " \t\r\n");
            if (!self.code[last]) run = std.mem.trimEnd(u8, run, " \t\r\n");
            if (words.items.len != 0) try words.appendSlice(a, "\n…\n");
            try words.appendSlice(a, run);
            try citations.append(a, .{ .first = self.lines[index].id, .last = self.lines[last].id });
            index = last + 1;
        }
        if (words.items.len == 0) return error.InvalidReferenceExtraction;
        const value = try words.toOwnedSlice(a);
        return .{ .citations = try citations.toOwnedSlice(a), .content = switch (proposal.category) {
            inline .business, .scope_guard => |tag| @unionInit(extraction.ProposalContent, @tagName(tag), .{ .segments = try a.dupe(text.BusinessSegment, &.{.{ .literal = .{ .value = value } }}) }),
            inline else => |tag| @unionInit(extraction.ProposalContent, @tagName(tag), .{ .nodes = try a.dupe(text.ReferenceNode, &.{.{ .literal = .{ .value = value } }}) }),
        } };
    }
};
