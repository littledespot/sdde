const std = @import("std");
const toolchain = @import("../../domain/toolchain.zig");
const parser_port = @import("../../ports/toolchain_document_parser.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    parser: parser_port.Parser,
    pub const contract: pipeline.NodeContract = .{ .id = "parse-toolchain-documents@1", .kind = .action, .requires = &.{ .project_toolchain_capture, .toolchain_preset_captures }, .produces = &.{.raw_toolchain_documents}, .side_effect = .none };
    pub fn execute(self: Action, allocator: std.mem.Allocator, project: toolchain.Capture, presets: []const toolchain.Capture) toolchain.Error![]const toolchain.RawDocument {
        const captures = allocator.alloc(toolchain.Capture, presets.len + 1) catch return error.InvalidToolchain;
        captures[0] = project;
        @memcpy(captures[1..], presets);
        return self.parser.parse(allocator, captures) catch error.InvalidToolchain;
    }
};
