const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const text = @import("typed_text.zig");
pub fn validate(validator: text.Validator, allocator: std.mem.Allocator, registry: @import("passive_literals.zig").Registry, inputs: evidence.Inputs, parsed: extraction.Parsed) extraction.Error!extraction.TextResult {
    // Even empty/blocked candidate sets must bind current source data.
    try @import("path_token_grammar.zig").validateInputs(registry.grammar, inputs);
    if (parsed.revision == 0) return error.InvalidReferenceExtraction;
    const entries = try allocator.alloc(extraction.TextValidatedResult, parsed.entries.len);
    var structure: Structure = try .init(allocator, inputs);
    for (parsed.entries, entries) |candidate, *entry| {
        const context: text.ScopeSetContext = .{ .registry = registry, .inputs = inputs, .scopes = &.{candidate.scope}, .field = .extraction_reason };
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
                .invalid => |issue| return reject(allocator, inputs, registry, parsed, candidate, .reason, issue, .{ .reason = reason }),
            } },
            .claims => |proposals| claims: {
                const origin = if (candidate.producers) |producers| producers.content else candidate.origin;
                const layout = try Layout.init(allocator, inputs, candidate.scope, &structure);
                var checked: std.ArrayList(extraction.TextValidatedProposal) = .empty;
                for (proposals) |proposal| for (try layout.quotes(allocator, proposal)) |quoted| {
                    // Quoted source text has no model wording to repair (ADR 0036).
                    const content = switch (try checkContent(validator, allocator, context, quoted.content)) {
                        .valid => |accepted| accepted,
                        .invalid => return error.InvalidReferenceExtraction,
                    };
                    _ = try appendDistinct(allocator, &checked, .{ .content = content, .citations = quoted.citations, .origin = origin });
                };
                break :claims .{ .claims = try checked.toOwnedSlice(allocator) };
            },
        };
    }
    return .{ .valid = .{ .revision = parsed.revision, .last_repair = parsed.last_repair, .entries = entries } };
}

/// One piece of source evidence is one claim. A claim's text is the
/// engine's quote of its cited lines (ADR 0036), so a later claim of the same
/// category citing the same lines of the same chunk is the same evidence and adds
/// nothing: the first is kept, with its origin, before any claim identity exists.
/// The raw model response is unchanged. Returns whether `claim` was appended.
pub fn appendDistinct(a: std.mem.Allocator, claims: *std.ArrayList(extraction.TextValidatedProposal), claim: extraction.TextValidatedProposal) std.mem.Allocator.Error!bool {
    for (claims.items) |existing| {
        if (std.meta.activeTag(existing.content) == std.meta.activeTag(claim.content) and sameCitations(existing.citations, claim.citations)) return false;
    }
    try claims.append(a, claim);
    return true;
}

fn sameCitations(left: []const @import("source_selections.zig").Selection, right: []const @import("source_selections.zig").Selection) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| if (!std.meta.eql(l, r)) return false;
    return true;
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
pub fn validTarget(validator: text.Validator, a: std.mem.Allocator, registry: @import("passive_literals.zig").Registry, inputs: evidence.Inputs, parsed: extraction.Parsed, scope: evidence.Scope, target: extraction.TextTarget) extraction.Error!bool {
    try @import("path_token_grammar.zig").validateInputs(registry.grammar, inputs);
    _ = try evidence.resolve(inputs, scope);
    for (parsed.entries) |entry| if (entry.scope.chunk_id.eql(scope.chunk_id)) {
        if (!entry.scope.state_id.eql(scope.state_id)) return error.InvalidReferenceExtraction;
        const context: text.ScopeSetContext = .{ .registry = registry, .inputs = inputs, .scopes = &.{scope}, .field = .extraction_reason };
        return switch (target) {
            .reason => if (entry.outcome == .no_feature_claim)
                (try validator.checkReferenceIn(a, context, entry.outcome.no_feature_claim)) == .valid
            else
                error.InvalidReferenceExtraction,
        };
    };
    return error.InvalidReferenceExtraction;
}

fn reject(a: std.mem.Allocator, inputs: evidence.Inputs, registry: @import("passive_literals.zig").Registry, parsed: extraction.Parsed, entry: extraction.ParsedResult, target: extraction.TextTarget, issue: text.Issue, observed: @FieldType(extraction.TextRejection, "observed")) extraction.Error!extraction.TextResult {
    const context = @import("reference_extraction_context.zig");
    return .{ .invalid = .{ .scope = entry.scope, .revision = parsed.revision, .target = target, .origin = extraction.textOrigin(entry, target), .issue = issue, .observed = observed, .dependencies = try @import("atomic_repair.zig").snapshot(context.TextFacts, a, context.textFacts(inputs, registry, parsed)) } };
}

pub const RequoteError = extraction.Error || @import("naming_policy.zig").Error;

/// ADR 0036: a stored model claim's wording is the engine's quote of the source lines its citations span, in canonical
/// text. Readback derives that quote again with the code that admitted it, so a stored claim that no longer quotes its
/// own citations is rejected before any later check relies on it. A preserved token quotes nothing, and a no-claim
/// reason is model text, so neither is checked here.
pub const Requote = struct {
    inputs: evidence.Inputs,
    canonical: text.CanonicalText,
    structure: Structure,

    pub fn init(a: std.mem.Allocator, inputs: evidence.Inputs, normalizer: @import("../ports/unicode_normalizer.zig").Normalizer) std.mem.Allocator.Error!Requote {
        return .{ .inputs = inputs, .canonical = try text.CanonicalText.fromInputs(a, normalizer, inputs), .structure = try .init(a, inputs) };
    }

    /// `citations` is the ledger's citation list, which `claim.citation_ids` index by ordinal. Every allocation is
    /// from `a`, with no release of its own, so `a` must be a scratch arena.
    pub fn check(self: *Requote, a: std.mem.Allocator, claim: extraction.Claim, citations: []const extraction.Citation) RequoteError!void {
        const stored = switch (claim.content) {
            .model => |content| content,
            .preserved_token => return,
        };
        const layout = try Layout.init(a, self.inputs, .{ .state_id = self.inputs.corpus.state_id, .chunk_id = claim.chunk_id }, &self.structure);
        // The lines each stored citation spans; a run quotes every line from its first to its last.
        const cited = try a.alloc(bool, layout.lines.len);
        @memset(cited, false);
        for (claim.citation_ids) |id| {
            if (id.ordinal == 0 or id.ordinal > citations.len) return error.InvalidReferenceExtraction;
            const span = citations[id.ordinal - 1].value.location;
            const first = layout.lineStartingAt(span.start.byte) orelse return error.InvalidReferenceExtraction;
            const last = layout.lineEndingAt(span.end.byte) orelse return error.InvalidReferenceExtraction;
            if (last < first) return error.InvalidReferenceExtraction;
            @memset(cited[first .. last + 1], true);
        }
        // Admission makes one claim of each top-level list item (ADR 0038), so one stored claim never spans two.
        if (layout.spansItems(cited)) return error.InvalidReferenceExtraction;
        const quoted = try layout.quote(a, std.meta.activeTag(stored), cited);
        // Admission stores one citation per run, in source order.
        if (quoted.citations.len != claim.citation_ids.len) return error.InvalidReferenceExtraction;
        for (quoted.citations, claim.citation_ids) |run, id| {
            const span = citations[id.ordinal - 1].value.location;
            if (layout.lines[run.first.ordinal - 1].span.start.byte != span.start.byte or layout.lines[run.last.ordinal - 1].span.end.byte != span.end.byte) return error.InvalidReferenceExtraction;
        }
        switch (stored) {
            inline .business, .scope_guard => |value, tag| {
                const wanted = try text.canonicalNodes(text.BusinessSegment, a, self.canonical, @field(quoted.content, @tagName(tag)).segments);
                if (!text.equivalentBusiness(.{ .value = .{ .segments = wanted } }, value)) return error.InvalidReferenceExtraction;
            },
            inline else => |value, tag| {
                const wanted = try text.canonicalNodes(text.ReferenceNode, a, self.canonical, @field(quoted.content, @tagName(tag)).nodes);
                if (!text.equivalentReference(.{ .value = .{ .nodes = wanted } }, value)) return error.InvalidReferenceExtraction;
            },
        }
    }
};

const selections = @import("source_selections.zig");
const markdown = @import("markdown_code_spans.zig");
const Quote = struct { content: extraction.ProposalContent, citations: []const selections.Selection };

/// Each source's list structure from its reader (ADR 0038), built once per
/// validation and only for sources whose claims are quoted, so a chunk boundary
/// can't change it.
const Structure = struct {
    inputs: evidence.Inputs,
    sources: []?[]const markdown.ListLine,

    fn init(a: std.mem.Allocator, inputs: evidence.Inputs) std.mem.Allocator.Error!Structure {
        const sources = try a.alloc(?[]const markdown.ListLine, inputs.corpus.sources.len);
        @memset(sources, null);
        return .{ .inputs = inputs, .sources = sources };
    }
    fn of(self: *Structure, a: std.mem.Allocator, source: evidence.Source) extraction.Error![]const markdown.ListLine {
        const index = for (self.inputs.corpus.sources, 0..) |candidate, index| {
            if (candidate.id.ordinal == source.id.ordinal) break index;
        } else return error.InvalidReferenceExtraction;
        if (self.sources[index] == null) self.sources[index] = switch (source.reader) {
            .markdown_source_v1 => try markdown.listSegments(a, source.bytes),
        };
        return self.sources[index].?;
    }
};

/// ADR 0036, ADR 0038: one chunk's supplied lines, each with the source line
/// holding it, which gives its top-level list segment and whether it is fenced code.
const Layout = struct {
    bytes: []const u8,
    lines: []const selections.Line,
    list: []const markdown.ListLine,

    fn init(a: std.mem.Allocator, inputs: evidence.Inputs, scope: evidence.Scope, structure: *Structure) extraction.Error!Layout {
        const view = try evidence.resolve(inputs, scope);
        const lines = try selections.lines(a, inputs, scope);
        const source = try structure.of(a, view.source);
        const list = try a.alloc(markdown.ListLine, lines.len);
        // The source line holding the chunk's first line, then a forward walk.
        var low: usize = 0;
        var high = source.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (lines.len != 0 and source[middle].start <= lines[0].span.start.byte) low = middle + 1 else high = middle;
        }
        var index = low -| 1;
        for (lines, list) |line, *holding| {
            while (index + 1 < source.len and source[index + 1].start <= line.span.start.byte) index += 1;
            if (index >= source.len or source[index].start > line.span.start.byte) return error.InvalidReferenceExtraction;
            holding.* = source[index];
        }
        return .{ .bytes = view.source.bytes, .lines = lines, .list = list };
    }

    /// The index of the line that starts at source byte `byte`, if the chunk supplies one.
    fn lineStartingAt(self: Layout, byte: usize) ?usize {
        for (self.lines, 0..) |line, index| if (line.span.start.byte == byte) return index;
        return null;
    }

    /// The index of the line that ends at source byte `byte`, if the chunk supplies one.
    fn lineEndingAt(self: Layout, byte: usize) ?usize {
        for (self.lines, 0..) |line, index| if (line.span.end.byte == byte) return index;
        return null;
    }

    /// Whether the cited lines belong to two or more top-level list items, which admission quotes as separate claims.
    fn spansItems(self: Layout, cited: []const bool) bool {
        var first: ?u32 = null;
        for (cited, self.list) |selected, line| if (selected and line.inItem()) {
            if (first == null) first = line.segment else if (first.? != line.segment) return true;
        };
        return false;
    }

    /// A claim quotes the lines it cites. When they belong to two or more
    /// top-level list items, each item becomes its own claim, and the cited
    /// lines in each gap between items become one claim.
    fn quotes(self: Layout, a: std.mem.Allocator, proposal: extraction.Proposal) extraction.Error![]const Quote {
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
        const split = self.spansItems(cited);
        var result: std.ArrayList(Quote) = .empty;
        const group = try a.alloc(bool, self.lines.len);
        var start: usize = 0;
        while (start < self.lines.len) {
            var end = self.lines.len;
            if (split) {
                end = start + 1;
                while (end < self.lines.len and self.list[end].segment == self.list[start].segment) end += 1;
            }
            @memset(group, false);
            var any = false;
            for (start..end) |index| {
                group[index] = cited[index];
                any = any or cited[index];
            }
            if (any) try result.append(a, try self.quote(a, proposal.category, group));
            start = end;
        }
        if (result.items.len == 0) return error.InvalidReferenceExtraction;
        return result.toOwnedSlice(a);
    }

    /// The source bytes of each run of cited lines, as written. A run continues
    /// across uncited blank lines and is trimmed at its ends, except where a
    /// fenced code line keeps every byte. Runs are joined by an ellipsis line,
    /// which marks uncited text and can't complete a JSON value across the gap.
    fn quote(self: Layout, a: std.mem.Allocator, category: extraction.Kind, cited: []const bool) extraction.Error!Quote {
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
            if (!self.list[index].code) run = std.mem.trimStart(u8, run, " \t\r\n");
            if (!self.list[last].code) run = std.mem.trimEnd(u8, run, " \t\r\n");
            if (words.items.len != 0) try words.appendSlice(a, "\n…\n");
            try words.appendSlice(a, run);
            try citations.append(a, .{ .first = self.lines[index].id, .last = self.lines[last].id });
            index = last + 1;
        }
        if (words.items.len == 0) return error.InvalidReferenceExtraction;
        const value = try words.toOwnedSlice(a);
        return .{ .citations = try citations.toOwnedSlice(a), .content = switch (category) {
            inline .business, .scope_guard => |tag| @unionInit(extraction.ProposalContent, @tagName(tag), .{ .segments = try a.dupe(text.BusinessSegment, &.{.{ .literal = .{ .value = value } }}) }),
            inline else => |tag| @unionInit(extraction.ProposalContent, @tagName(tag), .{ .nodes = try a.dupe(text.ReferenceNode, &.{.{ .literal = .{ .value = value } }}) }),
        } };
    }
};
