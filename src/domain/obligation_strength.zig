//! ADR 0044: generated text keeps the obligation strength of the source claims
//! it is linked to. A closed marker policy over literal prose only; exact values
//! and other typed insertions are never read, and a sentence copied from a linked
//! claim is the source's own wording.
const std = @import("std");
const text = @import("typed_text.zig");
const r = @import("reference_reconciliation.zig");

pub const Marker = enum {
    must,
    shall,
    may,
    might,
    should,
    could,

    pub const Strength = enum { mandatory, weaker };
    pub fn strength(self: Marker) Strength {
        return switch (self) {
            .must, .shall => .mandatory,
            .may, .might, .should, .could => .weaker,
        };
    }
};

/// A linked claim's prose, borrowed from the reference items.
pub const Prose = union(enum) { business: []const text.BusinessSegment, reference: []const text.ReferenceNode };

/// The linked claim whose mandatory marker the field's weaker marker replaces.
pub const Weakening = struct { claim_id: r.ClaimId, claim: Prose, source: Marker, field: Marker };

/// A field weakens an obligation when one of its linked claims states a mandatory
/// marker and the field states a weaker marker and no mandatory one.
pub fn weakening(items: r.Items, claim_ids: []const r.ClaimId, segments: []const text.BusinessSegment) r.Error!?Weakening {
    const linked: Linked = .{ .items = items, .claim_ids = claim_ids };
    var field: Found = .{};
    for (segments, 0..) |segment, index| if (segment == .literal) try scanField(segment.literal.value, index == 0, index + 1 == segments.len, linked, &field);
    const weaker = field.weaker orelse return null;
    if (field.mandatory != null) return null;
    for (claim_ids) |id| {
        const claim = (try claimProse(items, id)) orelse continue;
        var source: Found = .{};
        switch (claim) {
            inline else => |nodes| for (nodes) |node| if (node == .literal) scanProse(node.literal.value, &source),
        }
        if (source.mandatory) |mandatory| return .{ .claim_id = id, .claim = claim, .source = mandatory, .field = weaker };
    }
    return null;
}

/// The repair requirement leads with the action and quotes the claim, so the repair
/// restates the obligation as the source states it; it ends on the defect, never on
/// the weaker word as a goal. The quote is closed by its own full stop, since a quoted
/// claim needn't end a sentence. A claim's text is the engine's quote of its source
/// lines, one literal (ADR 0036).
pub fn requirement(a: std.mem.Allocator, found: Weakening) std.mem.Allocator.Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    out.writer.print("Restate linked claim {d}'s obligation as the claim states it: \"", .{found.claim_id.ordinal}) catch return error.OutOfMemory;
    switch (found.claim) {
        inline else => |nodes| for (nodes) |node| if (node == .literal) out.writer.writeAll(node.literal.value) catch return error.OutOfMemory,
    }
    out.writer.print("\". This text uses \"{s}\" where the claim uses \"{s}\".", .{ @tagName(found.field), @tagName(found.source) }) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

const Found = struct { mandatory: ?Marker = null, weaker: ?Marker = null };

fn claimProse(items: r.Items, id: r.ClaimId) r.Error!?Prose {
    return switch ((try r.item(items, id)).claim.content) {
        .preserved_token => null,
        .model => |content| switch (content) {
            inline .business, .scope_guard => |value| .{ .business = value.value.segments },
            inline else => |value| .{ .reference = value.value.nodes },
        },
    };
}

/// The claims a field is linked to. A source sentence can't weaken itself.
const Linked = struct {
    items: r.Items,
    claim_ids: []const r.ClaimId,

    /// Whether a whole field sentence is a whole sentence of a linked claim.
    fn copies(self: Linked, sentence: []const u8) r.Error!bool {
        for (self.claim_ids) |id| switch ((try claimProse(self.items, id)) orelse continue) {
            inline else => |nodes| for (nodes, 0..) |node, index| if (node == .literal) {
                var claim: Sentences = .{ .bytes = node.literal.value, .opens = index == 0, .closes = index + 1 == nodes.len };
                while (claim.next()) |source| if (source.whole and sameLoosely(body(source.bytes), body(sentence))) return true;
            },
        };
        return false;
    }
};

/// A copied sentence's weaker markers don't count; its mandatory markers still do.
fn scanField(literal: []const u8, opens: bool, closes: bool, linked: Linked, found: *Found) r.Error!void {
    var sentences: Sentences = .{ .bytes = literal, .opens = opens, .closes = closes };
    while (sentences.next()) |sentence| {
        var markers: Found = .{};
        scanProse(sentence.bytes, &markers);
        found.mandatory = found.mandatory orelse markers.mandatory;
        if (markers.weaker != null and !(sentence.whole and try linked.copies(sentence.bytes))) found.weaker = found.weaker orelse markers.weaker;
    }
}

const sentence_breaks = ".!?;:";

/// Sentences end at ".!?;:", the breaks that also end a negation's reach. A
/// sentence is whole unless an insertion cuts it at its literal's start or end.
const Sentences = struct {
    bytes: []const u8,
    opens: bool,
    closes: bool,
    start: usize = 0,

    const Sentence = struct { bytes: []const u8, whole: bool };
    fn next(self: *Sentences) ?Sentence {
        if (self.start == self.bytes.len) return null;
        const stop = std.mem.indexOfAnyPos(u8, self.bytes, self.start, sentence_breaks);
        const end = if (stop) |at| at + 1 else self.bytes.len;
        const sentence: Sentence = .{ .bytes = self.bytes[self.start..end], .whole = (self.start != 0 or self.opens) and (stop != null or self.closes) };
        self.start = end;
        return sentence;
    }
};

/// A sentence's words, without surrounding whitespace, a leading Markdown list or
/// quote marker, or its closing break.
fn body(sentence: []const u8) []const u8 {
    const spaces = " \t\r\n";
    return std.mem.trimStart(u8, std.mem.trimEnd(u8, sentence, spaces ++ sentence_breaks), spaces ++ "-*+>");
}

/// Equal, ignoring ASCII case and treating any run of whitespace as one.
fn sameLoosely(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        const space = std.ascii.isWhitespace(a[i]);
        if (space != std.ascii.isWhitespace(b[j])) return false;
        if (space) {
            while (i < a.len and std.ascii.isWhitespace(a[i])) i += 1;
            while (j < b.len and std.ascii.isWhitespace(b[j])) j += 1;
        } else {
            if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[j])) return false;
            i += 1;
            j += 1;
        }
    }
    return i == a.len and j == b.len;
}

/// Whole words, ignoring case. A marker followed by "not" or "never" in the same
/// sentence states a prohibition.
fn scanProse(prose: []const u8, found: *Found) void {
    var words: Words = .{ .bytes = prose };
    var current = words.next();
    while (current) |word| {
        const following = words.next();
        const negated = if (following) |next| !next.after_break and (std.ascii.eqlIgnoreCase(next.bytes, "not") or std.ascii.eqlIgnoreCase(next.bytes, "never")) else false;
        if (!negated) if (markerOf(word.bytes)) |marker| switch (marker.strength()) {
            .mandatory => found.mandatory = found.mandatory orelse marker,
            .weaker => found.weaker = found.weaker orelse marker,
        };
        current = following;
    }
}

fn markerOf(word: []const u8) ?Marker {
    inline for (std.meta.fields(Marker)) |field| if (std.ascii.eqlIgnoreCase(word, field.name)) return @enumFromInt(field.value);
    return null;
}

/// ASCII letters and apostrophes, so contractions such as "mustn't" are their
/// own words and never read as a marker. A word records whether sentence
/// punctuation separates it from the word before.
const Words = struct {
    bytes: []const u8,
    index: usize = 0,

    const Word = struct { bytes: []const u8, after_break: bool };
    fn next(self: *Words) ?Word {
        var after_break = false;
        while (self.index < self.bytes.len and !wordByte(self.bytes[self.index])) : (self.index += 1) {
            if (std.mem.indexOfScalar(u8, ".!?;:", self.bytes[self.index]) != null) after_break = true;
        }
        if (self.index == self.bytes.len) return null;
        const start = self.index;
        while (self.index < self.bytes.len and wordByte(self.bytes[self.index])) self.index += 1;
        return .{ .bytes = self.bytes[start..self.index], .after_break = after_break };
    }
    fn wordByte(byte: u8) bool {
        return std.ascii.isAlphabetic(byte) or byte == '\'';
    }
};

fn testClaim(comptime ordinal: u32, comptime content: @import("reference_extraction.zig").ClaimContent) r.Item {
    return .{ .claim = .{ .id = .{ .ordinal = ordinal }, .chunk_id = .{ .bytes = "chunk" }, .content = content, .citation_ids = &.{} }, .source_id = .{ .ordinal = 1 }, .block_id = .{ .ordinal = 1 }, .citations = &.{} };
}
fn businessClaim(comptime ordinal: u32, comptime prose: []const u8) r.Item {
    return testClaim(ordinal, .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = prose } }} } } } });
}
fn literalField(comptime prose: []const u8) []const text.BusinessSegment {
    return &.{.{ .literal = .{ .value = prose } }};
}

test "a weaker marker replaces a linked claim's mandatory marker" {
    const cases = .{
        .{ "A borrower must be able to renew a loan.", "A borrower may renew a loan.", Marker.may },
        .{ "The system shall refuse renewal.", "The system should refuse renewal.", Marker.should },
        .{ "Renewal MUST extend the due date.", "Renewal might extend the due date.", Marker.might },
        .{ "Renewal must extend the due date.", "Renewal could extend the due date.", Marker.could },
        // Sentence punctuation ends the negation lookahead.
        .{ "A borrower must be able to renew a loan.", "Renewal may happen. Not every loan qualifies.", Marker.may },
        .{ "A borrower must be able to renew a loan.", "Renewal may happen; never twice.", Marker.may },
        .{ "A borrower must be able to renew a loan.", "A borrower can renew a loan.", null },
        .{ "A borrower must be able to renew a loan.", "A borrower must be able to renew; renewal may happen once.", null },
        .{ "A borrower must be able to renew a loan.", "A borrower may not renew twice.", null },
        .{ "A borrower must be able to renew a loan.", "A borrower may never renew twice.", null },
        .{ "A borrower must not renew twice.", "A borrower may renew once.", null },
        .{ "A borrower must never renew twice.", "A borrower may renew once.", null },
        .{ "A loan may be renewed only once.", "A loan may be renewed once.", null },
        .{ "A borrower mustn't renew twice.", "A borrower could renew once.", null },
        .{ "A borrower must be able to renew a loan.", "Mayday is shown to a borrower.", null },
    };
    inline for (cases) |case| {
        const entries = [_]r.Item{businessClaim(1, case[0])};
        const found = try weakening(.{ .state_id = .{ .bytes = "state" }, .entries = &entries }, &.{.{ .ordinal = 1 }}, literalField(case[1]));
        try std.testing.expectEqual(@as(?Marker, case[2]), if (found) |weakened| weakened.field else null);
        if (found) |weakened| {
            try std.testing.expectEqual(@as(u32, 1), weakened.claim_id.ordinal);
            try std.testing.expect(weakened.source.strength() == .mandatory);
        }
    }
}

test "every linked claim is read, including reference claims, and only linked claims" {
    const entries = [_]r.Item{
        businessClaim(1, "A borrower renews a loan."),
        testClaim(2, .{ .model = .{ .validation = .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "Renewal shall be refused for an overdue loan." } }} } } } }),
    };
    const items: r.Items = .{ .state_id = .{ .bytes = "state" }, .entries = &entries };
    const field = literalField("Renewal might be refused for an overdue loan.");
    const found = (try weakening(items, &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, field)).?;
    try std.testing.expectEqual(@as(u32, 2), found.claim_id.ordinal);
    try std.testing.expectEqual(Marker.shall, found.source);
    try std.testing.expectEqual(Marker.might, found.field);
    try std.testing.expectEqual(@as(?Weakening, null), try weakening(items, &.{.{ .ordinal = 1 }}, field));
    try std.testing.expectError(error.InvalidReferenceReconciliation, weakening(items, &.{.{ .ordinal = 3 }}, field));
}

test "a whole sentence copied from a linked claim is the source's own wording" {
    const entries = [_]r.Item{
        businessClaim(1, "A borrower must be able to renew an active loan."),
        businessClaim(2, "- A loan may be renewed only once."),
        businessClaim(3, "If no hold is queued, a borrower may renew an active loan."),
    };
    const items: r.Items = .{ .state_id = .{ .bytes = "state" }, .entries = &entries };
    const linked = [_]r.ClaimId{ .{ .ordinal = 1 }, .{ .ordinal = 2 }, .{ .ordinal = 3 } };
    const cases = .{
        .{ "A loan may be renewed only once.", null },
        .{ "a loan  MAY be renewed\nonly once", null },
        .{ "A borrower must be able to renew an active loan. A loan may be renewed only once.", null },
        // A copied sentence's "must" still counts, whatever the break before the next.
        .{ "A borrower must be able to renew an active loan. Renewal may happen once.", null },
        .{ "A borrower must be able to renew an active loan; renewal may happen once.", null },
        // A paraphrase is the field's own wording.
        .{ "A loan may be renewed once.", Marker.may },
        .{ "A loan may be renewed only once. A borrower may renew an active loan.", Marker.may },
        // Part of a claim's sentence isn't a copy of it: this drops claim 3's condition.
        .{ "A borrower may renew an active loan.", Marker.may },
    };
    inline for (cases) |case| {
        const found = try weakening(items, &linked, literalField(case[0]));
        try std.testing.expectEqual(@as(?Marker, case[1]), if (found) |weakened| weakened.field else null);
        if (found) |weakened| try std.testing.expectEqual(@as(u32, 1), weakened.claim_id.ordinal);
    }
    // Only linked claims are copied from.
    try std.testing.expectEqual(Marker.may, (try weakening(items, &.{.{ .ordinal = 1 }}, literalField("A loan may be renewed only once."))).?.field);
    // A sentence cut by an insertion isn't whole, so it is never exempt.
    const cut = [_]text.BusinessSegment{
        .{ .literal = .{ .value = "A loan may be renewed " } },
        .{ .exact_copy = .{ .claim_id = .{ .ordinal = 2 } } },
        .{ .literal = .{ .value = " only once." } },
    };
    try std.testing.expectEqual(Marker.may, (try weakening(items, &linked, &cut)).?.field);
}

test "the copy rule holds in an unrelated domain" {
    const entries = [_]r.Item{
        businessClaim(1, "Exports shall run every Monday."),
        businessClaim(2, "* An administrator might pause an export: it resumes on the next run."),
    };
    const items: r.Items = .{ .state_id = .{ .bytes = "state" }, .entries = &entries };
    const linked = [_]r.ClaimId{ .{ .ordinal = 1 }, .{ .ordinal = 2 } };
    const cases = .{
        .{ "An administrator might pause an export:", null },
        .{ "Exports should run every Monday.", Marker.should },
        .{ "An administrator might pause an export.", null },
        .{ "Exports could run weekly. Exports shall run every Monday.", null },
        .{ "An administrator might pause exports.", Marker.might },
    };
    inline for (cases) |case| {
        const found = try weakening(items, &linked, literalField(case[0]));
        try std.testing.expectEqual(@as(?Marker, case[1]), if (found) |weakened| weakened.field else null);
    }
}

test "the repair requirement leads with the action, quotes the claim and names both words" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const entries = [_]r.Item{businessClaim(1, "A borrower must be able to renew a loan.")};
    const found = (try weakening(.{ .state_id = .{ .bytes = "state" }, .entries = &entries }, &.{.{ .ordinal = 1 }}, literalField("A borrower may renew a loan."))).?;
    try std.testing.expectEqualStrings(
        "Restate linked claim 1's obligation as the claim states it: \"A borrower must be able to renew a loan.\". This text uses \"may\" where the claim uses \"must\".",
        try requirement(arena.allocator(), found),
    );
    // A quoted list item or heading needn't end a sentence; the quote still closes one.
    const unpunctuated = [_]r.Item{businessClaim(1, "- The system shall refuse renewal")};
    const refused = (try weakening(.{ .state_id = .{ .bytes = "state" }, .entries = &unpunctuated }, &.{.{ .ordinal = 1 }}, literalField("The system should refuse renewal."))).?;
    try std.testing.expectEqualStrings(
        "Restate linked claim 1's obligation as the claim states it: \"- The system shall refuse renewal\". This text uses \"should\" where the claim uses \"shall\".",
        try requirement(arena.allocator(), refused),
    );
}

test "exact values and other insertions are never read" {
    const entries = [_]r.Item{businessClaim(1, "The system must display the renewal message.")};
    const field = [_]text.BusinessSegment{
        .{ .literal = .{ .value = "Display " } },
        .{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } },
        .{ .literal = .{ .value = " on renewal." } },
    };
    try std.testing.expectEqual(@as(?Weakening, null), try weakening(.{ .state_id = .{ .bytes = "state" }, .entries = &entries }, &.{.{ .ordinal = 1 }}, &field));
}
