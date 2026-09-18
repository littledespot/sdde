//! Scoped repair of mechanically invalid review data, never of a negative verdict.
pub fn Contract(comptime purpose: @import("specification_support.zig").Purpose) type {
    return struct {
        const std = @import("std");
        const review = @import("specification_support.zig").Contract(purpose);
        const admission = if (purpose == .source) @import("specification_support_evidence.zig") else @import("principle_assessment.zig");
        const authority = @import("required_authority.zig");
        const evidence = @import("reference_evidence.zig");
        const shared = @import("atomic_repair.zig");
        const p = @import("specification_provenance.zig");
        const packets = @import("model_input_packet.zig");
        const Origin = @import("model_candidate_origin.zig").Origin;
        const retry = @import("workflow_retry.zig");
        const Target = struct {
            requirement: authority.Id,
            ordinal: u32,
            index: usize,
            pub fn guidance(self: Target) struct { requirement_ordinal: u32 } {
                return .{ .requirement_ordinal = self.ordinal };
            }
        };
        const Selection = if (purpose == .principles) struct { citations: []const @import("principle_registry.zig").Citation } else struct { provenance: @import("specification.zig").Selection, source_ids: []const @import("reference_identity.zig").SourceId };
        pub const Replacement = union(enum) { finding: review.Value, selection: Selection, detail: struct { detail: []const u8 } };
        const Facts = struct { inputs: authority.Inputs, sources: evidence.Inputs, candidate: review.Candidate };
        const Rule = struct {
            rejection: review.Diagnostic,
            finding: ?review.Value,
            pub fn guidance(self: @This()) struct { issue: review.Issue, evidence_issue: ?admission.Issue, evidence_rule: ?admission.Rule.Guidance, finding: ?review.Value } {
                return .{ .issue = self.rejection.issue, .evidence_issue = if (self.rejection.evidence) |value| value.issue else null, .evidence_rule = if (self.rejection.evidence) |value| value.rule.guidance() else null, .finding = self.finding };
            }
        };
        const atomic = shared.Contract(Target, Replacement, Facts, Rule);
        pub const Authorization = atomic.Authorization;
        pub const State = struct { authorization: Authorization, response: ?struct { value: Replacement, origin: ?Origin } = null };
        pub const Error = review.Error || atomic.Error || @import("repair_occurrences.zig").Error || error{UnsafeSupportRepair};
        const Family = enum { assignment, evidence, detail, duplicate };
        const StableTarget = struct { requirement: authority.Id, occurrence: ?@import("repair_occurrences.zig").Id = null };

        fn bindRetry(a: std.mem.Allocator, authorization: Authorization) Error!Authorization {
            var result = authorization;
            const candidate = authorization.dependencies.candidate;
            const family: Family = switch (authorization.operation) {
                .insert => .assignment,
                .delete => .duplicate,
                .replace => |value| switch (value) {
                    .finding => .assignment,
                    .selection => .evidence,
                    .detail => .detail,
                },
            };
            const target: StableTarget = .{ .requirement = authorization.target.requirement, .occurrence = if (family == .duplicate) try candidate.occurrences.at(authorization.target.index, candidate.review.entries.len) else null };
            const ledger = try authority.build(a, authorization.dependencies.inputs);
            const count = std.math.add(usize, std.math.mul(usize, ledger.requirements.len, 3) catch return error.InvalidAtomicRepair, candidate.review.entries.len) catch return error.InvalidAtomicRepair;
            var permit = try shared.permit(StableTarget, Family, a, authorization.owner, target, family, authorization.id, authorization.revision, std.math.cast(u32, count) orelse return error.InvalidAtomicRepair);
            const Scope = struct { owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, purpose: @import("specification_support.zig").Purpose, origin: ?Origin };
            permit.key.scope = (try shared.snapshot(Scope, a, .{ .owner = authorization.owner, .purpose = purpose, .origin = candidate.origin })).bytes;
            if (candidate.last_repair) |last| if (last.retry) |prior| {
                if (!std.mem.eql(u8, &prior.key.scope, &permit.key.scope)) return error.InvalidAtomicRepair;
                permit.maximum_targets = prior.maximum_targets;
            };
            result.retry = permit;
            return result;
        }

        /// Full collection validation has already run; inspect the selected native
        /// family across all diagnostics, never just the next selected diagnostic.
        pub fn progress(authorization: Authorization, result: review.Collection) retry.Validation {
            if (result == .accepted or authorization.operation == .delete) return .resolved;
            for (result.rejected.rejection.diagnostics) |issue| {
                if (issue.requirement == null or !std.meta.eql(issue.requirement.?, authorization.target.requirement)) continue;
                const unresolved = switch (authorization.operation) {
                    .insert => issue.issue == .missing_requirement,
                    .replace => |value| switch (value) {
                        .finding => true,
                        .selection => issue.issue == .invalid_evidence,
                        .detail => issue.issue == .invalid_detail,
                    },
                    .delete => unreachable,
                };
                if (unresolved) return .recurring;
            }
            return .resolved;
        }

        pub fn authorize(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, rejected: @FieldType(review.Collection, "rejected")) Error!Authorization {
            const candidate = rejected.candidate orelse return error.UnsafeSupportRepair;
            const current = try review.validate(a, inputs, context.inputs, candidate);
            if (current != .rejected or !std.meta.eql(try shared.snapshot(review.Rejection, a, current.rejected.rejection), try shared.snapshot(review.Rejection, a, rejected.rejection))) return error.InvalidAtomicRepair;
            const rejection = rejected.rejection.selected() orelse return error.InvalidAtomicRepair;
            if (purpose == .source) if (rejection.evidence) |invalid| if (invalid.issue == .invalid_loss) return error.UnsafeSupportRepair;
            const id = rejection.requirement orelse return error.UnsafeSupportRepair;
            if (authority.policy(id) == null) return error.UnsafeSupportRepair;
            const ordinal = rejection.ordinal orelse return error.UnsafeSupportRepair;
            const base = try review.packet(a, inputs, context);
            defer packets.release(base);
            const facts: Facts = .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate };
            if (rejection.issue == .missing_requirement) return bindRetry(a, try atomic.authorizeInsert(a, base.unit(), candidate.revision, .{ .requirement = id, .ordinal = ordinal, .index = candidate.review.entries.len }, .finding, facts, .{ .rejection = rejection, .finding = null }));
            const first = for (candidate.review.entries, 0..) |finding, index| {
                if (finding.requirement_ordinal == ordinal) break index;
            } else return error.InvalidAtomicRepair;
            var target: Target = .{ .requirement = id, .ordinal = ordinal, .index = first };
            const value = candidate.review.entries[first].value;
            if (rejection.issue == .duplicate_requirement) {
                for (candidate.review.entries[first + 1 ..], first + 1..) |finding, index| {
                    if (finding.requirement_ordinal != ordinal) continue;
                    if (!try atomic.equal(a, .{ .finding = value }, .{ .finding = finding.value })) return error.UnsafeSupportRepair;
                    target.index = index;
                    return bindRetry(a, try atomic.authorizeDelete(a, base.unit(), candidate.revision, target, .{ .finding = value }, facts, .{ .rejection = rejection, .finding = value }));
                }
                return error.InvalidAtomicRepair;
            }
            const expected: Replacement = switch (rejection.issue) {
                .invalid_detail => .{ .detail = .{ .detail = value.detail } },
                .invalid_evidence => .{ .selection = selection(value) },
                .invalid_json, .unknown_requirement, .duplicate_requirement, .missing_requirement, .invalid_decision => return error.UnsafeSupportRepair,
            };
            return bindRetry(a, try atomic.authorize(a, base.unit(), candidate.revision, target, expected, facts, .{ .rejection = rejection, .finding = value }));
        }
        pub fn packet(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: review.Candidate, authorization: Authorization) Error!*packets.Packet {
            try atomic.checkDependencies(a, authorization, .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate });
            const kind = switch (authorization.operation) {
                .replace => |value| std.meta.activeTag(value),
                .insert => |value| value,
                .delete => return error.InvalidAtomicRepair,
            };
            const base = try review.packetFor(a, inputs, context, if (kind == .finding) .{ .finding = authorization.target.requirement } else .{ .correction = authorization.target.requirement });
            defer packets.release(base);
            const definition = if (purpose == .principles) switch (kind) {
                .finding => "principle_finding",
                .selection => "principle_selection",
                .detail => "detail",
            } else if (kind == .finding and try review.applicability(inputs, authorization.target.requirement) == .review) "applicability_finding" else @tagName(kind);
            return atomic.packet(a, authorization, base, .{ .bytes = definition });
        }
        pub const parse = atomic.parse;
        pub fn merge(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: review.Candidate, authorization: Authorization, replacement: ?Replacement, origin: ?Origin) Error!review.Collection {
            const target = authorization.target;
            const base = try review.packet(a, inputs, context);
            defer packets.release(base);
            const expected: ?Replacement = if (authorization.operation == .insert) null else valueAt(candidate, target.index, std.meta.activeTag(if (authorization.operation == .replace) authorization.operation.replace else authorization.operation.delete));
            const facts: Facts = .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate };
            const merged = try atomic.checkMerge(a, base.unit(), candidate.revision, expected, facts, authorization, replacement, origin);
            var entries: std.ArrayList(review.Finding) = .empty;
            var origins: std.ArrayList(?Origin) = .empty;
            for (candidate.review.entries, candidate.origins, 0..) |finding, previous_origin, index| {
                if (authorization.operation == .delete and index == target.index) continue;
                var next = finding;
                if (authorization.operation == .replace and index == target.index) switch (try atomic.copyReplacement(a, replacement.?)) {
                    .detail => |value| next.value.detail = value.detail,
                    .selection => |value| {
                        if (purpose == .principles) next.value.citations = value.citations else {
                            next.value.provenance = value.provenance;
                            next.value.source_ids = value.source_ids;
                        }
                    },
                    .finding => return error.InvalidAtomicRepair,
                };
                try entries.append(a, next);
                try origins.append(a, if (authorization.operation == .replace and index == target.index) origin else previous_origin);
            }
            if (authorization.operation == .insert) {
                if (target.index != entries.items.len or replacement.? != .finding) return error.InvalidAtomicRepair;
                try entries.append(a, .{ .requirement_ordinal = target.ordinal, .value = (try atomic.copyReplacement(a, replacement.?)).finding });
                try origins.append(a, origin);
            }
            const occurrences = switch (authorization.operation) {
                .replace => candidate.occurrences,
                .insert => try candidate.occurrences.inserting(a, target.index, candidate.review.entries.len),
                .delete => try candidate.occurrences.deleting(a, target.index, candidate.review.entries.len),
            };
            return review.validate(a, inputs, context.inputs, .{ .review = .{ .entries = try entries.toOwnedSlice(a) }, .revision = merged.revision_after, .origin = candidate.origin, .origins = try origins.toOwnedSlice(a), .last_repair = merged, .occurrences = occurrences });
        }
        fn valueAt(candidate: review.Candidate, index: usize, kind: std.meta.Tag(Replacement)) ?Replacement {
            if (index >= candidate.review.entries.len) return null;
            const value = candidate.review.entries[index].value;
            return switch (kind) {
                .finding => .{ .finding = value },
                .detail => .{ .detail = .{ .detail = value.detail } },
                .selection => .{ .selection = selection(value) },
            };
        }

        fn selection(value: review.Value) Selection {
            return if (purpose == .principles) .{ .citations = value.citations } else .{ .provenance = value.provenance, .source_ids = value.source_ids };
        }
    };
}

pub const Source = Contract(.source);
