const acquire_lock = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const release_lock = @import("../actions/log/release_feature_log_stream_lock.zig");
const recover_stream = @import("../actions/log/recover_feature_log_stream.zig");
const create_segment = @import("../actions/log/create_feature_log_segment.zig");
const rotate_segment = @import("../actions/log/rotate_feature_log_segment.zig");
const append_record = @import("../actions/log/append_feature_log_record.zig");
const close_stream = @import("../actions/log/close_feature_log_stream.zig");
const read_clock = @import("../actions/log/read_trusted_log_clock.zig");
const write_console = @import("../actions/log/write_console_log_record.zig");
const emit_emergency = @import("../actions/log/emit_emergency_log_failure_record.zig");
const stabilize_failure = @import("../actions/log/stabilize_log_failure.zig");

pub const ChildActions = struct {
    acquire_lock: acquire_lock.Action,
    release_lock: release_lock.Action,
    recover_stream: recover_stream.Action,
    create_segment: create_segment.Action,
    rotate_segment: rotate_segment.Action,
    append_record: append_record.Action,
    close_stream: close_stream.Action,
    read_clock: read_clock.Action,
    write_console: write_console.Action,
    emit_emergency: emit_emergency.Action,
    stabilize_failure: stabilize_failure.Action,
};
