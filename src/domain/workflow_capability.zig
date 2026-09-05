const std = @import("std");

pub const model_provider = "model-provider";
pub const toolchain_read = "toolchain-read";
pub const toolchain_parser = "toolchain-parser";
pub const reference_read = "reference-read";

pub fn known(id: []const u8) bool {
    inline for (.{ model_provider, toolchain_read, toolchain_parser, reference_read }) |known_id| {
        if (std.mem.eql(u8, id, known_id)) return true;
    }
    return false;
}

pub fn permits(ceiling: []const []const u8, required: []const []const u8) bool {
    for (required) |id| {
        var found = false;
        for (ceiling) |allowed| if (std.mem.eql(u8, id, allowed)) {
            found = true;
        };
        if (!found) return false;
    }
    return true;
}
