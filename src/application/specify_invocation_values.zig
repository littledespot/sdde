const invocation_types = @import("../domain/specify_invocation.zig");
const values = @import("pipeline_values.zig");
const maximum_bytes = @import("../domain/relative_directory_path.zig").max_bytes * 8 + 2048;

pub const parsed = values.schema(.parsed_specify_invocation, invocation_types.ParsedInvocation, 1, maximum_bytes);
pub const invocation = values.schema(.specify_invocation, invocation_types.Invocation, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ parsed, invocation };
