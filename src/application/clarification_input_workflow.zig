const artifacts = @import("../domain/workflow_artifact_registry.zig");
const clarification = @import("../domain/clarification_inputs.zig");
const values = @import("pipeline_values.zig");

// The stage action `prepare-inputs` publishes these three; the parsed and validated state stay
// function-local (ADR 0031).
const maximum = clarification.max_state_bytes * 4;
pub const paths_schema = values.schema(.feature_artifact_paths, artifacts.FeaturePaths, 1, 128 * 1024);
pub const captures_schema = values.schema(.raw_clarification_inputs, clarification.Captures, 1, maximum);
pub const inputs_schema = values.schema(.clarification_inputs, clarification.Inputs, 1, maximum);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ paths_schema, captures_schema, inputs_schema };
