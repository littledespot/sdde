//! Read-only clarification inputs. Neither a submitted close nor a loaded
//! response establishes current applicability or authorizes a state transition.
const std = @import("std");
const feature = @import("feature_identity.zig");

pub const max_forms = 297;
pub const max_form_bytes = 16 * 1024;
pub const max_state_bytes = 8 * 1024 * 1024;
/// The deepest nesting the closed state has: the document, records, a record, its answer
/// schema, `select_many`, its options, one option. A subject's lines reach it too: the document, records, a record, its
/// subject, its sources, one span, its lines.
pub const max_state_depth = 7;
pub const max_responses = 4096;
pub const max_text_bytes = 2000;
/// v3: every response's `authentication_evidence_id` joins the actor-evidence registry, so a v2 state, whose IDs join none,
/// is rejected without a reader (ADR 0025). v4: a subject carries the engine-derived source selector, not a per-run
/// ordinal or a model-picked kind, so a v3 state's subjects match no current need and the state is rejected without a
/// reader (ADR 0025).
pub const schema_version = "clarification-state/v4";
/// The most source spans one subject names.
pub const max_subject_spans = 128;
/// The most authorities one record names.
pub const max_record_authorities = 64;
pub const Error = std.mem.Allocator.Error || error{InvalidClarificationInput};
pub const Stage = enum { spec, plan, tasks };
pub const Id = struct {
    stage: Stage,
    ordinal: u8,

    pub fn parse(bytes: []const u8) ?Id {
        if (bytes.len != 3 or !std.ascii.isDigit(bytes[1]) or !std.ascii.isDigit(bytes[2])) return null;
        const ordinal = (bytes[1] - '0') * 10 + bytes[2] - '0';
        if (ordinal == 0) return null;
        return .{ .stage = switch (bytes[0]) {
            'S' => .spec,
            'P' => .plan,
            'T' => .tasks,
            else => return null,
        }, .ordinal = ordinal };
    }

    /// What a directory entry's name says it is. `form` is exactly a form's file name. `form_shaped` is a name a form
    /// could be mistaken for, ignoring ASCII case (`s01.md`, `S01.MD`), or whose ordinal no form has (`S00.md`): the
    /// capture fails on it. `other` is any other name, which is no form's.
    pub const Name = union(enum) { form: Id, form_shaped, other };

    pub fn classifyName(name: []const u8) Name {
        const shaped = name.len == 6 and std.mem.indexOfScalar(u8, "SPTspt", name[0]) != null and
            std.ascii.isDigit(name[1]) and std.ascii.isDigit(name[2]) and std.ascii.eqlIgnoreCase(name[3..], ".md");
        if (!shaped) return .other;
        const id = parse(name[0..3]) orelse return .form_shaped;
        return if (std.mem.eql(u8, name[3..], ".md")) .{ .form = id } else .form_shaped;
    }

    pub fn index(self: Id) usize {
        return @as(usize, @intFromEnum(self.stage)) * 99 + self.ordinal - 1;
    }

    pub fn filename(self: Id) [6]u8 {
        return .{ switch (self.stage) {
            .spec => 'S',
            .plan => 'P',
            .tasks => 'T',
        }, '0' + self.ordinal / 10, '0' + self.ordinal % 10, '.', 'm', 'd' };
    }
};

pub const FormCapture = struct { id: Id, bytes: []const u8 };
pub const Captures = struct { state: ?[]const u8, forms: []const FormCapture };
/// The text of one source a clarification is about: the source's normalized relative path in the reference directory and
/// the exact lines, or the whole source when `lines` is null. Not a per-run ID, a hash or a model value.
pub const SourceSpan = struct { path: []const u8, lines: ?@import("source_coordinates.zig").Lines };
/// What a clarification is about, derived by the engine. `sources` is canonical (`validSources`): sorted by path, then
/// lines, with no overlapping or adjacent line ranges, and empty when the unit names no source text.
pub const Subject = struct { requirement: []const u8, unit: []const u8, slot: []const u8, sources: []const SourceSpan };
pub const Authority = @import("authority_identity.zig").Authority;
pub const Option = struct { key: []const u8, label: []const u8 };
pub const AnswerSchema = union(enum) {
    bounded_business_text: usize,
    select_one: []const Option,
    select_many: struct { minimum: usize, maximum: usize, options: []const Option },
};
pub const Answer = union(enum) {
    none: void,
    business_text: []const u8,
    selected_option: []const u8,
    selected_options: []const []const u8,
    defer_reason: []const u8,
    cancel_reason: []const u8,
};
pub const EngineStatus = enum { open, resolved_by_user, resolved_by_authority, cancelled_by_user };
pub const RequestedStatus = enum { open, closed, cancel };
pub const Record = struct {
    id: []const u8,
    revision: u64,
    subject: Subject,
    authority: []const Authority,
    question: []const u8,
    why_required: []const u8,
    answer_schema: AnswerSchema,
    status: EngineStatus,
    response_id: ?u64,
    authority_resolution: ?[]const u8,
};
pub const Response = struct {
    id: u64,
    clarification_id: []const u8,
    input_state_ordinal: u64,
    input_state_revision: u64,
    input_record_revision: u64,
    submitted_form_bytes: []const u8,
    answer: Answer,
    actor_id: []const u8,
    authentication_evidence_id: []const u8,
    answered_at: []const u8,
};
/// Native closed wire contract. JSON decoding does not validate its authority.
pub const State = struct {
    schema: []const u8,
    feature_id: []const u8,
    state_ordinal: u64,
    revision: u64,
    next_ordinal: struct { spec: u8, plan: u8, tasks: u8 },
    next_response_ordinal: u64,
    records: []const Record,
    responses: []const Response,
};
pub const ParsedState = struct { value: ?State };
pub const ValidatedState = struct { value: ?State };
pub const Submission = struct {
    id: Id,
    subject: Subject,
    authority: []const Authority,
    requested_status: RequestedStatus,
    answer: Answer,
    origin: enum { submitted, recorded },
};
pub const Inputs = struct {
    state: ValidatedState,
    submissions: []const Submission,
    /// Exact captured bytes remain inputs. Only accepted responses own durable
    /// submitted bytes; this execution-local projection adds no persisted copy.
    protected_forms: []const FormCapture,
};

pub fn validate(parsed: ParsedState, selected: feature.FeatureId) Error!ValidatedState {
    const state = parsed.value orelse return .{ .value = null };
    if (!std.mem.eql(u8, state.schema, schema_version) or !std.mem.eql(u8, state.feature_id, selected.bytes) or
        feature.FeatureId.parse(state.feature_id) == null or state.state_ordinal == 0 or state.revision == 0 or
        state.records.len > max_forms or state.responses.len > max_responses) return error.InvalidClarificationInput;
    var counts: [3]u8 = @splat(0);
    var previous_index: ?usize = null;
    for (state.records, 0..) |record, index| {
        const id = Id.parse(record.id) orelse return error.InvalidClarificationInput;
        if (previous_index != null and id.index() <= previous_index.?) return error.InvalidClarificationInput;
        previous_index = id.index();
        const stage_index = @intFromEnum(id.stage);
        counts[stage_index] += 1;
        if (id.ordinal != counts[stage_index] or record.revision == 0 or record.revision > state.revision or
            !validSubject(record.subject) or !validText(record.question, max_text_bytes) or
            !validText(record.why_required, max_text_bytes) or record.authority.len == 0 or record.authority.len > max_record_authorities) return error.InvalidClarificationInput;
        for (state.records[0..index]) |other| {
            if (Id.parse(other.id).?.stage == id.stage and sameSubject(other.subject, record.subject)) return error.InvalidClarificationInput;
        }
        for (record.authority, 0..) |authority, authority_index| {
            if (!authority.valid()) return error.InvalidClarificationInput;
            for (record.authority[0..authority_index]) |other| {
                if (other.sameRecord(authority)) return error.InvalidClarificationInput;
            }
        }
        try validateAnswerSchema(record.answer_schema);
        switch (record.status) {
            .open => if (record.response_id != null or record.authority_resolution != null) return error.InvalidClarificationInput,
            .resolved_by_user, .cancelled_by_user => {
                if (record.authority_resolution != null) return error.InvalidClarificationInput;
                const response = findResponse(state, record.response_id orelse return error.InvalidClarificationInput) orelse return error.InvalidClarificationInput;
                if (!std.mem.eql(u8, response.clarification_id, record.id) or response.input_record_revision >= record.revision or
                    (record.status == .cancelled_by_user) != (response.answer == .cancel_reason)) return error.InvalidClarificationInput;
            },
            .resolved_by_authority => if (record.response_id != null or !validText(record.authority_resolution orelse return error.InvalidClarificationInput, max_text_bytes)) return error.InvalidClarificationInput,
        }
    }
    if (state.next_ordinal.spec != counts[0] + 1 or state.next_ordinal.plan != counts[1] + 1 or
        state.next_ordinal.tasks != counts[2] + 1 or state.next_response_ordinal == 0) return error.InvalidClarificationInput;
    for (state.responses, 0..) |response, index| {
        const record = findRecord(state, response.clarification_id) orelse return error.InvalidClarificationInput;
        if (response.id != index + 1 or response.input_state_ordinal == 0 or response.input_state_ordinal >= state.state_ordinal or
            response.input_state_revision == 0 or response.input_state_revision >= state.revision or response.input_record_revision == 0 or
            response.input_record_revision > response.input_state_revision or response.input_record_revision >= record.revision or
            response.submitted_form_bytes.len == 0 or response.submitted_form_bytes.len > max_form_bytes or
            !std.unicode.utf8ValidateSlice(response.submitted_form_bytes) or
            !validToken(response.actor_id) or !validToken(response.authentication_evidence_id) or !validText(response.answered_at, 64) or
            (response.answer != .defer_reason and record.response_id != response.id)) return error.InvalidClarificationInput;
        switch (response.answer) {
            .none => return error.InvalidClarificationInput,
            .business_text, .defer_reason, .cancel_reason => |text| if (!validText(text, max_text_bytes)) return error.InvalidClarificationInput,
            .selected_option => |key| if (!validToken(key)) return error.InvalidClarificationInput,
            .selected_options => |keys| {
                if (keys.len == 0 or keys.len > 32) return error.InvalidClarificationInput;
                for (keys, 0..) |key, key_index| {
                    if (!validToken(key)) return error.InvalidClarificationInput;
                    for (keys[0..key_index]) |other| if (std.mem.eql(u8, key, other)) return error.InvalidClarificationInput;
                }
            },
        }
    }
    if (state.next_response_ordinal != state.responses.len + 1) return error.InvalidClarificationInput;
    return .{ .value = state };
}

/// Structural input validation precedes corpus construction. Engine-owned
/// question prose is revalidated once the current native source witness exists;
/// submitted answer/business text is deliberately outside this model rule.
pub fn validateQuestions(a: std.mem.Allocator, state: ValidatedState, sources: []const @import("model_text_wire.zig").SourceText) Error!void {
    const wire = @import("model_text_wire.zig");
    if (!wire.validSources(sources)) return error.InvalidClarificationInput;
    const current = state.value orelse return;
    const text = @import("typed_text.zig");
    for (current.records) |record| {
        const nodes: []const text.BusinessSegment = &.{.{ .literal = .{ .value = record.question } }};
        if (text.composition(text.BusinessSegment, .clarification_question, nodes) != null or
            try text.wireCompositionSources(text.BusinessSegment, a, sources, .clarification_question, nodes) != null) return error.InvalidClarificationInput;
    }
}

pub fn findRecord(state: State, id: []const u8) ?Record {
    for (state.records) |record| if (std.mem.eql(u8, record.id, id)) return record;
    return null;
}
pub fn findResponse(state: State, id: u64) ?Response {
    for (state.responses) |response| if (response.id == id) return response;
    return null;
}
pub fn sameSubject(a: Subject, b: Subject) bool {
    return orderSubject(a, b) == .eq;
}
/// The one total order of subjects: the three names, then the spans. Equal exactly when the subjects are the same.
pub fn orderSubject(a: Subject, b: Subject) std.math.Order {
    inline for (.{ "requirement", "unit", "slot" }) |field| {
        const order = std.mem.order(u8, @field(a, field), @field(b, field));
        if (order != .eq) return order;
    }
    for (a.sources, 0..) |span, index| {
        if (index == b.sources.len) return .gt;
        const order = orderSpan(span, b.sources[index]);
        if (order != .eq) return order;
    }
    return if (a.sources.len < b.sources.len) .lt else .eq;
}
fn orderSpan(a: SourceSpan, b: SourceSpan) std.math.Order {
    const path = std.mem.order(u8, a.path, b.path);
    if (path != .eq) return path;
    // A whole source precedes any lines of it.
    const left = a.lines orelse return if (b.lines == null) .eq else .lt;
    const right = b.lines orelse return .gt;
    if (left.first != right.first) return std.math.order(left.first, right.first);
    return std.math.order(left.last, right.last);
}
fn validSubject(subject: Subject) bool {
    return validToken(subject.requirement) and validToken(subject.unit) and validToken(subject.slot) and validSources(subject.sources);
}
/// Canonical spans: each path passes the reference directory's path policy, lines are one-based and ordered, paths
/// ascend, and on one path a whole source stands alone and line ranges ascend without overlapping or touching.
pub fn validSources(spans: []const SourceSpan) bool {
    if (spans.len > max_subject_spans) return false;
    for (spans, 0..) |span, index| {
        @import("relative_directory_path.zig").validate(span.path) catch return false;
        if (span.lines) |lines| if (lines.first == 0 or lines.last < lines.first) return false;
        if (index == 0) continue;
        const previous = spans[index - 1];
        switch (std.mem.order(u8, previous.path, span.path)) {
            .gt => return false,
            .lt => {},
            .eq => {
                const before = previous.lines orelse return false;
                const after = span.lines orelse return false;
                if (after.first <= before.last +| 1) return false;
            },
        }
    }
    return true;
}
/// The one syntax of a stored identifier or actor name: ASCII letters, digits and `-_.@`, at most 128 bytes.
pub fn validToken(bytes: []const u8) bool {
    if (bytes.len == 0 or bytes.len > 128) return false;
    for (bytes) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '@')) return false;
    return true;
}
pub fn validText(bytes: []const u8, maximum: usize) bool {
    if (bytes.len == 0 or bytes.len > maximum or std.mem.trim(u8, bytes, " \t\r\n").len == 0 or !std.unicode.utf8ValidateSlice(bytes)) return false;
    for (bytes) |byte| if ((byte < 32 and byte != '\n' and byte != '\t') or byte == 127) return false;
    return true;
}
fn validateOptions(options: []const Option) Error!void {
    if (options.len == 0 or options.len > 32) return error.InvalidClarificationInput;
    for (options, 0..) |option, index| {
        if (!validToken(option.key) or !validText(option.label, max_text_bytes)) return error.InvalidClarificationInput;
        for (options[0..index]) |other| if (std.mem.eql(u8, option.key, other.key)) return error.InvalidClarificationInput;
    }
}
fn validateAnswerSchema(schema: AnswerSchema) Error!void {
    switch (schema) {
        .bounded_business_text => |maximum| if (maximum == 0 or maximum > max_text_bytes) return error.InvalidClarificationInput,
        .select_one => |options| try validateOptions(options),
        .select_many => |many| {
            try validateOptions(many.options);
            if (many.minimum == 0 or many.minimum > many.maximum or many.maximum > many.options.len) return error.InvalidClarificationInput;
        },
    }
}
