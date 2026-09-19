//! Read-only lookup of current compiled authority. No execution or fallback.
const compilation = @import("../domain/workflow_compilation.zig");
const workflow = @import("../domain/workflow.zig");
pub const Context = opaque {};
pub const Source = struct {
    context: *const Context,
    resolve_fn: *const fn (*const Context, workflow.WorkflowId) ?*const compilation.SemanticAuthority,
    pub fn resolve(self: Source, id: workflow.WorkflowId) ?*const compilation.SemanticAuthority {
        return self.resolve_fn(self.context, id);
    }
};
