//! Configured temperatures for offline fixtures: the shipped E2E pair (ADR 0039).
const controls = @import("../domain/model_controls.zig");

pub const temperatures: controls.Temperatures = .{ .configured = .{ .value = 0.1 }, .runaway_retry = .{ .value = 1 } };
pub const supported: controls.InferenceControls = .{ .temperatures = temperatures };
