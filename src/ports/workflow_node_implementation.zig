const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow_registry.zig");

pub const Error = error{NodeExecutionFailed};

pub const InvocationInput = struct {
    arguments: []const []const u8,
};

pub const NodeInput = struct {
    node: *const workflow.CompiledNode,
    log: pipeline.WorkflowLog,
};

pub const InvocationImplementation = struct {
    contract_id: []const u8,
    context: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque, InvocationInput) Error!execution.Candidate,

    pub fn invoke(self: InvocationImplementation, input: InvocationInput) Error!execution.Candidate {
        return self.invoke_fn(self.context, input);
    }
};

pub const NodeImplementation = struct {
    contract_id: []const u8,
    context: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque, NodeInput) Error!execution.Candidate,

    pub fn invoke(self: NodeImplementation, input: NodeInput) Error!execution.Candidate {
        return self.invoke_fn(self.context, input);
    }
};

pub const Registry = struct {
    invocations: []const InvocationImplementation,
    nodes: []const NodeImplementation,

    pub fn resolveInvocation(self: Registry, id: workflow.RegisteredRef) ?InvocationImplementation {
        var found: ?InvocationImplementation = null;
        for (self.invocations) |implementation| {
            if (!@import("std").mem.eql(u8, implementation.contract_id, id.bytes)) continue;
            if (found != null) return null;
            found = implementation;
        }
        return found;
    }

    pub fn resolveNode(self: Registry, id: workflow.RegisteredRef) ?NodeImplementation {
        var found: ?NodeImplementation = null;
        for (self.nodes) |implementation| {
            if (!@import("std").mem.eql(u8, implementation.contract_id, id.bytes)) continue;
            if (found != null) return null;
            found = implementation;
        }
        return found;
    }

    pub fn matchesCompiler(self: Registry, compiler: workflow.CompilerRegistry) bool {
        if (self.invocations.len != compiler.invocations.len or self.nodes.len != compiler.nodes.len) return false;
        for (compiler.invocations) |contract| {
            const id = workflow.RegisteredRef.parse(contract.id) orelse return false;
            _ = self.resolveInvocation(id) orelse return false;
        }
        for (compiler.nodes) |contract| {
            const id = workflow.RegisteredRef.parse(contract.id) orelse return false;
            _ = self.resolveNode(id) orelse return false;
        }
        return true;
    }
};
