const reference = @import("../domain/reference_selector.zig");
const values = @import("pipeline_values.zig");

// The stage action `prepare-inputs` publishes the directory; the selectors stay function-local.
const maximum_bytes = reference.max_bytes * 4 + 1024;
pub const directory = values.schema(.reference_directory, reference.Directory, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{directory};
