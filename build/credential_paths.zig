//! Credential-like paths that development build tools never read.
const std = @import("std");

pub fn excluded(path: []const u8) bool {
    var parts = std.mem.tokenizeScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.startsWith(u8, part, ".env") or std.mem.eql(u8, part, ".aws") or std.mem.eql(u8, part, "credentials") or std.mem.eql(u8, part, ".git") or std.mem.endsWith(u8, part, ".pem") or std.mem.endsWith(u8, part, ".key")) return true;
    }
    return false;
}
