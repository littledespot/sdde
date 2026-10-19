//! Model-identity evidence for development acceptance. This does not authorize a
//! model, invoke a provider, or establish grader accuracy. A supplied
//! specification has no observed generation identity.
const contracts = @import("contracts.zig");

pub const Result = union(enum) {
    independent,
    self_grading: contracts.GenerationModel,
    unknown_generation,
};
