const std = @import("std");
const workflow = @import("workflow.zig");
const identity = @import("model_request_identity.zig");

pub const parameter_id = "retry-limit";

pub const Limit = struct {
    value: u32,

    pub fn within(self: Limit, maximum: u32) bool {
        return maximum != 0 and self.value <= maximum;
    }
};

/// Terminal evidence owns its operation name and survives graph/runner teardown.
pub const Exhaustion = struct {
    operation_name: [workflow.max_step_id_bytes]u8,
    operation_name_len: u8,
    limit: Limit,
    completed_executions: u64,

    pub const Description = struct {
        operation_instance_id: workflow.WorkflowStepId,
        retry_limit: u32,
        completed_executions: u64,
    };

    pub fn init(step: workflow.WorkflowStepId, limit: Limit, completed: u64) ?Exhaustion {
        if (workflow.WorkflowStepId.parse(step.bytes) == null or completed <= limit.value) return null;
        var result: Exhaustion = .{ .operation_name = @splat(0), .operation_name_len = @intCast(step.bytes.len), .limit = limit, .completed_executions = completed };
        @memcpy(result.operation_name[0..step.bytes.len], step.bytes);
        return result;
    }

    pub fn operation(self: *const Exhaustion) workflow.WorkflowStepId {
        return .{ .bytes = self.operation_name[0..self.operation_name_len] };
    }

    pub fn describe(self: *const Exhaustion, allocator: std.mem.Allocator) std.mem.Allocator.Error!Description {
        return .{ .operation_instance_id = .{ .bytes = try allocator.dupe(u8, self.operation().bytes) }, .retry_limit = self.limit.value, .completed_executions = self.completed_executions };
    }
};

pub const CompiledAuthority = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    operation_instance_id: workflow.WorkflowStepId,
    limit: Limit,
    scope: Scope = .operation,

    pub fn isValid(self: CompiledAuthority) bool {
        return self.workflow_version != 0 and
            workflow.WorkflowId.parse(self.workflow_id.bytes) != null and
            workflow.WorkflowStepId.parse(self.operation_instance_id.bytes) != null;
    }

    pub fn eql(left: CompiledAuthority, right: CompiledAuthority) bool {
        return left.workflow_version == right.workflow_version and
            left.limit.value == right.limit.value and
            left.scope == right.scope and
            std.mem.eql(u8, left.workflow_id.bytes, right.workflow_id.bytes) and
            std.mem.eql(u8, left.operation_instance_id.bytes, right.operation_instance_id.bytes);
    }
};

pub const Scope = enum { operation, repair, model_request };
pub const DefectCount = struct {
    key: struct { scope: []const u8, target: []const u8, family: []const u8 },
    completed_executions: u64,

    fn init(allocator: std.mem.Allocator, key: Key, completed: u64) std.mem.Allocator.Error!DefectCount {
        const scope = try allocator.dupe(u8, &std.fmt.bytesToHex(key.scope, .lower));
        errdefer allocator.free(scope);
        const target = try allocator.dupe(u8, &std.fmt.bytesToHex(key.target, .lower));
        errdefer allocator.free(target);
        const family = try allocator.dupe(u8, &std.fmt.bytesToHex(key.family, .lower));
        return .{ .key = .{ .scope = scope, .target = target, .family = family }, .completed_executions = completed };
    }

    pub fn deinit(self: DefectCount, allocator: std.mem.Allocator) void {
        allocator.free(self.key.scope);
        allocator.free(self.key.target);
        allocator.free(self.key.family);
    }
};
/// Owned read-only report projection; counts retain their independent scopes.
pub const Observation = struct {
    step: []const u8,
    limit: u32,
    scope: Scope,
    operation_executions: u64,
    defects: []const DefectCount,
    assignments: []const AssignmentCount = &.{},

    pub fn deinit(self: Observation, allocator: std.mem.Allocator) void {
        allocator.free(self.step);
        for (self.defects) |defect| defect.deinit(allocator);
        allocator.free(self.defects);
        allocator.free(self.assignments);
    }
};
pub const Role = enum { none, authorize, merge, validate, merge_validate };
/// Native repair membership uses u32 ordinals. This representational bound also
/// bounds the execution's distinct keys across multiple native scopes.
pub const maximum_repair_keys: u32 = std.math.maxInt(u32);
pub const maximum_request_assignments: u32 = std.math.maxInt(u32);

pub const AssignmentCount = struct { request: identity.RecordIndex, completed_executions: u64 };
/// Borrows canonical request identity from the runner's execution-long ledger.
pub const Assignment = struct {
    request: *const identity.ModelRequestId,
    record: identity.RecordIndex,
    parent: ?Key = null,
};

const AttemptKey = union(enum) {
    defect: Key,
    assignment: Assignment,

    fn eql(a: AttemptKey, b: AttemptKey) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .defect => |key| std.meta.eql(key, b.defect),
            .assignment => |value| std.meta.eql(value.parent, b.assignment.parent) and identity.sameAssignment(value.request, b.assignment.request),
        };
    }
};

pub fn permitsTransition(role: Role, transition: ?Transition) bool {
    const value = transition orelse return true;
    return switch (role) {
        .none => false,
        .authorize => value == .authorized,
        .merge => value == .merged,
        .validate => value == .validated,
        .merge_validate => value == .merged_validated,
    };
}

/// Native defect identity. Values, request IDs and revisions are deliberately
/// absent: changing them cannot grant another repair allowance.
pub const Key = struct {
    scope: [32]u8,
    target: [32]u8,
    family: [32]u8,
};

pub const Permit = struct {
    key: Key,
    authorization: [32]u8,
    revision: u64,
    /// Frozen native bound on distinct target/family keys in this scope.
    maximum_targets: u32,
};

pub const Validation = enum { resolved, recurring };
pub const ValidationMode = enum { native, dependent_review };
pub const Transition = union(enum) {
    authorized: Permit,
    merged: struct { permit: Permit, revision_after: u64, validation: ValidationMode = .native },
    validated: struct { permit: Permit, revision: u64, result: Validation },
    merged_validated: struct { permit: Permit, revision_after: u64, result: Validation },
};
pub const ProgressError = error{InvalidRepairProgress};
pub const StateError = std.mem.Allocator.Error || ProgressError;
pub const AttemptResult = union(enum) { allowed: u64, exhausted: u64 };

/// Runner-owned execution state. Domain owners supply authorization and validated
/// progress; only this owner counts visits. No provider-attempt ledger is copied.
pub const State = struct {
    allocator: std.mem.Allocator,
    scopes: std.ArrayList(Population) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    attempts: std.ArrayList(Attempt) = .empty,
    active: ?Active = null,
    deferred: std.ArrayList(Active) = .empty,
    revision: u64 = 0,

    const Population = struct { id: [32]u8, maximum_targets: u32, targets: u32, revision: u64 };
    const Entry = struct { key: Key, authorization: [32]u8, revision: u64 };
    const Attempt = struct { key: AttemptKey, operation_id: workflow.WorkflowStepId, limit: Limit, completed: u64 };
    const Active = struct {
        permit: Permit,
        phase: union(enum) { authorized, merged: struct { revision: u64, validation: ValidationMode }, recurring },
    };

    /// Preparation may grow capacity but does not change logical state. Commit
    /// allocates nothing, so the runner can prepare before applying its node delta.
    pub const Prepared = struct {
        owner: *const State,
        revision: u64,
        transition: Transition,
    };

    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        for (self.attempts.items) |attempt| self.allocator.free(attempt.operation_id.bytes);
        self.attempts.deinit(self.allocator);
        self.deferred.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.scopes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn currentPermit(self: *const State) ?Permit {
        return if (self.active) |active| active.permit else null;
    }

    pub fn currentDependentPermit(self: *const State) ?Permit {
        return if (self.suspendsParent()) self.active.?.permit else null;
    }

    pub fn completedAttempts(self: *const State, operation_id: workflow.WorkflowStepId, key: Key) u64 {
        return self.completed(operation_id, .{ .defect = key });
    }

    pub fn completedAssignmentAttempts(self: *const State, operation_id: workflow.WorkflowStepId, assignment: Assignment) u64 {
        return self.completed(operation_id, .{ .assignment = assignment });
    }

    fn completed(self: *const State, operation_id: workflow.WorkflowStepId, key: AttemptKey) u64 {
        for (self.attempts.items) |attempt| {
            if (attempt.key.eql(key) and std.mem.eql(u8, attempt.operation_id.bytes, operation_id.bytes)) return attempt.completed;
        }
        return 0;
    }

    pub fn observe(self: *const State, allocator: std.mem.Allocator, operation_id: workflow.WorkflowStepId) std.mem.Allocator.Error![]const DefectCount {
        var result: std.ArrayList(DefectCount) = .empty;
        errdefer {
            for (result.items) |item| item.deinit(allocator);
            result.deinit(allocator);
        }
        for (self.attempts.items) |attempt| {
            if (attempt.key != .defect or !std.mem.eql(u8, attempt.operation_id.bytes, operation_id.bytes)) continue;
            const item = try DefectCount.init(allocator, attempt.key.defect, attempt.completed);
            errdefer item.deinit(allocator);
            try result.append(allocator, item);
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn observeAssignments(self: *const State, allocator: std.mem.Allocator, operation_id: workflow.WorkflowStepId) std.mem.Allocator.Error![]const AssignmentCount {
        var result: std.ArrayList(AssignmentCount) = .empty;
        errdefer result.deinit(allocator);
        for (self.attempts.items) |attempt| {
            if (attempt.key != .assignment or !std.mem.eql(u8, attempt.operation_id.bytes, operation_id.bytes)) continue;
            try result.append(allocator, .{ .request = attempt.key.assignment.record, .completed_executions = attempt.completed });
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn prepare(self: *State, transition: Transition) StateError!Prepared {
        try self.validateTransition(transition);
        _ = std.math.add(u64, self.revision, 1) catch return error.InvalidRepairProgress;
        if (transition == .authorized) {
            const permit = transition.authorized;
            if (self.scopeIndex(permit.key.scope) == null) try self.scopes.ensureUnusedCapacity(self.allocator, 1);
            if (self.entryIndex(permit.key) == null) try self.entries.ensureUnusedCapacity(self.allocator, 1);
            if (self.suspendsParent()) try self.deferred.ensureUnusedCapacity(self.allocator, 1);
        }
        return .{ .owner = self, .revision = self.revision, .transition = transition };
    }

    pub fn commit(self: *State, prepared: Prepared) ProgressError!void {
        if (prepared.owner != self or prepared.revision != self.revision) return error.InvalidRepairProgress;
        try self.validateTransition(prepared.transition);
        const next_revision = std.math.add(u64, self.revision, 1) catch return error.InvalidRepairProgress;
        switch (prepared.transition) {
            .authorized => |permit| {
                if (self.suspendsParent()) self.deferred.appendAssumeCapacity(self.active.?);
                const scope_index = self.scopeIndex(permit.key.scope) orelse index: {
                    self.scopes.appendAssumeCapacity(.{ .id = permit.key.scope, .maximum_targets = permit.maximum_targets, .targets = 0, .revision = permit.revision });
                    break :index self.scopes.items.len - 1;
                };
                if (self.entryIndex(permit.key)) |index| {
                    self.entries.items[index].authorization = permit.authorization;
                    self.entries.items[index].revision = permit.revision;
                } else {
                    self.entries.appendAssumeCapacity(.{ .key = permit.key, .authorization = permit.authorization, .revision = permit.revision });
                    self.scopes.items[scope_index].targets += 1;
                }
                self.scopes.items[scope_index].revision = permit.revision;
                self.active = .{ .permit = permit, .phase = .authorized };
            },
            .merged => |value| {
                self.entries.items[self.entryIndex(value.permit.key).?].revision = value.revision_after;
                self.scopes.items[self.scopeIndex(value.permit.key.scope).?].revision = value.revision_after;
                self.active.?.phase = .{ .merged = .{ .revision = value.revision_after, .validation = value.validation } };
            },
            .validated => |value| {
                self.entries.items[self.entryIndex(value.permit.key).?].revision = value.revision;
                const scope = &self.scopes.items[self.scopeIndex(value.permit.key.scope).?];
                scope.revision = @max(scope.revision, value.revision);
                self.finishValidation(value.result);
            },
            .merged_validated => |value| {
                self.entries.items[self.entryIndex(value.permit.key).?].revision = value.revision_after;
                self.scopes.items[self.scopeIndex(value.permit.key.scope).?].revision = value.revision_after;
                self.finishValidation(value.result);
            },
        }
        self.revision = next_revision;
    }

    /// Returns the operation's completed count after admission, or its unchanged
    /// exhausted count. A resolved key retains every prior operation count.
    pub fn beginAttempt(self: *State, operation_id: workflow.WorkflowStepId, limit: Limit, permit: Permit) StateError!AttemptResult {
        _ = workflow.WorkflowStepId.parse(operation_id.bytes) orelse return error.InvalidRepairProgress;
        const active = self.active orelse return error.InvalidRepairProgress;
        if (!std.meta.eql(active.permit, permit) or active.phase != .authorized) return error.InvalidRepairProgress;
        return self.countAttempt(operation_id, limit, .{ .defect = permit.key });
    }

    pub fn beginAssignmentAttempt(self: *State, operation_id: workflow.WorkflowStepId, limit: Limit, assignment: Assignment) StateError!AttemptResult {
        if (assignment.request.purpose == .atomic_repair) return error.InvalidRepairProgress;
        const parent = self.currentDependentPermit();
        if (!std.meta.eql(assignment.parent, if (parent) |value| value.key else null)) return error.InvalidRepairProgress;
        return self.countAttempt(operation_id, limit, .{ .assignment = assignment });
    }

    fn countAttempt(self: *State, operation_id: workflow.WorkflowStepId, limit: Limit, key: AttemptKey) StateError!AttemptResult {
        _ = workflow.WorkflowStepId.parse(operation_id.bytes) orelse return error.InvalidRepairProgress;
        for (self.attempts.items) |*attempt| {
            if (!attempt.key.eql(key) or !std.mem.eql(u8, attempt.operation_id.bytes, operation_id.bytes)) continue;
            if (attempt.limit.value != limit.value) return error.InvalidRepairProgress;
            if (attempt.completed > limit.value) return .{ .exhausted = attempt.completed };
            const next_revision = std.math.add(u64, self.revision, 1) catch return error.InvalidRepairProgress;
            attempt.completed += 1;
            self.revision = next_revision;
            return .{ .allowed = attempt.completed };
        }
        if (key == .assignment) {
            var count: u64 = 0;
            for (self.attempts.items) |attempt| if (attempt.key == .assignment) {
                count += 1;
            };
            if (count >= maximum_request_assignments) return error.InvalidRepairProgress;
        }
        const next_revision = std.math.add(u64, self.revision, 1) catch return error.InvalidRepairProgress;
        const name = try self.allocator.dupe(u8, operation_id.bytes);
        errdefer self.allocator.free(name);
        try self.attempts.append(self.allocator, .{ .key = key, .operation_id = .{ .bytes = name }, .limit = limit, .completed = 1 });
        self.revision = next_revision;
        return .{ .allowed = 1 };
    }

    fn validateTransition(self: *const State, transition: Transition) ProgressError!void {
        switch (transition) {
            .authorized => |permit| {
                if (permit.revision == 0 or permit.maximum_targets == 0) return error.InvalidRepairProgress;
                if (self.entryIndex(permit.key) == null and self.entries.items.len >= maximum_repair_keys) return error.InvalidRepairProgress;
                if (self.active) |active| {
                    if (self.suspendsParent()) {
                        if (std.meta.eql(active.permit.key, permit.key) or self.deferred.items.len >= maximum_repair_keys) return error.InvalidRepairProgress;
                    } else {
                        if (active.phase != .recurring or !std.meta.eql(active.permit.key, permit.key)) return error.InvalidRepairProgress;
                    }
                }
                for (self.deferred.items) |parent| if (std.meta.eql(parent.permit.key, permit.key)) return error.InvalidRepairProgress;
                if (self.scopeIndex(permit.key.scope)) |index| {
                    const scope = self.scopes.items[index];
                    if (scope.maximum_targets != permit.maximum_targets or permit.revision < scope.revision) return error.InvalidRepairProgress;
                    if (self.entryIndex(permit.key) == null and scope.targets >= scope.maximum_targets) return error.InvalidRepairProgress;
                }
                if (self.entryIndex(permit.key)) |index| {
                    const previous = self.entries.items[index];
                    if (permit.revision < previous.revision or std.meta.eql(previous.authorization, permit.authorization)) return error.InvalidRepairProgress;
                }
            },
            .merged => |value| {
                const active = self.active orelse return error.InvalidRepairProgress;
                const revision_after = std.math.add(u64, value.permit.revision, 1) catch return error.InvalidRepairProgress;
                if (active.phase != .authorized or !std.meta.eql(active.permit, value.permit) or value.revision_after != revision_after) return error.InvalidRepairProgress;
            },
            .validated => |value| {
                const active = self.active orelse return error.InvalidRepairProgress;
                if (active.phase != .merged or !std.meta.eql(active.permit, value.permit)) return error.InvalidRepairProgress;
                const merged_revision = active.phase.merged.revision;
                if (switch (active.phase.merged.validation) {
                    .native => value.revision != merged_revision,
                    .dependent_review => value.revision < merged_revision,
                }) return error.InvalidRepairProgress;
            },
            .merged_validated => |value| try self.validateTransition(.{ .merged = .{ .permit = value.permit, .revision_after = value.revision_after } }),
        }
    }

    fn suspendsParent(self: *const State) bool {
        const active = self.active orelse return false;
        return active.phase == .merged and active.phase.merged.validation == .dependent_review;
    }

    fn finishValidation(self: *State, result: Validation) void {
        if (result == .resolved) self.active = self.deferred.pop() else self.active.?.phase = .recurring;
    }

    fn scopeIndex(self: *const State, id: [32]u8) ?usize {
        for (self.scopes.items, 0..) |scope, index| if (std.meta.eql(scope.id, id)) return index;
        return null;
    }

    fn entryIndex(self: *const State, key: Key) ?usize {
        for (self.entries.items, 0..) |entry, index| if (std.meta.eql(entry.key, key)) return index;
        return null;
    }
};
