//! Closed authority payloads; allocation/retention has one shared owner.
const a = @import("../domain/required_authority.zig");
pub const Payload = union(enum) { inputs: a.Inputs, ledger: a.Ledger, raw: []const u8, observations: a.Observations, result: a.Result, content: @import("../domain/specification.zig").IdentifiedContent, rejected: enum { invalid_contract } };
const storage = @import("retained_candidate.zig").Storage(Payload, .{ .rejected = .invalid_contract });
pub const Value = storage.Value;
pub const Owner = storage.Owner;
pub const create = storage.create;
pub const destroy = storage.destroy;
pub const view = storage.view;
pub const payload = storage.payload;
pub const publish = storage.publish;
pub fn read(inputs: *const @import("../domain/pipeline_data.zig").View, schema: @import("../domain/pipeline_data.zig").Schema, comptime tag: @import("std").meta.Tag(Payload)) !@FieldType(Payload, @tagName(tag)) {
    return storage.read(inputs, schema, tag) catch |err| switch (err) {
        error.InvalidCandidatePayload => error.InvalidRequiredAuthority,
        else => err,
    };
}
