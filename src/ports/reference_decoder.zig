const std = @import("std");
const reference = @import("../domain/reference_ingestion.zig");
pub const Error = std.mem.Allocator.Error || error{ UnsupportedMedia, MalformedText, DecodeLimitExceeded };
pub const Decoder = struct {
    context: *anyopaque,
    /// This reader consumes captured bytes only. No filesystem or process port.
    decode_fn: *const fn (*anyopaque, std.mem.Allocator, reference.RelativePath, []const u8, usize) Error!reference.Decoded,
    pub fn decode(self: Decoder, allocator: std.mem.Allocator, path: reference.RelativePath, bytes: []const u8, maximum: usize) Error!reference.Decoded {
        return self.decode_fn(self.context, allocator, path, bytes, maximum);
    }
};
