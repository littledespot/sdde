//! Typed progress of source review. YAML owns calls and continuation.
const support = @import("specification_support.zig");
pub const Source = support.Source;
pub const Progress = union(enum) { initial, source: Source.Collection };
pub const Error = Source.Error;
