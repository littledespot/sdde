const execution = @import("../domain/workflow_execution.zig");
const model_request_stage = @import("../domain/model_request_stage.zig");

pub const Stage = model_request_stage.Stage;

/// The runner-owned bindings the request orchestrator coordinates. The runner invokes
/// the stage, validates and applies its delta, and owns every retry count, bound and the
/// accounting of actual tokens; the orchestrator only follows typed outcomes.
pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        invoke_stage: *const fn (*anyopaque, Stage) execution.Applied,
    };

    pub fn invokeStage(self: ChildBindings, stage: Stage) execution.Applied {
        return self.vtable.invoke_stage(self.context, stage);
    }
};
