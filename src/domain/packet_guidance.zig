//! Workflow-owned semantic packet guidance (FIX06 D3.1; ADR 0016 packet-guidance
//! amendment). One closed resource supplies exactly one text per registered key;
//! native packet builders place these texts and never author them.
//! All allocations belong to the caller's arena, including on rejection.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const review = @import("specification_review_subject.zig");

pub const version = "packet-guidance/v1";
pub const Error = error{InvalidPacketGuidance} || std.mem.Allocator.Error;
pub const max_bytes: u32 = 64 * 1024;
const max_depth = 3;

fn featurePurposeSlot(slot: authority.Slot) bool {
    // A collection of one record family is presented by that family's definition.
    if (@import("specification_authority.zig").collectionFamily(slot) != null) return false;
    for (std.enums.values(authority.Kind)) |kind| {
        if (authority.policy(.{ .kind = kind, .unit = .{ .feature = .singleton }, .slot = slot }) != null) return true;
    }
    return false;
}
fn recordFieldSlot(slot: authority.Slot) bool {
    // A record's text field is its family's definition.
    if (slot == .text) return false;
    for (std.enums.values(spec.Kind)) |kind| if (authority.recordField(kind, slot)) return true;
    return false;
}
fn SlotKey(comptime selected: fn (authority.Slot) bool) type {
    @setEvalBranchQuota(20_000);
    var names: []const []const u8 = &.{};
    for (std.enums.values(authority.Slot)) |slot| {
        if (selected(slot)) names = names ++ .{@tagName(slot)};
    }
    return @Enum(u8, .exhaustive, names, &std.simd.iota(u8, names.len));
}

/// Registered keys, derived from the native registries rather than listed again.
pub const FeaturePurpose = SlotKey(featurePurposeSlot);
pub const RecordField = SlotKey(recordFieldSlot);
pub const ReferenceUnit = std.meta.Tag(review.ReferenceSubject);
pub const FieldPlacement = enum { in_record, standalone };
pub const QuestionRule = enum { retained_gap, required, omitted };
pub const RepairTail = enum { entity_record_meaning, value_choices };
/// A reference task brackets its native ordinal.
pub const Fragments = struct { before: []const u8, after: []const u8 };

/// The key of a feature slot with its own purpose entry; family-presented and
/// non-feature slots have none.
pub fn featurePurpose(slot: authority.Slot) ?FeaturePurpose {
    return switch (slot) {
        inline else => |tag| if (@hasField(FeaturePurpose, @tagName(tag))) @field(FeaturePurpose, @tagName(tag)) else null,
    };
}
/// The key of a record slot with its own field entry; `text` has none.
pub fn recordField(slot: authority.Slot) ?RecordField {
    return switch (slot) {
        inline else => |tag| if (@hasField(RecordField, @tagName(tag))) @field(RecordField, @tagName(tag)) else null,
    };
}

comptime {
    for (std.meta.tags(ReferenceUnit)) |tag| {
        if (!@hasField(authority.Unit, @tagName(tag))) @compileError("reference guidance must name a registered authority unit");
    }
    const scope = std.meta.fieldNames(@FieldType(Wire, "review_scope"));
    const subjects = std.meta.tags(std.meta.Tag(review.Subject));
    if (scope.len != subjects.len + shared_scope.len) @compileError("review scopes must cover exactly the registered subjects");
    for (subjects) |tag| {
        if (!@hasField(@FieldType(Wire, "review_scope"), @tagName(tag))) @compileError("review scope missing a registered subject");
    }
    for (shared_scope) |name| {
        if (!@hasField(@FieldType(Wire, "review_scope"), name)) @compileError("review scope missing shared guidance");
    }
}
/// Review-scope texts shared by every source-review subject.
pub const shared_scope = [_][]const u8{ "original_sources", "derived_evidence" };

fn Entries(comptime Key: type, comptime Value: type) type {
    return std.enums.EnumFieldStruct(Key, Value, null);
}

/// The closed `packet-guidance/v1` wire shape. Missing, extra, duplicate and
/// wrongly typed entries reject while decoding.
pub const Wire = struct {
    schema: enum { @"packet-guidance/v1" },
    feature_purposes: Entries(FeaturePurpose, []const u8),
    record_families: Entries(spec.Kind, []const u8),
    record_fields: Entries(RecordField, []const u8),
    reference_tasks: Entries(ReferenceUnit, Fragments),
    review_scope: struct {
        original_sources: []const u8,
        derived_evidence: []const u8,
        source_preservation: []const u8,
        candidate_field: Entries(FieldPlacement, []const u8),
        collection: []const u8,
        entity_applicability: []const u8,
        reference: Entries(ReferenceUnit, []const u8),
    },
    summary_purpose: []const u8,
    support_evidence: struct {
        selection: []const u8,
        detail: []const u8,
        obligation: []const u8,
        authority_gap: []const u8,
        question: Entries(QuestionRule, []const u8),
    },
    repair_tails: Entries(RepairTail, []const u8),
};

/// Validated guidance with total lookups for every registered key.
pub const Guidance = struct {
    feature_purposes: std.EnumArray(FeaturePurpose, []const u8),
    record_families: std.EnumArray(spec.Kind, []const u8),
    record_fields: std.EnumArray(RecordField, []const u8),
    reference_tasks: std.EnumArray(ReferenceUnit, Fragments),
    review_scope: ReviewScope,
    summary_purpose: []const u8,
    support_evidence: SupportEvidence,
    repair_tails: std.EnumArray(RepairTail, []const u8),
};
pub const ReviewScope = struct {
    original_sources: []const u8,
    derived_evidence: []const u8,
    source_preservation: []const u8,
    candidate_field: std.EnumArray(FieldPlacement, []const u8),
    collection: []const u8,
    entity_applicability: []const u8,
    reference: std.EnumArray(ReferenceUnit, []const u8),
};
pub const SupportEvidence = struct {
    selection: []const u8,
    detail: []const u8,
    obligation: []const u8,
    authority_gap: []const u8,
    question: std.EnumArray(QuestionRule, []const u8),
};

/// The compiled resource: its exact source bytes and the guidance they define.
pub const Compiled = struct {
    source: []const u8,
    guidance: Guidance,

    pub fn bytes(self: *const Compiled) []const u8 {
        return self.source;
    }
};

pub fn compile(allocator: std.mem.Allocator, bytes: []const u8) Error!*const Compiled {
    const source = try allocator.dupe(u8, bytes);
    const wire = @import("strict_json.zig").decode(Wire, allocator, source, .{ .maximum_bytes = max_bytes, .maximum_depth = max_depth }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidPacketGuidance,
    };
    const result = try allocator.create(Compiled);
    result.* = .{ .source = source, .guidance = try fromWire(wire) };
    return result;
}

/// Validate every text and index it by its registered key.
pub fn fromWire(wire: Wire) error{InvalidPacketGuidance}!Guidance {
    try checkTexts(Wire, wire);
    return .{
        .feature_purposes = .init(wire.feature_purposes),
        .record_families = .init(wire.record_families),
        .record_fields = .init(wire.record_fields),
        .reference_tasks = .init(wire.reference_tasks),
        .review_scope = .{
            .original_sources = wire.review_scope.original_sources,
            .derived_evidence = wire.review_scope.derived_evidence,
            .source_preservation = wire.review_scope.source_preservation,
            .candidate_field = .init(wire.review_scope.candidate_field),
            .collection = wire.review_scope.collection,
            .entity_applicability = wire.review_scope.entity_applicability,
            .reference = .init(wire.review_scope.reference),
        },
        .summary_purpose = wire.summary_purpose,
        .support_evidence = .{
            .selection = wire.support_evidence.selection,
            .detail = wire.support_evidence.detail,
            .obligation = wire.support_evidence.obligation,
            .authority_gap = wire.support_evidence.authority_gap,
            .question = .init(wire.support_evidence.question),
        },
        .repair_tails = .init(wire.repair_tails),
    };
}

fn checkTexts(comptime T: type, value: T) error{InvalidPacketGuidance}!void {
    if (T == []const u8) return if (validText(value)) {} else error.InvalidPacketGuidance;
    switch (@typeInfo(T)) {
        .@"enum" => {},
        .@"struct" => |info| inline for (info.fields) |field| try checkTexts(field.type, @field(value, field.name)),
        else => @compileError("packet guidance holds only texts"),
    }
}

/// Nonblank UTF-8 without control characters. Fragments keep their boundary spaces.
pub fn validText(text: []const u8) bool {
    if (std.mem.trim(u8, text, " ").len == 0) return false;
    const view = std.unicode.Utf8View.init(text) catch return false;
    var points = view.iterator();
    while (points.nextCodepoint()) |point| if (point < 0x20 or (point >= 0x7f and point <= 0x9f)) return false;
    return true;
}
