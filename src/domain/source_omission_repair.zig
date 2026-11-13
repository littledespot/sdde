//! The source-omission repair owners' rules (ADR 0033 owners `source-omission`,
//! `source-omission-extraction` and `source-omission-reconciliation`), composed from the extraction and
//! reconciliation omission rules and the pre-generation phase witness. Pure functions of their inputs:
//! the owner's binding reads the native facts and publishes the result.
const std = @import("std");
const loss = @import("source_omission.zig");
const ex = @import("reference_extraction_repair.zig").Omission;
const rec = @import("reference_reconciliation_repair.zig").Omission;
const r = @import("reference_reconciliation.zig");
const Context = @import("reference_reconciliation_validation.zig").TextContext;
const typed_text = @import("typed_text.zig");

pub const Error = ex.Error || rec.Error;

/// Which branch the omission belongs to: the location of the support gap selects the extraction or the
/// reconciliation owner, and an omission with no producer cannot be repaired.
pub fn authorize(a: std.mem.Allocator, extraction: ex.Facts, parsed: r.Parsed, ctx: Context) Error!loss.Repair {
    try loss.requireRepairPhase(extraction.support.repair_phase);
    const selected = try loss.select(a, ctx.inputs, extraction.support);
    return .{ .authorization = switch (selected.location) {
        .unlocalized, .candidate, .source_association, .unsupported_summary => return error.InvalidAtomicRepair,
        .extraction_claim, .token_classification => .{ .extraction = try ex.authorize(a, extraction) },
        .reconciliation_signal, .reconciliation_disposition, .reconciliation_conflict => .{ .reconciliation = try rec.authorize(a, parsed, ctx, extraction.support) },
    } };
}

pub fn packet(a: std.mem.Allocator, extraction: ex.Facts, parsed: r.Parsed, ctx: Context, repair: loss.Repair, guidance: *const @import("packet_guidance.zig").Guidance) Error!*@import("model_input_packet.zig").Packet {
    try loss.requireRepairPhase(extraction.support.repair_phase);
    return switch (repair.authorization) {
        .extraction => |auth| ex.packet(a, extraction, ctx.registry, auth, guidance),
        .reconciliation => |auth| rec.packet(a, parsed, ctx, extraction.support, auth, guidance),
    };
}

pub fn parse(a: std.mem.Allocator, repair: loss.Repair, input: *const @import("model_input_packet.zig").Packet, body: []const u8, origin: @import("model_candidate_origin.zig").Origin) Error!loss.Repair {
    return .{ .authorization = repair.authorization, .response = .{ .origin = origin, .value = switch (repair.authorization) {
        .extraction => |auth| .{ .extraction = try ex.parse(a, auth, input, body) },
        .reconciliation => |auth| .{ .reconciliation = try rec.parse(a, auth, input, body) },
    } } };
}

pub fn mergeExtraction(a: std.mem.Allocator, validator: r.text.Validator, facts: ex.Facts, ctx: Context, repair: loss.Repair) ex.Error!r.extraction.TextValidated {
    try loss.requireRepairPhase(facts.support.repair_phase);
    var canonical = try typed_text.CanonicalText.fromInputs(a, validator.normalizer, facts.extraction.inputs);
    defer canonical.deinit(a);
    const response = repair.response orelse return error.InvalidAtomicRepair;
    if (repair.authorization != .extraction or response.value != .extraction) return error.InvalidAtomicRepair;
    return ex.merge(a, canonical, validator, ctx.registry, ctx.current, facts, repair.authorization.extraction, response.value.extraction, response.origin);
}

pub fn mergeReconciliation(a: std.mem.Allocator, normalizer: @import("../ports/unicode_normalizer.zig").Normalizer, parsed: r.Parsed, ctx: Context, support: loss.Support, repair: loss.Repair) rec.Error!r.Parsed {
    try loss.requireRepairPhase(support.repair_phase);
    var canonical = try typed_text.CanonicalText.fromInputs(a, normalizer, ctx.inputs);
    defer canonical.deinit(a);
    const response = repair.response orelse return error.InvalidAtomicRepair;
    if (repair.authorization != .reconciliation or response.value != .reconciliation) return error.InvalidAtomicRepair;
    return rec.merge(a, canonical, parsed, ctx, support, repair.authorization.reconciliation, response.value.reconciliation, response.origin);
}
