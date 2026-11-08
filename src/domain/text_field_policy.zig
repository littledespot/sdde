//! Closed composition requirements for native model-text fields. These are
//! structural admission rules; prose presence does not establish semantic truth.
const std = @import("std");
pub const Field = enum {
    spec_title,
    spec_description,
    spec_goal,
    spec_story,
    spec_entity_basis,
    clarification_question,
    ac_given,
    ac_when,
    ac_then,
    visible_outcome,
    edge_condition,
    edge_outcome,
    functional_requirement,
    business_rule,
    assumption,
    non_goal,
    prohibited_behavior,
    entity_name,
    extraction_business,
    extraction_design,
    extraction_technical,
    extraction_validation,
    extraction_implementation_assumption,
    extraction_open_question,
    extraction_scope_guard,
    extraction_reason,
    reconciliation_business,
    reconciliation_design,
    reconciliation_technical,
    reconciliation_validation,
    reconciliation_implementation_assumption,
    reconciliation_open_question,
    reconciliation_scope_guard,
    reconciliation_conflict,
};
pub const Role = enum { prohibited, incidental, obligation_bearing };
pub const Insertion = enum { exact_copy, passive, source };
pub const Insertions = std.EnumSet(Insertion);
pub const Policy = struct {
    field: Field,
    prose: enum { required, optional },
    exact_copy: Role,
    passive: Role,
    source: Role,
    explanation: []const u8,
};
pub fn get(field: Field) Policy {
    // Exhaustive assignment is intentional: adding a field requires an
    // explicit insertion role instead of silently inheriting a permissive one.
    const exact_role: Role = switch (field) {
        .extraction_business, .extraction_design, .extraction_technical, .extraction_validation, .extraction_implementation_assumption, .extraction_open_question, .extraction_scope_guard, .extraction_reason, .reconciliation_business, .reconciliation_design, .reconciliation_technical, .reconciliation_validation, .reconciliation_implementation_assumption, .reconciliation_open_question, .reconciliation_scope_guard, .reconciliation_conflict => .prohibited,
        .spec_description, .ac_given, .ac_when, .ac_then, .visible_outcome, .edge_condition, .edge_outcome, .functional_requirement, .business_rule, .non_goal, .prohibited_behavior => .obligation_bearing,
        .spec_title, .spec_goal, .spec_entity_basis, .clarification_question, .assumption => .prohibited,
        // ADR 0047: the engine-composed story quotes exact values but discharges no duty.
        .entity_name, .spec_story => .incidental,
    };
    const source_role: Role = switch (field) {
        .extraction_design, .extraction_technical, .extraction_validation, .extraction_implementation_assumption, .extraction_open_question, .extraction_reason, .reconciliation_design, .reconciliation_technical, .reconciliation_validation, .reconciliation_implementation_assumption, .reconciliation_open_question, .reconciliation_conflict => .incidental,
        .spec_title, .spec_description, .spec_goal, .spec_story, .spec_entity_basis, .clarification_question, .ac_given, .ac_when, .ac_then, .visible_outcome, .edge_condition, .edge_outcome, .functional_requirement, .business_rule, .assumption, .non_goal, .prohibited_behavior, .entity_name, .extraction_business, .extraction_scope_guard, .reconciliation_business, .reconciliation_scope_guard => .prohibited,
    };
    return .{
        .field = field,
        .prose = if (field == .entity_name) .optional else .required,
        .exact_copy = exact_role,
        .passive = .incidental,
        .source = source_role,
        .explanation = if (field == .entity_name)
            "An entity name is an identity label and may consist of supplied insertions. Its occurrence does not satisfy a behavioral exact-copy obligation."
        else
            referenceOnly(exact_role),
    };
}
/// The `reference_only` correction. Only a field whose exact-copy role isn't
/// prohibited recognizes typed text as an exact source value, so only its
/// correction names that value, including one typed with no prose around it.
fn referenceOnly(exact_role: Role) []const u8 {
    return switch (exact_role) {
        .incidental, .obligation_bearing => reference_only_frame ++ "An exact source value or supplied display reference" ++ reference_only_tail,
        .prohibited => reference_only_frame ++ "A supplied display reference" ++ reference_only_tail,
    };
}
const reference_only_frame = "Supply nonblank prose for this field's declared meaning or behavior. ";
const reference_only_tail = " may appear within that prose but cannot be the whole text.";
pub const ReferencePhase = enum { extraction, reconciliation };
pub fn referenceField(comptime phase: ReferencePhase, comptime name: []const u8) Field {
    return @field(Field, @tagName(phase) ++ "_" ++ name);
}
pub fn referenceOnlyExplanation(field: Field) []const u8 {
    return get(field).explanation;
}
pub const Guidance = struct { field: Field, prose_required: bool, instruction: []const u8, exact_copy: Role, passive: Role, source: Role };
pub fn guidance(field: Field) Guidance {
    const policy = get(field);
    return .{ .field = field, .prose_required = policy.prose == .required, .instruction = if (policy.prose == .optional)
        "Supply the identity label using only forms permitted by the selected response schema."
    else
        "Write nonblank prose for this field's declared meaning or behavior. Type required exact values verbatim in that prose. Any display reference must be permitted by the selected response schema.", .exact_copy = .prohibited, .passive = policy.passive, .source = policy.source };
}
/// Presentation may offer only alternatives in the exact selected wire leaf.
/// Native admission and exact-copy coverage continue to use get(), unchanged.
pub fn selectedGuidance(field: Field, offered: Insertions) Guidance {
    const policy = get(field);
    var result = guidance(field);
    if (!offered.contains(.passive)) result.passive = .prohibited;
    if (!offered.contains(.source)) result.source = .prohibited;
    const insertions_available = result.passive != .prohibited or result.source != .prohibited;
    result.instruction = if (!insertions_available)
        (if (policy.prose == .optional) "Write the identity label as plain text." else "Write nonblank prose for this field's declared meaning or behavior as plain text. Type required exact values verbatim in that prose.")
    else if (policy.prose == .optional)
        "Supply the identity label using only display references listed for this field or plain text. An identity label alone does not express required behavior."
    else
        "Write nonblank prose for this field's declared meaning or behavior. Type required exact values verbatim in that prose. Only supplied display references may supplement it.";
    return result;
}
pub fn permits(field: Field, kind: Insertion) bool {
    const policy = get(field);
    return switch (kind) {
        .exact_copy => policy.exact_copy,
        .passive => policy.passive,
        .source => policy.source,
    } != .prohibited;
}

/// Model schemas and guidance expose only selectable display references.
/// Exact occurrences remain a canonical native representation and policy.
pub fn permitsModel(field: Field, kind: Insertion) bool {
    return kind != .exact_copy and permits(field, kind);
}

test "the reference-only correction names an exact source value only where recognition runs" {
    const exact = "exact source value";
    for (std.meta.tags(Field)) |field| {
        const value = get(field);
        if (value.prose == .optional) continue;
        try std.testing.expectEqualStrings(referenceOnly(value.exact_copy), referenceOnlyExplanation(field));
        try std.testing.expectEqual(value.exact_copy != .prohibited, std.mem.indexOf(u8, referenceOnlyExplanation(field), exact) != null);
    }
    // Accepted: a bare value typed in an obligation-bearing field is named in its correction.
    try std.testing.expect(std.mem.indexOf(u8, referenceOnlyExplanation(.visible_outcome), exact) != null);
    // Rejected: fields that admit a bare value as prose are never told it can't be the whole text.
    for ([_]Field{ .spec_title, .extraction_design, .reconciliation_business }) |field| {
        try std.testing.expect(std.mem.indexOf(u8, referenceOnlyExplanation(field), exact) == null);
    }
}

test "closed composition inventory has one justified identity exception and distinct coverage roles" {
    var exceptions: usize = 0;
    for (std.meta.tags(Field)) |field| {
        const value = get(field);
        try std.testing.expectEqual(field, value.field);
        try std.testing.expect(value.explanation.len != 0);
        if (value.prose == .optional) {
            exceptions += 1;
            try std.testing.expectEqual(Field.entity_name, field);
            try std.testing.expectEqual(Role.incidental, value.exact_copy);
        }
        if (value.exact_copy == .obligation_bearing) try std.testing.expectEqual(.required, value.prose);
        try std.testing.expect(!permitsModel(field, .exact_copy));
        try std.testing.expectEqual(.prohibited, guidance(field).exact_copy);
        try std.testing.expectEqual(permits(field, .passive), permitsModel(field, .passive));
        try std.testing.expectEqual(permits(field, .source), permitsModel(field, .source));
    }
    try std.testing.expectEqual(@as(usize, 1), exceptions);
    try std.testing.expectEqual(.prohibited, get(.extraction_business).exact_copy);
    try std.testing.expectEqual(.obligation_bearing, get(.functional_requirement).exact_copy);
    try std.testing.expectEqual(.prohibited, get(.spec_title).exact_copy);
    try std.testing.expectEqual(.incidental, get(.spec_story).exact_copy);
    try std.testing.expectEqual(.required, get(.spec_story).prose);
    try std.testing.expectEqual(.prohibited, get(.clarification_question).exact_copy);
    try std.testing.expectEqual(.prohibited, get(.extraction_business).source);
    try std.testing.expectEqual(.prohibited, get(.reconciliation_scope_guard).source);
    try std.testing.expectEqual(.incidental, get(.extraction_design).source);
    try std.testing.expectEqual(.incidental, get(.reconciliation_conflict).source);
}
