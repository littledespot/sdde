const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const toolchain = @import("../domain/toolchain.zig");
const safety = @import("../domain/toolchain_safety.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const schemas = @import("toolchain_workflow_values.zig");
const publish = @import("workflow_candidate.zig").publish;

// Each binding runs exactly one action. YAML, not this module, owns their order.
pub const CaptureProject = struct {
    pub const Action = @import("../actions/toolchain/capture_project_toolchain.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator()) catch return failed();
        return publish(self.allocator, schemas.project_capture, toolchain.Capture, result);
    }
};
pub const InventoryPresets = struct {
    pub const Action = @import("../actions/toolchain/inventory_toolchain_presets.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator()) catch return failed();
        return publish(self.allocator, schemas.preset_inventory, []const toolchain.Entry, result);
    }
};
pub const CapturePresets = struct {
    pub const Action = @import("../actions/toolchain/capture_toolchain_presets.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const project = values.read(&input.step.data, schemas.project_capture, toolchain.Capture) catch return failed();
        const entries = values.read(&input.step.data, schemas.preset_inventory, []const toolchain.Entry) catch return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), project.*, entries.*) catch return failed();
        return publish(self.allocator, schemas.preset_captures, []const toolchain.Capture, result);
    }
};
pub const ParseDocuments = struct {
    pub const Action = @import("../actions/toolchain/parse_toolchain_documents.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const project = values.read(&input.step.data, schemas.project_capture, toolchain.Capture) catch return failed();
        const presets = values.read(&input.step.data, schemas.preset_captures, []const toolchain.Capture) catch return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), project.*, presets.*) catch return failed();
        return publish(self.allocator, schemas.raw_documents, []const toolchain.RawDocument, result);
    }
};
pub const ValidateProject = struct {
    pub const Action = @import("../actions/toolchain/validate_project_toolchain_schema.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const documents = values.read(&input.step.data, schemas.raw_documents, []const toolchain.RawDocument) catch return failed();
        if (documents.len == 0) return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), documents.*[0]) catch return failed();
        return publish(self.allocator, schemas.project, toolchain.Project, result);
    }
};
pub const ValidateRegistry = struct {
    pub const Action = @import("../actions/toolchain/validate_toolchain_preset_registry.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const documents = values.read(&input.step.data, schemas.raw_documents, []const toolchain.RawDocument) catch return failed();
        if (documents.len == 0) return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), documents.*[1..]) catch return failed();
        return publish(self.allocator, schemas.registry, toolchain.Registry, result);
    }
};
pub const ResolveInheritance = struct {
    pub const Action = @import("../actions/toolchain/resolve_toolchain_inheritance.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const project = values.read(&input.step.data, schemas.project, toolchain.Project) catch return failed();
        const registry = values.read(&input.step.data, schemas.registry, toolchain.Registry) catch return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), project.*, registry.*) catch return failed();
        return publish(self.allocator, schemas.resolved, toolchain.Resolved, result);
    }
};
pub const Compose = struct {
    pub const Action = @import("../actions/toolchain/compose_toolchain.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const project = values.read(&input.step.data, schemas.project, toolchain.Project) catch return failed();
        const resolved = values.read(&input.step.data, schemas.resolved, toolchain.Resolved) catch return failed();
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), project.*, resolved.*) catch return failed();
        return publish(self.allocator, schemas.composed, toolchain.Composed, result);
    }
};
pub const ValidateSafety = struct {
    pub const Action = @import("../actions/toolchain/validate_toolchain_safety.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const composed = values.read(&input.step.data, schemas.composed, toolchain.Composed) catch return failed();
        const owner = self.action.execute(self.allocator, composed.*) catch return failed();
        const result = values.adopt(self.allocator, schemas.valid, safety.ValidToolchain, safety.Owner, owner, safety.value, safety.deinitOwner, safety.retainedBytes(owner)) catch {
            safety.deinitOwner(owner);
            return failed();
        };
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schemas.valid.key)] = result;
        return .{ .outcome = .ok, .delta = delta };
    }
};

fn failed() operations.Error {
    return error.OperationExecutionFailed;
}
