const std = @import("std");

pub const Error = std.mem.Allocator.Error || error{ InvalidUtf8, NormalizationLimitExceeded, NormalizationFailed };

/// Pure, bounded text transformation. It conveys no operational capability.
pub const Normalizer = struct {
    normalize_fn: *const fn (std.mem.Allocator, []const u8, usize) Error![]u8,
    fold_fn: *const fn (std.mem.Allocator, []const u8, usize) Error![]u8,

    pub fn nfc(self: Normalizer, allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
        return self.normalize_fn(allocator, input, maximum_bytes);
    }

    /// Pinned compatibility decomposition, case folding, and mark removal.
    /// Remaining characters are preserved; this does not apply slug policy.
    pub fn fold(self: Normalizer, allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
        return self.fold_fn(allocator, input, maximum_bytes);
    }
};
