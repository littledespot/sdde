//! The project's principles as context for the records request (D17.1). Only that request carries
//! them, as the principle files the registry captured, unnumbered, so no record can cite one.
const std = @import("std");
const packets = @import("model_input_packet.zig");
const registry = @import("principle_registry.zig");
const session = @import("specification_session.zig");

pub const Error = packets.Error || @import("strict_json.zig").Error;

/// One principle file's text, as captured.
const Principle = struct { text: []const u8 };

/// Whether the request in flight is the records request and the project has principles to give it.
/// The brief, entities, scenarios and repair requests never carry them.
pub fn carried(current: session.Session, principles: registry.Registry) bool {
    return current.completed == session.records_index and !session.scenarioPhase(current) and principles.sources.len != 0;
}

/// The records request with every principle file added, in the registry's order.
pub fn carry(allocator: std.mem.Allocator, base: *const packets.Packet, principles: registry.Registry) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const files = try arena.allocator().alloc(Principle, principles.sources.len);
    for (principles.sources, files) |source, *file| file.* = .{ .text = source.bytes };
    return packets.withContext([]const Principle, allocator, base, "principles", files);
}
