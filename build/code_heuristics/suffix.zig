//! Exact substring index over separated text units, for the brittleness counts.
//! Each unit ends in its own separator symbol, so no match crosses a unit boundary.
const std = @import("std");

pub const Index = struct {
    /// Unit bytes as symbols below 256, each unit followed by a unique symbol ≥ 256.
    text: []const u32,
    /// Start offset of each unit in `text`.
    starts: []const usize,
    /// Suffix array: suffix start offsets in lexicographic order.
    order: []const u32,

    /// All returned storage belongs to `a`.
    pub fn build(a: std.mem.Allocator, units: []const []const u8) !Index {
        var length: usize = 0;
        for (units) |text_unit| length += text_unit.len + 1;
        if (length + 256 > std.math.maxInt(u32)) return error.IndexTooLarge;
        const text = try a.alloc(u32, length);
        const starts = try a.alloc(usize, units.len);
        var cursor: usize = 0;
        for (units, starts, 0..) |text_unit, *start, ordinal| {
            start.* = cursor;
            for (text_unit, text[cursor..][0..text_unit.len]) |byte, *symbol| symbol.* = byte;
            cursor += text_unit.len;
            text[cursor] = @intCast(256 + ordinal);
            cursor += 1;
        }
        return .{ .text = text, .starts = starts, .order = try sortSuffixes(a, text) };
    }

    /// Whether `needle` occurs inside one unit.
    pub fn contains(self: Index, needle: []const u8) bool {
        if (needle.len == 0) return true;
        var low: usize = 0;
        var high: usize = self.order.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (compare(self.text[self.order[middle]..], needle) == .lt) low = middle + 1 else high = middle;
        }
        return low < self.order.len and compare(self.text[self.order[low]..], needle) == .eq;
    }

    /// The unit holding `offset`.
    pub fn unit(self: Index, offset: usize) usize {
        return std.sort.upperBound(usize, self.starts, offset, struct {
            fn order(target: usize, start: usize) std.math.Order {
                return std.math.order(target, start);
            }
        }.order) - 1;
    }

    /// Maximal repeats of at least `minimum` symbols: spans occurring at two or more
    /// offsets that no longer span with the same offsets contains. Returned storage
    /// belongs to `a`.
    pub fn repeats(self: Index, a: std.mem.Allocator, minimum: usize) ![]const Repeat {
        const n = self.order.len;
        if (n == 0) return &.{};
        // Kasai: lcp[i] is the common prefix of the suffixes ranked i - 1 and i.
        const rank = try a.alloc(u32, n);
        defer a.free(rank);
        for (self.order, 0..) |offset, position| rank[offset] = @intCast(position);
        const lcp = try a.alloc(usize, n);
        defer a.free(lcp);
        lcp[0] = 0;
        var shared: usize = 0;
        for (0..n) |offset| {
            if (rank[offset] == 0) {
                shared = 0;
                continue;
            }
            const previous = self.order[rank[offset] - 1];
            while (offset + shared < n and previous + shared < n and self.text[offset + shared] == self.text[previous + shared]) shared += 1;
            lcp[rank[offset]] = shared;
            shared -|= 1;
        }
        // Bottom-up lcp intervals; each interval is a right-maximal repeat.
        const Open = struct { length: usize, first: usize };
        var stack: std.ArrayList(Open) = .empty;
        defer stack.deinit(a);
        try stack.append(a, .{ .length = 0, .first = 0 });
        var found: std.ArrayList(Repeat) = .empty;
        errdefer found.deinit(a);
        for (1..n + 1) |position| {
            const current = if (position < n) lcp[position] else 0;
            var first = position - 1;
            while (current < stack.items[stack.items.len - 1].length) {
                const interval = stack.pop().?;
                first = interval.first;
                if (interval.length >= minimum and self.leftMaximal(interval.first, position - 1)) {
                    const offsets = try a.alloc(usize, position - interval.first);
                    for (offsets, self.order[interval.first..position]) |*target, offset| target.* = offset;
                    std.mem.sort(usize, offsets, {}, std.sort.asc(usize));
                    try found.append(a, .{ .length = interval.length, .offsets = offsets });
                }
            }
            if (current > stack.items[stack.items.len - 1].length) try stack.append(a, .{ .length = current, .first = first });
        }
        return found.toOwnedSlice(a);
    }

    /// Whether the suffixes ranked `first..last` aren't all preceded by one symbol.
    fn leftMaximal(self: Index, first: usize, last: usize) bool {
        const lead = self.order[first];
        if (lead == 0) return true;
        for (self.order[first + 1 .. last + 1]) |offset| {
            if (offset == 0 or self.text[offset - 1] != self.text[lead - 1]) return true;
        }
        return false;
    }
};

pub const Repeat = struct { length: usize, offsets: []const usize };

fn compare(suffix: []const u32, needle: []const u8) std.math.Order {
    for (needle, 0..) |byte, index| {
        if (index == suffix.len) return .lt;
        if (suffix[index] != byte) return std.math.order(suffix[index], byte);
    }
    return .eq;
}

/// Prefix doubling: each round orders suffixes by their first 2k symbols.
fn sortSuffixes(a: std.mem.Allocator, text: []const u32) ![]const u32 {
    const n = text.len;
    const order = try a.alloc(u32, n);
    for (order, 0..) |*offset, index| offset.* = @intCast(index);
    const rank = try a.alloc(u64, n);
    defer a.free(rank);
    for (rank, text) |*value, symbol| value.* = symbol;
    const keys = try a.alloc(u64, n);
    defer a.free(keys);
    var span: usize = 1;
    while (n > 1) : (span *= 2) {
        for (keys, 0..) |*key, offset| key.* = (rank[offset] << 32) | (if (offset + span < n) rank[offset + span] + 1 else 0);
        std.mem.sort(u32, order, keys, struct {
            fn less(context: []const u64, left: u32, right: u32) bool {
                return context[left] < context[right];
            }
        }.less);
        rank[order[0]] = 0;
        for (1..n) |position| rank[order[position]] = rank[order[position - 1]] + @intFromBool(keys[order[position - 1]] != keys[order[position]]);
        if (rank[order[n - 1]] == n - 1) break;
    }
    return order;
}

test "contains finds exact spans inside one unit and never across units" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const index = try Index.build(arena.allocator(), &.{ "banana", "bandana" });
    for ([_][]const u8{ "", "ban", "anana", "bandana", "dan", "a" }) |needle| try std.testing.expect(index.contains(needle));
    for ([_][]const u8{ "bananab", "nab", "bananas", "x" }) |needle| try std.testing.expect(!index.contains(needle));
    try std.testing.expectEqual(@as(usize, 0), index.unit(3));
    try std.testing.expectEqual(@as(usize, 1), index.unit(7));
}

test "suffix order is lexicographic, including repeated symbols" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const index = try Index.build(arena.allocator(), &.{"aaaaab"});
    for (index.order[1..], index.order[0 .. index.order.len - 1]) |current, previous|
        try std.testing.expect(std.mem.order(u32, index.text[previous..], index.text[current..]) == .lt);
}

test "repeats are maximal, need two offsets and the minimum length" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // "the quick fox" repeats in full; its shorter prefix with the same offsets doesn't.
    const index = try Index.build(a, &.{ "say the quick fox now", "the quick fox", "unrelated" });
    const found = try index.repeats(a, 5);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqual(@as(usize, 13), found[0].length);
    try std.testing.expectEqual(@as(usize, 2), found[0].offsets.len);
    try std.testing.expectEqual(@as(usize, 0), (try index.repeats(a, 14)).len);
    // A span shared by three units is its own repeat beside a longer one shared by two.
    const nested = try Index.build(a, &.{ "abcdefgh!", "abcdefgh?", "abcdXYZ" });
    const lengths = try nested.repeats(a, 4);
    try std.testing.expectEqual(@as(usize, 2), lengths.len);
}
