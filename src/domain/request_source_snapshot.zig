//! Captured diagnostic source text, never a file-access capability or authority.
const std = @import("std");
const strict = @import("strict_json.zig");
const workflow = @import("workflow.zig");
pub const Entry = @import("workflow_source.zig").Entry;
pub const Document = struct { path: []const u8, content: []const u8, redacted: bool };
pub const Resource = struct {
    role: enum { prompt, protocol_prompt, result, input, composition },
    alias: []const u8,
    kind: @import("workflow_operation.zig").ResourceKind,
    document: Document,
};
pub const Location = struct { step: []const u8, chain: []const Entry };
pub const Selection = struct {
    definition: ?[]const u8,
    part: ?[]const u8,
    // Decoded JSON pointer segments, not guessed property names.
    paths: []const []const []const u8,
};
pub const Snapshot = struct {
    version: enum { @"request-source/v1" } = .@"request-source/v1",
    workflow: []const u8,
    document: Document,
    caller: Location,
    preparation: Location,
    resources: []const Resource,
    selection: Selection,

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) strict.Error!Snapshot {
        const result = try strict.decode(Snapshot, a, bytes, .{ .maximum_depth = 64 });
        try result.validate();
        return result;
    }
    pub fn validate(self: Snapshot) error{InvalidJsonDocument}!void {
        if (workflow.WorkflowId.parse(self.workflow) == null) return error.InvalidJsonDocument;
        try documentValid(self.document);
        try locationValid(self.caller);
        try locationValid(self.preparation);
        var roles: std.EnumSet(@FieldType(Resource, "role")) = .initEmpty();
        for (self.resources, 0..) |resource, index| {
            if (workflow.WorkflowResourceId.parse(resource.alias) == null) return error.InvalidJsonDocument;
            try documentValid(resource.document);
            for (self.resources[0..index]) |prior| if (prior.role == resource.role) return error.InvalidJsonDocument;
            const expected: @TypeOf(resource.kind) = switch (resource.role) {
                .prompt, .protocol_prompt => .prompt,
                .result => .result_schema,
                .input => .data,
                .composition => .json_composition,
            };
            if (resource.kind != expected) return error.InvalidJsonDocument;
            roles.insert(resource.role);
        }
        if (!roles.contains(.prompt) or !roles.contains(.result) or roles.contains(.composition) != (self.selection.part != null)) return error.InvalidJsonDocument;
        if (self.selection.part) |part| {
            if (workflow.WorkflowResourceId.parse(part) == null or self.selection.paths.len == 0) return error.InvalidJsonDocument;
        } else if (self.selection.paths.len != 0) return error.InvalidJsonDocument;
        if (self.selection.definition) |id| if (@import("model_result_schema.zig").DefinitionId.parse(id) == null) return error.InvalidJsonDocument;
    }
    pub fn matches(self: Snapshot, workflow_id: []const u8, caller: []const u8, preparation: []const u8) bool {
        return std.mem.eql(u8, self.workflow, workflow_id) and std.mem.eql(u8, self.caller.step, caller) and std.mem.eql(u8, self.preparation.step, preparation);
    }
};
fn documentValid(document: Document) error{InvalidJsonDocument}!void {
    if (!@import("workflow_inventory.zig").validPath(document.path) or !std.unicode.utf8ValidateSlice(document.content)) return error.InvalidJsonDocument;
}
fn locationValid(location: Location) error{InvalidJsonDocument}!void {
    if (workflow.WorkflowStepId.parse(location.step) == null or location.chain.len == 0) return error.InvalidJsonDocument;
    for (location.chain, 0..) |entry, index| {
        if (workflow.WorkflowStepId.parseLocal(entry.id) == null or entry.declaration.len == 0 or !std.unicode.utf8ValidateSlice(entry.declaration)) return error.InvalidJsonDocument;
        if (entry.subgraph) |scope| {
            if (workflow.WorkflowStepId.parseLocal(scope) == null or index == 0) return error.InvalidJsonDocument;
            if (!std.mem.eql(u8, location.chain[index - 1].target, scope)) return error.InvalidJsonDocument;
        } else if (index != 0) return error.InvalidJsonDocument;
        if (index + 1 == location.chain.len) {
            if (entry.kind != .operation or workflow.OperationId.parse(entry.target) == null) return error.InvalidJsonDocument;
        } else if (entry.kind != .subgraph or workflow.WorkflowStepId.parseLocal(entry.target) == null) return error.InvalidJsonDocument;
    }
}
