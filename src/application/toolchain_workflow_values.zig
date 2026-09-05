const toolchain = @import("../domain/toolchain.zig");
const safety = @import("../domain/toolchain_safety.zig");
const values = @import("pipeline_values.zig");

// Source bytes plus the bounded decoder's maximum native tree overhead.
pub const maximum_value_bytes = toolchain.max_total_bytes + (toolchain.max_presets + 1) *
    toolchain.max_yaml_events * (@sizeOf(toolchain.RawNode) + @sizeOf(toolchain.Pair) + @sizeOf(*const toolchain.RawNode));
pub const project_capture = values.schema(.project_toolchain_capture, toolchain.Capture, 1, maximum_value_bytes);
pub const preset_inventory = values.schema(.toolchain_preset_inventory, []const toolchain.Entry, 1, maximum_value_bytes);
pub const preset_captures = values.schema(.toolchain_preset_captures, []const toolchain.Capture, 1, maximum_value_bytes);
pub const raw_documents = values.schema(.raw_toolchain_documents, []const toolchain.RawDocument, 1, maximum_value_bytes);
pub const project = values.schema(.schema_valid_project_toolchain, toolchain.Project, 1, maximum_value_bytes);
pub const registry = values.schema(.schema_valid_toolchain_registry, toolchain.Registry, 1, maximum_value_bytes);
pub const resolved = values.schema(.resolved_toolchain_inheritance, toolchain.Resolved, 1, maximum_value_bytes);
pub const composed = values.schema(.composed_toolchain, toolchain.Composed, 1, maximum_value_bytes);
pub const valid = values.schema(.valid_toolchain, safety.ValidToolchain, 1, maximum_value_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{
    project_capture, preset_inventory, preset_captures, raw_documents, project, registry, resolved, composed, valid,
};
