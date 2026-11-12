const toolchain = @import("../domain/toolchain.zig");
const safety = @import("../domain/toolchain_safety.zig");
const values = @import("pipeline_values.zig");

// Source bytes plus the bounded decoder's maximum native tree overhead.
pub const maximum_value_bytes = toolchain.max_total_bytes + (toolchain.max_presets + 1) *
    toolchain.max_yaml_events * (@sizeOf(toolchain.RawNode) + @sizeOf(toolchain.Pair) + @sizeOf(*const toolchain.RawNode));
// The stage's only pipeline data: its intermediates are function-local (ADR 0031).
pub const valid = values.schema(.valid_toolchain, safety.ValidToolchain, 1, maximum_value_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{valid};
