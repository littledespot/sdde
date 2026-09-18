//! Immutable captured policy prose and exact transport selections. No semantic inference.
const std = @import("std");
const inventory = @import("source_inventory.zig");
const policy = @import("principle_policy.zig");
const identity = @import("filesystem_identity.zig");
const coordinates = @import("source_coordinates.zig");
pub const Error = std.mem.Allocator.Error || policy.Error || @import("canonical_json.zig").Error || error{InvalidPrincipleRegistry};
pub const limits: inventory.Limits = .{ .entries = 1024, .depth = 16, .duration_ms = 5000 };
pub const max_source_bytes: usize = 1024 * 1024;
pub const max_total_bytes: usize = 8 * 1024 * 1024;
pub const chunk_bytes: usize = 16 * 1024;
pub const Root = struct { path: []const u8, identity: identity.FileIdentity };
pub const Id = struct { root: identity.FileIdentity, ordinal: u64, revision: u64 };
pub const SourceId = struct { ordinal: u32 };
pub const ChunkId = struct { ordinal: u32 };
pub const Kind = enum { directory, mechanical_toolchain_layer_excluded, semantic_markdown };
pub const Entry = struct { descriptor: inventory.Entry, kind: Kind };
pub const Raw = struct { root: Root, entries: []const inventory.Descriptor };
pub const Inventory = struct { root: Root, entries: []const Entry, source_bytes: usize };
pub const Capture = struct { entry: u32, bytes: []const u8 };
pub const Captured = struct { inventory: Inventory, sources: []const Capture };
pub const Source = struct { id: SourceId, entry: u32, category: policy.Category, bytes: []const u8 };
pub const Chunk = struct { id: ChunkId, source: SourceId, span: coordinates.Span };
pub const Registry = struct {
    id: Id,
    inventory: Inventory,
    policy: policy.Policy,
    sources: []const Source,
    chunks: []const Chunk,
    next_source: u32,
    next_chunk: u32,
};
pub const Selection = struct { registry: Id, scope: policy.Scope, chunks: []const ChunkId };
pub const Citation = struct { chunk: ChunkId, first_line: u32, last_line: u32 };
pub const Guidance = struct { id: ChunkId, category: policy.Category, first_line: u32, text: []const u8 };

pub fn classify(a: std.mem.Allocator, raw: Raw, normalizer: @import("../ports/unicode_normalizer.zig").Normalizer, folder: @import("../ports/unicode_normalizer.zig").CaseFolder) Error!Inventory {
    @import("relative_directory_path.zig").validate(raw.root.path) catch return error.InvalidPrincipleRegistry;
    const checked = inventory.validate(a, raw.entries, limits, normalizer, folder) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidPrincipleRegistry;
    const entries = try a.alloc(Entry, checked.len);
    for (checked, entries) |item, *entry| {
        const kind: Kind = switch (item.observation) {
            .directory => .directory,
            .file => if (std.mem.eql(u8, item.path, @import("toolchain.zig").project_filename)) .mechanical_toolchain_layer_excluded else if (std.mem.endsWith(u8, item.path, ".md")) .semantic_markdown else return error.InvalidPrincipleRegistry,
            else => return error.InvalidPrincipleRegistry,
        };
        entry.* = .{ .descriptor = item, .kind = kind };
    }
    var result: Inventory = .{ .root = raw.root, .entries = entries, .source_bytes = 0 };
    for (entries) |entry| if (entry.kind == .semantic_markdown) {
        const size = entry.descriptor.observation.file.size;
        if (size > max_source_bytes or size > max_total_bytes - result.source_bytes) return error.InvalidPrincipleRegistry;
        result.source_bytes += @intCast(size);
    };
    try validateInventory(result);
    return result;
}

pub fn validateInventory(value: Inventory) Error!void {
    @import("relative_directory_path.zig").validate(value.root.path) catch return error.InvalidPrincipleRegistry;
    if (value.entries.len > limits.entries) return error.InvalidPrincipleRegistry;
    var mechanical: usize = 0;
    var total: usize = 0;
    for (value.entries, 0..) |entry, index| {
        const path = entry.descriptor.path;
        @import("relative_directory_path.zig").validate(path) catch return error.InvalidPrincipleRegistry;
        @import("relative_directory_path.zig").validate(entry.descriptor.raw_path) catch return error.InvalidPrincipleRegistry;
        if (std.mem.count(u8, path, "/") >= limits.depth or (index != 0 and std.mem.order(u8, value.entries[index - 1].descriptor.path, path) != .lt)) return error.InvalidPrincipleRegistry;
        switch (entry.kind) {
            .directory => if (entry.descriptor.observation != .directory) return error.InvalidPrincipleRegistry,
            .mechanical_toolchain_layer_excluded => {
                if (entry.descriptor.observation != .file or !std.mem.eql(u8, path, @import("toolchain.zig").project_filename)) return error.InvalidPrincipleRegistry;
                mechanical += 1;
            },
            .semantic_markdown => {
                if (entry.descriptor.observation != .file or !std.mem.endsWith(u8, path, ".md")) return error.InvalidPrincipleRegistry;
                const size = entry.descriptor.observation.file.size;
                if (size > max_source_bytes or size > max_total_bytes - total) return error.InvalidPrincipleRegistry;
                total += @intCast(size);
            },
        }
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| {
            for (value.entries[0..index]) |parent| {
                if (std.mem.eql(u8, parent.descriptor.path, path[0..slash]) and parent.kind == .directory) break;
            } else return error.InvalidPrincipleRegistry;
        }
    }
    if (mechanical != 1 or total != value.source_bytes) return error.InvalidPrincipleRegistry;
}

pub fn buildConfigured(a: std.mem.Allocator, captured: Captured, configured: policy.Input, normalizer: @import("../ports/unicode_normalizer.zig").Normalizer, folder: @import("../ports/unicode_normalizer.zig").CaseFolder, prior: ?Registry) Error!Registry {
    return build(a, captured, try policy.compile(a, configured, normalizer, folder), prior);
}

pub fn build(a: std.mem.Allocator, captured: Captured, selected_policy: policy.Policy, prior: ?Registry) Error!Registry {
    try validateInventory(captured.inventory);
    try policy.validate(selected_policy);
    if (prior) |old| try validate(old);
    const same_root = if (prior) |old| old.id.root.eql(captured.inventory.root.identity) and std.mem.eql(u8, old.inventory.root.path, captured.inventory.root.path) else false;
    var result: Registry = .{
        .id = .{ .root = captured.inventory.root.identity, .ordinal = if (same_root) prior.?.id.ordinal else 1, .revision = if (same_root) std.math.add(u64, prior.?.id.revision, 1) catch return error.InvalidPrincipleRegistry else 1 },
        .inventory = captured.inventory,
        .policy = selected_policy,
        .sources = &.{},
        .chunks = &.{},
        .next_source = if (same_root) prior.?.next_source else 1,
        .next_chunk = if (same_root) prior.?.next_chunk else 1,
    };
    var sources: std.ArrayList(Source) = .empty;
    var chunks: std.ArrayList(Chunk) = .empty;
    var cursor: usize = 0;
    for (captured.inventory.entries, 0..) |entry, index| {
        if (entry.kind != .semantic_markdown) continue;
        if (cursor >= captured.sources.len) return error.InvalidPrincipleRegistry;
        const source = captured.sources[cursor];
        cursor += 1;
        if (source.entry != index + 1 or source.bytes.len != entry.descriptor.observation.file.size or !std.unicode.utf8ValidateSlice(source.bytes)) return error.InvalidPrincipleRegistry;
        const category_hint = policy.category(selected_policy, entry.descriptor.path);
        const retained: ?Source = found: {
            if (same_root) for (prior.?.sources) |old| {
                const old_entry = prior.?.inventory.entries[old.entry - 1];
                if (old.category == category_hint and std.mem.eql(u8, old_entry.descriptor.path, entry.descriptor.path) and std.meta.eql(old_entry.descriptor.observation, entry.descriptor.observation) and std.mem.eql(u8, old.bytes, source.bytes)) break :found old;
            };
            break :found null;
        };
        const id: SourceId = if (retained) |old| old.id else .{ .ordinal = try allocate(&result.next_source) };
        try sources.append(a, .{ .id = id, .entry = @intCast(index + 1), .category = category_hint, .bytes = source.bytes });
        var start: coordinates.Position = .{ .byte = 0, .line = 1, .column = 1 };
        while (start.byte < source.bytes.len) {
            var end = start;
            while (end.byte < source.bytes.len and end.byte - start.byte < chunk_bytes) end = coordinates.advance(source.bytes, end) catch return error.InvalidPrincipleRegistry;
            const span: coordinates.Span = .{ .start = start, .end = end };
            const chunk_id: ChunkId = retained_chunk: {
                if (retained != null) for (prior.?.chunks) |old| {
                    if (std.meta.eql(old.source, id) and std.meta.eql(old.span, span)) break :retained_chunk old.id;
                };
                break :retained_chunk .{ .ordinal = try allocate(&result.next_chunk) };
            };
            try chunks.append(a, .{ .id = chunk_id, .source = id, .span = span });
            start = end;
        }
    }
    if (cursor != captured.sources.len) return error.InvalidPrincipleRegistry;
    result.sources = try sources.toOwnedSlice(a);
    result.chunks = try chunks.toOwnedSlice(a);
    if (same_root) {
        var unchanged = result;
        unchanged.id = prior.?.id;
        if (try equal(a, unchanged, prior.?)) result.id = prior.?.id;
    }
    try validate(result);
    return result;
}
pub fn validate(value: Registry) Error!void {
    try validateInventory(value.inventory);
    try policy.validate(value.policy);
    if (value.id.ordinal == 0 or value.id.revision == 0 or !value.id.root.eql(value.inventory.root.identity) or value.next_source == 0 or value.next_chunk == 0) return error.InvalidPrincipleRegistry;
    var source_cursor: usize = 0;
    var chunk_cursor: usize = 0;
    for (value.inventory.entries, 0..) |entry, entry_index| {
        if (entry.kind != .semantic_markdown) continue;
        if (source_cursor >= value.sources.len) return error.InvalidPrincipleRegistry;
        const source = value.sources[source_cursor];
        if (source.entry != entry_index + 1 or source.id.ordinal == 0 or source.id.ordinal >= value.next_source or source.category != policy.category(value.policy, entry.descriptor.path) or source.bytes.len != entry.descriptor.observation.file.size or !std.unicode.utf8ValidateSlice(source.bytes)) return error.InvalidPrincipleRegistry;
        for (value.sources[0..source_cursor]) |other| if (std.meta.eql(other.id, source.id)) return error.InvalidPrincipleRegistry;
        source_cursor += 1;
        var position: coordinates.Position = .{ .byte = 0, .line = 1, .column = 1 };
        while (position.byte < source.bytes.len) {
            if (chunk_cursor >= value.chunks.len) return error.InvalidPrincipleRegistry;
            const chunk = value.chunks[chunk_cursor];
            if (chunk.id.ordinal == 0 or chunk.id.ordinal >= value.next_chunk or !std.meta.eql(chunk.source, source.id) or !std.meta.eql(chunk.span.start, position)) return error.InvalidPrincipleRegistry;
            for (value.chunks[0..chunk_cursor]) |other| if (std.meta.eql(other.id, chunk.id)) return error.InvalidPrincipleRegistry;
            const start = position;
            while (position.byte < source.bytes.len and position.byte - start.byte < chunk_bytes) position = coordinates.advance(source.bytes, position) catch return error.InvalidPrincipleRegistry;
            if (!std.meta.eql(position, chunk.span.end)) return error.InvalidPrincipleRegistry;
            chunk_cursor += 1;
        }
    }
    if (source_cursor != value.sources.len or chunk_cursor != value.chunks.len) return error.InvalidPrincipleRegistry;
}
pub fn select(a: std.mem.Allocator, registry: Registry, scope: policy.Scope) Error!Selection {
    try validate(registry);
    const categories = try policy.select(registry.policy, scope);
    var ids: std.ArrayList(ChunkId) = .empty;
    for (registry.chunks) |chunk| if (categories.contains((try sourceFor(registry, chunk.source)).category)) try ids.append(a, chunk.id);
    return .{ .registry = registry.id, .scope = scope, .chunks = try ids.toOwnedSlice(a) };
}
pub fn validateSelection(a: std.mem.Allocator, registry: Registry, selection: Selection) Error!void {
    if (!std.meta.eql(registry.id, selection.registry)) return error.InvalidPrincipleRegistry;
    const expected = try select(a, registry, selection.scope);
    if (expected.chunks.len != selection.chunks.len) return error.InvalidPrincipleRegistry;
    for (expected.chunks, selection.chunks) |left, right| if (!std.meta.eql(left, right)) return error.InvalidPrincipleRegistry;
}
pub fn guidance(a: std.mem.Allocator, registry: Registry, selection: Selection) Error![]const Guidance {
    try validateSelection(a, registry, selection);
    const result = try a.alloc(Guidance, selection.chunks.len);
    for (selection.chunks, result) |id, *entry| {
        const chunk = try chunkFor(registry, id);
        const source = try sourceFor(registry, chunk.source);
        entry.* = .{ .id = id, .category = source.category, .first_line = chunk.span.start.line, .text = source.bytes[chunk.span.start.byte..chunk.span.end.byte] };
    }
    return result;
}
pub fn validateCitation(registry: Registry, selection: Selection, citation: Citation) Error!void {
    if (!std.meta.eql(registry.id, selection.registry)) return error.InvalidPrincipleRegistry;
    for (selection.chunks) |id| {
        if (std.meta.eql(id, citation.chunk)) break;
    } else return error.InvalidPrincipleRegistry;
    const chunk = try chunkFor(registry, citation.chunk);
    const last = chunk.span.end.line - @as(u32, if (chunk.span.end.column == 1) 1 else 0);
    if (citation.first_line < chunk.span.start.line or citation.first_line > citation.last_line or citation.last_line > last) return error.InvalidPrincipleRegistry;
}
pub fn sourceFor(registry: Registry, id: SourceId) Error!Source {
    for (registry.sources) |source| if (std.meta.eql(source.id, id)) return source;
    return error.InvalidPrincipleRegistry;
}
pub fn chunkFor(registry: Registry, id: ChunkId) Error!Chunk {
    for (registry.chunks) |chunk| if (std.meta.eql(chunk.id, id)) return chunk;
    return error.InvalidPrincipleRegistry;
}
fn allocate(next: *u32) Error!u32 {
    const value = next.*;
    next.* = std.math.add(u32, value, 1) catch return error.InvalidPrincipleRegistry;
    return value;
}
pub fn equal(a: std.mem.Allocator, left: Registry, right: Registry) Error!bool {
    const l = try @import("canonical_json.zig").encode(Registry, a, left);
    defer a.free(l);
    const r = try @import("canonical_json.zig").encode(Registry, a, right);
    defer a.free(r);
    return std.mem.eql(u8, l, r);
}
