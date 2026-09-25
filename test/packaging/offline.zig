//! Automated subprocesses retain the application entry point with model
//! connections compiled out. Runtime arguments and credentials cannot enable it.
pub const live_model_connections = false;
pub const main = @import("application").main;
