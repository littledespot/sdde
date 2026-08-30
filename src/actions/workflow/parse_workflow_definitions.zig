const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");
const parser_port = @import("../../ports/workflow_definition_parser.zig");

pub const Error = error{WorkflowDefinitionParseError};

pub const Action = struct {
    parser: parser_port.Parser,

    pub const contract: pipeline.NodeContract = .{
        .id = "parse-workflow-definitions@1",
        .kind = .action,
        .requires = &.{.workflow_definition_captures},
        .produces = &.{.raw_workflow_definitions},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        captures: []const workflow.Capture,
    ) Error![]const workflow.RawDefinition {
        return self.parser.parse(allocator, captures) catch {
            return error.WorkflowDefinitionParseError;
        };
    }
};
