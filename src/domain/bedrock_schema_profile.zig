const schema = @import("model_result_schema.zig");

// Exact intersection of the compiled result schema and Bedrock's native
// feature set. Never erase constraints to make a schema representable.
pub fn represents(node: *const schema.Node) bool {
    return switch (node.*) {
        .object => |properties| blk: {
            for (properties) |property| if (!represents(property.schema)) break :blk false;
            break :blk true;
        },
        .boolean, .null_value, .constant, .enumeration => true,
        // SDDE requires bounds on these types. Bedrock cannot enforce them.
        .string, .integer, .array, .one_of => false,
    };
}
