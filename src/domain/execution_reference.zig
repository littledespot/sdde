const std = @import("std");

const Identity = opaque {};
const Storage = struct {
    allocator: std.mem.Allocator,
    references: usize = 1,
};

/// A same-process identity only: no payload, authority, or operation capability.
/// Retained identities cannot be recycled while an execution value references
/// them. Owners retain explicitly; borrowed copies must not be destroyed.
pub const Ref = struct {
    identity: *Identity,

    pub fn eql(self: Ref, other: Ref) bool {
        return self.identity == other.identity;
    }

    pub fn retain(self: Ref) Ref {
        const value = storage(self);
        value.references = std.math.add(usize, value.references, 1) catch {
            @panic("execution reference count exhausted");
        };
        return self;
    }

    pub fn release(self: Ref) void {
        const value = storage(self);
        std.debug.assert(value.references > 0);
        value.references -= 1;
        if (value.references == 0) value.allocator.destroy(value);
    }
};

pub fn create(allocator: std.mem.Allocator) std.mem.Allocator.Error!Ref {
    const value = try allocator.create(Storage);
    value.* = .{ .allocator = allocator };
    return .{ .identity = @ptrCast(value) };
}

fn storage(reference: Ref) *Storage {
    return @ptrCast(@alignCast(reference.identity));
}
