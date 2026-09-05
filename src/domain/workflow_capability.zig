const std = @import("std");

pub const model_provider = "model-provider";

pub fn known(id: []const u8) bool {
    return std.mem.eql(u8, id, model_provider);
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
