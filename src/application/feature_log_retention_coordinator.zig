const acquire = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const prune = @import("../actions/log/prune_feature_log_segments.zig");
const release = @import("../actions/log/release_feature_log_stream_lock.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

pub const Outcome = union(enum) { ok, blocked: runtime.FailureCode };

pub fn run(
    sink: sink_port.Sink,
    current: *const runtime.ValidatedFeatureLogBinding,
    historical: *const runtime.ValidatedFeatureLogBinding,
    authorization: *runtime.RetentionAuthorizationOwner,
) Outcome {
    const stream = runtime.retentionStream(authorization, current, historical) orelse return .{ .blocked = .LOG_SINK_FAILURE };
    (acquire.Action{ .sink = sink }).execute(historical, stream) catch return .{ .blocked = .LOG_LOCK_TIMEOUT };
    var failure: ?runtime.FailureCode = null;
    (prune.Action{ .sink = sink }).execute(historical, authorization) catch {
        failure = .LOG_SINK_FAILURE;
    };
    (release.Action{ .sink = sink }).execute() catch return .{ .blocked = .LOG_RELEASE_FAILURE };
    return if (failure) |code| .{ .blocked = code } else .ok;
}
