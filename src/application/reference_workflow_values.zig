const reference = @import("../domain/reference_selector.zig");
const values = @import("pipeline_values.zig");

const maximum_bytes = reference.max_bytes * 4 + 1024;
pub const normalized = values.schema(.normalized_reference_selector, reference.NormalizedCandidate, 1, maximum_bytes);
pub const selector = values.schema(.relative_reference_selector, reference.RelativeSelector, 1, maximum_bytes);
pub const directory = values.schema(.reference_directory, reference.Directory, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ normalized, selector, directory };
