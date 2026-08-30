const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
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
        captures: []const inventory.Capture,
    ) Error![]const definition.RawDefinition {
        return self.parser.parse(allocator, captures) catch {
            return error.WorkflowDefinitionParseError;
        };
    }
};
