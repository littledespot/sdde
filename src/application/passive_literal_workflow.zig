const literals = @import("../domain/passive_literals.zig");
const values = @import("pipeline_values.zig");

// The registry derives only from bounded captured references, never model response bytes. The stage
// action `prepare-reference-tokens` publishes it; the candidates and identities stay function-local.
pub const registry_schema = values.schema(.reference_passive_literals, literals.Registry, 1, 64 * 1024 * 1024);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{registry_schema};
