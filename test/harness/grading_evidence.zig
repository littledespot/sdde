//! Capability-free proof identity shared by development reports and evidence
//! inspection. These facts never authorize a production workflow transition.
pub const Proof = struct {
    panel_sha256: []const u8,
    review_sha256: []const u8,
    qualification_sha256: []const u8,
    judge_config_sha256: []const u8,
    protocol_sha256: []const u8,
};
pub const Reason = enum {
    panel_missing,
    panel_stale,
    review_missing,
    review_pending,
    review_stale,
    qualification_missing,
    qualification_pending,
    qualification_stale,
    specimen_missing,
    specimen_stale,
    report_missing,
    report_stale,
    report_mismatch,
    report_unresolved,
    verdict_mismatch,
};
pub const Evidence = union(enum) { qualified: Proof, unresolved: Reason };
