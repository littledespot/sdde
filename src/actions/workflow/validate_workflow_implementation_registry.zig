const compilation = @import("../../domain/workflow_compilation.zig");
const pipeline = @import("../../domain/pipeline.zig");
const implementations = @import("../../ports/workflow_node_implementation.zig");

pub const Error = error{WorkflowImplementationRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-workflow-implementation-registry@1",
        .kind = .action,
        .requires = &.{ .workflow_implementation_registry, .workflow_compiler_registry },
        .produces = &.{.workflow_implementation_registry_evidence},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        implementation_registry: implementations.Registry,
        compiler_registry: compilation.CompilerRegistry,
    ) Error!void {
        if (!implementation_registry.matchesCompiler(compiler_registry)) {
            return error.WorkflowImplementationRegistryInvalid;
        }
    }
};

test "rejects any implementation catalogue that does not exactly match the compiler" {
    const empty_implementations: implementations.Registry = .{ .invocations = &.{}, .nodes = &.{} };
    const empty_compiler: compilation.CompilerRegistry = .{
        .invocations = &.{},
        .nodes = &.{},
        .policies = &.{},
        .gates = &.{},
        .capabilities = &.{},
    };
    try (Action{}).execute(empty_implementations, empty_compiler);

    var mismatched = empty_compiler;
    mismatched.invocations = &.{.{
        .id = "test.invocation@1",
        .capability_free = true,
        .produces = &.{},
    }};
    try @import("std").testing.expectError(
        error.WorkflowImplementationRegistryInvalid,
        (Action{}).execute(empty_implementations, mismatched),
    );
}
