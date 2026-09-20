const std = @import("std");
const debug = @import("../domain/request_debugger.zig");
const replay = @import("request_replay.zig");
pub const Session = struct {
    context: *replay.Context,
    list_fn: *const fn (*replay.Context, std.mem.Allocator) replay.Error![]const debug.Call,
    replay_fn: *const fn (*replay.Context, std.mem.Allocator, debug.ReplayInput) replay.Error![]const debug.Call,
};
