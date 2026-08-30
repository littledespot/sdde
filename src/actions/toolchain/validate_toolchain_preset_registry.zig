const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const schema = @import("../../domain/toolchain_schema.zig");
const inheritance = @import("../../domain/toolchain_inheritance.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-toolchain-preset-registry@1", .kind = .action, .requires = &.{.raw_toolchain_documents}, .produces = &.{.schema_valid_toolchain_registry}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, documents: []const toolchain.RawDocument) toolchain.Error!toolchain.Registry {
        const registry = try schema.parseRegistry(allocator, documents);
        try inheritance.validateCompleteRegistry(allocator, registry);
        return registry;
    }
};
