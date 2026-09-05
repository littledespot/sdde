const std = @import("std");

pub const Error = std.mem.Allocator.Error || error{ InvalidUtf8, NormalizationLimitExceeded, NormalizationFailed };

/// Pure, bounded text transformation. It conveys no operational capability.
pub const Normalizer = struct {
    normalize_fn: *const fn (std.mem.Allocator, []const u8, usize) Error![]u8,

    pub fn nfc(self: Normalizer, allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
        return self.normalize_fn(allocator, input, maximum_bytes);
    }
};

pub const CaseFolder = struct {
    fold_fn: *const fn (std.mem.Allocator, []const u8, usize) Error![]u8,
    pub fn key(self: CaseFolder, allocator: std.mem.Allocator, input: []const u8, maximum_bytes: usize) Error![]u8 {
        return self.fold_fn(allocator, input, maximum_bytes);
    }
};
