const execution = @import("../../domain/workflow_execution.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Action = struct {
    pub fn execute(_: Action, arguments: []const []const u8) execution.InvocationError!execution.Invocation {
        if (arguments.len == 0) return error.MissingWorkflowId;
        if (arguments.len > execution.max_invocation_arguments + 1) return error.TooManyArguments;
        return .{
            .workflow_id = workflow.WorkflowId.parse(arguments[0]) orelse return error.InvalidWorkflowId,
            .arguments = arguments[1..],
        };
    }
};

test "selects one exact workflow id and preserves its invocation arguments" {
    const invocation = try (Action{}).execute(&.{ "hello", "--mode", "safe" });
    try @import("std").testing.expectEqualStrings("hello", invocation.workflow_id.bytes);
    try @import("std").testing.expectEqualStrings("--mode", invocation.arguments[0]);
}

test "rejects a missing or malformed workflow id" {
    try @import("std").testing.expectError(error.MissingWorkflowId, (Action{}).execute(&.{}));
    try @import("std").testing.expectError(error.InvalidWorkflowId, (Action{}).execute(&.{"Specify"}));
}
