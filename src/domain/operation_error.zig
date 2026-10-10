//! Closed native failure contracts shared by ports and the operation runner.
//! No dynamic error names or payloads cross the runner boundary.
const std = @import("std");
pub const ProviderAuthorizationLease = error{ AuthorizationDenied, AuthorizationExpired, ClockUnavailable, Cancelled };
pub const FeatureInputSource = std.mem.Allocator.Error || error{FeatureInputUnavailable};
pub const ReferenceStateIdentity = error{IdentityUnavailable};
pub const ReferenceCorpusSource = std.mem.Allocator.Error || error{ ReferenceUnavailable, ReferenceInventoryChanged, ReferenceLimitExceeded, Cancelled };
pub const FeatureDirectoryInspector = std.mem.Allocator.Error || error{FeatureDirectoryUnavailable};
pub const PrincipleSource = @import("principle_registry.zig").Error || error{PrincipleSourceUnavailable};
pub const ReferenceDirectoryInspector = std.mem.Allocator.Error || error{ReferenceDirectoryUnavailable};
pub const UnicodeNormalizer = std.mem.Allocator.Error || error{ InvalidUtf8, NormalizationLimitExceeded, NormalizationFailed };
pub const ReferenceDecoder = std.mem.Allocator.Error || error{ UnsupportedMedia, MalformedText, DecodeLimitExceeded };
pub const ToolchainAuthoritySource = error{InvalidToolchainSource};
pub const ToolchainDocumentParser = error{InvalidToolchainDocument};
pub const FeatureLogLayout = std.mem.Allocator.Error || error{ InvalidFeatureLogLayout, FeatureLogLayoutUnavailable, InsecurePermissions, Cancelled };
pub const FeatureLogSink = error{
    LockUnavailable,
    InvalidBinding,
    CorruptStream,
    SegmentLimitExhausted,
    SinkFailure,
    FlushFailure,
    ReleaseFailure,
};
pub const LlmProviderInterface = std.mem.Allocator.Error || error{ Cancelled, ModelLoggingBlocked };
pub const PortError = ProviderAuthorizationLease ||
    FeatureInputSource ||
    ReferenceStateIdentity ||
    ReferenceCorpusSource ||
    FeatureDirectoryInspector ||
    PrincipleSource ||
    ReferenceDirectoryInspector ||
    UnicodeNormalizer ||
    ReferenceDecoder ||
    ToolchainAuthoritySource ||
    ToolchainDocumentParser ||
    FeatureLogLayout ||
    FeatureLogSink ||
    LlmProviderInterface;

/// Stable serializable names derived from a closed error set, never arbitrary text.
pub fn Code(comptime Errors: type) type {
    const errors = @typeInfo(Errors).error_set orelse @compileError("operation errors must be closed");
    var names: [errors.len][:0]const u8 = undefined;
    for (errors, 0..) |err, index| names[index] = err.name;
    const Int = std.math.IntFittingRange(0, errors.len);
    return @Enum(Int, .exhaustive, &names, &std.simd.iota(Int, errors.len));
}
pub fn code(comptime Errors: type, cause: Errors) Code(Errors) {
    return std.meta.stringToEnum(Code(Errors), @errorName(cause)).?;
}

/// Closed union of native operation contracts. Causes cross the runner boundary
/// by value; reporting an allocation failure never allocates another object.
pub const Error = @import("pipeline_data.zig").ValueError ||
    @import("pipeline_data.zig").EnvelopeError ||
    @import("reference_reconciliation.zig").Error ||
    @import("specification_coverage_repair.zig").Error ||
    @import("specification_repair.zig").Error ||
    @import("source_omission.zig").Error ||
    @import("required_authority.zig").Error ||
    @import("reference_ingestion.zig").Error ||
    @import("workflow_retry.zig").StateError ||
    @import("specify_invocation.zig").Error ||
    PortError ||
    @import("feature_directory.zig").Error ||
    @import("reference_selector.zig").Error ||
    @import("clarification_refresh.zig").Error ||
    @import("json_composition_runtime.zig").Error ||
    @import("model_request_handoff.zig").Error ||
    @import("model_attempt_accounting.zig").Error ||
    @import("model_attempt_accounting.zig").RequestError ||
    @import("provider_operation_lifecycle.zig").Error ||
    @import("provider_invocation_validation.zig").Error ||
    @import("provider_authorization_result.zig").Error ||
    @import("model_transport.zig").Error ||
    @import("workflow_output.zig").Error ||
    @import("specification_support_repair.zig").Contract(.source).Error ||
    @import("workflow_artifact_registry.zig").FeaturePathError ||
    @import("model_invocation_result.zig").Error ||
    @import("toolchain.zig").Error ||
    @import("std").fmt.BufPrintError ||
    @import("reference_snapshot.zig").Error ||
    @import("workflow_token_accounting.zig").Error ||
    @import("workflow_token_accounting.zig").BudgetError ||
    @import("specification_state.zig").Error ||
    @import("incomplete_specification.zig").Error ||
    error{OperationExecutionFailed};
