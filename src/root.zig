const std = @import("std");
const composition = @import("composition/root.zig");

pub const config = @import("domain/config.zig");
pub const BootstrapOutcome = @import("application/bootstrap_orchestrator.zig").Outcome;

pub fn run(io: std.Io, allocator: std.mem.Allocator) BootstrapOutcome {
    return composition.run(io, allocator);
}

fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

test {
    refAllDeclsRecursive(@This());
}
