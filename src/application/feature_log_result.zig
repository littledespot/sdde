const log_stream = @import("../domain/feature_log_stream.zig");

/// Internal result for one feature-log operation. The common pipeline boundary
/// translates this result into workflow_execution.Candidate.
pub const Outcome = union(enum) {
    dropped,
    persisted: log_stream.PersistedEvidence,
    blocked: log_stream.FailureCode,
};
