const std = @import("std");
const config = @import("../domain/config.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");

pub const Outcome = union(enum) {
    ready: config.Registry,
    failed: config.PublicError,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*registry| registry.deinit(),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator) Outcome {
    var root = locate.execute(io, allocator) catch {
        return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
    };
    defer root.deinit(allocator);

    var raw = read.execute(root.dir, io, allocator) catch {
        return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
    };
    defer raw.deinit(allocator);

    const decoded = decode.execute(allocator, raw.bytes) catch {
        return .{ .failed = .ENGINE_CONFIG_PARSE_ERROR };
    };
    return .{ .ready = config.Registry.init(decoded) };
}
