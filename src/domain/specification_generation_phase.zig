//! Generation consumes source authority independently of review projections.
pub const Phase = enum { pre_generation, generation_started };

/// Every native operation proving the generation phase reads these same facts.
pub const optional = [_]@import("pipeline.zig").DataKey{ .specification_generation_session, .identified_specification_content };
