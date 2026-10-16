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
    entity_meaning,
    entity_relationship,
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
        .spec_description, .spec_story, .ac_given, .ac_when, .ac_then, .visible_outcome, .edge_condition, .edge_outcome, .functional_requirement, .business_rule, .non_goal, .prohibited_behavior => .obligation_bearing,
        .spec_title, .spec_goal, .spec_entity_basis, .clarification_question, .assumption, .entity_name, .entity_meaning, .entity_relationship => .incidental,
    };
    const source_role: Role = switch (field) {
        .extraction_design, .extraction_technical, .extraction_validation, .extraction_implementation_assumption, .extraction_open_question, .extraction_reason, .reconciliation_design, .reconciliation_technical, .reconciliation_validation, .reconciliation_implementation_assumption, .reconciliation_open_question, .reconciliation_conflict => .incidental,
        .spec_title, .spec_description, .spec_goal, .spec_story, .spec_entity_basis, .clarification_question, .ac_given, .ac_when, .ac_then, .visible_outcome, .edge_condition, .edge_outcome, .functional_requirement, .business_rule, .assumption, .non_goal, .prohibited_behavior, .entity_name, .entity_meaning, .entity_relationship, .extraction_business, .extraction_scope_guard, .reconciliation_business, .reconciliation_scope_guard => .prohibited,
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
            "Supply nonblank prose for this field's declared meaning or behavior. Typed insertions may supplement that prose but cannot replace it.",
    };
}
pub const ReferencePhase = enum { extraction, reconciliation };
pub fn referenceField(comptime phase: ReferencePhase, comptime name: []const u8) Field {
    return @field(Field, @tagName(phase) ++ "_" ++ name);
}
/// Presentation is a projection of the same closed inventory as validation.
pub fn referencePolicies(comptime phase: ReferencePhase) [8]Policy {
    var result: [8]Policy = undefined;
    inline for (.{ "business", "design", "technical", "validation", "implementation_assumption", "open_question", "scope_guard" }, 0..) |name, index| result[index] = get(referenceField(phase, name));
    result[7] = get(if (phase == .extraction) .extraction_reason else .reconciliation_conflict);
    return result;
}
pub fn referenceOnlyExplanation(field: Field) []const u8 {
    return get(field).explanation;
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
    }
    try std.testing.expectEqual(@as(usize, 1), exceptions);
    try std.testing.expectEqual(.prohibited, get(.extraction_business).exact_copy);
    try std.testing.expectEqual(.obligation_bearing, get(.functional_requirement).exact_copy);
    try std.testing.expectEqual(.incidental, get(.spec_title).exact_copy);
    try std.testing.expectEqual(.incidental, get(.clarification_question).exact_copy);
    try std.testing.expectEqual(.prohibited, get(.extraction_business).source);
    try std.testing.expectEqual(.prohibited, get(.reconciliation_scope_guard).source);
    try std.testing.expectEqual(.incidental, get(.extraction_design).source);
    try std.testing.expectEqual(.incidental, get(.reconciliation_conflict).source);
}
