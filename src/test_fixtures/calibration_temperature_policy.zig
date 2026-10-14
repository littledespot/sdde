//! Fixed current temperature used by offline diagnostic metadata.
const controls = @import("../domain/model_controls.zig");

pub const temperature = controls.Temperature.fixed.wireValue();
