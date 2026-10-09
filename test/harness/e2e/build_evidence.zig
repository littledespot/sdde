//! Development source reconstruction evidence, separate from runtime authority.
const std = @import("std");
const provenance = @import("../../../build/provenance.zig");
const Store = @import("../evidence.zig").Store;
pub const Reconstruction = @FieldType(@typeInfo(@FieldType(@import("contracts.zig").Report, "build")).optional.child, "reconstruction");

pub fn save(store: Store, bytes: []const u8) !Reconstruction {
    var arena: std.heap.ArenaAllocator = .init(store.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bundle = try @import("../contracts.zig").decode(provenance.Bundle, a, bytes);
    if (!std.mem.eql(u8, bundle.schema, "build-inputs/v1")) return error.InvalidBuildInputs;
    // Redact each source before encoding so quoted credentials cannot bypass the
    // shared credential filter. A redacted snapshot is explicitly non-exact.
    var redacted = false;
    const inputs = try a.dupe(provenance.Input, bundle.inputs);
    for (inputs) |*input| {
        if (input.state == .captured) {
            const source = input.bytes orelse return error.InvalidBuildInputs;
            const safe = try store.redact(a, source);
            if (!std.mem.eql(u8, safe, source)) redacted = true;
            input.bytes = safe;
        } else {
            if (input.bytes != null) return error.InvalidBuildInputs;
            if (input.state != .deleted) bundle.complete = false;
        }
    }
    bundle.inputs = inputs;
    if (redacted) bundle.complete = false;
    try @import("../output.zig").write(store.io, store.run, "build-inputs.json", try std.json.Stringify.valueAlloc(a, bundle, .{}));
    return if (redacted) .redacted else if (bundle.complete) .captured else .incomplete;
}
