const feature = @import("../domain/feature_directory.zig");
const values = @import("pipeline_values.zig");

// The stage action `prepare-inputs` publishes both; its normalized candidate stays function-local.
const maximum_bytes = @import("../domain/relative_directory_path.zig").max_bytes * 8 + 2048;
pub const selector = values.schema(.relative_feature_directory, feature.Selector, 1, maximum_bytes);
pub const directory = values.schema(.feature_directory, feature.Directory, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ selector, directory };
