//! Native admitted-text observations. Reusing native composition/wire checks
//! proves only mechanical admission escapes, never semantic correctness. Later
//! model consumption is chronological exposure, not the escape's causal cost.
const std = @import("std");
const text = @import("../../../src/domain/typed_text.zig");
const policy = @import("../../../src/domain/text_field_policy.zig");
const wire = @import("../../../src/domain/model_text_wire.zig");
const evidence = @import("../../../src/domain/reference_evidence.zig");
const extraction = @import("../../../src/domain/reference_extraction.zig");
const reconciliation = @import("../../../src/domain/reference_reconciliation.zig");
const specification = @import("../../../src/domain/specification.zig");
const generation = @import("../../../src/domain/specification_generation.zig");
const candidate = @import("../../../src/domain/specification_candidate.zig");
const data = @import("../../../src/domain/pipeline_data.zig");
const values = @import("../../../src/application/pipeline_values.zig");
const native_spec = @import("../../../src/application/specification_workflow.zig");
const native_extraction = @import("../../../src/application/reference_extraction_workflow.zig");
const native_reconciliation = @import("../../../src/application/reference_reconciliation_workflow.zig");
const authority = @import("../../../src/domain/required_authority.zig");
const support = @import("../../../src/domain/specification_support.zig");
const native_support = @import("../../../src/application/specification_support_workflow.zig");
const session = @import("../../../src/domain/specification_session.zig");
const clarification = @import("../../../src/domain/clarification_inputs.zig");
const clarification_refresh = @import("../../../src/domain/clarification_refresh.zig");
const native_clarifications = @import("../../../src/application/clarification_refresh_workflow.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;

pub const Source = struct { source_id: evidence.identity.SourceId, path: []const u8, bytes: []const u8 };
pub const Value = union(enum) { business: text.BusinessText, reference: text.ReferenceSemanticText };
pub const Violation = text.Issue;
pub const Subject = union(enum) {
    extraction: struct { scope: evidence.Scope, target: extraction.TextTarget },
    reconciliation: struct { partition: reconciliation.PartitionId, unit: reconciliation.diagnostic.Unit },
    specification: struct { unit: generation.Unit, field: candidate.Field, record_kind: ?specification.Kind = null },
    source_review: struct { requirement: authority.Id, ordinal: u32, question: enum { question, authority_gap_question } },
    clarification: clarification.Id,
};
/// Model production and deterministic native projection are distinct facts.
/// Native facts never manufacture a model request/attempt or its authority.
pub const Producer = union(enum) {
    model: Origin,
    native: NativeProducer,
    unavailable: enum { missing_model_origin, missing_model_receipt, missing_native_parent },
};
pub const NativeProducer = union(enum) {
    summary_reuse: struct {
        partition: reconciliation.PartitionId,
        from_summary: reconciliation.SummaryId,
        source_statement: usize,
        source_check: usize,
        validation_sha256: []const u8,
    },
    clarification_refresh: struct {
        id: clarification.Id,
        state_ordinal: u64,
        state_revision: u64,
        record_revision: u64,
        state_sha256: []const u8,
    },
};
pub const Check = struct {
    sequence: usize,
    after_call: usize,
    producer: Producer,
    subject: Subject,
    field: policy.Field,
    value: Value,
    value_sha256: []const u8,
    violation: ?Violation,
};
pub const Audit = struct {
    scope: enum { native_admitted_text_composition_and_wire } = .native_admitted_text_composition_and_wire,
    sources: []const Source,
    checks: []const Check,
    complete: bool,
};
pub const Exchange = struct { call: usize, origin: Origin, usage: ?@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage, uncertain_delivery: bool = false };
pub const Exposure = struct {
    physical_sends: u64 = 0,
    known_input_tokens: u64 = 0,
    known_output_tokens: u64 = 0,
    known_actual_tokens: u64 = 0,
    actual_tokens: ?u64 = 0,
    usage_complete: bool = true,
    uncertain_delivery: bool = false,
};
pub const Metric = struct {
    status: enum { measured, unavailable },
    denominator: enum { distinct_observed_producers } = .distinct_observed_producers,
    admitted_values: u64 = 0,
    escaped_values: u64 = 0,
    admitted_origins: u64 = 0,
    escaped_origins: u64 = 0,
    producer_escape_rate: ?f64 = null,
    unattributed_values: u64 = 0,
    first_escape_after_call: ?usize = null,
    downstream: Exposure = .{},
    downstream_interpretation: enum { chronological_exposure_not_causal_cost } = .chronological_exposure_not_causal_cost,
};
pub const Workload = struct { attempted: bool, metric: Metric };
pub const Summary = struct {
    /// Counts actual native invocations, including retained zero-send failures.
    /// The comparison scorecard retains its separate dispatched-arm convention.
    denominator: enum { invoked_native_workloads } = .invoked_native_workloads,
    attempted_workloads: u64 = 0,
    unattempted_workloads: u64 = 0,
    measured_workloads: u64 = 0,
    unknown_workloads: u64 = 0,
    escaped_workloads: u64 = 0,
    escaped_values: u64 = 0,
    admitted_origins: u64 = 0,
    escaped_origins: u64 = 0,
    workload_escape_rate: ?f64 = null,
    producer_escape_rate: ?f64 = null,
    evidence_complete: bool = true,
    downstream: Exposure = .{},
    downstream_interpretation: enum { chronological_exposure_not_causal_cost } = .chronological_exposure_not_causal_cost,
};

pub const Tracker = struct {
    arena: std.heap.ArenaAllocator,
    sources: []const Source = &.{},
    checks: std.ArrayList(Check) = .empty,

    pub fn init(a: std.mem.Allocator) Tracker {
        return .{ .arena = .init(a) };
    }
    pub fn deinit(self: *Tracker) void {
        self.arena.deinit();
    }
    pub fn snapshot(self: *const Tracker, complete: bool) Audit {
        return .{ .sources = self.sources, .checks = self.checks.items, .complete = complete };
    }

    /// Native observations can survive a transport-evidence failure. Preserve
    /// that uncertainty explicitly; never turn an unmatched call into native
    /// production or a measured zero. Readback still validates known claims.
    pub fn reconcile(self: *Tracker, exchanges: []const Exchange) void {
        for (self.checks.items, 0..) |*observed, index| switch (observed.producer) {
            .model => |origin| {
                const found = for (exchanges) |exchange| {
                    if (std.meta.eql(exchange.origin, origin)) break true;
                } else false;
                if (!found) observed.producer = .{ .unavailable = .missing_model_receipt };
            },
            .native => |native| if (native == .summary_reuse) {
                const parent = native.summary_reuse.source_check;
                if (parent != 0 and parent <= index and self.checks.items[parent - 1].producer == .unavailable) observed.producer = .{ .unavailable = .missing_native_parent };
            },
            .unavailable => {},
        };
    }

    pub fn observe(self: *Tracker, view: *const data.View, sequence: usize, after_call: usize) !void {
        const input_schema = @import("../../../src/application/reference_evidence_workflow.zig").inputs_schema;
        if (!view.contains(input_schema.key)) return;
        const inputs = (try values.read(view, input_schema, evidence.Inputs)).*;
        try self.bindSources(inputs);
        if (view.contains(native_extraction.text_schema.key)) {
            const owned = try values.read(view, native_extraction.text_schema, @import("../../../src/domain/reference_candidate_value.zig").Value);
            if (owned.payload().* == .text_validated) for (owned.payload().text_validated.entries) |entry| switch (entry.outcome) {
                .claims => |claims| for (claims, 0..) |proposal, index| try self.claim(.extraction, sequence, after_call, proposal.origin, .{ .extraction = .{ .scope = entry.scope, .target = .{ .claim = index } } }, proposal.content),
                .no_feature_claim => |reason| try self.inspect(sequence, after_call, if (entry.producers) |producers| producers.content else entry.origin, .{ .extraction = .{ .scope = entry.scope, .target = .reason } }, .extraction_reason, .{ .reference = reason.value }),
                .blocked => {},
            };
        }
        if (view.contains(native_reconciliation.summary_schema.key)) {
            const owned = try values.read(view, native_reconciliation.summary_schema, @import("../../../src/domain/reference_candidate_value.zig").Value);
            if (owned.payload().* == .reconciliation_summary) {
                const checked = owned.payload().reconciliation_summary;
                for (checked.projection.originals, 0..) |statement, index| if (statement.content == .model) {
                    const subject: Subject = .{ .reconciliation = .{ .partition = checked.input.partition.id, .unit = .{ .statement = index } } };
                    const producer = if (checked.projection.carried_from != null) try self.reuseProducer(checked, index, statement.content.model) else modelProducer(checked.projection.source.at(.{ .statement = index }, .content));
                    try self.claimProduced(.reconciliation, sequence, after_call, producer, subject, statement.content.model);
                };
            }
        }
        if (view.contains(native_reconciliation.signals_schema.key)) {
            const owned = try values.read(view, native_reconciliation.signals_schema, @import("../../../src/domain/reference_candidate_value.zig").Value);
            if (owned.payload().* == .reconciliation_signals) {
                const checked = owned.payload().reconciliation_signals;
                for (checked.signals, 0..) |signal, index| if (signal.content == .model) try self.claim(.reconciliation, sequence, after_call, checked.prior.source.at(.{ .signal = index }, .content), .{ .reconciliation = .{ .partition = checked.prior.input.partition.id, .unit = .{ .signal = index } } }, signal.content.model);
            }
        }
        if (view.contains(native_reconciliation.conflicts_schema.key)) {
            const owned = try values.read(view, native_reconciliation.conflicts_schema, @import("../../../src/domain/reference_candidate_value.zig").Value);
            if (owned.payload().* == .reconciliation_conflicts) {
                const checked = owned.payload().reconciliation_conflicts;
                for (checked.conflicts, 0..) |conflict, index| try self.inspect(sequence, after_call, checked.prior.prior.source.at(.{ .conflict = index }, .content), .{ .reconciliation = .{ .partition = checked.prior.prior.input.partition.id, .unit = .{ .conflict = index } } }, .reconciliation_conflict, .{ .reference = conflict.summary.value });
            }
        }
        const current: ?session.Session = if (view.contains(native_spec.session_schema.key)) try native_spec.readSession(view) else null;
        if (view.contains(native_spec.checked_schema.key)) {
            const storage = @import("../../../src/application/specification_values.zig").storage;
            const owned = try values.read(view, native_spec.checked_schema, storage.Value);
            if (storage.payload(owned).* == .checked) try self.unit(sequence, after_call, storage.payload(owned).checked, try recordOffset(current, storage.payload(owned).checked));
        }
        if (current) |native| {
            for (native.units) |checked| if (checked) |checked_unit| try self.unit(sequence, after_call, checked_unit, try recordOffset(current, checked_unit));
            for (native.record_batches) |checked_unit| try self.unit(sequence, after_call, checked_unit, try recordOffset(current, checked_unit));
        }
        if (view.contains(native_support.schema.key)) {
            const reviewed = try native_support.progress(view);
            switch (reviewed) {
                .initial => {},
                .source => |collection| try self.sourceReview(sequence, after_call, try native_support.inputs(view, reviewed), collection),
                .pending => |pending| try self.sourceReview(sequence, after_call, pending.source.inputs, .{ .accepted = pending.source }),
                .principles => |result| try self.sourceReview(sequence, after_call, result.pending.source.inputs, .{ .accepted = result.pending.source }),
            }
        }
        if (view.contains(native_clarifications.state_schema.key)) {
            const refreshed = try values.read(view, native_clarifications.state_schema, clarification_refresh.Result);
            if (refreshed.* == .ready) try self.refreshedQuestions(sequence, after_call, refreshed.ready);
        }
    }

    fn bindSources(self: *Tracker, inputs: evidence.Inputs) !void {
        if (self.sources.len != 0) {
            if (self.sources.len != inputs.corpus.sources.len) return error.AdmissionSourcesChanged;
            for (self.sources, inputs.corpus.sources) |prior, current| if (!std.meta.eql(prior.source_id, current.id) or !std.mem.eql(u8, prior.path, current.path.bytes) or !std.mem.eql(u8, prior.bytes, current.bytes)) return error.AdmissionSourcesChanged;
            return;
        }
        const a = self.arena.allocator();
        const sources = try a.alloc(Source, inputs.corpus.sources.len);
        for (inputs.corpus.sources, sources) |source, *copy| copy.* = .{ .source_id = source.id, .path = try a.dupe(u8, source.path.bytes), .bytes = try a.dupe(u8, source.bytes) };
        self.sources = sources;
    }

    fn claim(self: *Tracker, comptime phase: policy.ReferencePhase, sequence: usize, after_call: usize, origin: ?Origin, subject: Subject, content: extraction.Content) !void {
        return self.claimProduced(phase, sequence, after_call, modelProducer(origin), subject, content);
    }

    fn claimProduced(self: *Tracker, comptime phase: policy.ReferencePhase, sequence: usize, after_call: usize, producer: Producer, subject: Subject, content: extraction.Content) !void {
        switch (content) {
            inline else => |_, tag| try self.inspectProduced(sequence, after_call, producer, subject, policy.referenceField(phase, @tagName(tag)), claimValue(content)),
        }
    }

    /// Native reuse was admitted by the canonical checker and carries its exact
    /// child identity/validation. Bind each copied statement to the earlier
    /// observed child occurrence; a missing model parent stays unavailable.
    fn reuseProducer(self: *Tracker, checked: reconciliation.CheckedSummary, index: usize, content: extraction.Content) !Producer {
        const from = checked.projection.carried_from orelse return error.InvalidAdmissionAudit;
        if (checked.projection.source.at(.{ .statement = index }, .content) != null) return error.InvalidAdmissionAudit;
        const child = for (checked.input.summaries) |summary| {
            if (summary.id.ordinal == from.ordinal) break summary;
        } else return error.InvalidAdmissionAudit;
        const value = claimValue(content);
        const a = self.arena.allocator();
        const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
        defer a.free(bytes);
        const digest = hash(bytes);
        for (child.projection.originals, child.projection.statement_indices, 0..) |original, mapped, source_index| {
            if (mapped != index or original.content != .model or !reconciliation.equivalentContent(original.content, .{ .model = content })) continue;
            const expected_origin = child.projection.source.at(.{ .statement = source_index }, .content);
            var prior_index = self.checks.items.len;
            while (prior_index != 0) {
                prior_index -= 1;
                const prior = self.checks.items[prior_index];
                if (prior.subject != .reconciliation or prior.subject.reconciliation.partition.ordinal != child.partition_id.ordinal or prior.subject.reconciliation.unit != .statement or prior.subject.reconciliation.unit.statement != source_index or !std.mem.eql(u8, prior.value_sha256, &digest)) continue;
                if (expected_origin) |origin| {
                    if (prior.producer != .model or !std.meta.eql(prior.producer.model, origin)) continue;
                } else if (child.projection.carried_from == null or prior.producer != .native) continue;
                const validation = std.fmt.bytesToHex(checked.validation.bytes, .lower);
                return .{ .native = .{ .summary_reuse = .{ .partition = checked.input.partition.id, .from_summary = child.id, .source_statement = source_index, .source_check = prior_index + 1, .validation_sha256 = try a.dupe(u8, &validation) } } };
            }
        }
        return .{ .unavailable = .missing_native_parent };
    }

    /// Only natively admitted collections and validated working prefixes own
    /// these questions. Rejected candidates do not count as admission escapes.
    fn sourceReview(self: *Tracker, sequence: usize, after_call: usize, inputs: authority.Inputs, collection: support.Source.Collection) !void {
        const admitted = switch (collection) {
            .accepted => |value| value.candidate,
            .pending => |value| value,
            .rejected => return,
        };
        if (admitted.origins.len != admitted.review.entries.len) return error.InvalidAdmissionAudit;
        var scratch: std.heap.ArenaAllocator = .init(self.arena.allocator());
        defer scratch.deinit();
        const population = try authority.build(scratch.allocator(), inputs);
        for (admitted.review.entries, admitted.origins) |entry, origin| {
            if (entry.requirement_ordinal == 0 or entry.requirement_ordinal > population.requirements.len) return error.InvalidAdmissionAudit;
            const requirement = population.requirements[entry.requirement_ordinal - 1].seed.id;
            if (entry.value.question) |question| try self.reviewQuestion(sequence, after_call, origin, requirement, entry.requirement_ordinal, .question, question);
            if (entry.value.authority_gap) |gap| try self.reviewQuestion(sequence, after_call, origin, requirement, entry.requirement_ordinal, .authority_gap_question, gap.question);
        }
    }

    fn reviewQuestion(self: *Tracker, sequence: usize, after_call: usize, origin: ?Origin, requirement: authority.Id, ordinal: u32, question_kind: @FieldType(@FieldType(Subject, "source_review"), "question"), question: []const u8) !void {
        const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = question } }};
        try self.inspect(sequence, after_call, origin, .{ .source_review = .{ .requirement = requirement, .ordinal = ordinal, .question = question_kind } }, .clarification_question, .{ .business = .{ .segments = &nodes } });
    }

    /// Ready owns deterministic source-aware question readback. Its current
    /// native admission has an explicit state identity, without inventing the
    /// historical model origin of a persisted question.
    fn refreshedQuestions(self: *Tracker, sequence: usize, after_call: usize, ready: clarification_refresh.Ready) !void {
        if (!wire.validSources(ready.original_sources) or ready.original_sources.len != self.sources.len) return error.InvalidAdmissionAudit;
        for (ready.original_sources, self.sources) |witness, source| if (witness.source_id.ordinal != source.source_id.ordinal or !std.mem.eql(u8, witness.bytes, source.bytes)) return error.InvalidAdmissionAudit;
        const state = ready.state.value orelse return;
        const bytes = try @import("../../../src/domain/canonical_json.zig").encode(clarification.State, self.arena.allocator(), state);
        defer self.arena.allocator().free(bytes);
        const digest = hash(bytes);
        for (state.records) |record| {
            const id = clarification.Id.parse(record.id) orelse return error.InvalidAdmissionAudit;
            const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = record.question } }};
            try self.inspectProduced(sequence, after_call, .{ .native = .{ .clarification_refresh = .{ .id = id, .state_ordinal = state.state_ordinal, .state_revision = state.revision, .record_revision = record.revision, .state_sha256 = &digest } } }, .{ .clarification = id }, .clarification_question, .{ .business = .{ .segments = &nodes } });
        }
    }

    fn unit(self: *Tracker, sequence: usize, after_call: usize, checked: generation.Checked, record_offset: usize) !void {
        switch (checked.response) {
            .inconclusive => {},
            .clarification => |need| try self.business(sequence, after_call, checked, record_offset, .clarification_question, .clarification_question, need.question.value),
            .content => |content| switch (content) {
                .brief => |brief| {
                    try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .title, .field = .value } } }, .spec_title, brief.title.value);
                    try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .description, .field = .value } } }, .spec_description, brief.description.value);
                    try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .primary_goal, .field = .value } } }, .spec_goal, brief.primary_goal.value);
                },
                .primary_user_story => |story| try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .story, .field = .value } } }, .spec_story, story.value),
                .entities => |entities| {
                    try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .entity_basis, .field = .value } } }, .spec_entity_basis, entities.basis.value);
                    try self.auditRecords(sequence, after_call, checked, record_offset, entities.records);
                },
                .records => |records| try self.auditRecords(sequence, after_call, checked, record_offset, records),
            },
        }
    }

    fn auditRecords(self: *Tracker, sequence: usize, after_call: usize, checked: generation.Checked, record_offset: usize, proposals: []const specification.RecordProposal) !void {
        for (proposals, 0..) |record, index| switch (record.content) {
            inline else => |fields, kind| inline for (std.meta.fields(@TypeOf(fields))) |field| {
                const value = @field(fields, field.name);
                if (comptime field.type == specification.BusinessValue) {
                    try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .{ .record = index }, .field = @unionInit(candidate.ValueField, field.name, {}) } } }, specification.textField(kind, field.name), value);
                } else for (value, 0..) |relationship, relationship_index| try self.business(sequence, after_call, checked, record_offset, .{ .target = .{ .value = .{ .subject = .{ .record = index }, .field = .{ .relationship = relationship_index } } } }, specification.textField(kind, field.name), relationship);
            },
        };
    }

    fn business(self: *Tracker, sequence: usize, after_call: usize, checked: generation.Checked, record_offset: usize, field: candidate.Field, declared: policy.Field, value: specification.BusinessValue) !void {
        var stable = field;
        var record_kind: ?specification.Kind = null;
        if (field == .target) if (candidate.recordIndex(field.target)) |index| {
            if (checked.response != .content) return error.InvalidAdmissionAudit;
            const records = generation.recordCollection(.canonical, checked.response.content) orelse return error.InvalidAdmissionAudit;
            if (index >= records.len) return error.InvalidAdmissionAudit;
            record_kind = std.meta.activeTag(records[index].content);
            stable.target = (try checked.origins.stableTarget(field.target, records.len)).value;
            stable.target.value.subject.record = try std.math.add(usize, stable.target.value.subject.record, record_offset);
        };
        try self.inspect(sequence, after_call, checked.origins.at(field), .{ .specification = .{ .unit = checked.unit, .field = stable, .record_kind = record_kind } }, declared, .{ .business = .{ .segments = value.segments } });
    }

    fn inspect(self: *Tracker, sequence: usize, after_call: usize, origin: ?Origin, subject: Subject, field: policy.Field, value: Value) !void {
        return self.inspectProduced(sequence, after_call, modelProducer(origin), subject, field, value);
    }

    fn inspectProduced(self: *Tracker, sequence: usize, after_call: usize, producer: Producer, subject: Subject, field: policy.Field, value: Value) !void {
        const a = self.arena.allocator();
        var scratch: std.heap.ArenaAllocator = .init(a);
        defer scratch.deinit();
        const temporary = scratch.allocator();
        const bytes = try std.json.Stringify.valueAlloc(temporary, value, .{});
        const digest = hash(bytes);
        // Stable native subjects deduplicate assembly views without collapsing
        // two equal fields authored for distinct records in one response.
        for (self.checks.items) |prior| if (sameProducer(prior.producer, producer) and prior.field == field and std.mem.eql(u8, prior.value_sha256, &digest) and try sameSubject(temporary, prior.subject, subject)) return;
        if (!validSubject(subject, field, value)) return error.InvalidAdmissionAudit;
        const owned_value = try @import("../contracts.zig").decode(Value, a, bytes);
        try self.checks.append(a, .{ .sequence = sequence, .after_call = after_call, .producer = try @import("../contracts.zig").decode(Producer, a, try std.json.Stringify.valueAlloc(temporary, producer, .{})), .subject = try @import("../contracts.zig").decode(Subject, a, try std.json.Stringify.valueAlloc(temporary, subject, .{})), .field = field, .value = owned_value, .value_sha256 = try a.dupe(u8, &digest), .violation = try check(temporary, self.sources, field, value) });
    }
};

fn modelProducer(origin: ?Origin) Producer {
    return if (origin) |value| .{ .model = value } else .{ .unavailable = .missing_model_origin };
}
fn claimValue(content: extraction.Content) Value {
    return switch (content) {
        inline .business, .scope_guard => |value| .{ .business = value.value },
        inline else => |value| .{ .reference = value.value },
    };
}
fn sameProducer(left: Producer, right: Producer) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .model => |value| std.meta.eql(value, right.model),
        .unavailable => |value| value == right.unavailable,
        .native => |value| if (std.meta.activeTag(value) != std.meta.activeTag(right.native)) false else switch (value) {
            .summary_reuse => |proof| proof.partition.ordinal == right.native.summary_reuse.partition.ordinal and proof.from_summary.ordinal == right.native.summary_reuse.from_summary.ordinal and proof.source_statement == right.native.summary_reuse.source_statement and proof.source_check == right.native.summary_reuse.source_check and std.mem.eql(u8, proof.validation_sha256, right.native.summary_reuse.validation_sha256),
            .clarification_refresh => |proof| std.meta.eql(proof.id, right.native.clarification_refresh.id) and proof.state_ordinal == right.native.clarification_refresh.state_ordinal and proof.state_revision == right.native.clarification_refresh.state_revision and proof.record_revision == right.native.clarification_refresh.record_revision and std.mem.eql(u8, proof.state_sha256, right.native.clarification_refresh.state_sha256),
        },
    };
}
fn validDigest(bytes: []const u8) bool {
    if (bytes.len != 64) return false;
    for (bytes) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

/// Batch-local occurrence ordinals project through the native concatenation
/// order. Combined units already carry global stable occurrence ordinals.
fn recordOffset(current: ?session.Session, checked: generation.Checked) !usize {
    const assigned = checked.record_assignment orelse return 0;
    const native = current orelse return error.InvalidAdmissionAudit;
    var offset: usize = 0;
    for (native.record_batches) |batch| {
        const prior = batch.record_assignment orelse return error.InvalidAdmissionAudit;
        if (prior.group_index >= assigned.group_index) break;
        if (batch.response != .content or batch.response.content != .records) return error.InvalidAdmissionAudit;
        offset = try std.math.add(usize, offset, try batch.origins.record_occurrences.reservedSpan(batch.response.content.records.len));
    }
    if (assigned.group_index > native.record_batches.len) return error.InvalidAdmissionAudit;
    return offset;
}

fn sameSubject(a: std.mem.Allocator, left: Subject, right: Subject) !bool {
    const l = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(l);
    const r = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(r);
    return std.mem.eql(u8, l, r);
}

fn referenceSubject(comptime phase: policy.ReferencePhase, field: policy.Field, value: Value) bool {
    inline for (std.meta.fields(extraction.Content)) |kind| {
        if (field == policy.referenceField(phase, kind.name)) return if (comptime kind.type == text.ValidatedBusinessText) value == .business else value == .reference;
    }
    return false;
}

/// The captured native selector owns its policy. Persisted evidence cannot
/// relabel a prose field as the optional entity-name identity exception.
fn validSubject(subject: Subject, field: policy.Field, value: Value) bool {
    return switch (subject) {
        .extraction => |selected| if (selected.scope.state_id.bytes.len == 0 or selected.scope.chunk_id.bytes.len == 0) false else switch (selected.target) {
            .reason => field == .extraction_reason and value == .reference,
            .claim => referenceSubject(.extraction, field, value),
        },
        .reconciliation => |selected| if (selected.partition.ordinal == 0) false else switch (selected.unit) {
            .statement, .signal => referenceSubject(.reconciliation, field, value),
            .conflict => field == .reconciliation_conflict and value == .reference,
            else => false,
        },
        .source_review => |selected| selected.ordinal != 0 and authority.policy(selected.requirement) != null and field == .clarification_question and value == .business,
        .clarification => |id| id.ordinal > 0 and id.ordinal <= 99 and field == .clarification_question and value == .business,
        .specification => |selected| value == .business and switch (selected.field) {
            .clarification_question => selected.record_kind == null and field == .clarification_question,
            .target => |target| if (target != .value) false else if (target.value.subject == .record)
                selected.record_kind != null and (if (selected.record_kind.? == .entity) selected.unit == .entities else selected.unit == .records) and field == (candidate.recordKindTextField(selected.record_kind.?, target.value.field) catch return false)
            else
                selected.record_kind == null and target.value.field == .value and field == (candidate.singletonTextField(target.value.subject) catch return false) and switch (target.value.subject) {
                    .title, .description, .primary_goal => selected.unit == .brief,
                    .story => selected.unit == .primary_user_story,
                    .entity_basis => selected.unit == .entities,
                    .record => false,
                },
            .unit, .interpretation => false,
        },
    };
}

fn hash(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

pub fn check(a: std.mem.Allocator, sources: []const Source, field: policy.Field, value: Value) !?Violation {
    const originals = try a.alloc(wire.SourceText, sources.len);
    defer a.free(originals);
    for (sources, originals) |source, *original| original.* = .{ .source_id = source.source_id, .bytes = source.bytes };
    const wire_issue = try switch (value) {
        .business => |business| text.wireCompositionSources(text.BusinessSegment, a, originals, field, business.segments),
        .reference => |reference| text.wireCompositionSources(text.ReferenceNode, a, originals, field, reference.nodes),
    };
    if (wire_issue) |failure| return failure;
    return switch (value) {
        .business => |business| text.composition(text.BusinessSegment, field, business.segments),
        .reference => |reference| text.composition(text.ReferenceNode, field, reference.nodes),
    };
}

pub fn validate(a: std.mem.Allocator, audit: Audit, exchanges: []const Exchange) !void {
    for (exchanges, 0..) |exchange, index| {
        if (exchange.call != index + 1 or exchange.origin.request.value == 0 or exchange.origin.attempt.value == 0 or exchange.origin.kind != .inference) return error.InvalidAdmissionAudit;
        if (exchange.usage) |usage| if (@import("../../../src/domain/llm_provider_operation.zig").ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null) return error.InvalidAdmissionAudit;
        for (exchanges[0..index]) |prior| if (std.meta.eql(prior.origin, exchange.origin)) return error.InvalidAdmissionAudit;
    }
    for (audit.sources, 0..) |source, index| {
        try @import("../contracts.zig").path(source.path);
        if (source.source_id.ordinal != index + 1 or !std.unicode.utf8ValidateSlice(source.bytes)) return error.InvalidAdmissionAudit;
    }
    for (audit.checks, 0..) |observed, index| {
        const bytes = try std.json.Stringify.valueAlloc(a, observed.value, .{});
        defer a.free(bytes);
        if (!validSubject(observed.subject, observed.field, observed.value) or observed.sequence == 0 or observed.after_call > exchanges.len or (index != 0 and observed.sequence < audit.checks[index - 1].sequence) or
            !std.mem.eql(u8, observed.value_sha256, &hash(bytes)) or
            !std.meta.eql(observed.violation, try check(a, audit.sources, observed.field, observed.value))) return error.InvalidAdmissionAudit;
        switch (observed.producer) {
            .model => |origin| {
                const producing = for (exchanges) |exchange| {
                    if (std.meta.eql(exchange.origin, origin)) break exchange;
                } else return error.InvalidAdmissionAudit;
                if (producing.call > observed.after_call) return error.InvalidAdmissionAudit;
            },
            .native => |native| switch (native) {
                .summary_reuse => |proof| {
                    if (observed.subject != .reconciliation or observed.subject.reconciliation.unit != .statement or observed.subject.reconciliation.partition.ordinal != proof.partition.ordinal or
                        proof.from_summary.ordinal == 0 or proof.from_summary.ordinal >= proof.partition.ordinal or proof.source_check == 0 or proof.source_check > index or !validDigest(proof.validation_sha256)) return error.InvalidAdmissionAudit;
                    const parent = audit.checks[proof.source_check - 1];
                    if (parent.producer == .unavailable or parent.subject != .reconciliation or parent.subject.reconciliation.partition.ordinal != proof.from_summary.ordinal or parent.subject.reconciliation.unit != .statement or
                        parent.subject.reconciliation.unit.statement != proof.source_statement or parent.field != observed.field or !std.mem.eql(u8, parent.value_sha256, observed.value_sha256) or parent.sequence >= observed.sequence) return error.InvalidAdmissionAudit;
                },
                .clarification_refresh => |proof| {
                    if (observed.subject != .clarification or !std.meta.eql(proof.id, observed.subject.clarification) or proof.state_ordinal == 0 or proof.state_revision == 0 or proof.record_revision == 0 or proof.record_revision > proof.state_revision or !validDigest(proof.state_sha256)) return error.InvalidAdmissionAudit;
                    for (audit.checks[0..index]) |prior| if (prior.producer == .native and prior.producer.native == .clarification_refresh) {
                        const preceding = prior.producer.native.clarification_refresh;
                        if (preceding.state_ordinal == proof.state_ordinal and preceding.state_revision == proof.state_revision and !std.mem.eql(u8, preceding.state_sha256, proof.state_sha256)) return error.InvalidAdmissionAudit;
                    };
                },
            },
            .unavailable => {},
        }
        for (audit.checks[0..index]) |prior| if (sameProducer(prior.producer, observed.producer) and prior.field == observed.field and std.mem.eql(u8, prior.value_sha256, observed.value_sha256) and try sameSubject(a, prior.subject, observed.subject)) return error.InvalidAdmissionAudit;
    }
}

pub fn measure(audit: ?Audit, exchanges: []const Exchange) !Metric {
    const observed = audit orelse return .{ .status = .unavailable };
    var result: Metric = .{ .status = if (observed.complete) .measured else .unavailable };
    result.admitted_values = observed.checks.len;
    for (observed.checks, 0..) |item, index| {
        if (item.violation != null) {
            result.escaped_values += 1;
            if (result.first_escape_after_call == null or item.after_call < result.first_escape_after_call.?) result.first_escape_after_call = item.after_call;
        }
        if (item.producer == .unavailable) {
            result.unattributed_values += 1;
            continue;
        }
        var seen = false;
        var escaped = false;
        for (observed.checks[0..index]) |prior| if (sameProducer(prior.producer, item.producer)) {
            seen = true;
            escaped = escaped or prior.violation != null;
        };
        if (!seen) result.admitted_origins += 1;
        if (item.violation != null and !escaped) result.escaped_origins += 1;
    }
    if (result.unattributed_values != 0) result.status = .unavailable;
    if (result.status == .measured and result.admitted_origins != 0) result.producer_escape_rate = @as(f64, @floatFromInt(result.escaped_origins)) / @as(f64, @floatFromInt(result.admitted_origins));
    if (result.first_escape_after_call) |after_call| for (exchanges) |exchange| {
        if (exchange.call <= after_call) continue;
        result.downstream.physical_sends += 1;
        result.downstream.uncertain_delivery = result.downstream.uncertain_delivery or exchange.uncertain_delivery;
        if (exchange.usage) |usage| {
            result.downstream.known_input_tokens = try std.math.add(u64, result.downstream.known_input_tokens, usage.input_tokens);
            result.downstream.known_output_tokens = try std.math.add(u64, result.downstream.known_output_tokens, usage.output_tokens);
            result.downstream.known_actual_tokens = try std.math.add(u64, result.downstream.known_actual_tokens, usage.total_tokens);
        } else result.downstream.usage_complete = false;
    };
    result.downstream.actual_tokens = if (result.downstream.usage_complete) result.downstream.known_actual_tokens else null;
    return result;
}

pub fn summarize(workloads: []const Workload) !Summary {
    var result: Summary = .{};
    for (workloads) |workload| {
        if (!workload.attempted) {
            result.unattempted_workloads += 1;
            continue;
        }
        result.attempted_workloads += 1;
        const metric = workload.metric;
        if (metric.status == .measured) result.measured_workloads += 1 else {
            result.unknown_workloads += 1;
            result.evidence_complete = false;
        }
        if (metric.escaped_values != 0) result.escaped_workloads += 1;
        result.escaped_values = try std.math.add(u64, result.escaped_values, metric.escaped_values);
        result.admitted_origins = try std.math.add(u64, result.admitted_origins, metric.admitted_origins);
        result.escaped_origins = try std.math.add(u64, result.escaped_origins, metric.escaped_origins);
        result.downstream.physical_sends = try std.math.add(u64, result.downstream.physical_sends, metric.downstream.physical_sends);
        result.downstream.known_input_tokens = try std.math.add(u64, result.downstream.known_input_tokens, metric.downstream.known_input_tokens);
        result.downstream.known_output_tokens = try std.math.add(u64, result.downstream.known_output_tokens, metric.downstream.known_output_tokens);
        result.downstream.known_actual_tokens = try std.math.add(u64, result.downstream.known_actual_tokens, metric.downstream.known_actual_tokens);
        result.downstream.usage_complete = result.downstream.usage_complete and metric.downstream.usage_complete;
        result.downstream.uncertain_delivery = result.downstream.uncertain_delivery or metric.downstream.uncertain_delivery;
    }
    if (result.evidence_complete and result.attempted_workloads != 0) result.workload_escape_rate = @as(f64, @floatFromInt(result.escaped_workloads)) / @as(f64, @floatFromInt(result.attempted_workloads));
    if (result.evidence_complete and result.admitted_origins != 0) result.producer_escape_rate = @as(f64, @floatFromInt(result.escaped_origins)) / @as(f64, @floatFromInt(result.admitted_origins));
    result.downstream.actual_tokens = if (result.downstream.usage_complete) result.downstream.known_actual_tokens else null;
    return result;
}

fn testOrigin(request: usize) Origin {
    return .{ .request = .{ .value = request }, .attempt = .{ .value = 1 } };
}

test "native admitted values use shared policy and retain chronological downstream unknown usage" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const literal = [_]text.BusinessSegment{.{ .literal = .{ .value = "Notify the sender after delivery." } }};
    const insertion = [_]text.BusinessSegment{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } }};
    const subject: Subject = .{ .specification = .{ .unit = .primary_user_story, .field = .{ .target = .{ .value = .{ .subject = .story, .field = .value } } } } };
    try tracker.inspect(2, 1, testOrigin(1), subject, .spec_story, .{ .business = .{ .segments = &insertion } });
    // Retaining/assembling the same admitted value does not invent a second
    // producer or inflate the escaped-value count.
    try tracker.inspect(3, 1, testOrigin(1), subject, .spec_story, .{ .business = .{ .segments = &insertion } });
    try tracker.inspect(5, 2, testOrigin(2), subject, .spec_story, .{ .business = .{ .segments = &literal } });
    const usage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;
    const exchanges = [_]Exchange{
        .{ .call = 1, .origin = testOrigin(1), .usage = usage.init(10, 1, 11) },
        .{ .call = 2, .origin = testOrigin(2), .usage = usage.init(20, 2, 22) },
        .{ .call = 3, .origin = testOrigin(3), .usage = null, .uncertain_delivery = true },
        .{ .call = 4, .origin = testOrigin(4), .usage = usage.init(4, 1, 5) },
    };
    const audit = tracker.snapshot(true);
    try validate(a, audit, &exchanges);
    const metric = try measure(audit, &exchanges);
    try std.testing.expectEqual(.measured, metric.status);
    try std.testing.expectEqual(@as(u64, 2), metric.admitted_values);
    try std.testing.expectEqual(@as(u64, 1), metric.escaped_values);
    try std.testing.expectEqual(@as(u64, 2), metric.admitted_origins);
    try std.testing.expectEqual(@as(u64, 1), metric.escaped_origins);
    try std.testing.expectEqual(@as(?f64, 0.5), metric.producer_escape_rate);
    try std.testing.expectEqual(@as(u64, 3), metric.downstream.physical_sends);
    try std.testing.expectEqual(@as(u64, 27), metric.downstream.known_actual_tokens);
    try std.testing.expectEqual(@as(u64, 24), metric.downstream.known_input_tokens);
    try std.testing.expectEqual(@as(u64, 3), metric.downstream.known_output_tokens);
    try std.testing.expect(metric.downstream.actual_tokens == null and metric.downstream.uncertain_delivery);
    try std.testing.expectEqual(.unavailable, (try measure(null, &exchanges)).status);
    try std.testing.expectEqual(.unavailable, (try measure(tracker.snapshot(false), &exchanges)).status);
    var changed = try a.dupe(Check, audit.checks);
    defer a.free(changed);
    changed[0].violation = null;
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = audit.sources, .checks = changed, .complete = true }, &exchanges));
    changed[0] = audit.checks[0];
    changed[0].producer = .{ .model = testOrigin(99) };
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = audit.sources, .checks = changed, .complete = true }, &exchanges));
    const summary = try summarize(&.{ .{ .attempted = true, .metric = metric }, .{ .attempted = true, .metric = .{ .status = .unavailable } }, .{ .attempted = false, .metric = .{ .status = .unavailable } } });
    try std.testing.expectEqual(@as(u64, 1), summary.escaped_workloads);
    try std.testing.expectEqual(@as(u64, 1), summary.unknown_workloads);
    try std.testing.expect(summary.workload_escape_rate == null and !summary.evidence_complete);
    try std.testing.expectEqual(@as(u64, 27), summary.downstream.known_actual_tokens);
    const complete_summary = try summarize(&.{ .{ .attempted = true, .metric = metric }, .{ .attempted = true, .metric = .{ .status = .measured, .admitted_origins = 100 } } });
    try std.testing.expectEqual(@as(u64, 2), complete_summary.attempted_workloads);
    try std.testing.expectEqual(@as(?f64, 0.5), complete_summary.workload_escape_rate);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 102.0), complete_summary.producer_escape_rate.?, 0.0000001);
    const no_admission = try summarize(&.{.{ .attempted = true, .metric = try measure(.{ .sources = &.{}, .checks = &.{}, .complete = true }, &exchanges) }});
    try std.testing.expectEqual(@as(?f64, 0), no_admission.workload_escape_rate);
    try std.testing.expect(no_admission.producer_escape_rate == null);
}

test "wire escape checking uses original source bytes and declared identity exception" {
    const a = std.testing.allocator;
    const embedded = "Display {\"fragments\":[{\"kind\":\"exact_copy\",\"claim_id\":2}]} after approval.";
    const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = embedded } }};
    const value: Value = .{ .business = .{ .segments = &nodes } };
    try std.testing.expectEqual(Violation{ .reason = .embedded_insertion_syntax, .first_node = 0, .last_node = 0, .field = .functional_requirement }, (try check(a, &.{}, .functional_requirement, value)).?);
    const original = [_]Source{.{ .source_id = .{ .ordinal = 1 }, .path = "reference/input.md", .bytes = embedded }};
    try std.testing.expect((try check(a, &original, .functional_requirement, value)) == null);
    const insertion = [_]text.BusinessSegment{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 2 } } }};
    try std.testing.expect((try check(a, &.{}, .entity_name, .{ .business = .{ .segments = &insertion } })) == null);
    for ([_]policy.Field{ .spec_story, .functional_requirement, .ac_then, .entity_meaning }) |field| {
        const failure = (try check(a, &.{}, field, .{ .business = .{ .segments = &insertion } })).?;
        const expected: @FieldType(Violation, "reason") = if (policy.get(field).exact_copy == .prohibited) .prohibited_exact else .reference_only;
        try std.testing.expectEqual(expected, failure.reason);
        try std.testing.expectEqual(field, failure.field.?);
    }
}

test "audit observes native admitted slots and ignores rejected candidate payloads" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const schema = @import("../../../src/application/reference_evidence_workflow.zig").inputs_schema;
    const source = [_]evidence.Source{.{ .id = .{ .ordinal = 1 }, .path = .{ .bytes = "references/message.md" }, .reader = .markdown_source_v1, .bytes = "Send Delivered. after delivery.", .blocks = &.{} }};
    const inputs: evidence.Inputs = .{ .corpus = .{ .state_id = .{ .bytes = "state" }, .feature_id = .{ .bytes = "parcel" }, .sources = &source, .source_mappings = &.{}, .block_mappings = &.{} }, .chunks = .{ .state_id = .{ .bytes = "state" }, .partition = .source_list_items_v1, .entries = &.{} } };
    const input = try values.create(a, schema, evidence.Inputs, inputs);
    defer values.destroy(input);
    const storage = @import("../../../src/application/specification_values.zig").storage;
    const owner = try storage.create(a, .{});
    var transferred = false;
    defer if (!transferred) storage.destroy(owner);
    const field = [_]text.BusinessSegment{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } }};
    owner.payload = .{ .checked = .{ .unit = .primary_user_story, .origins = .{ .initial = testOrigin(1) }, .response = .{ .content = .{ .primary_user_story = .{ .value = .{ .segments = &field }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} } } } } } };
    const admitted = try values.adopt(a, native_spec.checked_schema, storage.Value, storage.Owner, owner, storage.view, storage.destroy, null);
    transferred = true;
    defer values.destroy(admitted);
    var view: data.View = .{};
    view.slots[@intFromEnum(schema.key)] = input;
    view.slots[@intFromEnum(native_spec.checked_schema.key)] = admitted;
    try tracker.observe(&view, 3, 1);
    try std.testing.expectEqual(@as(usize, 1), tracker.checks.items.len);
    try std.testing.expectEqual(.reference_only, tracker.checks.items[0].violation.?.reason);
    try std.testing.expectEqualDeep(testOrigin(1), tracker.checks.items[0].producer.model);
    owner.payload = .rejected;
    try tracker.observe(&view, 4, 1);
    try std.testing.expectEqual(@as(usize, 1), tracker.checks.items.len);
}

test "native audit retains distinct equal record fields but deduplicates their assembled stable subjects" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = "Send the receipt after confirmation." } }};
    const records = [_]specification.RecordProposal{
        .{ .content = .{ .functional_requirement = .{ .text = .{ .segments = &nodes } } }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} } },
        .{ .content = .{ .functional_requirement = .{ .text = .{ .segments = &nodes } } }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} } },
    };
    const batch: generation.Checked = .{ .unit = .records, .origins = .{ .initial = testOrigin(1) }, .response = .{ .content = .{ .records = &records } } };
    try tracker.unit(1, 1, batch, 1);
    try std.testing.expectEqual(@as(usize, 2), tracker.checks.items.len);
    var assembled = batch;
    const assembled_records = [_]specification.RecordProposal{ records[0], records[0], records[1] };
    const origins = [_]candidate.FieldOrigin{
        .{ .target = .{ .record = 0 }, .origin = testOrigin(2) },
        .{ .target = .{ .record = 1 }, .origin = testOrigin(1) },
        .{ .target = .{ .record = 2 }, .origin = testOrigin(1) },
    };
    assembled.response.content.records = &assembled_records;
    assembled.origins = .{ .fields = &origins };
    try tracker.unit(2, 2, assembled, 0);
    try std.testing.expectEqual(@as(usize, 3), tracker.checks.items.len);
    try tracker.unit(3, 2, assembled, 0);
    try std.testing.expectEqual(@as(usize, 3), tracker.checks.items.len);
    const deleted = try assembled.origins.deleting(a, 0, assembled_records.len);
    defer a.free(deleted.fields);
    defer a.free(deleted.record_occurrences.values);
    assembled.response.content.records = assembled_records[1..];
    assembled.origins = deleted;
    try tracker.unit(4, 2, assembled, 0);
    try std.testing.expectEqual(@as(usize, 3), tracker.checks.items.len);
    try validate(a, tracker.snapshot(true), &.{ .{ .call = 1, .origin = testOrigin(1), .usage = null }, .{ .call = 2, .origin = testOrigin(2), .usage = null } });
}

test "audit binds Subject and value kind to the native field policy instead of trusting labels" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const nodes = [_]text.BusinessSegment{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } }};
    const subject: Subject = .{ .specification = .{ .unit = .brief, .field = .{ .target = .{ .value = .{ .subject = .title, .field = .value } } } } };
    try tracker.inspect(1, 1, testOrigin(1), subject, .spec_title, .{ .business = .{ .segments = &nodes } });
    const exchanges = [_]Exchange{.{ .call = 1, .origin = testOrigin(1), .usage = null }};
    var tampered = tracker.checks.items[0];
    tampered.field = .entity_name;
    tampered.violation = null; // recomputed composition for the forged policy
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = &.{}, .checks = &.{tampered}, .complete = true }, &exchanges));
    tampered = tracker.checks.items[0];
    tampered.subject.specification.unit = .entities;
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = &.{}, .checks = &.{tampered}, .complete = true }, &exchanges));
    const reference_value: Value = .{ .reference = .{ .nodes = &.{.{ .literal = .{ .value = "A business statement." } }} } };
    try std.testing.expectError(error.InvalidAdmissionAudit, tracker.inspect(2, 1, testOrigin(1), subject, .spec_title, reference_value));
    const wrong_record: Subject = .{ .specification = .{ .unit = .records, .record_kind = .functional_requirement, .field = .{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .text } } } } };
    try std.testing.expectError(error.InvalidAdmissionAudit, tracker.inspect(2, 1, testOrigin(1), wrong_record, .entity_name, .{ .business = .{ .segments = &nodes } }));
}

test "admitted source-review questions retain exact native subjects and rejected questions remain candidates" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const seeds = [_]authority.Seed{
        .{ .id = .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 1 } }, .slot = .disposition }, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = &.{} },
        .{ .id = .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 2 } }, .slot = .disposition }, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = &.{} },
    };
    const inputs: authority.Inputs = .{ .feature = .{ .bytes = "audit-source-questions" }, .detected_at = .spec, .authorities = &.{}, .evidence = &.{}, .seeds = &seeds };
    const question = "Which authorized delivery decision should apply?";
    const entries = [_]support.Source.Finding{
        .{ .requirement_ordinal = 1, .value = .{ .kind = .unsupported, .detail = "A source decision is missing.", .source_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .question = question } },
        .{ .requirement_ordinal = 2, .value = .{ .kind = .candidate_invalid, .detail = "The candidate exceeds its source.", .source_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .authority_gap = .{ .kind = .unsupported, .source_ids = &.{}, .detail = "An authorization decision is missing.", .question = question } } },
    };
    const origins = [_]?Origin{ testOrigin(1), testOrigin(1) };
    const admitted: support.Source.Candidate = .{ .review = .{ .entries = &entries }, .origin = testOrigin(1), .origins = &origins };
    try tracker.sourceReview(1, 1, inputs, .{ .pending = admitted });
    try tracker.sourceReview(2, 1, inputs, .{ .accepted = .{ .inputs = inputs, .candidate = admitted } });
    try std.testing.expectEqual(@as(usize, 2), tracker.checks.items.len);
    try std.testing.expectEqualDeep(seeds[0].id, tracker.checks.items[0].subject.source_review.requirement);
    try std.testing.expectEqual(.question, tracker.checks.items[0].subject.source_review.question);
    try std.testing.expectEqualDeep(seeds[1].id, tracker.checks.items[1].subject.source_review.requirement);
    try std.testing.expectEqual(.authority_gap_question, tracker.checks.items[1].subject.source_review.question);
    const escaped = "Which {\"kind\":\"exact_copy\",\"claim_id\":1} is authorized?";
    var invalid_entries = entries;
    invalid_entries[0].value.question = escaped;
    var rejected = admitted;
    rejected.review.entries = &invalid_entries;
    try tracker.sourceReview(3, 1, inputs, .{ .rejected = .{ .candidate = rejected, .rejection = .{ .diagnostics = &.{} } } });
    try std.testing.expectEqual(@as(usize, 2), tracker.checks.items.len);
    // An actual admitted invalid value would be a measured mechanical escape.
    try tracker.sourceReview(4, 1, inputs, .{ .pending = rejected });
    try std.testing.expectEqual(@as(usize, 3), tracker.checks.items.len);
    try std.testing.expectEqual(.embedded_insertion_syntax, tracker.checks.items[2].violation.?.reason);
    try validate(a, tracker.snapshot(true), &.{.{ .call = 1, .origin = testOrigin(1), .usage = null }});
}

test "audit batch offsets share native reserved occurrence spans and repaired field assembly provenance" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = "Publish a receipt after approval." } }};
    const records = [_]specification.RecordProposal{.{ .content = .{ .functional_requirement = .{ .text = .{ .segments = &nodes } } }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} } }};
    const left_ids = [_]@import("../../../src/domain/repair_occurrences.zig").Id{.{ .ordinal = 2 }};
    const right_ids = [_]@import("../../../src/domain/repair_occurrences.zig").Id{.{ .ordinal = 2 }};
    const repaired_fields = [_]candidate.FieldOrigin{.{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .text } }, .origin = testOrigin(3) }};
    const batches = [_]generation.Checked{
        .{ .unit = .records, .response = .{ .content = .{ .records = &records } }, .origins = .{ .initial = testOrigin(1), .record_occurrences = .{ .values = &left_ids, .next_ordinal = 4 } }, .record_assignment = .{ .reference_state = .{ .bytes = "state" }, .group_index = 0, .source_group_id = .{ .ordinal = 1 }, .references = .{ .bytes = @splat(0) } } },
        .{ .unit = .records, .response = .{ .content = .{ .records = &records } }, .origins = .{ .initial = testOrigin(2), .fields = &repaired_fields, .record_occurrences = .{ .values = &right_ids, .next_ordinal = 3 } }, .record_assignment = .{ .reference_state = .{ .bytes = "state" }, .group_index = 1, .source_group_id = .{ .ordinal = 2 }, .references = .{ .bytes = @splat(0) } } },
    };
    const current: session.Session = .{ .feature = .{ .bytes = "receipts" }, .reference_state = .{ .bytes = "state" }, .record_batches = &batches };
    const offset = try recordOffset(current, batches[1]);
    try std.testing.expectEqual(@as(usize, 3), offset);
    try tracker.unit(1, 3, batches[1], offset);
    try std.testing.expectEqual(@as(usize, 4), tracker.checks.items[0].subject.specification.field.target.value.subject.record);
    const joined = try batches[0].origins.appendingRecords(a, 1, batches[1].origins, 1);
    defer a.free(joined.fields);
    defer a.free(joined.record_occurrences.values);
    const assembled_records = [_]specification.RecordProposal{ records[0], records[0] };
    const assembled: generation.Checked = .{ .unit = .records, .response = .{ .content = .{ .records = &assembled_records } }, .origins = joined };
    try tracker.unit(2, 3, assembled, 0);
    try std.testing.expectEqual(@as(usize, 2), tracker.checks.items.len);
    try std.testing.expectEqualDeep(testOrigin(3), tracker.checks.items[0].producer.model);
    try validate(a, tracker.snapshot(true), &.{ .{ .call = 1, .origin = testOrigin(1), .usage = null }, .{ .call = 2, .origin = testOrigin(2), .usage = null }, .{ .call = 3, .origin = testOrigin(3), .usage = null } });
}

test "source-checked refreshed questions retain native producers without inventing model origins" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const quoted = "{\"kind\":\"exact_copy\",\"claim_id\":7}";
    const sources = [_]evidence.Source{.{ .id = .{ .ordinal = 1 }, .path = .{ .bytes = "requirements.md" }, .reader = .markdown_source_v1, .bytes = "A delivery approval decision remains unresolved. Example: " ++ quoted, .blocks = &.{} }};
    const inputs: evidence.Inputs = .{ .corpus = .{ .state_id = .{ .bytes = "state" }, .feature_id = .{ .bytes = "parcels" }, .sources = &sources, .source_mappings = &.{}, .block_mappings = &.{} }, .chunks = .{ .state_id = .{ .bytes = "state" }, .partition = .source_list_items_v1, .entries = &.{} } };
    const original_sources = [_]wire.SourceText{.{ .source_id = sources[0].id, .bytes = sources[0].bytes }};
    const records = [_]clarification.Record{.{ .id = "S01", .revision = 1, .subject = .{ .requirement = "specification", .unit = "brief", .slot = "content" }, .authority = &.{.{ .reference = .{ .bytes = "state" } }}, .question = "Which delivery approval rule applies?", .why_required = "The captured source leaves this decision open.", .answer_schema = .{ .bounded_business_text = clarification.max_text_bytes }, .status = .open, .response_id = null, .authority_resolution = null }};
    const ready: clarification_refresh.Ready = .{ .state = .{ .value = .{ .schema = clarification.schema_version, .feature_id = "parcels", .state_ordinal = 1, .revision = 1, .next_ordinal = .{ .spec = 2, .plan = 1, .tasks = 1 }, .next_response_ordinal = 1, .records = &records, .responses = &.{} } }, .original_sources = &original_sources };
    _ = try ready.validate(a);
    const input_schema = @import("../../../src/application/reference_evidence_workflow.zig").inputs_schema;
    const input_value = try values.create(a, input_schema, evidence.Inputs, inputs);
    defer values.destroy(input_value);
    const refreshed = try values.create(a, native_clarifications.state_schema, clarification_refresh.Result, .{ .ready = ready });
    defer values.destroy(refreshed);
    var view: data.View = .{};
    view.slots[@intFromEnum(input_schema.key)] = input_value;
    view.slots[@intFromEnum(native_clarifications.state_schema.key)] = refreshed;
    try tracker.observe(&view, 1, 0);
    try tracker.observe(&view, 2, 0);
    try std.testing.expectEqual(@as(usize, 1), tracker.checks.items.len);
    try std.testing.expectEqualDeep(clarification.Id.parse("S01").?, tracker.checks.items[0].subject.clarification);
    try std.testing.expect(tracker.checks.items[0].producer == .native and tracker.checks.items[0].violation == null);
    try validate(a, tracker.snapshot(true), &.{});
    const metric = try measure(tracker.snapshot(true), &.{});
    try std.testing.expectEqual(.measured, metric.status);
    try std.testing.expectEqual(@as(u64, 0), metric.unattributed_values);
    try std.testing.expectEqual(@as(u64, 0), metric.escaped_values);
    try std.testing.expectEqual(@as(?f64, 0), metric.producer_escape_rate);
    var tampered = tracker.checks.items[0];
    tampered.field = .entity_name;
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = tracker.sources, .checks = &.{tampered}, .complete = true }, &.{}));
    tampered = tracker.checks.items[0];
    tampered.subject.clarification.ordinal = 0;
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = tracker.sources, .checks = &.{tampered}, .complete = true }, &.{}));
    const blocked = try values.create(a, native_clarifications.state_schema, clarification_refresh.Result, .{ .blocked = .protected_clarification });
    defer values.destroy(blocked);
    view.slots[@intFromEnum(native_clarifications.state_schema.key)] = blocked;
    try tracker.observe(&view, 3, 0);
    try std.testing.expectEqual(@as(usize, 1), tracker.checks.items.len);
    // Simulate an owning native gate admitting the bad question. The audit
    // must observe it, not prefilter it with Ready.validate and lose the escape.
    var escaped_records = records;
    escaped_records[0].question = "Which {\"kind\":\"exact_copy\",\"claim_id\":8} controls approval?";
    var escaped_ready = ready;
    escaped_ready.state.value.?.records = &escaped_records;
    escaped_ready.state.value.?.state_ordinal = 2;
    escaped_ready.state.value.?.revision = 2;
    try std.testing.expectError(error.InvalidClarificationInput, escaped_ready.validate(a));
    const escaped = try values.create(a, native_clarifications.state_schema, clarification_refresh.Result, .{ .ready = escaped_ready });
    defer values.destroy(escaped);
    view.slots[@intFromEnum(native_clarifications.state_schema.key)] = escaped;
    try tracker.observe(&view, 4, 0);
    try std.testing.expectEqual(@as(usize, 2), tracker.checks.items.len);
    try std.testing.expectEqual(.embedded_insertion_syntax, tracker.checks.items[1].violation.?.reason);
    const escaped_metric = try measure(tracker.snapshot(true), &.{});
    try std.testing.expectEqual(.measured, escaped_metric.status);
    try std.testing.expectEqual(@as(u64, 1), escaped_metric.escaped_values);
    try std.testing.expectEqual(@as(u64, 0), escaped_metric.unattributed_values);
    // The exact source-backed grammar object remains legitimate prose under
    // both the native readback owner and the independent audit.
    var quoted_records = records;
    quoted_records[0].question = "Which example " ++ quoted ++ " controls approval?";
    var quoted_ready = ready;
    quoted_ready.state.value.?.records = &quoted_records;
    quoted_ready.state.value.?.state_ordinal = 3;
    quoted_ready.state.value.?.revision = 3;
    _ = try quoted_ready.validate(a);
    const source_backed = try values.create(a, native_clarifications.state_schema, clarification_refresh.Result, .{ .ready = quoted_ready });
    defer values.destroy(source_backed);
    view.slots[@intFromEnum(native_clarifications.state_schema.key)] = source_backed;
    try tracker.observe(&view, 5, 0);
    try std.testing.expectEqual(@as(usize, 3), tracker.checks.items.len);
    try std.testing.expect(tracker.checks.items[2].violation == null);
    try validate(a, tracker.snapshot(true), &.{});
    const all = try measure(tracker.snapshot(true), &.{});
    try std.testing.expectEqual(.measured, all.status);
    try std.testing.expectEqual(@as(u64, 1), all.escaped_values);
}

test "missing model provenance remains unavailable and cannot be relabelled native" {
    const a = std.testing.allocator;
    var tracker: Tracker = .init(a);
    defer tracker.deinit();
    const nodes = [_]text.BusinessSegment{.{ .literal = .{ .value = "Retain the original decision." } }};
    const subject: Subject = .{ .specification = .{ .unit = .brief, .field = .{ .target = .{ .value = .{ .subject = .title, .field = .value } } } } };
    try tracker.inspect(1, 0, null, subject, .spec_title, .{ .business = .{ .segments = &nodes } });
    try validate(a, tracker.snapshot(true), &.{});
    const metric = try measure(tracker.snapshot(true), &.{});
    try std.testing.expectEqual(.unavailable, metric.status);
    try std.testing.expectEqual(@as(u64, 1), metric.unattributed_values);
    var forged = tracker.checks.items[0];
    forged.producer = .{ .native = .{ .clarification_refresh = .{ .id = .{ .stage = .spec, .ordinal = 1 }, .state_ordinal = 1, .state_revision = 1, .record_revision = 1, .state_sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" } } };
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = &.{}, .checks = &.{forged}, .complete = true }, &.{}));
    forged.producer = .{ .model = testOrigin(1) };
    try std.testing.expectError(error.InvalidAdmissionAudit, validate(a, .{ .sources = &.{}, .checks = &.{forged}, .complete = true }, &.{}));
    try tracker.inspect(2, 0, testOrigin(1), subject, .spec_title, .{ .business = .{ .segments = &nodes } });
    tracker.reconcile(&.{});
    try std.testing.expectEqual(.missing_model_receipt, tracker.checks.items[1].producer.unavailable);
    try validate(a, tracker.snapshot(true), &.{});
    try std.testing.expectEqual(.unavailable, (try measure(tracker.snapshot(true), &.{})).status);
}
