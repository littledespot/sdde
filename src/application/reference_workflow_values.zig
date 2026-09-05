const reference = @import("../domain/reference_selector.zig");
const invocation_types = @import("../domain/specify_invocation.zig");
const values = @import("pipeline_values.zig");

const maximum_bytes = reference.max_bytes * 4 + 1024;
pub const parsed = values.schema(.parsed_specify_invocation, invocation_types.ParsedInvocation, 1, maximum_bytes * 2);
pub const invocation = values.schema(.specify_invocation, invocation_types.Invocation, 1, maximum_bytes * 2);
pub const normalized = values.schema(.normalized_reference_selector, reference.NormalizedCandidate, 1, maximum_bytes);
pub const selector = values.schema(.relative_reference_selector, reference.RelativeSelector, 1, maximum_bytes);
pub const directory = values.schema(.reference_directory, reference.Directory, 1, maximum_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ parsed, invocation, normalized, selector, directory };
