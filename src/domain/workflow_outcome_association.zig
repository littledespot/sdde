//! Execution-local outcome references. Native owners remain the sole authorities
//! for requests, repair progress, reconciliation and clarification admission.
const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const identity = @import("model_request_identity.zig");
const retry = @import("workflow_retry.zig");
const provider = @import("llm_provider_operation.zig");

pub const Kind = enum { request, candidate, authority, clarification };
pub const Binding = struct {
    kind: Kind,
    subject: pipeline.DataKey,
    evidence: pipeline.DataKey,
    result: ?pipeline.DataKey = null,
};

/// Engine-owned native associations, never workflow parameters or model facts.
pub const Descriptor = union(enum) {
    independent,
    observe: Binding,
    preserve: Binding,
    request_decode: Binding,
    request_admission: Binding,
    request_protocol: Binding,
    request_closure: Binding,
    advisory_request_closure: Binding,
    repair_authorize: Binding,
    repair_merge: Binding,
    repair_validate: Binding,
    diagnostic_admission: Binding,
    authority_reconcile: Binding,
    clarification_route: Binding,
    clarification_refresh: Binding,
    advisory_completion: Binding,

    pub fn binding(self: Descriptor) ?Binding {
        return switch (self) {
            .independent => null,
            inline else => |value| value,
        };
    }

    pub fn eql(a: Descriptor, b: Descriptor) bool {
        return std.meta.eql(a, b);
    }
};

pub const OccurrenceId = struct { ordinal: u64 };
pub const NativeSubject = struct {
    kind: Kind,
    key: pipeline.DataKey,
    generation: u64,
    occurrence: u64,
};
pub const RequestSubject = provider.ProviderOperationId;
/// Request pointers borrow the runner's canonical, execution-long identity owner.
/// Native generations and occurrences are assigned by this execution's envelope.
pub const Subject = union(enum) {
    operation: OccurrenceId,
    request: RequestSubject,
    native: NativeSubject,
    repair: retry.Key,

    pub fn eql(a: Subject, b: Subject) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .native => |value| value.key == b.native.key and value.generation == b.native.generation and value.occurrence == b.native.occurrence,
            .request => |value| value.eql(b.request),
            .operation => |value| value.ordinal == b.operation.ordinal,
            .repair => |value| std.meta.eql(value, b.repair),
        };
    }
};
pub const Observation = struct {
    subject: Subject,
    outcome: workflow.OutcomeTag,
    /// A recurring native validation carries its exact authorized repair key.
    /// The runner validates this transition against the canonical retry owner.
    repair_progress: ?retry.Transition = null,
};
pub const RepairContinuation = struct {
    owner: *const retry.State,
    permit: retry.Permit,
    mode: enum { atomic_repair, dependent_regeneration } = .atomic_repair,
};
/// The runner projects this closed native decision only from the registered
/// diagnostic owner's sealed accepted result, never from an operation's .ok.
pub const DiagnosticAdmission = @import("workflow_gate.zig").Decision;
/// References to the current native authorizer's retained blocked result. The
/// application projects this only from that owner's sealed result, not a tag.
pub const BlockedRepairEvidence = struct {
    subject: NativeSubject,
    result: NativeSubject,
};
pub const Resolution = union(enum) {
    request_admitted: Subject,
    repair_resolved: struct { subject: Subject, transition: retry.Transition },
    authority_reconciled: Subject,
    diagnostic_admitted: struct { subject: Subject, evidence: DiagnosticAdmission },
    clarification_routed: struct { subject: Subject, needs: Subject },
    /// The application proves the sealed advisory request and native stopped
    /// assessment before proposing this narrow retirement of optional work.
    advice_stopped: struct { subject: Subject, request: provider.ProviderOperationId, permit: ?retry.Permit = null },
};
pub const Change = union(enum) {
    observe: Observation,
    preserve: Subject,
    associate: struct { source: Subject, target: Subject },
    authorize: struct { subject: Subject, transition: retry.Transition },
    reclassify: union(enum) {
        missing_final_text: *const @import("provider_invocation_validation.zig").Evidence,
        authority_result: struct { subject: Subject, result: *const @import("required_authority.zig").Result },
        clarification_result: struct { subject: Subject, result: *const @import("clarification_refresh.zig").Result },
        repair_blocked: BlockedRepairEvidence,
    },
    seal: Observation,
    /// The native closure owner proves an advisory inference request failed.
    /// Its internal routing tag does not change that retained logical fact.
    advisory_request_failed: provider.ProviderOperationId,
    resolve: Resolution,
};
pub const Error = std.mem.Allocator.Error || error{ InvalidOutcomeAssociation, UnresolvedOperationOutcome };

pub fn prohibiting(outcome: workflow.OutcomeTag) bool {
    return switch (outcome) {
        .ok, .more => false,
        .invalid, .needs_user, .blocked, .failed, .cancelled => true,
    };
}

const Entry = struct {
    observation: Observation,
    irreversible: bool = false,
    deferred_advice: bool = false,
    repair_key: ?retry.Key = null,
};
const Association = struct { source: Subject, target: Subject };

/// One reference-only control projection owned by the existing envelope. It does
/// not copy native records, count retries, or authorize native resolutions.
pub const State = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    associations: std.ArrayList(Association) = .empty,
    revision: u64 = 0,

    pub const Prepared = struct {
        owner: *const State,
        revision: u64,
        entries: std.ArrayList(Entry),
        associations: std.ArrayList(Association),
        owns_storage: bool,

        pub fn deinit(self: *Prepared) void {
            if (self.owns_storage) {
                self.entries.deinit(self.owner.allocator);
                self.associations.deinit(self.owner.allocator);
            }
            self.* = undefined;
        }

        pub fn compatible(self: *const Prepared, terminal: workflow.OutcomeTag) bool {
            if (self.owner.revision != self.revision) return false;
            return compatibleEntries(self.entries.items, terminal);
        }

        pub fn firstUnresolved(self: *const Prepared) error{InvalidOutcomeAssociation}!?Observation {
            if (self.owner.revision != self.revision) return error.InvalidOutcomeAssociation;
            return if (self.entries.items.len == 0) null else self.entries.items[0].observation;
        }
    };

    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        self.entries.deinit(self.allocator);
        self.associations.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn compatible(self: *const State, terminal: workflow.OutcomeTag) bool {
        return compatibleEntries(self.entries.items, terminal);
    }

    pub fn firstUnresolved(self: *const State) ?Observation {
        return if (self.entries.items.len == 0) null else self.entries.items[0].observation;
    }

    /// Native provenance may pass through current carriers, never a historical
    /// replacement or a repair endpoint. The envelope supplies exact references.
    pub fn associatedCurrentNative(self: *const State, left: NativeSubject, right: NativeSubject, current: []const NativeSubject) bool {
        const source: Subject = .{ .native = left };
        const target: Subject = .{ .native = right };
        if (!validSubject(source) or !validSubject(target) or
            !currentNative(source, current) or !currentNative(target, current)) return false;
        return walkAssociations(self.associations.items, source, target, current);
    }

    /// Captured authorization replacements retain their exact native repair
    /// reference. The canonical retry owner validates the full merge permit.
    pub fn referencesRepair(self: *const State, evidence: NativeSubject, key: retry.Key) bool {
        const subject: Subject = .{ .native = evidence };
        return validSubject(subject) and associated(self.associations.items, subject, .{ .repair = key });
    }

    /// The native prepared output must carry each pending clarification. A
    /// matching terminal tag alone cannot authorize a protected writer.
    pub fn permitsPublication(self: *const State, current: NativeSubject, terminal: workflow.OutcomeTag) bool {
        const subject: Subject = .{ .native = current };
        if (!validSubject(subject) or current.kind != .clarification or
            (terminal != .ok and terminal != .needs_user) or !self.compatible(terminal)) return false;
        for (self.entries.items) |entry| {
            if (entry.observation.subject != .native or entry.observation.subject.native.kind != .clarification or
                !associated(self.associations.items, entry.observation.subject, subject)) return false;
        }
        return true;
    }

    pub fn permitsDiagnosticAdmission(self: *const State, subject: Subject) bool {
        if (subject != .native or subject.native.kind != .candidate or !validSubject(subject)) return false;
        for (self.entries.items) |entry| {
            if (!associated(self.associations.items, entry.observation.subject, subject)) continue;
            if (entry.irreversible or entry.observation.outcome != .invalid) return false;
            if (entry.repair_key != null) return false;
        }
        return true;
    }

    /// Protocol, repair and dependent calls cover each pending subject exactly.
    /// The runner validates current request, permit and native packet evidence.
    pub fn permitsRequest(self: *const State, request: *const identity.ModelRequestId, correction: ?provider.ProviderOperationId, continuation: ?RepairContinuation, packet_subjects: []const NativeSubject) bool {
        if (continuation) |value| if (value.mode == .dependent_regeneration and
            !value.owner.permitsDependentContinuation(value.permit, value.permit.key)) return false;
        if (correction) |source| {
            if (source.model_request_id != request or source.kind != .inference or source.model_attempt_ordinal.value == 0) return false;
            var rejected = false;
            for (self.entries.items) |entry| {
                if (entry.observation.subject != .request or !entry.observation.subject.request.eql(source)) continue;
                if (entry.irreversible or entry.observation.outcome != .invalid) return false;
                rejected = true;
            }
            if (!rejected) return false;
        }
        for (self.entries.items) |entry| {
            if (entry.irreversible or entry.observation.outcome == .needs_user or entry.observation.outcome == .cancelled) return false;
            if (entry.observation.subject == .request and entry.observation.subject.request.model_request_id == request and
                entry.observation.subject.request.kind == .inference and
                entry.observation.outcome == .invalid)
            {
                if (correction) |source| if (entry.observation.subject.request.model_attempt_ordinal.value <= source.model_attempt_ordinal.value) continue;
            }
            if (continuation) |value| switch (value.mode) {
                .atomic_repair => if (entry.repair_key) |key| {
                    if (value.owner.permitsContinuation(value.permit, key)) continue;
                },
                .dependent_regeneration => {
                    if (entry.observation.subject != .native or entry.observation.outcome == .failed) return false;
                    if (entry.repair_key) |key| {
                        if (!value.owner.permitsDependentContinuation(value.permit, key)) return false;
                    } else if (request.purpose != .semantic_review) return false;
                    // Native dependent validation grants continuation only for
                    // affected inputs. A scoped semantic review may also
                    // diagnose its own unbound invalid or blocked candidate.
                    if (coveredBy(self.associations.items, entry.observation.subject, packet_subjects)) continue;
                    return false;
                },
            };
            if (entry.observation.subject == .native and entry.observation.outcome != .failed and entry.repair_key == null) {
                if (coveredBy(self.associations.items, entry.observation.subject, packet_subjects)) continue;
            }
            return false;
        }
        return true;
    }

    /// Prepare references before the envelope applies its complete delta. The
    /// allocation-free commit below advances both owners together.
    pub fn prepare(self: *State, descriptor: Descriptor, outcome: workflow.OutcomeTag, changes: []const Change) Error!Prepared {
        _ = std.math.add(u64, self.revision, 1) catch return error.InvalidOutcomeAssociation;
        if (descriptor == .advisory_request_closure and (changes.len != 1 or changes[0] != .advisory_request_failed)) return error.InvalidOutcomeAssociation;
        if (changes.len == 0) return .{ .owner = self, .revision = self.revision, .entries = self.entries, .associations = self.associations, .owns_storage = false };
        var prepared: Prepared = .{ .owner = self, .revision = self.revision, .entries = .empty, .associations = .empty, .owns_storage = true };
        errdefer prepared.deinit();
        try prepared.entries.appendSlice(self.allocator, self.entries.items);
        try prepared.associations.appendSlice(self.allocator, self.associations.items);
        for (changes) |change| try apply(self.allocator, &prepared.entries, &prepared.associations, descriptor, outcome, change);
        return prepared;
    }

    pub fn commit(self: *State, prepared: *Prepared) Error!void {
        if (prepared.owner != self or prepared.revision != self.revision) return error.InvalidOutcomeAssociation;
        const next_revision = std.math.add(u64, self.revision, 1) catch return error.InvalidOutcomeAssociation;
        if (prepared.owns_storage) {
            self.entries.deinit(self.allocator);
            self.associations.deinit(self.allocator);
            self.entries = prepared.entries;
            self.associations = prepared.associations;
        }
        prepared.entries = .empty;
        prepared.associations = .empty;
        self.revision = next_revision;
    }
};

fn compatibleEntries(entries: []const Entry, terminal: workflow.OutcomeTag) bool {
    if (terminal == .more) return false;
    for (entries) |entry| if (entry.observation.outcome != terminal) return false;
    return true;
}

fn validSubject(subject: Subject) bool {
    return switch (subject) {
        .operation => |value| value.ordinal != 0,
        .request => |value| value.model_attempt_ordinal.value != 0,
        .native => |value| value.generation != 0 and value.occurrence != 0,
        .repair => true,
    };
}

fn apply(a: std.mem.Allocator, entries: *std.ArrayList(Entry), aliases: *std.ArrayList(Association), descriptor: Descriptor, outcome: workflow.OutcomeTag, change: Change) Error!void {
    switch (change) {
        .observe, .seal => |observation| {
            if (descriptor == .advisory_request_closure) return error.InvalidOutcomeAssociation;
            if (!validSubject(observation.subject)) return error.InvalidOutcomeAssociation;
            if (observation.outcome != outcome) return error.InvalidOutcomeAssociation;
            if (descriptor == .independent and observation.subject != .operation) return error.InvalidOutcomeAssociation;
            if (change == .seal and descriptor != .request_closure) return error.InvalidOutcomeAssociation;
            const repair_key: ?retry.Key = if (observation.repair_progress) |progress| key: {
                if (descriptor != .repair_validate or change == .seal) return error.InvalidOutcomeAssociation;
                const permit = switch (progress) {
                    .validated => |value| if (value.result == .recurring) value.permit else return error.InvalidOutcomeAssociation,
                    .merged_validated => |value| if (value.changed and value.result == .recurring) value.permit else return error.InvalidOutcomeAssociation,
                    .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
                };
                if (!associated(aliases.items, observation.subject, .{ .repair = permit.key })) return error.InvalidOutcomeAssociation;
                break :key permit.key;
            } else null;
            if (!prohibiting(observation.outcome)) return;
            if (change == .seal) {
                try sealRequest(a, entries, observation, false);
                return;
            }
            const canonical_transfer = switch (descriptor) {
                .preserve, .request_admission, .request_closure, .diagnostic_admission => true,
                else => false,
            };
            if (canonical_transfer) {
                for (entries.items) |*entry| if (associated(aliases.items, entry.observation.subject, observation.subject)) {
                    if (entry.observation.outcome != observation.outcome) return error.InvalidOutcomeAssociation;
                    if (change == .seal) entry.irreversible = true;
                    return;
                };
            }
            for (entries.items) |*entry| if (entry.observation.subject.eql(observation.subject) and entry.observation.outcome == observation.outcome) {
                if (repair_key) |key| {
                    if (entry.repair_key) |existing| if (!std.meta.eql(existing, key)) return error.InvalidOutcomeAssociation;
                    entry.repair_key = key;
                }
                return;
            };
            try entries.append(a, .{ .observation = .{ .subject = observation.subject, .outcome = observation.outcome }, .irreversible = change == .seal, .repair_key = repair_key });
        },
        .advisory_request_failed => |request| {
            if (descriptor != .advisory_request_closure or !advisoryClosureRoute(descriptor.advisory_request_closure, outcome) or
                request.kind != .inference or request.model_attempt_ordinal.value == 0) return error.InvalidOutcomeAssociation;
            switch (request.model_request_id.purpose) {
                .semantic_review, .atomic_repair => {},
                .initial_generation, .context_followup, .clarification_resolution => return error.InvalidOutcomeAssociation,
            }
            try sealRequest(a, entries, .{ .subject = .{ .request = request }, .outcome = .failed }, true);
        },
        .preserve => |subject| {
            if (!validSubject(subject)) return error.InvalidOutcomeAssociation;
            if (subject == .request) {
                if (descriptor != .preserve) return error.InvalidOutcomeAssociation;
                for (entries.items) |entry| if (entry.observation.subject.eql(subject) and entry.observation.outcome != outcome)
                    return error.InvalidOutcomeAssociation;
            }
        },
        .associate => |value| {
            if (descriptor == .independent or !validSubject(value.source) or !validSubject(value.target) or
                value.source != .native or value.target != .native) return error.InvalidOutcomeAssociation;
            if (value.source.eql(value.target) or associated(aliases.items, value.source, value.target)) return;
            try aliases.append(a, .{ .source = value.source, .target = value.target });
        },
        .authorize => |value| {
            if (descriptor != .repair_authorize or (outcome != .ok and outcome != .more) or !validSubject(value.subject) or value.subject != .native) return error.InvalidOutcomeAssociation;
            const permit = switch (value.transition) {
                .authorized => |authorized| authorized,
                .merged, .validated, .merged_validated, .abandoned_advice => return error.InvalidOutcomeAssociation,
            };
            const target: Subject = .{ .repair = permit.key };
            if (!associated(aliases.items, value.subject, target)) try aliases.append(a, .{ .source = value.subject, .target = target });
            for (entries.items) |*entry| if (entry.repair_key == null and associated(aliases.items, entry.observation.subject, value.subject)) {
                entry.repair_key = permit.key;
            };
        },
        .reclassify => |classification| switch (classification) {
            .repair_blocked => |value| {
                if (descriptor != .repair_authorize or outcome != .blocked or
                    (value.subject.kind != .candidate and value.subject.kind != .authority)) return error.InvalidOutcomeAssociation;
                const binding = descriptor.repair_authorize;
                const subject: Subject = .{ .native = value.subject };
                const result: Subject = .{ .native = value.result };
                if (!validSubject(subject) or !validSubject(result) or binding.subject != value.subject.key or
                    binding.result == null or binding.result.? != value.result.key or
                    !associated(aliases.items, subject, result)) return error.InvalidOutcomeAssociation;
                for (entries.items) |*entry| if (associated(aliases.items, entry.observation.subject, subject)) {
                    if (entry.irreversible or entry.observation.subject != .native or
                        (entry.observation.outcome != .invalid and entry.observation.outcome != .blocked)) return error.InvalidOutcomeAssociation;
                    // This native result prevents recovery; it removes neither
                    // the rejected subject nor its authorized repair obligation.
                    entry.observation.outcome = .blocked;
                };
            },
            .missing_final_text => |evidence| {
                if ((descriptor != .request_decode and descriptor != .request_admission) or outcome != .invalid or !evidence.missingFinalText()) return error.InvalidOutcomeAssociation;
                const operation = evidence.operationId();
                const subject: Subject = .{ .request = operation };
                if (operation.kind != .inference) return error.InvalidOutcomeAssociation;
                for (entries.items) |*entry| if (entry.observation.subject.eql(subject)) {
                    if (entry.irreversible or (entry.observation.outcome != .failed and entry.observation.outcome != .invalid)) return error.InvalidOutcomeAssociation;
                    entry.observation.outcome = .invalid;
                };
            },
            .authority_result => |value| {
                if (descriptor != .authority_reconcile or value.subject != .native or value.subject.native.kind != .authority or !validSubject(value.subject)) return error.InvalidOutcomeAssociation;
                const canonical: workflow.OutcomeTag = switch (value.result.continuation) {
                    .all_resolved => return error.InvalidOutcomeAssociation,
                    .invalid => .invalid,
                    .needs_user => .needs_user,
                    .blocked => .blocked,
                };
                if (outcome != canonical) return error.InvalidOutcomeAssociation;
                for (entries.items) |*entry| if (associated(aliases.items, entry.observation.subject, value.subject)) {
                    if (entry.irreversible or entry.observation.outcome == .failed or entry.observation.outcome == .cancelled) return error.InvalidOutcomeAssociation;
                    entry.observation.outcome = canonical;
                };
            },
            .clarification_result => |value| {
                if (descriptor != .clarification_refresh or outcome != .blocked or value.result.* != .blocked or value.subject != .native or value.subject.native.kind != .clarification or !validSubject(value.subject)) return error.InvalidOutcomeAssociation;
                for (entries.items) |*entry| if (associated(aliases.items, entry.observation.subject, value.subject)) {
                    if (entry.irreversible or (entry.observation.outcome != .needs_user and entry.observation.outcome != .blocked)) return error.InvalidOutcomeAssociation;
                    entry.observation.outcome = .blocked;
                };
            },
        },
        .resolve => |resolution| {
            if (resolution == .advice_stopped) {
                try stopAdvice(entries, aliases, descriptor, outcome, resolution.advice_stopped);
                return;
            }
            const subject: Subject = switch (resolution) {
                .request_admitted => |value| value,
                .repair_resolved => |value| value.subject,
                .authority_reconciled => |value| value,
                .diagnostic_admitted => |value| value.subject,
                .clarification_routed => |value| value.subject,
                .advice_stopped => unreachable,
            };
            if (!validSubject(subject) or subject == .operation) return error.InvalidOutcomeAssociation;
            switch (resolution) {
                .request_admitted => if (descriptor != .request_admission or outcome != .ok or subject != .request or subject.request.kind != .inference) return error.InvalidOutcomeAssociation,
                .repair_resolved => |value| {
                    if (descriptor != .repair_validate) return error.InvalidOutcomeAssociation;
                    const permit = switch (value.transition) {
                        .validated => |progress| if (progress.result == .resolved) progress.permit else return error.InvalidOutcomeAssociation,
                        .merged_validated => |progress| if (progress.changed and progress.result == .resolved) progress.permit else return error.InvalidOutcomeAssociation,
                        .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
                    };
                    if (!associated(aliases.items, subject, .{ .repair = permit.key })) return error.InvalidOutcomeAssociation;
                },
                .authority_reconciled => if (descriptor != .authority_reconcile or outcome != .ok or subject != .native or subject.native.kind != .authority) return error.InvalidOutcomeAssociation,
                .diagnostic_admitted => |value| {
                    if (descriptor != .diagnostic_admission or outcome != .ok or subject != .native or subject.native.kind != .candidate or value.evidence != .accepted) return error.InvalidOutcomeAssociation;
                    // Native repair validation remains the sole owner once an
                    // authorized permit is associated with this subject.
                    for (entries.items) |entry| if (entry.repair_key != null and associated(aliases.items, subject, entry.observation.subject)) return error.InvalidOutcomeAssociation;
                },
                .clarification_routed => |value| {
                    if (descriptor != .clarification_route or !validSubject(value.needs) or value.needs != .native or
                        value.needs.native.kind != .clarification or (outcome != .ok and outcome != .needs_user)) return error.InvalidOutcomeAssociation;
                },
                .advice_stopped => unreachable,
            }
            var index: usize = 0;
            while (index < entries.items.len) {
                const entry = entries.items[index];
                const same_subject = if (resolution == .request_admitted)
                    requestPrefix(entry.observation.subject, subject.request)
                else
                    associated(aliases.items, entry.observation.subject, subject);
                if (!same_subject) {
                    index += 1;
                    continue;
                }
                if (resolution == .repair_resolved) {
                    const key = switch (resolution.repair_resolved.transition) {
                        .validated => |value| value.permit.key,
                        .merged_validated => |value| value.permit.key,
                        .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
                    };
                    if (entry.repair_key == null or !std.meta.eql(entry.repair_key.?, key)) {
                        index += 1;
                        continue;
                    }
                } else if (resolution == .authority_reconciled and entry.repair_key != null) {
                    index += 1;
                    continue;
                }
                if (entry.irreversible) return error.InvalidOutcomeAssociation;
                if (resolution == .request_admitted and entry.observation.outcome != .invalid) return error.InvalidOutcomeAssociation;
                if (resolution == .diagnostic_admitted and entry.observation.outcome != .invalid) return error.InvalidOutcomeAssociation;
                if (resolution == .authority_reconciled and entry.observation.outcome != .invalid and entry.observation.outcome != .blocked) return error.InvalidOutcomeAssociation;
                if (resolution == .repair_resolved and (entry.observation.outcome == .needs_user or entry.observation.outcome == .cancelled)) return error.InvalidOutcomeAssociation;
                if (resolution == .clarification_routed) {
                    if (entry.observation.outcome != .blocked and entry.observation.outcome != .needs_user) return error.InvalidOutcomeAssociation;
                    entries.items[index].observation = .{ .subject = resolution.clarification_routed.needs, .outcome = .needs_user };
                    index += 1;
                } else _ = entries.orderedRemove(index);
            }
            if (resolution == .repair_resolved) {
                const permit = switch (resolution.repair_resolved.transition) {
                    .validated => |value| value.permit,
                    .merged_validated => |value| value.permit,
                    .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
                };
                const repaired: Subject = .{ .repair = permit.key };
                var alias_index: usize = 0;
                while (alias_index < aliases.items.len) {
                    const alias = aliases.items[alias_index];
                    if (alias.source.eql(repaired) or alias.target.eql(repaired)) _ = aliases.orderedRemove(alias_index) else alias_index += 1;
                }
            }
        },
    }
}

fn sealRequest(a: std.mem.Allocator, entries: *std.ArrayList(Entry), observation: Observation, deferred_advice: bool) Error!void {
    if (observation.subject != .request or !validSubject(observation.subject)) return error.InvalidOutcomeAssociation;
    var exact = false;
    for (entries.items) |*entry| {
        if (!requestPrefix(entry.observation.subject, observation.subject.request)) continue;
        if (entry.irreversible and (entry.observation.outcome != observation.outcome or entry.deferred_advice != deferred_advice)) return error.InvalidOutcomeAssociation;
        if (entry.observation.outcome != observation.outcome and entry.observation.outcome != .invalid) return error.InvalidOutcomeAssociation;
        entry.observation.outcome = observation.outcome;
        entry.irreversible = true;
        entry.deferred_advice = deferred_advice;
        if (entry.observation.subject.eql(observation.subject)) exact = true;
    }
    if (!exact) try entries.append(a, .{ .observation = .{ .subject = observation.subject, .outcome = observation.outcome }, .irreversible = true, .deferred_advice = deferred_advice });
}

/// Distinct native witnesses retain distinct internal branches until retirement.
pub fn advisoryClosureRoute(binding: Binding, outcome: workflow.OutcomeTag) bool {
    if (binding.kind != .request or binding.subject != .prepared_model_request) return false;
    return switch (binding.evidence) {
        .model_payload_schema_result => outcome == .more,
        .accounted_model_attempt => outcome == .blocked,
        else => false,
    };
}

fn stopAdvice(entries: *std.ArrayList(Entry), aliases: *std.ArrayList(Association), descriptor: Descriptor, outcome: workflow.OutcomeTag, stopped: @FieldType(Resolution, "advice_stopped")) Error!void {
    if (descriptor != .advisory_completion or (outcome != .ok and outcome != .more) or stopped.subject != .native or
        stopped.subject.native.kind != .candidate or !validSubject(stopped.subject) or
        descriptor.advisory_completion.kind != .candidate or descriptor.advisory_completion.subject != stopped.subject.native.key or
        stopped.request.kind != .inference or stopped.request.model_attempt_ordinal.value == 0) return error.InvalidOutcomeAssociation;
    switch (stopped.request.model_request_id.purpose) {
        .semantic_review => {},
        .atomic_repair => if (stopped.permit == null) return error.InvalidOutcomeAssociation,
        else => return error.InvalidOutcomeAssociation,
    }
    if (stopped.permit) |permit| if (!associated(aliases.items, stopped.subject, .{ .repair = permit.key })) return error.InvalidOutcomeAssociation;
    var index: usize = 0;
    while (index < entries.items.len) {
        const entry = entries.items[index];
        const own_request = requestPrefix(entry.observation.subject, stopped.request);
        const own_candidate = entry.observation.subject == .native and entry.observation.subject.native.kind == .candidate and
            entry.observation.subject.native.key == stopped.subject.native.key and
            associated(aliases.items, entry.observation.subject, stopped.subject);
        const model_failure = entry.observation.outcome == .failed or entry.observation.outcome == .invalid;
        if (own_request and model_failure and (!entry.irreversible or entry.deferred_advice)) {
            _ = entries.orderedRemove(index);
            continue;
        }
        const matching_repair = if (entry.repair_key) |key| if (stopped.permit) |permit| std.meta.eql(key, permit.key) else false else true;
        if (own_candidate and entry.observation.outcome == .invalid and !entry.irreversible and matching_repair) {
            _ = entries.orderedRemove(index);
            continue;
        }
        index += 1;
    }
    if (stopped.permit) |permit| {
        const abandoned: Subject = .{ .repair = permit.key };
        var alias_index: usize = 0;
        while (alias_index < aliases.items.len) {
            const alias = aliases.items[alias_index];
            if (alias.source.eql(abandoned) or alias.target.eql(abandoned)) _ = aliases.orderedRemove(alias_index) else alias_index += 1;
        }
    }
}

fn requestPrefix(subject: Subject, admitted: RequestSubject) bool {
    return subject == .request and subject.request.model_request_id == admitted.model_request_id and
        subject.request.kind == admitted.kind and subject.request.model_attempt_ordinal.value <= admitted.model_attempt_ordinal.value;
}

/// Alias insertion joins distinct components, so this is a forest. Walk its
/// directed edges in cyclic order without recursion or a second identity index.
fn associated(aliases: []const Association, left: Subject, right: Subject) bool {
    return walkAssociations(aliases, left, right, null);
}

fn coveredBy(aliases: []const Association, pending: Subject, subjects: []const NativeSubject) bool {
    for (subjects) |subject| if (associated(aliases, pending, .{ .native = subject })) return true;
    return false;
}

fn currentNative(subject: Subject, current: []const NativeSubject) bool {
    if (subject != .native) return false;
    for (current) |value| if (subject.eql(.{ .native = value })) return true;
    return false;
}

fn walkAssociations(aliases: []const Association, left: Subject, right: Subject, current_native: ?[]const NativeSubject) bool {
    if (left.eql(right)) return true;
    var current = left;
    var previous: ?Subject = null;
    const visits = std.math.mul(usize, aliases.len, 2) catch return false;
    for (0..visits) |_| {
        var first: ?Subject = null;
        var next: ?Subject = null;
        var after_previous = previous == null;
        for (aliases) |alias| {
            if (current_native) |current_values| {
                if (!currentNative(alias.source, current_values) or !currentNative(alias.target, current_values)) continue;
            }
            const neighbor = if (alias.source.eql(current)) alias.target else if (alias.target.eql(current)) alias.source else continue;
            if (first == null) first = neighbor;
            if (after_previous) {
                next = neighbor;
                break;
            }
            if (previous) |value| {
                if (neighbor.eql(value)) after_previous = true;
            }
        }
        const target = next orelse first orelse return false;
        if (target.eql(right)) return true;
        previous = current;
        current = target;
    }
    return false;
}

pub fn validDescriptor(descriptor: Descriptor, requires: []const pipeline.DataKey, optional: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey, repair_role: retry.Role) bool {
    const binding = descriptor.binding() orelse return true;
    if (!declared(binding.subject, requires, optional, produces, replaces) or
        !declared(binding.evidence, requires, optional, produces, replaces)) return false;
    if (binding.result) |result| if (!contains(produces, result) and !contains(replaces, result)) return false;
    return switch (descriptor) {
        .request_decode, .request_admission, .request_protocol, .request_closure => binding.kind == .request and binding.subject == .prepared_model_request,
        .advisory_request_closure => binding.kind == .request and binding.subject == .prepared_model_request and
            (binding.evidence == .model_payload_schema_result or binding.evidence == .accounted_model_attempt) and
            repair_role == .none and contains(requires, .prepared_model_request) and contains(requires, .model_request_identity_ledger) and
            contains(requires, binding.evidence) and contains(replaces, .model_request_identity_ledger),
        .repair_authorize => (binding.kind == .candidate or binding.kind == .authority) and repair_role == .authorize,
        .repair_merge => binding.kind == .candidate and (repair_role == .merge or repair_role == .merge_validate),
        .repair_validate => binding.kind == .candidate and (repair_role == .validate or repair_role == .merge_validate),
        .diagnostic_admission => binding.kind == .candidate,
        .authority_reconcile => binding.kind == .authority,
        .clarification_route => binding.kind != .request,
        .clarification_refresh => binding.kind == .clarification,
        .advisory_completion => binding.kind == .candidate and repair_role == .abandon_advice and
            contains(requires, binding.subject) and contains(requires, .prepared_model_request) and
            contains(requires, .model_request_identity_ledger) and contains(requires, .accounted_model_attempt),
        .independent, .observe, .preserve => true,
    };
}

fn declared(key: pipeline.DataKey, requires: []const pipeline.DataKey, optional: []const pipeline.DataKey, produces: []const pipeline.DataKey, replaces: []const pipeline.DataKey) bool {
    return contains(requires, key) or contains(optional, key) or contains(produces, key) or contains(replaces, key);
}
fn contains(keys: []const pipeline.DataKey, key: pipeline.DataKey) bool {
    return std.mem.indexOfScalar(pipeline.DataKey, keys, key) != null;
}

test "native advisory closure seals failed authority independently of its bounded routing tag" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{ .parent_unit_owner_id = .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "plan" }, .obligation_cluster_id = .{ .bytes = "subjects" } } }, .review_slot_id = .{ .bytes = "advice" } } };
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, owner, .{ .workflow_id = .{ .bytes = "flow" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review" } }, .{ .semantic_review = .{ .bytes = "advice" } });
    defer identity.deinitOwner(request.owner);
    const operation: provider.ProviderOperationId = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference };
    for ([_]struct { key: pipeline.DataKey, route: workflow.OutcomeTag }{
        .{ .key = .model_payload_schema_result, .route = .more },
        .{ .key = .accounted_model_attempt, .route = .blocked },
    }) |witness| {
        const binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = witness.key };
        const descriptor: Descriptor = .{ .advisory_request_closure = binding };
        const change: Change = .{ .advisory_request_failed = operation };
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, witness.route, &.{}));
        var closed = try state.prepare(descriptor, witness.route, &.{change});
        defer closed.deinit();
        try std.testing.expect(closed.compatible(.failed));
        try std.testing.expect(!closed.compatible(.ok));
        try std.testing.expectEqual(.failed, closed.entries.items[0].observation.outcome);
        try std.testing.expect(closed.entries.items[0].irreversible);
        try std.testing.expect(closed.entries.items[0].deferred_advice);
        try state.commit(&closed);
        for (std.enums.values(workflow.OutcomeTag)) |other| if (other != witness.route) {
            try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, other, &.{change}));
        };
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_closure = binding }, witness.route, &.{change}));
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, witness.route, &.{.{ .observe = .{ .subject = .{ .request = operation }, .outcome = witness.route } }}));
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, witness.route, &.{.{ .seal = .{ .subject = .{ .request = operation }, .outcome = .failed } }}));
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = .{ .request = operation } } }}));
        var counting = operation;
        counting.kind = .input_token_count;
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, witness.route, &.{.{ .advisory_request_failed = counting }}));
    }
}

test "ordinary failed closure cannot borrow deferred advisory authority" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{ .parent_unit_owner_id = .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "plan" }, .obligation_cluster_id = .{ .bytes = "subjects" } } }, .review_slot_id = .{ .bytes = "advice" } } };
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, owner, .{ .workflow_id = .{ .bytes = "flow" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review" } }, .{ .semantic_review = .{ .bytes = "advice" } });
    defer identity.deinitOwner(request.owner);
    const required = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "flow" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "generation" } }, .initial_generation);
    defer identity.deinitOwner(required.owner);
    const operation: provider.ProviderOperationId = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference };
    const binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var closed = try state.prepare(.{ .request_closure = binding }, .failed, &.{.{ .seal = .{ .subject = .{ .request = operation }, .outcome = .failed } }});
    defer closed.deinit();
    try state.commit(&closed);
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_request_closure = binding }, .more, &.{.{ .advisory_request_failed = operation }}));
    var required_operation = operation;
    required_operation.model_request_id = required.model_request_id;
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_request_closure = binding }, .more, &.{.{ .advisory_request_failed = required_operation }}));
    const review_binding: Binding = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review };
    var stopped = try state.prepare(.{ .advisory_completion = review_binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = .{ .native = .{ .kind = .candidate, .key = .specification_support_review, .generation = 1, .occurrence = 1 } }, .request = operation } } }});
    defer stopped.deinit();
    try std.testing.expect(stopped.compatible(.failed));
    try std.testing.expect(!stopped.compatible(.ok));
    try std.testing.expectEqual(@as(usize, 1), stopped.entries.items.len);
    try std.testing.expect(!stopped.entries.items[0].deferred_advice);
}

test "native advisory completion retires only the exact failed request prefix and review candidate" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const review_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{ .parent_unit_owner_id = .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "plan-state" }, .obligation_cluster_id = .{ .bytes = "business-subjects" } } }, .review_slot_id = .{ .bytes = "current-advice" } } };
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, review_owner, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review" } }, .{ .semantic_review = .{ .bytes = "current-advice" } });
    defer identity.deinitOwner(request.owner);
    const binding: Binding = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .required_authority_inputs, .result = .specification_support_review };
    const request_binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result };
    const previous: Subject = .{ .native = .{ .kind = .candidate, .key = .specification_support_review, .generation = 1, .occurrence = 1 } };
    const current: Subject = .{ .native = .{ .kind = .candidate, .key = .specification_support_review, .generation = 2, .occurrence = 2 } };
    const first: Subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } };
    const second: Subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 2 }, .kind = .inference } };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var rejected = try state.prepare(.{ .observe = request_binding }, .invalid, &.{.{ .observe = .{ .subject = first, .outcome = .invalid } }});
    defer rejected.deinit();
    try state.commit(&rejected);
    var sealed = try state.prepare(.{ .advisory_request_closure = request_binding }, .more, &.{.{ .advisory_request_failed = second.request }});
    defer sealed.deinit();
    try state.commit(&sealed);
    var invalid = try state.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = previous, .outcome = .invalid } }});
    defer invalid.deinit();
    try state.commit(&invalid);
    var carried = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = previous, .target = current } }});
    defer carried.deinit();
    try state.commit(&carried);
    try std.testing.expect(!state.compatible(.ok));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = request_binding }, .ok, &.{.{ .resolve = .{ .request_admitted = second } }}));
    const resolution: Change = .{ .resolve = .{ .advice_stopped = .{ .subject = current, .request = second.request } } };
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .diagnostic_admission = binding }, .ok, &.{resolution}));
    var stopped = try state.prepare(.{ .advisory_completion = binding }, .ok, &.{resolution});
    defer stopped.deinit();
    try std.testing.expect(stopped.compatible(.ok));
    try std.testing.expectEqual(@as(usize, 0), stopped.entries.items.len);
    try state.commit(&stopped);
    try std.testing.expect(state.compatible(.ok));
}

test "advice stop preserves cancellation required work unrelated requests and native failures" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const review_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{ .parent_unit_owner_id = .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "plan-state" }, .obligation_cluster_id = .{ .bytes = "business-subjects" } } }, .review_slot_id = .{ .bytes = "current-advice" } } };
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, review_owner, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review" } }, .{ .semantic_review = .{ .bytes = "current-advice" } });
    defer identity.deinitOwner(request.owner);
    const mandatory = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "required" } }, .initial_generation);
    defer identity.deinitOwner(mandatory.owner);
    const foreign = try identity.createSuccessor(identity.ledger(initial), .initial, review_owner, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "foreign-review" } }, .{ .semantic_review = .{ .bytes = "current-advice" } });
    defer identity.deinitOwner(foreign.owner);
    const binding: Binding = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .required_authority_inputs };
    const subject: Subject = .{ .native = .{ .kind = .candidate, .key = .specification_support_review, .generation = 1, .occurrence = 1 } };
    const operation: provider.ProviderOperationId = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 2 }, .kind = .inference };
    for ([_]Observation{
        .{ .subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 3 }, .kind = .inference } }, .outcome = .invalid },
        .{ .subject = .{ .request = .{ .model_request_id = foreign.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } }, .outcome = .failed },
        .{ .subject = .{ .request = operation }, .outcome = .cancelled },
        .{ .subject = .{ .request = operation }, .outcome = .needs_user },
        .{ .subject = .{ .request = operation }, .outcome = .blocked },
        .{ .subject = subject, .outcome = .failed },
        .{ .subject = subject, .outcome = .cancelled },
        .{ .subject = subject, .outcome = .needs_user },
        .{ .subject = subject, .outcome = .blocked },
        .{ .subject = .{ .native = .{ .kind = .candidate, .key = .identified_specification_content, .generation = 2, .occurrence = 2 } }, .outcome = .invalid },
        .{ .subject = .{ .operation = .{ .ordinal = 1 } }, .outcome = .failed },
    }) |obstruction| {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        var observed = try state.prepare(if (obstruction.subject == .operation) .independent else .{ .observe = binding }, obstruction.outcome, &.{.{ .observe = obstruction }});
        defer observed.deinit();
        try state.commit(&observed);
        if (obstruction.subject == .native and !obstruction.subject.eql(subject)) {
            var joined = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = obstruction.subject, .target = subject } }});
            defer joined.deinit();
            try state.commit(&joined);
        }
        var stopped = try state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = operation } } }});
        defer stopped.deinit();
        try std.testing.expect(!stopped.compatible(.ok));
        try std.testing.expectEqual(@as(usize, 1), stopped.entries.items.len);
        try std.testing.expectEqualDeep(obstruction, stopped.entries.items[0].observation);
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = .{ .model_request_id = mandatory.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } } } }}));
        var counting = operation;
        counting.kind = .input_token_count;
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = counting } } }}));
    }
}

test "advice stop abandons only its explicit associated repair permit" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const review_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{ .parent_unit_owner_id = .{ .task_cluster = .{ .plan_state_id = .{ .bytes = "plan-state" }, .obligation_cluster_id = .{ .bytes = "business-subjects" } } }, .review_slot_id = .{ .bytes = "current-advice" } } };
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, review_owner, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review-finding-repair" } }, .{ .atomic_repair = .{ .bytes = "finding-repair" } });
    defer identity.deinitOwner(request.owner);
    const binding: Binding = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .required_authority_inputs };
    const subject: Subject = .{ .native = .{ .kind = .candidate, .key = .specification_support_review, .generation = 1, .occurrence = 1 } };
    const permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 2 };
    const operation: provider.ProviderOperationId = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var invalid = try state.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = subject, .outcome = .invalid } }});
    defer invalid.deinit();
    try state.commit(&invalid);
    var authorized = try state.prepare(.{ .repair_authorize = binding }, .ok, &.{.{ .authorize = .{ .subject = subject, .transition = .{ .authorized = permit } } }});
    defer authorized.deinit();
    try state.commit(&authorized);
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = operation } } }}));
    var foreign = permit;
    foreign.key.target = @splat(8);
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = operation, .permit = foreign } } }}));
    var stopped = try state.prepare(.{ .advisory_completion = binding }, .ok, &.{.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = operation, .permit = permit } } }});
    defer stopped.deinit();
    try std.testing.expect(stopped.compatible(.ok));
    try state.commit(&stopped);
    try std.testing.expect(!state.referencesRepair(subject.native, permit.key));
}

test "sealed blocked repair preserves its exact rejection and cannot relabel other outcome classes" {
    const source: Subject = .{ .native = .{ .kind = .candidate, .key = .parsed_reference_extraction, .generation = 1, .occurrence = 1 } };
    const result: Subject = .{ .native = .{ .kind = .candidate, .key = .reference_text_repair_authorization, .generation = 2, .occurrence = 2 } };
    const foreign: Subject = .{ .native = .{ .kind = .candidate, .key = .validated_reference_claims, .generation = 3, .occurrence = 3 } };
    const binding: Binding = .{ .kind = .candidate, .subject = source.native.key, .evidence = source.native.key, .result = result.native.key };
    const descriptor: Descriptor = .{ .repair_authorize = binding };
    const key: retry.Key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) };
    for ([_]workflow.OutcomeTag{ .invalid, .blocked, .failed, .cancelled, .needs_user }) |outcome| for ([_]bool{ false, true }) |bound| {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        var rejected = try state.prepare(.{ .observe = binding }, outcome, &.{.{ .observe = .{ .subject = source, .outcome = outcome } }});
        defer rejected.deinit();
        try state.commit(&rejected);
        var unrelated = try state.prepare(.{ .observe = .{ .kind = .candidate, .subject = foreign.native.key, .evidence = foreign.native.key } }, .invalid, &.{.{ .observe = .{ .subject = foreign, .outcome = .invalid } }});
        defer unrelated.deinit();
        try state.commit(&unrelated);
        if (bound) {
            var authorized = try state.prepare(descriptor, .ok, &.{.{ .authorize = .{ .subject = source, .transition = .{ .authorized = .{ .key = key, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 } } } }});
            defer authorized.deinit();
            try state.commit(&authorized);
        }
        const changes = [_]Change{
            .{ .associate = .{ .source = source, .target = result } },
            .{ .reclassify = .{ .repair_blocked = .{ .subject = source.native, .result = result.native } } },
        };
        const revision = state.revision;
        if (outcome != .invalid and outcome != .blocked) {
            try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, .blocked, &changes));
            try std.testing.expectEqual(revision, state.revision);
            try std.testing.expectEqual(outcome, state.entries.items[0].observation.outcome);
            continue;
        }
        var blocked = try state.prepare(descriptor, .blocked, &changes);
        defer blocked.deinit();
        try state.commit(&blocked);
        try std.testing.expectEqual(@as(usize, 2), state.entries.items.len);
        try std.testing.expect(state.entries.items[0].observation.subject.eql(source));
        try std.testing.expectEqual(workflow.OutcomeTag.blocked, state.entries.items[0].observation.outcome);
        try std.testing.expectEqual(bound, state.entries.items[0].repair_key != null);
        if (bound) try std.testing.expect(std.meta.eql(key, state.entries.items[0].repair_key.?));
        try std.testing.expect(state.entries.items[1].observation.subject.eql(foreign));
        try std.testing.expectEqual(workflow.OutcomeTag.invalid, state.entries.items[1].observation.outcome);
        try std.testing.expect(!state.compatible(.ok));
        try std.testing.expect(!state.compatible(.blocked));
        // Neither stale result references nor a different registered binding
        // can assert the native disposition, even with the same outcome tag.
        var stale_result = result.native;
        stale_result.generation += 1;
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(descriptor, .blocked, &.{.{ .reclassify = .{ .repair_blocked = .{ .subject = source.native, .result = stale_result } } }}));
        var wrong_binding = binding;
        wrong_binding.result = foreign.native.key;
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .repair_authorize = wrong_binding }, .blocked, changes[1..]));
        try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .preserve = binding }, .blocked, changes[1..]));
    };
}

test "ordinary success and unrelated native resolution retain opaque failures" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const fault: Observation = .{ .subject = .{ .operation = .{ .ordinal = 1 } }, .outcome = .failed };
    var observed = try state.prepare(.independent, .failed, &.{.{ .observe = fault }});
    defer observed.deinit();
    try state.commit(&observed);
    var noop = try state.prepare(.independent, .ok, &.{});
    defer noop.deinit();
    try std.testing.expect(!noop.compatible(.ok));
    try std.testing.expect(noop.compatible(.failed));
    const other: Subject = .{ .native = .{ .kind = .authority, .key = .required_authority_inputs, .generation = 2, .occurrence = 2 } };
    var unrelated = try state.prepare(.{ .authority_reconcile = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result } }, .ok, &.{.{ .resolve = .{ .authority_reconciled = other } }});
    defer unrelated.deinit();
    try std.testing.expect(!unrelated.compatible(.ok));
}

test "only exact validated repair resolution removes its associated failure" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const binding: Binding = .{ .kind = .candidate, .subject = .raw_engine_config, .evidence = .engine_config };
    const subject: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 1, .occurrence = 1 } };
    const key: retry.Key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) };
    const permit: retry.Permit = .{ .key = key, .authorization = @splat(4), .revision = 1, .maximum_targets = 2 };
    var observed = try state.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = subject, .outcome = .invalid } }});
    defer observed.deinit();
    try state.commit(&observed);
    try std.testing.expect(!state.referencesRepair(subject.native, key));
    var authorized = try state.prepare(.{ .repair_authorize = binding }, .ok, &.{.{ .authorize = .{ .subject = subject, .transition = .{ .authorized = permit } } }});
    defer authorized.deinit();
    try state.commit(&authorized);
    const captured: Subject = .{ .native = .{ .kind = .candidate, .key = .engine_config, .generation = 2, .occurrence = 2 } };
    const replacement: Subject = .{ .native = .{ .kind = .candidate, .key = .engine_config, .generation = 3, .occurrence = 3 } };
    var retained = try state.prepare(.{ .preserve = binding }, .ok, &.{
        .{ .associate = .{ .source = subject, .target = captured } },
        .{ .associate = .{ .source = captured, .target = replacement } },
    });
    defer retained.deinit();
    try state.commit(&retained);
    try std.testing.expect(state.referencesRepair(replacement.native, key));
    var foreign = key;
    foreign.target = @splat(5);
    try std.testing.expect(!state.referencesRepair(replacement.native, foreign));
    var unrelated = replacement.native;
    unrelated.generation += 1;
    try std.testing.expect(!state.referencesRepair(unrelated, key));
    try std.testing.expect(!state.compatible(.ok));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = subject, .transition = .{ .merged = .{ .permit = permit, .changed = true, .revision_after = 2 } } } } }}));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = subject, .transition = .{ .merged_validated = .{ .permit = permit, .changed = false, .revision_after = 2, .result = .resolved } } } } }}));
    var recurring = try state.prepare(.{ .repair_validate = binding }, .invalid, &.{});
    defer recurring.deinit();
    try std.testing.expect(!recurring.compatible(.ok));
    var resolved = try state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = subject, .transition = .{ .validated = .{ .permit = permit, .revision = 2, .result = .resolved } } } } }});
    defer resolved.deinit();
    try std.testing.expect(resolved.compatible(.ok));
    try state.commit(&resolved);
    try std.testing.expect(!state.referencesRepair(replacement.native, key));
    try std.testing.expect(state.permitsDiagnosticAdmission(subject));
}

test "native generations and exact permit keys separate parent and child failures" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const binding: Binding = .{ .kind = .candidate, .subject = .raw_engine_config, .evidence = .engine_config };
    const parent: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 1, .occurrence = 1 } };
    const child: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 2, .occurrence = 2 } };
    const parent_permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 2 };
    const child_permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(5), .family = @splat(6) }, .authorization = @splat(7), .revision = 2, .maximum_targets = 2 };
    var observed = try state.prepare(.{ .observe = binding }, .invalid, &.{
        .{ .observe = .{ .subject = parent, .outcome = .invalid } },
        .{ .observe = .{ .subject = child, .outcome = .invalid } },
    });
    defer observed.deinit();
    try state.commit(&observed);
    var authorized = try state.prepare(.{ .repair_authorize = binding }, .ok, &.{
        .{ .authorize = .{ .subject = parent, .transition = .{ .authorized = parent_permit } } },
        .{ .authorize = .{ .subject = child, .transition = .{ .authorized = child_permit } } },
    });
    defer authorized.deinit();
    try state.commit(&authorized);
    try std.testing.expect(!state.permitsDiagnosticAdmission(child));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = child, .transition = .{ .validated = .{ .permit = parent_permit, .revision = 2, .result = .resolved } } } } }}));
    var resolved = try state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = child, .transition = .{ .validated = .{ .permit = child_permit, .revision = 3, .result = .resolved } } } } }});
    defer resolved.deinit();
    try std.testing.expect(!resolved.compatible(.ok));
    try std.testing.expect(resolved.compatible(.invalid));
    try state.commit(&resolved);
    try std.testing.expect(state.permitsDiagnosticAdmission(child));
    try std.testing.expect(!state.permitsDiagnosticAdmission(parent));
}

test "joined native carriers retain parent and foreign repair obligations" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "repair" } }, .initial_generation);
    defer identity.deinitOwner(request.owner);
    const review_owner: identity.ImmutableUnitOwnerId = .{ .semantic_review = .{
        .parent_unit_owner_id = .{ .task_cluster = .{
            .plan_state_id = .{ .bytes = "plan-state-1" },
            .obligation_cluster_id = .{ .bytes = "cluster-1" },
        } },
        .review_slot_id = .{ .bytes = "review-1" },
    } };
    const review_request = try identity.createSuccessor(identity.ledger(initial), .initial, review_owner, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "review" } }, .{ .semantic_review = .{ .bytes = "review-1" } });
    defer identity.deinitOwner(review_request.owner);
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var native = retry.State.init(std.testing.allocator);
    defer native.deinit();
    const binding: Binding = .{ .kind = .candidate, .subject = .raw_engine_config, .evidence = .engine_config };
    const parent: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 1, .occurrence = 1 } };
    const child: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 2, .occurrence = 2 } };
    const foreign: Subject = .{ .native = .{ .kind = .candidate, .key = .engine_config, .generation = 3, .occurrence = 3 } };
    const parent_permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 3 };
    const child_permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(5), .family = @splat(6) }, .authorization = @splat(7), .revision = 2, .maximum_targets = 3 };
    const foreign_permit: retry.Permit = .{ .key = .{ .scope = @splat(8), .target = @splat(9), .family = @splat(10) }, .authorization = @splat(11), .revision = 1, .maximum_targets = 1 };
    var native_validation = retry.State.init(std.testing.allocator);
    defer native_validation.deinit();
    try native_validation.commit(try native_validation.prepare(.{ .authorized = child_permit }));
    try native_validation.commit(try native_validation.prepare(.{ .merged = .{ .permit = child_permit, .changed = true, .revision_after = 3 } }));
    try std.testing.expect(!native_validation.permitsDependentContinuation(child_permit, child_permit.key));
    var observed = try state.prepare(.{ .observe = binding }, .invalid, &.{
        .{ .observe = .{ .subject = parent, .outcome = .invalid } },
        .{ .observe = .{ .subject = child, .outcome = .invalid } },
    });
    defer observed.deinit();
    try state.commit(&observed);
    var authorized = try state.prepare(.{ .repair_authorize = binding }, .ok, &.{
        .{ .authorize = .{ .subject = parent, .transition = .{ .authorized = parent_permit } } },
        .{ .authorize = .{ .subject = child, .transition = .{ .authorized = child_permit } } },
    });
    defer authorized.deinit();
    try state.commit(&authorized);
    try native.commit(try native.prepare(.{ .authorized = parent_permit }));
    try native.commit(try native.prepare(.{ .merged = .{ .permit = parent_permit, .changed = true, .revision_after = 2, .validation = .dependent_review } }));
    try native.commit(try native.prepare(.{ .authorized = child_permit }));
    var joined = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = parent, .target = child } }});
    defer joined.deinit();
    try state.commit(&joined);
    try std.testing.expect(state.permitsRequest(request.model_request_id, null, .{ .owner = &native, .permit = child_permit }, &.{}));
    try std.testing.expect(!native.permitsContinuation(parent_permit, child_permit.key));
    const dependent: RepairContinuation = .{ .owner = &native, .permit = child_permit, .mode = .dependent_regeneration };
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, dependent, &.{child.native}));
    try native.commit(try native.prepare(.{ .merged = .{ .permit = child_permit, .changed = true, .revision_after = 3, .validation = .dependent_review } }));
    try std.testing.expect(native.permitsDependentContinuation(child_permit, parent_permit.key));
    try std.testing.expect(!native.permitsDependentContinuation(parent_permit, child_permit.key));
    try std.testing.expect(state.permitsRequest(request.model_request_id, null, dependent, &.{child.native}));
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, dependent, &.{}));
    try std.testing.expect(!state.compatible(.ok));
    var stale_carrier = child.native;
    stale_carrier.generation += 1;
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, dependent, &.{stale_carrier}));
    var stale_permit = child_permit;
    stale_permit.revision += 1;
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, .{ .owner = &native, .permit = stale_permit, .mode = .dependent_regeneration }, &.{child.native}));
    const own_request: Subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } };
    const request_binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result };
    var protocol_rejection = try state.prepare(.{ .observe = request_binding }, .invalid, &.{.{ .observe = .{ .subject = own_request, .outcome = .invalid } }});
    defer protocol_rejection.deinit();
    try state.commit(&protocol_rejection);
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, dependent, &.{child.native}));
    try std.testing.expect(state.permitsRequest(request.model_request_id, own_request.request, dependent, &.{child.native}));
    var protocol_admission = try state.prepare(.{ .request_admission = request_binding }, .ok, &.{.{ .resolve = .{ .request_admitted = own_request } }});
    defer protocol_admission.deinit();
    try state.commit(&protocol_admission);
    try std.testing.expectEqual(@as(usize, 2), state.entries.items.len);
    try std.testing.expect(!state.compatible(.ok));
    const Obstruction = struct { subject: Subject, outcome: workflow.OutcomeTag, bound: bool };
    var atomic_native = retry.State.init(std.testing.allocator);
    defer atomic_native.deinit();
    try atomic_native.commit(try atomic_native.prepare(.{ .authorized = child_permit }));
    for ([_]workflow.OutcomeTag{ .invalid, .blocked }) |outcome| {
        var bound_state = State.init(std.testing.allocator);
        defer bound_state.deinit();
        var rejected = try bound_state.prepare(.{ .observe = binding }, outcome, &.{.{ .observe = .{ .subject = child, .outcome = outcome } }});
        defer rejected.deinit();
        try bound_state.commit(&rejected);
        var bound = try bound_state.prepare(.{ .repair_authorize = binding }, .ok, &.{.{ .authorize = .{ .subject = child, .transition = .{ .authorized = child_permit } } }});
        defer bound.deinit();
        try bound_state.commit(&bound);
        try std.testing.expect(!bound_state.permitsRequest(review_request.model_request_id, null, null, &.{child.native}));
        try std.testing.expect(bound_state.permitsRequest(review_request.model_request_id, null, dependent, &.{child.native}));
        try std.testing.expect(!bound_state.compatible(.ok));
    }
    for ([_]Obstruction{
        .{ .subject = .{ .operation = .{ .ordinal = 1 } }, .outcome = .invalid, .bound = false },
        .{ .subject = own_request, .outcome = .invalid, .bound = false },
        .{ .subject = child, .outcome = .invalid, .bound = false },
        .{ .subject = child, .outcome = .blocked, .bound = false },
        .{ .subject = child, .outcome = .failed, .bound = true },
        .{ .subject = child, .outcome = .cancelled, .bound = true },
        .{ .subject = child, .outcome = .needs_user, .bound = true },
    }) |obstruction| {
        var blocked_state = State.init(std.testing.allocator);
        defer blocked_state.deinit();
        var pending = try blocked_state.prepare(if (obstruction.subject == .operation) .independent else .{ .observe = binding }, obstruction.outcome, &.{.{ .observe = .{ .subject = obstruction.subject, .outcome = obstruction.outcome } }});
        defer pending.deinit();
        try blocked_state.commit(&pending);
        if (obstruction.bound) {
            var bound = try blocked_state.prepare(.{ .repair_authorize = binding }, .ok, &.{.{ .authorize = .{ .subject = obstruction.subject, .transition = .{ .authorized = child_permit } } }});
            defer bound.deinit();
            try blocked_state.commit(&bound);
        }
        try std.testing.expect(!blocked_state.permitsRequest(request.model_request_id, null, dependent, &.{child.native}));
        if (obstruction.subject == .native and !obstruction.bound) {
            try std.testing.expect(blocked_state.permitsRequest(review_request.model_request_id, null, null, &.{child.native}));
            try std.testing.expect(blocked_state.permitsRequest(review_request.model_request_id, null, dependent, &.{child.native}));
            try std.testing.expect(!blocked_state.permitsRequest(review_request.model_request_id, null, dependent, &.{stale_carrier}));
            try std.testing.expect(!blocked_state.permitsRequest(review_request.model_request_id, null, .{ .owner = &atomic_native, .permit = child_permit, .mode = .dependent_regeneration }, &.{child.native}));
            try std.testing.expect(!blocked_state.compatible(.ok));
        }
        if (obstruction.outcome == .failed) {
            try std.testing.expect(!blocked_state.permitsRequest(request.model_request_id, null, null, &.{child.native}));
            try std.testing.expect(blocked_state.permitsRequest(request.model_request_id, null, .{ .owner = &atomic_native, .permit = child_permit }, &.{}));
            try std.testing.expect(!blocked_state.compatible(.ok));
        }
    }
    var authority = try state.prepare(.{ .authority_reconcile = .{ .kind = .authority, .subject = .raw_engine_config, .evidence = .engine_config } }, .ok, &.{.{ .resolve = .{ .authority_reconciled = .{ .native = .{ .kind = .authority, .key = .raw_engine_config, .generation = 2, .occurrence = 2 } } } }});
    defer authority.deinit();
    try std.testing.expectEqual(@as(usize, 2), authority.entries.items.len);
    var foreign_failure = try state.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = foreign, .outcome = .invalid } }});
    defer foreign_failure.deinit();
    try state.commit(&foreign_failure);
    var foreign_authorization = try state.prepare(.{ .repair_authorize = binding }, .ok, &.{.{ .authorize = .{ .subject = foreign, .transition = .{ .authorized = foreign_permit } } }});
    defer foreign_authorization.deinit();
    try state.commit(&foreign_authorization);
    var fan_in = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = child, .target = foreign } }});
    defer fan_in.deinit();
    try state.commit(&fan_in);
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, dependent, &.{child.native}));
    try std.testing.expect(!state.permitsRequest(review_request.model_request_id, null, dependent, &.{child.native}));
    const successor: Subject = .{ .native = .{ .kind = .candidate, .key = .raw_engine_config, .generation = 4, .occurrence = 4 } };
    var recurring = try state.prepare(.{ .repair_validate = binding }, .invalid, &.{
        .{ .associate = .{ .source = child, .target = successor } },
        .{ .observe = .{ .subject = successor, .outcome = .invalid, .repair_progress = .{ .validated = .{ .permit = child_permit, .revision = 3, .result = .recurring } } } },
    });
    defer recurring.deinit();
    try state.commit(&recurring);
    var resolved = try state.prepare(.{ .repair_validate = binding }, .ok, &.{.{ .resolve = .{ .repair_resolved = .{ .subject = successor, .transition = .{ .validated = .{ .permit = child_permit, .revision = 3, .result = .resolved } } } } }});
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 2), resolved.entries.items.len);
    try std.testing.expect(resolved.entries.items[0].observation.subject.eql(parent));
    try std.testing.expect(resolved.entries.items[1].observation.subject.eql(foreign));
    try std.testing.expect(!resolved.compatible(.ok));
    try native.commit(try native.prepare(.{ .validated = .{ .permit = child_permit, .revision = 3, .result = .resolved } }));
    try std.testing.expect(!native.permitsDependentContinuation(child_permit, child_permit.key));
    try std.testing.expect(native.permitsDependentContinuation(parent_permit, parent_permit.key));
}

test "native association traversal remains bounded for disconnected forests" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const binding: Binding = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result };
    const center: Subject = .{ .native = .{ .kind = .authority, .key = .required_authority_inputs, .generation = 1, .occurrence = 1 } };
    var observed = try state.prepare(.{ .observe = binding }, .blocked, &.{.{ .observe = .{ .subject = center, .outcome = .blocked } }});
    defer observed.deinit();
    try state.commit(&observed);
    for (2..66) |ordinal| {
        const leaf: Subject = .{ .native = .{ .kind = .authority, .key = .required_authority_result, .generation = ordinal, .occurrence = ordinal } };
        var alias = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = center, .target = leaf } }});
        defer alias.deinit();
        try state.commit(&alias);
    }
    const disconnected: Subject = .{ .native = .{ .kind = .authority, .key = .required_authority_inputs, .generation = 100, .occurrence = 100 } };
    try std.testing.expect(!associated(state.associations.items, center, disconnected));
    const exact_leaf: Subject = .{ .native = .{ .kind = .candidate, .key = .required_authority_result, .generation = 65, .occurrence = 65 } };
    try std.testing.expect(associated(state.associations.items, center, exact_leaf));
}

test "prepared outcome control rejects foreign owners and stale revisions" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var other = State.init(std.testing.allocator);
    defer other.deinit();
    const fault: Observation = .{ .subject = .{ .operation = .{ .ordinal = 1 } }, .outcome = .failed };
    var pending = try state.prepare(.independent, .failed, &.{.{ .observe = fault }});
    defer pending.deinit();
    var stale = try state.prepare(.independent, .ok, &.{});
    defer stale.deinit();
    try std.testing.expect(state.compatible(.ok));
    try std.testing.expectError(error.InvalidOutcomeAssociation, other.commit(&pending));
    try std.testing.expect(state.compatible(.ok));
    try state.commit(&pending);
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.commit(&stale));
    try std.testing.expect(!stale.compatible(.ok));
    try std.testing.expectError(error.InvalidOutcomeAssociation, stale.firstUnresolved());
    try std.testing.expect(!state.compatible(.ok));
    try std.testing.expect(state.compatible(.failed));
    var borrowed = try state.prepare(.independent, .ok, &.{});
    defer borrowed.deinit();
    try std.testing.expect(borrowed.compatible(.failed));
    var replacement = try state.prepare(.independent, .failed, &.{.{ .observe = .{ .subject = .{ .operation = .{ .ordinal = 2 } }, .outcome = .failed } }});
    defer replacement.deinit();
    try state.commit(&replacement);
    // The borrowed arrays were released by replacement. Reject before reading
    // them, even though the current terminal class still matches the old one.
    try std.testing.expect(!borrowed.compatible(.failed));
    try std.testing.expectError(error.InvalidOutcomeAssociation, borrowed.firstUnresolved());
}

test "request admission excludes foreign subjects transport failure and counting operations" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const first = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "first" } }, .initial_generation);
    defer identity.deinitOwner(first.owner);
    const second = try identity.createSuccessor(identity.ledger(first.owner), identity.ledger(first.owner).revision(), .workflow_step, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "second" } }, .initial_generation);
    defer identity.deinitOwner(second.owner);
    const binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result };
    for ([_]workflow.OutcomeTag{ .invalid, .failed, .blocked, .needs_user, .cancelled }) |outcome| {
        var state = State.init(std.testing.allocator);
        defer state.deinit();
        const subject: Subject = .{ .request = .{ .model_request_id = first.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } };
        var observed = try state.prepare(.{ .observe = binding }, outcome, &.{.{ .observe = .{ .subject = subject, .outcome = outcome } }});
        defer observed.deinit();
        try state.commit(&observed);
        try std.testing.expectEqual(outcome == .invalid, state.permitsRequest(first.model_request_id, subject.request, null, &.{}));
        try std.testing.expect(!state.permitsRequest(second.model_request_id, subject.request, null, &.{}));
        var unrelated = try state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = .{ .request = .{ .model_request_id = second.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } } } }});
        defer unrelated.deinit();
        try std.testing.expect(!unrelated.compatible(.ok));
        if (outcome == .invalid) {
            var admitted = try state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = subject } }});
            defer admitted.deinit();
            try std.testing.expect(admitted.compatible(.ok));
            var closed = try state.prepare(.{ .request_closure = binding }, .invalid, &.{.{ .seal = .{ .subject = subject, .outcome = .invalid } }});
            defer closed.deinit();
            try state.commit(&closed);
            try std.testing.expect(!state.permitsRequest(first.model_request_id, subject.request, null, &.{}));
            try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = subject } }}));
        } else try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = subject } }}));
    }
    var counting = State.init(std.testing.allocator);
    defer counting.deinit();
    const count: Subject = .{ .request = .{ .model_request_id = first.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .input_token_count } };
    var observed = try counting.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = count, .outcome = .invalid } }});
    defer observed.deinit();
    try counting.commit(&observed);
    try std.testing.expect(!counting.permitsRequest(first.model_request_id, count.request, null, &.{}));
    try std.testing.expectError(error.InvalidOutcomeAssociation, counting.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = count } }}));
}

test "protocol admission uses the admitted attempt and closure retains genuine failures" {
    const initial = try identity.createInitial(std.testing.allocator, .all());
    defer identity.deinitOwner(initial);
    const request = try identity.createSuccessor(identity.ledger(initial), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "outcome-test" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "protocol" } }, .initial_generation);
    defer identity.deinitOwner(request.owner);
    const binding: Binding = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_payload_schema_result };
    const prior: Subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference } };
    const current: Subject = .{ .request = .{ .model_request_id = request.model_request_id, .model_attempt_ordinal = .{ .value = 2 }, .kind = .inference } };
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    var rejected = try state.prepare(.{ .observe = binding }, .invalid, &.{
        .{ .observe = .{ .subject = prior, .outcome = .invalid } },
        .{ .observe = .{ .subject = current, .outcome = .invalid } },
    });
    defer rejected.deinit();
    try state.commit(&rejected);
    try std.testing.expect(state.permitsRequest(request.model_request_id, current.request, null, &.{}));
    try std.testing.expect(!state.permitsRequest(request.model_request_id, null, null, &.{}));
    try std.testing.expect(!state.permitsRequest(request.model_request_id, prior.request, null, &.{}));
    var forged = current.request;
    forged.model_attempt_ordinal.value += 1;
    try std.testing.expect(!state.permitsRequest(request.model_request_id, forged, null, &.{}));
    forged = current.request;
    forged.model_attempt_ordinal.value = 0;
    try std.testing.expect(!state.permitsRequest(request.model_request_id, forged, null, &.{}));
    forged = current.request;
    forged.kind = .input_token_count;
    try std.testing.expect(!state.permitsRequest(request.model_request_id, forged, null, &.{}));
    var replay = try state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = prior } }});
    defer replay.deinit();
    try std.testing.expect(!replay.compatible(.ok));
    var admitted = try state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = current } }});
    defer admitted.deinit();
    try std.testing.expect(admitted.compatible(.ok));
    try state.commit(&admitted);
    var invalid = try state.prepare(.{ .observe = binding }, .invalid, &.{.{ .observe = .{ .subject = prior, .outcome = .invalid } }});
    defer invalid.deinit();
    try state.commit(&invalid);
    var failure = try state.prepare(.{ .preserve = binding }, .failed, &.{.{ .observe = .{ .subject = current, .outcome = .failed } }});
    defer failure.deinit();
    try state.commit(&failure);
    try std.testing.expect(!state.permitsRequest(request.model_request_id, current.request, null, &.{}));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = current } }}));
    var closed = try state.prepare(.{ .request_closure = binding }, .failed, &.{.{ .seal = .{ .subject = current, .outcome = .failed } }});
    defer closed.deinit();
    try std.testing.expect(closed.compatible(.failed));
    try state.commit(&closed);
    try std.testing.expect(!state.permitsRequest(request.model_request_id, current.request, null, &.{}));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .preserve = binding }, .ok, &.{.{ .preserve = current }}));
    var preserved = try state.prepare(.{ .preserve = binding }, .failed, &.{.{ .preserve = current }});
    defer preserved.deinit();
    try std.testing.expect(preserved.compatible(.failed));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_closure = binding }, .cancelled, &.{.{ .seal = .{ .subject = current, .outcome = .cancelled } }}));
    try std.testing.expectError(error.InvalidOutcomeAssociation, state.prepare(.{ .request_admission = binding }, .ok, &.{.{ .resolve = .{ .request_admitted = current } }}));
}

test "distinct unresolved terminal classes cannot collapse into one report" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    for ([_]workflow.OutcomeTag{ .failed, .needs_user, .cancelled }, 1..) |outcome, ordinal| {
        var pending = try state.prepare(.independent, outcome, &.{.{ .observe = .{ .subject = .{ .operation = .{ .ordinal = ordinal } }, .outcome = outcome } }});
        defer pending.deinit();
        try state.commit(&pending);
    }
    for (std.enums.values(workflow.OutcomeTag)) |terminal| try std.testing.expect(!state.compatible(terminal));
}

test "publication carries exact current clarification subjects rather than matching tags" {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    const prepared: NativeSubject = .{ .kind = .clarification, .key = .prepared_workflow_output, .generation = 2, .occurrence = 2 };
    try std.testing.expect(state.permitsPublication(prepared, .ok));
    const needs: Subject = .{ .native = .{ .kind = .clarification, .key = .clarification_needs, .generation = 1, .occurrence = 1 } };
    const binding: Binding = .{ .kind = .clarification, .subject = .clarification_needs, .evidence = .clarification_needs, .result = .prepared_workflow_output };
    var observed = try state.prepare(.{ .observe = binding }, .needs_user, &.{.{ .observe = .{ .subject = needs, .outcome = .needs_user } }});
    defer observed.deinit();
    try state.commit(&observed);
    try std.testing.expect(!state.permitsPublication(prepared, .needs_user));
    var carried = try state.prepare(.{ .preserve = binding }, .ok, &.{.{ .associate = .{ .source = needs, .target = .{ .native = prepared } } }});
    defer carried.deinit();
    try state.commit(&carried);
    try std.testing.expect(state.permitsPublication(prepared, .needs_user));
    try std.testing.expect(!state.permitsPublication(prepared, .ok));
    var foreign = prepared;
    foreign.generation += 1;
    try std.testing.expect(!state.permitsPublication(foreign, .needs_user));
    foreign = prepared;
    foreign.occurrence += 1;
    try std.testing.expect(!state.permitsPublication(foreign, .needs_user));
    var unassociated = try state.prepare(.independent, .needs_user, &.{.{ .observe = .{ .subject = .{ .operation = .{ .ordinal = 3 } }, .outcome = .needs_user } }});
    defer unassociated.deinit();
    try state.commit(&unassociated);
    try std.testing.expect(state.compatible(.needs_user));
    try std.testing.expect(!state.permitsPublication(prepared, .needs_user));
}
