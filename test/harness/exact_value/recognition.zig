//! Offline lexical prototype only. No schema, representation, lineage, coverage,
//! repair or publication authority is granted by this report. Inputs supply the
//! occurrence-to-requirement relation; matching text cannot establish it.
const std = @import("std");
const scalar = @import("../../../src/domain/typed_text.zig");
pub const LexicalClassifier = @import("../../../src/ports/unicode_normalizer.zig").LexicalClassifier;
pub const RequirementId = struct { value: u32 };
pub const OccurrenceId = struct { value: u32 };
pub const Occurrence = struct {
    id: OccurrenceId,
    requirements: []const RequirementId,
    bytes: []const u8,
};
pub const Input = struct {
    prose: []const u8,
    bound_requirements: []const RequirementId,
    occurrences: []const Occurrence,
};
pub const Witness = struct {
    occurrence: OccurrenceId,
    start_byte: usize,
    end_byte: usize,
};
pub const BoundaryRejection = struct {
    candidate: Witness,
    eligible: bool,
    left_boundary: bool,
    right_boundary: bool,
};
pub const Conflict = struct { left: Witness, right: Witness };
pub const Diagnostic = union(enum) {
    boundary_rejected: BoundaryRejection,
    competing_lineage: Conflict,
    overlapping_matches: Conflict,
};
pub const State = enum { matched, no_match, ambiguous };
pub const Report = struct {
    state: State,
    /// Only individually unambiguous, requirement-bound lexical witnesses.
    /// A nonempty list cannot make an ambiguous field usable by another owner.
    matches: []const Witness,
    /// Exact byte spans satisfying boundaries without the required binding.
    /// These remain visible evidence and never enter matches or conflicts.
    unbound_matches: []const Witness,
    diagnostics: []const Diagnostic,

    pub fn deinit(self: Report, a: std.mem.Allocator) void {
        a.free(self.matches);
        a.free(self.unbound_matches);
        a.free(self.diagnostics);
    }
};
pub const RejectionReason = enum {
    invalid_prose,
    invalid_occurrence_id,
    duplicate_occurrence_id,
    empty_occurrence,
    invalid_occurrence_bytes,
    invalid_requirement_id,
    duplicate_requirement_id,
};
pub const Rejection = struct {
    reason: RejectionReason,
    occurrence_index: ?usize = null,
    binding_index: ?usize = null,
};
pub const Outcome = union(enum) {
    rejected: Rejection,
    evaluated: Report,

    pub fn deinit(self: Outcome, a: std.mem.Allocator) void {
        switch (self) {
            .rejected => {},
            .evaluated => |report| report.deinit(a),
        }
    }
};

/// The supplied pure classifier must implement the declared whole-word policy:
/// Unicode letters, numbers, marks, connectors and format scalars cannot bound a
/// match. The offline adapter uses the repository's pinned Unicode data. This
/// module imports no Unicode/provider/filesystem/process implementation.
///
/// Match exact UTF-8 bytes before NFC, case folding, rendering or Markdown
/// escaping. Output stores original byte spans only and owns all returned arrays.
pub fn recognize(a: std.mem.Allocator, input: Input, classifier: LexicalClassifier) std.mem.Allocator.Error!Outcome {
    if (validate(input)) |rejection| return .{ .rejected = rejection };
    const boundaries = try boundaryMap(a, input.prose, classifier);
    defer a.free(boundaries);
    var eligible: std.ArrayList(Witness) = .empty;
    defer eligible.deinit(a);
    var unbound: std.ArrayList(Witness) = .empty;
    errdefer unbound.deinit(a);
    var rejected_boundaries: std.ArrayList(BoundaryRejection) = .empty;
    defer rejected_boundaries.deinit(a);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    errdefer diagnostics.deinit(a);
    for (input.occurrences) |occurrence| {
        const bound = intersects(input.bound_requirements, occurrence.requirements);
        var offset: usize = 0;
        while (std.mem.indexOfPos(u8, input.prose, offset, occurrence.bytes)) |start| {
            const end = start + occurrence.bytes.len;
            const witness: Witness = .{ .occurrence = occurrence.id, .start_byte = start, .end_byte = end };
            const left = boundaries[start].left;
            const right = boundaries[end].right;
            if (!left or !right) {
                try rejected_boundaries.append(a, .{ .candidate = witness, .eligible = bound, .left_boundary = left, .right_boundary = right });
            } else if (bound) {
                try eligible.append(a, witness);
            } else {
                try unbound.append(a, witness);
            }
            // Search overlapping occurrences too; choosing only disjoint/longest
            // occurrences would erase evidence that makes recognition ambiguous.
            offset = start + 1;
        }
    }
    std.mem.sort(Witness, eligible.items, {}, lessWitness);
    std.mem.sort(Witness, unbound.items, {}, lessWitness);
    std.mem.sort(BoundaryRejection, rejected_boundaries.items, {}, struct {
        fn less(_: void, left: BoundaryRejection, right: BoundaryRejection) bool {
            return lessWitness({}, left.candidate, right.candidate);
        }
    }.less);
    for (rejected_boundaries.items) |rejection| try diagnostics.append(a, .{ .boundary_rejected = rejection });
    const conflicted = try a.alloc(bool, eligible.items.len);
    defer a.free(conflicted);
    @memset(conflicted, false);
    var ambiguous = false;
    for (eligible.items, 0..) |left, index| {
        for (eligible.items[index + 1 ..], index + 1..) |right, right_index| {
            if (right.start_byte >= left.end_byte) break;
            if (left.start_byte >= right.end_byte) continue;
            ambiguous = true;
            conflicted[index] = true;
            conflicted[right_index] = true;
            const conflict: Conflict = .{ .left = left, .right = right };
            try diagnostics.append(a, if (left.start_byte == right.start_byte and left.end_byte == right.end_byte)
                .{ .competing_lineage = conflict }
            else
                .{ .overlapping_matches = conflict });
        }
    }
    var matches: std.ArrayList(Witness) = .empty;
    errdefer matches.deinit(a);
    for (eligible.items, conflicted) |witness, conflict| if (!conflict) try matches.append(a, witness);
    const matched = try matches.toOwnedSlice(a);
    errdefer a.free(matched);
    const unbound_matches = try unbound.toOwnedSlice(a);
    errdefer a.free(unbound_matches);
    return .{ .evaluated = .{
        .state = if (ambiguous) .ambiguous else if (matched.len != 0) .matched else .no_match,
        .matches = matched,
        .unbound_matches = unbound_matches,
        .diagnostics = try diagnostics.toOwnedSlice(a),
    } };
}

fn validate(input: Input) ?Rejection {
    if (!scalar.validScalar(input.prose)) return .{ .reason = .invalid_prose };
    if (invalidRequirements(input.bound_requirements, null)) |rejection| return rejection;
    for (input.occurrences, 0..) |occurrence, index| {
        if (occurrence.id.value == 0) return .{ .reason = .invalid_occurrence_id, .occurrence_index = index };
        for (input.occurrences[0..index]) |prior| if (prior.id.value == occurrence.id.value) return .{ .reason = .duplicate_occurrence_id, .occurrence_index = index };
        if (occurrence.bytes.len == 0) return .{ .reason = .empty_occurrence, .occurrence_index = index };
        if (!scalar.validScalar(occurrence.bytes)) return .{ .reason = .invalid_occurrence_bytes, .occurrence_index = index };
        if (invalidRequirements(occurrence.requirements, index)) |rejection| return rejection;
    }
    return null;
}
fn invalidRequirements(ids: []const RequirementId, occurrence: ?usize) ?Rejection {
    for (ids, 0..) |id, index| {
        if (id.value == 0) return .{ .reason = .invalid_requirement_id, .occurrence_index = occurrence, .binding_index = index };
        for (ids[0..index]) |prior| if (prior.value == id.value) return .{ .reason = .duplicate_requirement_id, .occurrence_index = occurrence, .binding_index = index };
    }
    return null;
}
fn intersects(left: []const RequirementId, right: []const RequirementId) bool {
    for (left) |one| for (right) |other| if (one.value == other.value) return true;
    return false;
}
fn lessWitness(_: void, left: Witness, right: Witness) bool {
    if (left.start_byte != right.start_byte) return left.start_byte < right.start_byte;
    if (left.end_byte != right.end_byte) return left.end_byte < right.end_byte;
    return left.occurrence.value < right.occurrence.value;
}
const Boundary = struct { left: bool, right: bool };
fn boundaryMap(a: std.mem.Allocator, prose: []const u8, classifier: LexicalClassifier) std.mem.Allocator.Error![]const Boundary {
    const count = std.math.add(usize, prose.len, 1) catch return error.OutOfMemory;
    const result = try a.alloc(Boundary, count);
    @memset(result, .{ .left = false, .right = false });
    // validate() established UTF-8 validity. Non-scalar byte positions stay
    // closed so no substring can manufacture a boundary within an encoding.
    const view = std.unicode.Utf8View.initUnchecked(prose);
    var iterator = view.iterator();
    var previous = true;
    var start: usize = 0;
    while (iterator.nextCodepoint()) |point| {
        const end = iterator.i;
        const current = classifier.isBoundary(point);
        result[start] = .{ .left = previous, .right = current };
        previous = current;
        start = end;
    }
    result[prose.len] = .{ .left = previous, .right = true };
    return result;
}
