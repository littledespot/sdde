const bootstrap_roots = @import("../domain/bootstrap_roots.zig");

pub const Error = error{ BootstrapRootInspectionFailure, Cancelled };

pub const Inspector = struct {
    context: *anyopaque,
    inspect_fn: *const fn (*anyopaque, []const u8) Error!bootstrap_roots.RootObservation,

    pub fn inspect(
        self: Inspector,
        normalized_relative_path: []const u8,
    ) Error!bootstrap_roots.RootObservation {
        return self.inspect_fn(self.context, normalized_relative_path);
    }
};
