//! Diagnostic-only token inspection after the canonical JSON parser rejects data.
//! It never repairs input or decides acceptance. All temporary data is arena-owned.
const std = @import("std");
const pointer = @import("json_pointer.zig");
pub const Location = struct { byte_offset: u64, line: u64, column: u64 };
pub const Context = struct {
    path: []const u8,
    key: ?[]const u8,
    first_occurrence: ?Location,
    repeated_occurrence: ?Location,

    pub fn deinit(self: Context, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.key) |key| allocator.free(key);
    }

    pub fn copy(self: Context, allocator: std.mem.Allocator) std.mem.Allocator.Error!Context {
        var result = self;
        result.path = try allocator.dupe(u8, self.path);
        errdefer allocator.free(result.path);
        if (self.key) |key| result.key = try allocator.dupe(u8, key);
        return result;
    }
};

const Frame = struct {
    object: bool,
    segment: ?pointer.Segment,
    key: ?[]const u8 = null,
    keys: std.StringHashMapUnmanaged(Location) = .empty,
    index: usize = 0,

    fn consume(self: *Frame) void {
        if (self.object) self.key = null else self.index += 1;
    }
};

pub fn describe(allocator: std.mem.Allocator, bytes: []const u8, stop: u64, duplicate: bool) std.mem.Allocator.Error!?Context {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var scanner = std.json.Scanner.initCompleteInput(a, bytes);
    defer scanner.deinit();
    var position: std.json.Diagnostics = .{};
    scanner.enableDiagnostics(&position);
    var frames: std.ArrayList(Frame) = .empty;
    while (position.getByteOffset() <= stop) {
        const before = position.getByteOffset();
        const token = scanner.nextAllocMax(a, .alloc_always, bytes.len) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break, // The canonical parser already owns this rejection.
        };
        if (position.getByteOffset() > stop) break;
        switch (token) {
            .object_begin, .array_begin => {
                var segment: ?pointer.Segment = null;
                if (frames.items.len != 0) {
                    const parent = &frames.items[frames.items.len - 1];
                    segment = if (parent.object) if (parent.key) |key| .{ .property = key } else null else .{ .index = parent.index };
                    parent.consume();
                }
                try frames.append(a, .{ .object = token == .object_begin, .segment = segment });
            },
            .object_end, .array_end => {
                _ = frames.pop();
            },
            .end_of_document => break,
            else => if (frames.items.len != 0) {
                const frame = &frames.items[frames.items.len - 1];
                if (frame.object and frame.key == null) {
                    const key = switch (token) {
                        .string, .allocated_string => |key| key,
                        else => break,
                    };
                    frame.key = key;
                    // Locations identify opening quotes, including escaped spellings.
                    const opening = std.mem.indexOfScalarPos(u8, bytes, @intCast(before), '"') orelse break;
                    const here = locate(bytes, opening);
                    const entry = try frame.keys.getOrPut(a, key);
                    if (entry.found_existing) {
                        if (duplicate) return try snapshot(allocator, a, frames.items, entry.value_ptr.*, here);
                    } else entry.value_ptr.* = here;
                } else frame.consume();
            },
        }
    }
    if (frames.items.len == 0) return null;
    return try snapshot(allocator, a, frames.items, null, null);
}

fn snapshot(allocator: std.mem.Allocator, scratch: std.mem.Allocator, frames: []const Frame, first: ?Location, repeated: ?Location) std.mem.Allocator.Error!Context {
    var segments: std.ArrayList(pointer.Segment) = .empty;
    for (frames) |frame| if (frame.segment) |segment| try segments.append(scratch, segment);
    const path = try pointer.render(allocator, segments.items);
    errdefer allocator.free(path);
    const key = frames[frames.len - 1].key;
    return .{ .path = path, .key = if (key) |value| try allocator.dupe(u8, value) else null, .first_occurrence = first, .repeated_occurrence = repeated };
}

fn locate(bytes: []const u8, offset: usize) Location {
    var result: Location = .{ .byte_offset = offset, .line = 1, .column = 1 };
    for (bytes[0..offset]) |byte| {
        if (byte == '\n') {
            result.line += 1;
            result.column = 1;
        } else result.column += 1;
    }
    return result;
}
