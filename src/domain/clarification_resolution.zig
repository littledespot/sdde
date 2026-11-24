//! The clarification answers generation applies. An answer is the user's decision: the engine resolves it from the
//! validated clarification state and the current claims, no model reads it, and no code judges its prose (ADR 0025).
//! Only a choice among the claims of one reference conflict is applied; every other answer stays protected and unused.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const r = @import("reference_reconciliation.zig");
const refs = @import("reference_support.zig");
const spec = @import("specification.zig");
const subject_text = @import("clarification_subject.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidClarificationInput};

/// The user's choice among the claims of one reference conflict: the response that holds it, the subject of the form it
/// answered, and the option it selected, by key and by the label the form showed (the claim's quotation).
pub const ConflictChoice = struct { response_id: spec.ResponseId, subject: c.Subject, key: []const u8, label: []const u8 };

/// The choices of the `resolved_by_user` Specify forms that offered one option for each claim of a conflict, in the
/// state's record order. A cancelled form, a deferral, an open form and an answer of another kind grant none.
/// Everything returned borrows the state.
pub fn choices(allocator: std.mem.Allocator, state: c.ValidatedState) Error![]const ConflictChoice {
    const held = state.value orelse return &.{};
    var result: std.ArrayList(ConflictChoice) = .empty;
    errdefer result.deinit(allocator);
    for (held.records) |record| {
        const id = c.Id.parse(record.id) orelse return error.InvalidClarificationInput;
        if (id.stage != .spec or record.status != .resolved_by_user or !isConflict(record.subject)) continue;
        const options = switch (record.answer_schema) {
            .select_one => |value| value,
            else => continue,
        };
        const response = c.findResponse(held, record.response_id orelse return error.InvalidClarificationInput) orelse return error.InvalidClarificationInput;
        if (response.id == 0) return error.InvalidClarificationInput;
        const key = switch (response.answer) {
            .selected_option => |value| value,
            else => return error.InvalidClarificationInput,
        };
        // An accepted answer was checked against the options its form offered; a state that says otherwise is not valid.
        const label = for (options) |option| {
            if (std.mem.eql(u8, option.key, key)) break option.label;
        } else return error.InvalidClarificationInput;
        try result.append(allocator, .{ .response_id = .{ .ordinal = response.id }, .subject = record.subject, .key = key, .label = label });
    }
    return result.toOwnedSlice(allocator);
}

/// The choice that answered the form of `subject`, if any.
pub fn answerFor(all: []const ConflictChoice, subject: c.Subject) ?ConflictChoice {
    for (all) |choice| if (c.sameSubject(choice.subject, subject)) return choice;
    return null;
}

fn isConflict(subject: c.Subject) bool {
    return std.mem.eql(u8, subject.requirement, "reference_meaning") and std.mem.eql(u8, subject.unit, "conflict") and std.mem.eql(u8, subject.slot, "disposition");
}

/// One option for each claim of the conflict. The key names the source lines the claim cites, so it is the same on every
/// run over the same sources and no per-run ordinal identifies a claim; the label is the claim's quotation. A key or label
/// the form cannot hold, or two claims that cite the same lines, are not options: nothing is shortened or renamed.
pub fn conflictOptions(allocator: std.mem.Allocator, corpus: []const r.evidence.Source, records: refs.Records, conflict: r.Conflict) Error![]const c.Option {
    if (conflict.value.claim_ids.len == 0) return error.InvalidClarificationInput;
    const options = try allocator.alloc(c.Option, conflict.value.claim_ids.len);
    var done: usize = 0;
    errdefer {
        for (options[0..done]) |option| {
            allocator.free(option.key);
            allocator.free(option.label);
        }
        allocator.free(options);
    }
    for (conflict.value.claim_ids, options) |claim_id, *option| {
        const item = r.item(records.items, claim_id) catch return error.InvalidClarificationInput;
        const key = try keyOf(allocator, corpus, records.items, item);
        errdefer allocator.free(key);
        const label = try labelOf(allocator, item);
        errdefer allocator.free(label);
        for (options[0..done]) |other| if (std.mem.eql(u8, other.key, key)) return error.InvalidClarificationInput;
        option.* = .{ .key = key, .label = label };
        done += 1;
    }
    return options;
}

/// The claim of the conflict the user chose, or none. The claim must offer the option now exactly as the form showed it:
/// the key names the lines, and the label is the quotation of those lines, so a text edited in place under the same lines
/// is not the text the user chose. A key that two claims of the conflict carry selects none either.
pub fn chosenClaim(allocator: std.mem.Allocator, corpus: []const r.evidence.Source, records: refs.Records, conflict: r.Conflict, key: []const u8, label: []const u8) Error!?r.ClaimId {
    var found: ?r.ClaimId = null;
    for (conflict.value.claim_ids) |claim_id| {
        const item = r.item(records.items, claim_id) catch return error.InvalidClarificationInput;
        const candidate = try keyOf(allocator, corpus, records.items, item);
        defer allocator.free(candidate);
        if (!std.mem.eql(u8, candidate, key)) continue;
        if (found != null) return null;
        const shown = try labelOf(allocator, item);
        defer allocator.free(shown);
        if (!std.mem.eql(u8, shown, label)) return null;
        found = claim_id;
    }
    return found;
}

fn keyOf(allocator: std.mem.Allocator, corpus: []const r.evidence.Source, items: r.Items, item: r.Item) Error![]const u8 {
    const spans = try subject_text.fromCitations(allocator, corpus, items.entries, item.claim.citation_ids);
    defer allocator.free(spans);
    var key: std.ArrayList(u8) = .empty;
    errdefer key.deinit(allocator);
    for (spans, 0..) |span, index| {
        if (index != 0) try key.append(allocator, '_');
        for (span.path) |byte| try key.append(allocator, if (byte == '/') '.' else byte);
        if (span.lines) |lines| {
            const part = if (lines.first == lines.last) try std.fmt.allocPrint(allocator, ".{d}", .{lines.first}) else try std.fmt.allocPrint(allocator, ".{d}-{d}", .{ lines.first, lines.last });
            defer allocator.free(part);
            try key.appendSlice(allocator, part);
        }
    }
    if (!c.validToken(key.items)) return error.InvalidClarificationInput;
    return key.toOwnedSlice(allocator);
}

/// The claim's quotation. A claim with no quotation to show is not an option: the form shows nothing the sources do not.
fn labelOf(allocator: std.mem.Allocator, item: r.Item) Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    for (item.citations) |citation| {
        const quote = std.mem.trim(u8, citation.value.verbatim orelse continue, " \t\r\n");
        if (quote.len == 0) continue;
        if (text.items.len != 0) try text.append(allocator, ' ');
        try text.appendSlice(allocator, quote);
    }
    if (!c.validText(text.items, c.max_text_bytes)) return error.InvalidClarificationInput;
    return text.toOwnedSlice(allocator);
}
