const evidence = @import("../domain/reference_evidence.zig");
const values = @import("pipeline_values.zig");
// The stage action `prepare-reference-evidence` publishes the citable inputs; the corpus and chunks
// stay function-local (ADR 0031).
pub const inputs_schema = values.schema(.citable_reference_inputs, evidence.Inputs, 1, values.max_value_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{inputs_schema};
