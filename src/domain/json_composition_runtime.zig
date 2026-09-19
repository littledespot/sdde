//! Pure execution-local composition. The caller retains the immutable packet,
//! compiled graph and schema evidence owners; allocations belong to its arena.
//! No provider invocation, retry, token, publication or persistence authority.
const std = @import("std");
const composition = @import("json_composition.zig");
const schema = @import("model_result_schema.zig");
const payload = @import("model_payload_schema.zig");
const envelope = @import("model_envelope.zig");
const identity = @import("model_request_identity.zig");
const packets = @import("model_input_packet.zig");
const Origin = @import("model_candidate_origin.zig").Origin;

pub const Error = error{ InvalidCompositionBinding, ConflictingCompositionPart, IncompleteComposition, InvalidAssembledCandidate } || std.mem.Allocator.Error;
pub const Prerequisite = struct { part: usize, origin: Origin };
pub const Binding = struct {
    plan: *const composition.Plan,
    part: usize,
    base: *const packets.Packet,
    epoch: identity.StageRunEpochId,
    schema: *const schema.Schema,
    prerequisites: []const Prerequisite,

    pub fn valid(self: Binding) bool {
        if (self.part >= self.plan.parts().len) return false;
        var expected: usize = 0;
        for (self.plan.parts(), 0..) |_, index| {
            if (!self.plan.dependsOn(self.part, index)) continue;
            expected += 1;
            var found = false;
            for (self.prerequisites) |required| {
                if (required.part != index) continue;
                if (found or required.origin.request.value == 0 or required.origin.attempt.value == 0) return false;
                found = true;
            }
            if (!found) return false;
        }
        if (expected != self.prerequisites.len) return false;
        for (self.plan.parts()[self.part].alternatives) |alternative| if (alternative.schema == self.schema) return true;
        return false;
    }
};
pub const Entry = struct {
    proof: *const payload.Evidence,
    origin: Origin,
    binding: Binding,
};
pub const State = struct {
    plan: *const composition.Plan,
    base: *const packets.Packet,
    epoch: identity.StageRunEpochId,
    entries: []const ?Entry = &.{},
    origin: ?Origin = null,

    pub fn init(allocator: std.mem.Allocator, plan: *const composition.Plan, base: *const packets.Packet, epoch: identity.StageRunEpochId) Error!State {
        const entries = try allocator.alloc(?Entry, plan.parts().len);
        @memset(entries, null);
        return .{ .plan = plan, .base = base, .epoch = epoch, .entries = entries };
    }
    pub fn select(self: State, allocator: std.mem.Allocator, part: usize) Error!Binding {
        if (part >= self.plan.parts().len or self.getEntry(part) != null) return error.InvalidCompositionBinding;
        var prerequisites: std.ArrayList(Prerequisite) = .empty;
        var input_values: std.ArrayList(composition.PartValue) = .empty;
        for (self.plan.parts(), 0..) |_, index| {
            if (!self.plan.dependsOn(part, index)) continue;
            const entry = self.getEntry(index) orelse return error.IncompleteComposition;
            try prerequisites.append(allocator, .{ .part = index, .origin = entry.origin });
            try input_values.append(allocator, .{ .part = index, .value = entry.proof.candidate().json().* });
        }
        return .{
            .plan = self.plan,
            .part = part,
            .base = self.base,
            .epoch = self.epoch,
            .schema = self.plan.selectSchema(part, input_values.items) catch return error.InvalidCompositionBinding,
            .prerequisites = try prerequisites.toOwnedSlice(allocator),
        };
    }
    /// Read only configured prerequisite responses. Sibling placement changes
    /// neither these dependencies nor the exact schema selected from them.
    pub fn inputs(self: State, allocator: std.mem.Allocator, binding: Binding) Error!std.json.Value {
        try self.checkBinding(binding);
        var result: std.json.ObjectMap = .{};
        for (binding.prerequisites) |required| {
            const source = self.getEntry(required.part).?;
            try result.put(allocator, self.plan.parts()[required.part].id.bytes, source.proof.candidate().json().*);
        }
        return .{ .object = result };
    }
    pub fn retain(self: State, allocator: std.mem.Allocator, binding: Binding, proof: *const payload.Evidence, origin: Origin, ledger: *const identity.ModelRequestIdentityLedger) Error!State {
        try self.checkBinding(binding);
        const candidate = proof.candidate();
        const request = candidate.association().request();
        const accepted = Origin.fromAccepted(ledger, proof) orelse return error.InvalidCompositionBinding;
        if (!sameOrigin(origin, accepted) or !self.epoch.eql(ledger.stageRunEpochId()) or request.response_schema != binding.schema) return error.InvalidCompositionBinding;
        _ = identity.validateBinding(ledger, ledger.revision(), request.model_request_id, self.base.unit(), request.model_request_id.model_operation_id, self.base.purpose()) catch return error.InvalidCompositionBinding;
        if (self.getEntry(binding.part)) |existing| {
            const current_bytes = candidate.association().result().complete.content();
            const existing_bytes = existing.proof.candidate().association().result().complete.content();
            if (!sameOrigin(existing.origin, origin) or !std.mem.eql(u8, current_bytes, existing_bytes)) return error.ConflictingCompositionPart;
            return self;
        }
        const entries = try allocator.alloc(?Entry, self.plan.parts().len);
        @memset(entries, null);
        @memcpy(entries[0..self.entries.len], self.entries);
        const retained_prerequisites = try allocator.dupe(Prerequisite, binding.prerequisites);
        var retained_binding = binding;
        retained_binding.prerequisites = retained_prerequisites;
        entries[binding.part] = .{ .proof = proof, .origin = origin, .binding = retained_binding };
        return .{ .plan = self.plan, .base = self.base, .epoch = self.epoch, .entries = entries, .origin = self.origin orelse origin };
    }
    pub fn assemble(self: State, allocator: std.mem.Allocator) Error!Candidate {
        if (self.entries.len != self.plan.parts().len or self.origin == null) return error.IncompleteComposition;
        var result: std.json.Value = .{ .object = .{} };
        for (self.entries, 0..) |optional, index| {
            const entry = optional orelse return error.IncompleteComposition;
            try self.checkBinding(entry.binding);
            const value = entry.proof.candidate().json().*;
            for (self.plan.parts()[index].paths) |path| {
                try place(allocator, &result, path.segments, value);
            }
        }
        return .{ .body = try std.json.Stringify.valueAlloc(allocator, result, .{}), .base = self.base, .origin = self.origin.?, .plan = self.plan, .entries = self.entries, .value = result };
    }
    pub fn getEntry(self: State, index: usize) ?Entry {
        return if (index < self.entries.len) self.entries[index] else null;
    }
    fn checkBinding(self: State, binding: Binding) Error!void {
        if (!binding.valid() or binding.plan != self.plan or binding.base != self.base or !binding.epoch.eql(self.epoch)) return error.InvalidCompositionBinding;
        var expected: usize = 0;
        var input_values: [schema.max_properties]composition.PartValue = undefined;
        for (self.plan.parts(), 0..) |_, index| {
            if (!self.plan.dependsOn(binding.part, index)) continue;
            expected += 1;
            const current = self.getEntry(index) orelse return error.InvalidCompositionBinding;
            input_values[expected - 1] = .{ .part = index, .value = current.proof.candidate().json().* };
            var matched = false;
            for (binding.prerequisites) |required| {
                if (required.part != index) continue;
                if (matched or !sameOrigin(required.origin, current.origin)) return error.InvalidCompositionBinding;
                matched = true;
            }
            if (!matched) return error.InvalidCompositionBinding;
        }
        if (binding.prerequisites.len != expected) return error.InvalidCompositionBinding;
        const selected = self.plan.selectSchema(binding.part, input_values[0..expected]) catch return error.InvalidCompositionBinding;
        if (selected != binding.schema) return error.InvalidCompositionBinding;
    }
};

pub const Candidate = struct {
    body: []const u8,
    base: *const packets.Packet,
    origin: Origin,
    plan: *const composition.Plan,
    entries: []const ?Entry,
    value: std.json.Value,

    /// A successful part alone never proves the complete candidate's shape.
    pub fn validate(self: Candidate) ?payload.Diagnostic {
        return payload.validateValue(envelope.value(&self.value), self.plan.resultSchema().root());
    }

    pub fn producer(self: Candidate, segments: []const []const u8) ?Origin {
        const path: composition.Pointer = .{ .segments = segments };
        _ = composition.lookup(self.value, path) orelse return null;
        var result: ?Origin = null;
        for (self.plan.parts(), self.entries) |part, entry| {
            for (part.paths) |selected| {
                // Structural parents have no invented producer. Attribute a
                // present subtree only when all its contributing values agree.
                if (!selected.isPrefixOf(path) and !(path.isPrefixOf(selected) and composition.lookup(self.value, selected) != null)) continue;
                const producer_origin = (entry orelse return null).origin;
                if (result) |prior| if (!sameOrigin(prior, producer_origin)) return null;
                result = producer_origin;
            }
        }
        return result;
    }
};

fn place(allocator: std.mem.Allocator, destination: *std.json.Value, segments: []const []const u8, source: std.json.Value) Error!void {
    if (segments.len == 0 or destination.* != .object or source != .object) return error.InvalidAssembledCandidate;
    const name = segments[0];
    const selected = source.object.get(name) orelse return;
    if (segments.len == 1) {
        if (destination.object.contains(name)) return error.InvalidAssembledCandidate;
        try destination.object.put(allocator, name, selected);
        return;
    }
    // Selected descendants can be optional even when their structural parent
    // is required. Preserve that admitted container when every leaf is absent.
    // Optional containers are selected whole, so their absence never enters here.
    const inserted = try destination.object.getOrPut(allocator, name);
    if (!inserted.found_existing) inserted.value_ptr.* = .{ .object = .{} };
    try place(allocator, inserted.value_ptr, segments[1..], selected);
}

fn sameOrigin(left: Origin, right: Origin) bool {
    return left.request.value == right.request.value and left.attempt.value == right.attempt.value and left.kind == right.kind;
}
