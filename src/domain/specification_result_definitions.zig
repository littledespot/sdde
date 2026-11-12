//! The result definitions that the Spec workflow's native request builders select from its result
//! schema resources (`design/workflows/spec/*.schema.json`). Each schema has one closed enum, so a
//! builder names a definition by a typed member, never by a string literal or a computed name, and
//! renaming or removing a member is a compile error at every site. The generic `DefinitionId` stays
//! a parsed name (ADR 0013, 0016); only Spec-owned code uses these enums.
//! `specification_result_definitions_test.zig` loads each shipped schema through the production
//! compiler and requires every member to be selectable, so a member that the shipped schema no
//! longer declares fails that test. A target project's own copy of a schema that lacks a member
//! still fails at request preparation (ADR 0013).
const std = @import("std");
const schema = @import("model_result_schema.zig");

/// `extraction.schema.json`: the extraction claims, their classification and text repairs.
pub const Extraction = enum {
    claim,
    classification,
    classification_replacement,
    reference_text_replacement,

    pub fn id(self: Extraction) schema.DefinitionId {
        return .{ .bytes = @tagName(self) };
    }

    /// The member a request's selected definition names, or null for a definition outside this schema.
    pub fn parse(selected: schema.DefinitionId) ?Extraction {
        return std.meta.stringToEnum(Extraction, selected.bytes);
    }
};

/// `reconciliation.schema.json`: the assignments, their repairs and the corrected text.
pub const Reconciliation = enum {
    summary,
    signals_assignment,
    dispositions_assignment,
    conflicts_assignment,
    business_text,
    reference_text,
    repair_selection,
    repair_disposition,
    repair_summary,
    repair_conflict_detail,
    repair_conflict_group,
    repair_conflict_selection,

    pub fn id(self: Reconciliation) schema.DefinitionId {
        return .{ .bytes = @tagName(self) };
    }

    pub fn parse(selected: schema.DefinitionId) ?Reconciliation {
        return std.meta.stringToEnum(Reconciliation, selected.bytes);
    }
};

/// `generation.schema.json`: the specification units and their repairs.
pub const Generation = enum {
    brief,
    entities,
    records,
    value,
    attributed_value,
    repair_record_entity,
    repair_record_acceptance_criterion,

    pub fn id(self: Generation) schema.DefinitionId {
        return .{ .bytes = @tagName(self) };
    }

    pub fn parse(selected: schema.DefinitionId) ?Generation {
        return std.meta.stringToEnum(Generation, selected.bytes);
    }
};

/// `links.schema.json`: one scenario link.
pub const Links = enum {
    scenario_link,

    pub fn id(self: Links) schema.DefinitionId {
        return .{ .bytes = @tagName(self) };
    }

    pub fn parse(selected: schema.DefinitionId) ?Links {
        return std.meta.stringToEnum(Links, selected.bytes);
    }
};

/// `support.schema.json`: the support review findings, comparisons and their repairs.
pub const Support = enum {
    finding,
    applicability_finding,
    preservation_finding,
    preservation_comparisons,
    detail,
    invalid_detail,
    omission_detail,
    gap_detail,
    selection,
    invalid_selection,

    pub fn id(self: Support) schema.DefinitionId {
        return .{ .bytes = @tagName(self) };
    }

    pub fn parse(selected: schema.DefinitionId) ?Support {
        return std.meta.stringToEnum(Support, selected.bytes);
    }
};
