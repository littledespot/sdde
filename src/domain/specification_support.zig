//! Model review admission. Shared authority classification owns continuation.
pub const Purpose = enum { source, principles };

/// One execution-local review assignment. The subject ID comes from the native
/// authority ledger; response ordinals and mutable candidate text never key it.
pub fn reviewSlot(allocator: @import("std").mem.Allocator, inputs: @import("required_authority.zig").Inputs, id: @import("required_authority.zig").Id) @import("std").mem.Allocator.Error![]const u8 {
    const std = @import("std");
    const prefix: []const u8 = if (inputs.projection == .principle_assessment) "principle-consistency" else if (inputs.specification != null or inputs.brief != null) "candidate-support" else "source-preservation";
    const digest = try @import("atomic_repair.zig").snapshot(@import("required_authority.zig").Id, allocator, id);
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, std.fmt.bytesToHex(digest.bytes, .lower) });
}

pub fn Contract(comptime purpose: Purpose) type {
    return struct {
        const std = @import("std");
        const a = @import("required_authority.zig");
        const p = @import("specification_provenance.zig");
        const packets = @import("model_input_packet.zig");
        const r = @import("reference_reconciliation.zig");
        const admission = @import("specification_support_evidence.zig");
        const source_model = @import("specification_support_model.zig");
        const subjects = @import("specification_review_subject.zig");
        const principles = @import("principle_assessment.zig");
        const evidence_admission = if (purpose == .source) admission else principles;
        const Origin = @import("model_candidate_origin.zig").Origin;
        pub const Error = @import("strict_json.zig").Error || a.Error || p.Error || packets.Error || principles.Error || (if (purpose == .source) @import("source_omission_binding.zig").ComparisonError else error{}) || @import("model_result_schema.zig").ChoiceBoundError;
        pub const Review = struct { entries: []const Finding };
        pub const Finding = struct { requirement_ordinal: u32, value: Value };
        /// A review judges support or an explicitly permitted applicability exception.
        /// Native authority evidence keeps the finding and resolution separate.
        pub const Decision = if (purpose == .principles) principles.Decision else source_model.Decision;
        pub const Value = if (purpose == .principles) principles.Value else source_model.Canonical;
        /// Source responses use the schema discriminator; policy reviews retain
        /// their independent closed decision vocabulary.
        pub fn decisionOf(value: Value) Decision {
            return if (purpose == .source) value.kind else value.decision;
        }

        pub const Candidate = struct {
            omission_conflict_claims: []const r.ClaimId = &.{},
            review: Review,
            revision: u64 = 1,
            working: bool = false,
            pending_localization: ?u32 = null,
            origin: ?Origin,
            origins: []const ?Origin,
            last_repair: ?@import("atomic_repair.zig").Merge = null,
            occurrences: @import("repair_occurrences.zig").Set = .{},
            occurrence_history: []const Occurrence = &.{},
        };
        pub const Occurrence = struct { subject: a.Id, occurrence: @import("repair_occurrences.zig").Id };
        pub const Issue = enum {
            invalid_json,
            unknown_requirement,
            duplicate_requirement,
            missing_finding,
            invalid_detail,
            invalid_obligation,
            missing_question,
            invalid_question,
            forbidden_question,
            invalid_evidence,
            invalid_decision,

            pub fn isText(self: Issue) bool {
                return switch (self) {
                    .invalid_detail, .invalid_obligation, .missing_question, .invalid_question, .forbidden_question => true,
                    else => false,
                };
            }
        };
        pub const Diagnostic = struct { issue: Issue, requirement: ?a.Id, ordinal: ?u32, revision: u64, origin: ?Origin, entry_index: ?usize = null, evidence: ?evidence_admission.Rejection = null };
        pub const Rejection = struct {
            diagnostics: []const Diagnostic,

            /// Selection is derived from the collector's stable order, never a second ledger.
            pub fn selected(self: Rejection) ?Diagnostic {
                return if (self.diagnostics.len == 0) null else self.diagnostics[0];
            }
        };
        pub const Collection = union(enum) {
            accepted: struct { inputs: a.Inputs, candidate: Candidate },
            rejected: struct { candidate: ?Candidate, rejection: Rejection },
            pending: Candidate,
        };

        /// Stop optional advice without manufacturing findings. Retain only a
        /// complete valid native assignment prefix; a rejected assignment is
        /// discarded as a whole, including its otherwise valid siblings.
        pub fn stop(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: ?Collection, reason: a.AdviceStop.Reason, origin: ?Origin) Error!Collection {
            if (!acceptsProjection(inputs.projection) or a.assessmentPolicy(inputs.projection) != .advisory or inputs.advice_stop != null or inputs.evidence.len != 0 or inputs.candidates.len != 0) return error.InvalidRequiredAuthority;
            const ledger = try a.build(allocator, inputs);
            if (prior) |value| if (value == .accepted) {
                var current = value.accepted.inputs;
                current.evidence = inputs.evidence;
                current.candidates = inputs.candidates;
                current.review_origin = inputs.review_origin;
                current.review_origins = inputs.review_origins;
                current.principle_assessment = inputs.principle_assessment;
                if (!std.mem.eql(u8, try @import("canonical_json.zig").encode(a.Inputs, allocator, current), try @import("canonical_json.zig").encode(a.Inputs, allocator, inputs))) return error.InvalidRequiredAuthority;
                try validateStored(allocator, value.accepted.inputs, context.inputs);
                return value;
            };
            var candidate: Candidate = if (prior) |value| switch (value) {
                .pending => |pending| pending,
                .rejected => |rejected| rejected.candidate orelse .{ .review = .{ .entries = &.{} }, .origin = null, .origins = &.{} },
                .accepted => unreachable,
            } else .{ .review = .{ .entries = &.{} }, .origin = null, .origins = &.{} };
            if (candidate.origins.len != candidate.review.entries.len or candidate.review.entries.len > ledger.requirements.len) return error.InvalidRequiredAuthority;
            var retained: usize = 0;
            while (retained < candidate.review.entries.len) {
                const assigned = try assignmentSubjects(allocator, inputs, ledger.requirements[retained].seed.id);
                const end = std.math.add(usize, retained, assigned.len) catch return error.InvalidRequiredAuthority;
                if (end > candidate.review.entries.len) break;
                var prefix = candidate;
                prefix.working = true;
                prefix.pending_localization = null;
                prefix.review.entries = candidate.review.entries[0..end];
                prefix.origins = candidate.origins[0..end];
                const checked = try validateWorking(allocator, inputs, context.inputs, prefix);
                if (checked == .rejected) break;
                retained = end;
            }
            candidate.working = false;
            candidate.pending_localization = null;
            candidate.review.entries = candidate.review.entries[0..retained];
            candidate.origins = candidate.origins[0..retained];
            if (retained == ledger.requirements.len) return validate(allocator, inputs, context.inputs, candidate);
            const requirements = try allocator.alloc(a.Id, ledger.requirements.len);
            for (ledger.requirements, requirements) |requirement, *id| id.* = requirement.seed.id;
            var stopped = inputs;
            stopped.advice_stop = .{ .reason = reason, .projection = inputs.projection, .candidate_revision = inputs.revision, .requirements = requirements, .unassessed = requirements[retained..], .authorities = inputs.authorities, .origin = origin };
            return validate(allocator, stopped, context.inputs, candidate);
        }

        // Correlate responses by ordinal; native identity/version and revision remain
        // in the retained ledger. Only the applicable review subject reaches the model.
        const Requirement = struct { ordinal: u32, task: []const u8, permitted_not_applicable: ?a.Rule, evidence: admission.Requirements.Guidance };

        pub const Applicability = a.Applicability;

        /// Requests, admission, repair and readback use the registered owner.
        pub const applicability = a.applicability;

        /// Only unresolved native applicability permits a `not_applicable` source
        /// verdict. Request schemas, guidance, admission and readback share this rule.
        pub fn permitsNotApplicable(required: Applicability) bool {
            return required == .review;
        }

        pub const Scope = union(enum) { finding: a.Id, correction: a.Id, assignment: a.Id };

        pub fn assignmentScope(inputs: a.Inputs, id: a.Id) Scope {
            return if (a.assessmentPolicy(inputs.projection) == .advisory) .{ .assignment = id } else .{ .finding = id };
        }

        pub fn assignmentSubjects(allocator: std.mem.Allocator, inputs: a.Inputs, id: a.Id) Error![]const a.Id {
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const ledger = try a.build(scratch, inputs);
            const owner = try subjects.assignmentUnit(scratch, inputs, id);
            var selected: std.ArrayList(a.Id) = .empty;
            var started = false;
            for (ledger.requirements) |required| {
                const current = required.seed.id;
                const same = std.meta.eql(owner, try subjects.assignmentUnit(scratch, inputs, current));
                if (!started) {
                    if (!std.meta.eql(current, id)) {
                        if (same) return error.InvalidRequiredAuthority;
                        continue;
                    }
                    started = true;
                }
                if (!same) break;
                try selected.append(allocator, current);
            }
            if (selected.items.len == 0) return error.InvalidRequiredAuthority;
            return selected.toOwnedSlice(allocator);
        }
        pub fn acceptsProjection(projection: @FieldType(a.Inputs, "projection")) bool {
            return switch (purpose) {
                .source => projection == .source_readiness or projection == .specification or projection == .source_preservation,
                .principles => projection == .principle_assessment,
            };
        }
        pub fn packetFor(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, scope: Scope) Error!*packets.Packet {
            if (scope == .assignment) return assignmentPacket(allocator, inputs, context, scope.assignment);
            if (purpose == .principles) return principles.packet(allocator, inputs, context, scope);
            return packetForContext(allocator, inputs, context, scope);
        }

        /// A stopped request must still belong to this exact current native
        /// assignment or authorized finding repair, not merely the same feature.
        pub fn matchesAdvicePacket(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: ?Collection, packet: *const packets.Packet) @import("specification_support_repair.zig").Contract(purpose).Error!bool {
            if (!acceptsProjection(inputs.projection) or a.assessmentPolicy(inputs.projection) != .advisory) return false;
            const bound = packet.advisoryAssessment() orelse return false;
            const dependencies = try adviceDependencies(allocator, inputs);
            if (bound.projection != (if (purpose == .source) .source else .principles) or bound.candidate_revision != inputs.revision or
                !std.mem.eql(u8, bound.feature.bytes, inputs.feature.bytes) or !bound.reference_state.eql(context.inputs.corpus.state_id) or
                !std.mem.eql(u8, &bound.dependencies, &dependencies)) return false;
            const expected = if (packet.repairPermit() != null) repaired: {
                const current = prior orelse return false;
                if (current != .rejected or current.rejected.candidate == null) return false;
                const Repair = @import("specification_support_repair.zig").Contract(purpose);
                const authorization = try Repair.authorize(allocator, inputs, context, current.rejected);
                break :repaired try Repair.packet(allocator, inputs, context, current.rejected.candidate.?, authorization);
            } else try packetFor(allocator, inputs, context, assignmentScope(inputs, try nextSubject(allocator, inputs, prior)));
            defer packets.release(expected);
            checkPacket(expected, packet) catch |err| return if (err == error.InvalidRequiredAuthority) false else err;
            return std.meta.eql(expected.repairPermit(), packet.repairPermit()) and
                std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, expected.excludedVariants(), .{}), try std.json.Stringify.valueAlloc(allocator, packet.excludedVariants(), .{})) and
                std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, expected.integerChoices(), .{}), try std.json.Stringify.valueAlloc(allocator, packet.integerChoices(), .{}));
        }

        fn assignmentDefinition() @import("model_result_schema.zig").DefinitionId {
            return .{ .bytes = if (purpose == .source) "assignment_findings" else "principle_assignment_findings" };
        }

        /// Copy a member-arena JSON value into the assignment arena. Both the
        /// serialized bytes and the decoded copy are allocated from `scratch`.
        fn copyJson(scratch: std.mem.Allocator, value: std.json.Value) Error!std.json.Value {
            return @import("strict_json.zig").decode(std.json.Value, scratch, try std.json.Stringify.valueAlloc(scratch, value, .{}), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
        }

        /// Positive verdicts a source member may not take: `not_applicable` outside
        /// an applicability review, and any positive verdict to which no claim
        /// set can be bound (ADR 0023 route 4). Negative verdicts always resolve.
        fn withheldVerdicts(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, target: a.Id) Error!std.EnumSet(source_model.Decision) {
            var withheld = std.EnumSet(source_model.Decision).initEmpty();
            if (!permitsNotApplicable(try applicability(inputs, target))) withheld.insert(.not_applicable);
            const required = try admission.requirements(allocator, inputs, sources, target);
            for ([_]source_model.Decision{ .supported, .not_applicable }) |verdict| if (!source_model.resolves(required, verdict)) withheld.insert(verdict);
            return withheld;
        }

        fn assignmentPacket(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, id: a.Id) Error!*packets.Packet {
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const selected = try assignmentSubjects(scratch, inputs, id);
            // The member choice is bounded (ADR 0006). A larger assignment rejects
            // before any member packet is built, and is never split (ADR 0011).
            if (!@import("model_result_schema.zig").withinChoiceBound(selected.len)) return error.ChoiceBoundExceeded;
            const ledger = try a.build(scratch, inputs);
            var body: ?std.json.Value = null;
            var business_context: ?std.json.Value = null;
            var assigned: std.ArrayList(std.json.Value) = .empty;
            const ordinals = try scratch.alloc(i64, selected.len);
            var sources: std.ArrayList(i64) = .empty;
            // The shared batch envelope lists every source verdict. Native
            // applicability and claim resolution narrow it, and one assignment
            // has one restriction.
            var withheld: ?std.EnumSet(source_model.Decision) = null;
            for (selected, ordinals) |target, *ordinal| {
                // Each member's single packet repeats the shared evidence. Build it in
                // a member arena and keep only its own entry, so a large record family
                // holds one copy of the shared body rather than one per member.
                var member_arena: std.heap.ArenaAllocator = .init(allocator);
                defer member_arena.deinit();
                const local = member_arena.allocator();
                if (purpose == .source) {
                    const member = try withheldVerdicts(local, inputs, context.inputs, target);
                    if (withheld) |prior| if (!prior.eql(member)) return error.InvalidRequiredAuthority;
                    withheld = member;
                }
                const single = if (purpose == .source) try packetForContext(local, inputs, context, .{ .finding = target }) else try principles.packet(local, inputs, context, .{ .finding = target });
                defer packets.release(single);
                var parsed = try @import("strict_json.zig").decode(std.json.Value, local, single.body(), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
                // Copy the shared body before the member entry below mutates aliased
                // maps; its per-member fields are replaced in the payload anyway.
                if (body == null) body = try copyJson(scratch, parsed);
                ordinal.* = for (ledger.requirements, 0..) |required, index| {
                    if (std.meta.eql(required.seed.id, target)) break @intCast(index + 1);
                } else return error.InvalidRequiredAuthority;
                var requirement: std.json.Value = if (purpose == .source) parsed.object.get("requirements").?.array.items[0] else .{ .object = .empty };
                if (purpose == .principles) {
                    try requirement.object.put(local, "ordinal", .{ .integer = ordinal.* });
                    try requirement.object.put(local, "task", parsed.object.get("task").?);
                }
                var subject = parsed.object.get("subject").?;
                if (purpose == .source) {
                    // A record family spans several records, so every member keeps
                    // its own record context; fields outside records carry none.
                    if (subject.object.get("record")) |value| if (value == .null) {
                        _ = subject.object.orderedRemove("record");
                    };
                } else {
                    if (subject.object.fetchOrderedRemove("context")) |entry| business_context = try copyJson(scratch, entry.value);
                }
                try requirement.object.put(local, "subject", subject);
                if (purpose == .source) {
                    try requirement.object.put(local, "assessment_scope", parsed.object.get("assessment_scope").?);
                    var rules = parsed.object.get("evidence_rules").?;
                    // Guidance offers only the verdicts the assignment may take.
                    if (withheld.?.contains(.supported)) _ = rules.object.orderedRemove("supported");
                    if (withheld.?.contains(.not_applicable)) {
                        _ = rules.object.orderedRemove("not_applicable");
                        _ = requirement.object.orderedRemove("permitted_not_applicable");
                    }
                    try requirement.object.put(local, "evidence_rules", rules);
                    for (rules.object.get("eligible_source_ids").?.array.items) |source| {
                        if (std.mem.indexOfScalar(i64, sources.items, source.integer) == null) try sources.append(scratch, source.integer);
                    }
                }
                try assigned.append(scratch, try copyJson(scratch, requirement));
            }
            var payload = body.?;
            _ = payload.object.orderedRemove("subject");
            _ = payload.object.orderedRemove("task");
            _ = payload.object.orderedRemove("assessment_scope");
            _ = payload.object.orderedRemove("evidence_rules");
            try payload.object.put(scratch, "requirements", .{ .array = std.array_list.Managed(std.json.Value).fromOwnedSlice(scratch, try assigned.toOwnedSlice(scratch)) });
            if (business_context) |value| try payload.object.put(scratch, "business_context", value);
            const slot = try std.fmt.allocPrint(scratch, "{s}-assignment", .{try reviewSlot(scratch, inputs, id)});
            const state = (try p.items(context)).state_id;
            const definition = assignmentDefinition();
            const reviewed = try reviewPacket(allocator, inputs, state, try std.json.Stringify.valueAlloc(scratch, payload, .{}), slot, definition);
            defer packets.release(reviewed);
            // A withheld verdict fails response admission, so it takes the bounded
            // protocol correction instead of reaching native canonicalization.
            const base: *const packets.Packet = if (purpose == .source and withheld.?.count() != 0) excluded: {
                const prior = reviewed.excludedVariants();
                const excluded = try scratch.alloc(@import("model_result_schema.zig").ExcludedVariant, prior.len + withheld.?.count());
                @memcpy(excluded[0..prior.len], prior);
                var next = prior.len;
                var verdicts = withheld.?.iterator();
                while (verdicts.next()) |verdict| : (next += 1) excluded[next] = .{ .kind = @tagName(verdict) };
                break :excluded try packets.withExcludedVariants(allocator, reviewed, excluded);
            } else try packets.retain(reviewed);
            defer packets.release(base);
            // Response admission requires exactly one finding per member, so a
            // missing, repeated or foreign member gets the bounded protocol correction.
            const ordinal_choice: @import("model_result_schema.zig").IntegerChoice = .{ .target = .{ .path = &.{ .{ .property = "findings" }, .items, .{ .property = "requirement_ordinal" } } }, .definition = definition, .allowed = ordinals, .collection = .exact_members };
            const selected_packet = if (purpose == .source) try packets.withIntegerChoices(allocator, base, &.{
                ordinal_choice,
                .{ .target = .{ .path = &.{ .{ .property = "findings" }, .items, .{ .property = "value" }, .{ .property = "source_ids" } } }, .definition = definition, .allowed = sources.items },
                .{ .target = .{ .path = &.{ .{ .property = "findings" }, .items, .{ .property = "value" }, .{ .property = "authority_gap" }, .{ .property = "source_ids" } } }, .definition = definition, .allowed = sources.items },
            }) else try packets.withIntegerChoices(allocator, base, &.{ordinal_choice});
            defer packets.release(selected_packet);
            return if (purpose == .source) withQuestionText(allocator, selected_packet, context.inputs, true) else packets.withBody(allocator, selected_packet, selected_packet.body());
        }

        fn packetForContext(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, scope: Scope) Error!*packets.Packet {
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const ledger = try a.build(scratch, inputs);
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            const all = try p.items(context);
            if (!acceptsProjection(inputs.projection) or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id }) or !records.items.state_id.eql(all.state_id)) return error.InvalidRequiredAuthority;
            const target: a.Id = switch (scope) {
                .finding, .correction => |id| id,
                .assignment => return error.InvalidRequiredAuthority,
            };
            const index = for (ledger.requirements, 0..) |requirement, ordinal| {
                if (std.meta.eql(target, requirement.seed.id)) break ordinal;
            } else return error.InvalidRequiredAuthority;
            const required = try applicability(inputs, target);
            const evidence_rule = try admission.requirements(scratch, inputs, context.inputs, target);
            const assigned = [_]Requirement{.{ .ordinal = try r.ordinal(index), .task = try @import("required_authority_description.zig").task(scratch, target), .permitted_not_applicable = if (permitsNotApplicable(required)) required.review else null, .evidence = evidence_rule.guidance() }};
            const projected = try @import("model_evidence.zig").project(scratch, all.entries);
            const sources = try @import("model_evidence.zig").sources(scratch, context.inputs);
            const subject = try subjects.project(scratch, inputs, context, target);
            const reconstruction = switch (subject) {
                .candidate_field => false,
                .reference => |reference| reference != .signal,
                .source_preservation, .collection, .entity_applicability => true,
            };
            const payload = .{ .subject = subject, .assessment_scope = @import("required_authority_description.zig").sourceReviewScope(subject), .evidence_rules = .{ .instruction = admission.selection_instruction, .eligible_source_ids = evidence_rule.eligible_source_ids, .supported = evidence_rule.rule(.supported, .{ .unlocalized = .{} }).minimum, .not_applicable = if (permitsNotApplicable(required)) evidence_rule.rule(Decision.not_applicable.finding(), .{ .unlocalized = .{} }).minimum else null, .candidate_omission = evidence_rule.rule(.candidate_omission, .{ .unlocalized = .{} }).minimum, .candidate_invalid = evidence_rule.rule(.candidate_invalid, .{ .unlocalized = .{} }).minimum, .negative = evidence_rule.rule(.unsupported, .{ .unlocalized = .{} }).minimum }, .requirements = @as([]const Requirement, &assigned), .sources = sources, .extraction = if (reconstruction) try @import("model_evidence.zig").extractionReview(scratch, context.inputs, all.extraction) else null, .dispositions = if (reconstruction) records.dispositions else null, .claims = projected.claims, .citations = projected.citations, .preserved_tokens = projected.preserved_tokens, .signals = if (reconstruction) try @import("model_evidence.zig").signals(scratch, records.signals) else null, .conflicts = if (reconstruction) try @import("model_evidence.zig").conflicts(scratch, records.conflicts) else null };
            const encoded = try @import("model_candidate_json.zig").encodeEvidence(@TypeOf(payload), scratch, payload);
            var projected_input = try @import("strict_json.zig").decode(std.json.Value, scratch, encoded, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
            packets.omitAbsent(&projected_input);
            // Guidance offers only verdicts native applicability permits.
            packets.omitAbsent(projected_input.object.getPtr("evidence_rules").?);
            for (projected_input.object.getPtr("requirements").?.array.items) |*requirement| {
                packets.omitAbsent(requirement.object.getPtr("evidence").?);
                packets.omitAbsent(requirement);
                // A correction preserves the decision; its retained diagnostic supplies
                // the selected evidence rule once. Insertion still needs all choices.
                if (scope == .correction) {
                    _ = requirement.object.orderedRemove("evidence");
                    _ = requirement.object.orderedRemove("permitted_not_applicable");
                }
            }
            if (scope == .correction) _ = projected_input.object.orderedRemove("evidence_rules");
            if (inputs.projection == .source_preservation and scope == .finding) {
                const rules = &projected_input.object.getPtr("evidence_rules").?.object;
                _ = rules.orderedRemove("negative");
            }
            const body = try std.json.Stringify.valueAlloc(scratch, projected_input, .{});
            const slot = try reviewSlot(scratch, inputs, target);
            const definition: ?@import("model_result_schema.zig").DefinitionId = .{ .bytes = if (inputs.projection == .source_preservation) "preservation_finding" else if (permitsNotApplicable(required)) "applicability_finding" else "finding" };
            const packet = try reviewPacket(allocator, inputs, all.state_id, body, slot, definition);
            defer packets.release(packet);
            const ids = try scratch.alloc(i64, evidence_rule.eligible_source_ids.len);
            for (ids, evidence_rule.eligible_source_ids) |*id, source| id.* = source.ordinal;
            const selected_sources: @import("model_result_schema.zig").IntegerChoice = .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = definition, .allowed = ids };
            const selected_packet = if (inputs.projection == .source_preservation)
                try packets.withIntegerChoices(allocator, packet, &.{selected_sources})
            else
                try packets.withIntegerChoices(allocator, packet, &.{ selected_sources, .{ .target = .{ .path = &.{ .{ .property = "authority_gap" }, .{ .property = "source_ids" } } }, .definition = definition, .allowed = ids } });
            defer packets.release(selected_packet);
            if (inputs.projection == .source_preservation) return packets.withOriginalSources(allocator, selected_packet, context.inputs);
            return withQuestionText(allocator, selected_packet, context.inputs, false);
        }

        fn withQuestionText(allocator: std.mem.Allocator, base: *const packets.Packet, sources: r.evidence.Inputs, batch: bool) Error!*packets.Packet {
            const witnessed = try packets.withOriginalSources(allocator, base, sources);
            defer packets.release(witnessed);
            const Field = @import("model_text_wire.zig").ProseField;
            const fields: []const Field = if (batch) &.{
                .{ .field = .clarification_question, .path = &.{ .{ .property = "findings" }, .items, .{ .property = "value" }, .{ .property = "question" } } },
                .{ .field = .clarification_question, .path = &.{ .{ .property = "findings" }, .items, .{ .property = "value" }, .{ .property = "authority_gap" }, .{ .property = "question" } } },
            } else &.{
                .{ .field = .clarification_question, .path = &.{.{ .property = "question" }} },
                .{ .field = .clarification_question, .path = &.{ .{ .property = "authority_gap" }, .{ .property = "question" } } },
            };
            const prose = try packets.withProseFields(allocator, witnessed, fields);
            defer packets.release(prose);
            const bindings = (if (batch)
                @import("model_candidate_json.zig").fieldBindings(source_model.Batch, allocator, .{})
            else
                @import("model_candidate_json.zig").fieldBindings(source_model.Value, allocator, .{})) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
            defer {
                for (bindings) |binding| {
                    for (binding.path) |step| switch (step) {
                        .property, .variant => |name| allocator.free(name),
                        .items => {},
                    };
                    allocator.free(binding.path);
                }
                allocator.free(bindings);
            }
            return packets.withFieldPolicies(allocator, prose, bindings);
        }

        fn lossFinding(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, candidate: Candidate) Error!struct { finding: Finding, target: a.Id } {
            if (purpose != .source) return error.InvalidRequiredAuthority;
            const ordinal = candidate.pending_localization orelse return error.InvalidRequiredAuthority;
            if (ordinal == 0 or ordinal > candidate.review.entries.len) return error.InvalidRequiredAuthority;
            const finding = candidate.review.entries[ordinal - 1];
            if (finding.requirement_ordinal != ordinal or finding.value.kind != .candidate_omission) return error.InvalidRequiredAuthority;
            const ledger = try a.build(allocator, inputs);
            if (ordinal > ledger.requirements.len) return error.InvalidRequiredAuthority;
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            const all = try p.items(context);
            if (!acceptsProjection(inputs.projection) or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id }) or !records.items.state_id.eql(all.state_id)) return error.InvalidRequiredAuthority;
            return .{ .finding = finding, .target = ledger.requirements[ordinal - 1].seed.id };
        }

        pub const ComparisonError = Error || @import("source_omission_binding.zig").ComparisonError;

        pub fn comparisonAssignment(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, candidate: Candidate) ComparisonError!@import("source_omission.zig").comparisons.Assignment {
            const fixed = try lossFinding(allocator, inputs, context, candidate);
            return @import("source_omission_binding.zig").build(allocator, inputs, context.inputs, fixed.target, fixed.finding.requirement_ordinal, candidate.revision, .{
                .detail = fixed.finding.value.detail,
                .missing_obligation = fixed.finding.value.missing_obligation,
                .source_ids = fixed.finding.value.source_ids,
                .provenance = .{ .claim_ids = fixed.finding.value.provenance.claim_ids, .citation_ids = &.{}, .clarification_response_ids = fixed.finding.value.provenance.clarification_response_ids },
            });
        }

        pub fn packetForLoss(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, candidate: Candidate) ComparisonError!*packets.Packet {
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const assigned = try comparisonAssignment(scratch, inputs, context, candidate);
            const presentation = @import("source_omission_context.zig");
            const ModelMember = struct { id: @import("source_omission.zig").comparisons.MemberId, requirement: presentation.ClaimMeaning };
            const ModelView = struct { id: @import("source_omission.zig").comparisons.Id, members: []const ModelMember };
            const views = try scratch.alloc(ModelView, assigned.comparisons.len);
            var claim_ids: std.ArrayList(r.ClaimId) = .empty;
            for (assigned.comparisons, views) |view, *projected| {
                const members = try scratch.alloc(ModelMember, view.members.len);
                for (view.members, members) |member, *projected_member| {
                    projected_member.* = .{ .id = member.id, .requirement = try presentation.claimMeaning(scratch, assigned.facts.records.items, member.claim_id, context) };
                    if (!r.contains(r.ClaimId, claim_ids.items, member.claim_id)) try claim_ids.append(scratch, member.claim_id);
                }
                projected.* = .{ .id = view.id, .members = members };
            }
            const payload = .{
                .fixed_finding = .{ .missing_obligation = assigned.finding.missing_obligation },
                .sources = assigned.sources,
                .comparisons = views,
                .supporting_evidence = .{
                    .diagnostic_detail = assigned.finding.detail,
                    .target_purpose = try @import("required_authority_description.zig").task(scratch, assigned.finding.subject),
                    .deficient_subject = presentation.fixedSubject(try subjects.projectLoss(scratch, inputs, context, assigned.finding.subject)),
                    .producers = try presentation.comparisonSupport(scratch, assigned.facts.records, context, assigned.finding.source_ids, claim_ids.items),
                },
            };
            const body = try @import("model_candidate_json.zig").encodeEvidence(@TypeOf(payload), scratch, payload);
            const slot = try std.fmt.allocPrint(scratch, "{s}-loss", .{try reviewSlot(scratch, inputs, assigned.finding.subject)});
            const packet = try reviewPacket(allocator, inputs, context.inputs.corpus.state_id, body, slot, .{ .bytes = "preservation_comparisons" });
            defer packets.release(packet);
            // The binding always assigns the extracted-claims comparison; none is not a state.
            if (assigned.comparisons.len == 0) return error.InvalidRequiredAuthority;
            const ids = try scratch.alloc(i64, assigned.comparisons.len);
            for (assigned.comparisons, ids) |view, *id| id.* = view.id.ordinal;
            // Native admission requires exactly one assessment per comparison, so
            // response admission binds the same member set.
            return packets.withIntegerChoices(allocator, packet, &.{.{ .target = .{ .path = &.{ .{ .property = "assessments" }, .items, .{ .property = "comparison_id" } } }, .definition = .{ .bytes = "preservation_comparisons" }, .allowed = ids, .collection = .exact_members }});
        }

        pub fn admitComparisons(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, candidate: Candidate, retained: @import("source_omission.zig").comparisons.Assignment, bytes: []const u8) ComparisonError!@import("source_omission.zig").comparisons.Attribution {
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const owner = @import("source_omission.zig").comparisons;
            const current = try comparisonAssignment(scratch, inputs, context, candidate);
            return owner.admit(scratch, retained, current, context.inputs, try @import("model_candidate_json.zig").decode(owner.Response, scratch, bytes));
        }

        fn reviewPacket(allocator: std.mem.Allocator, inputs: a.Inputs, state: r.evidence.identity.StateId, body: []const u8, slot: []const u8, definition: ?@import("model_result_schema.zig").DefinitionId) Error!*packets.Packet {
            const base = try packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = state.bytes }, .feature_id = inputs.feature, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = slot } } }, .{ .semantic_review = .{ .bytes = slot } }, definition);
            if (a.assessmentPolicy(inputs.projection) != .advisory) return base;
            defer packets.release(base);
            return classifyAdvicePacket(allocator, inputs, state, base);
        }

        pub fn classifyAdvicePacket(allocator: std.mem.Allocator, inputs: a.Inputs, state: r.evidence.identity.StateId, base: *const packets.Packet) Error!*packets.Packet {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            _ = try a.build(arena.allocator(), inputs);
            if (!acceptsProjection(inputs.projection) or a.assessmentPolicy(inputs.projection) != .advisory) return error.InvalidRequiredAuthority;
            return packets.withAdvisoryAssessment(allocator, base, .{ .feature = inputs.feature, .reference_state = .{ .bytes = state.bytes }, .candidate_revision = inputs.revision, .projection = if (purpose == .source) .source else .principles, .dependencies = try adviceDependencies(arena.allocator(), inputs) });
        }

        fn adviceDependencies(allocator: std.mem.Allocator, inputs: a.Inputs) std.mem.Allocator.Error![32]u8 {
            var native = inputs;
            native.evidence = &.{};
            native.candidates = &.{};
            native.review_origin = null;
            native.review_origins = &.{};
            native.principle_assessment = null;
            native.advice_stop = null;
            return (try @import("atomic_repair.zig").snapshot(a.Inputs, allocator, native)).bytes;
        }

        pub fn collectLoss(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: Collection, packet: *const packets.Packet, bytes: []const u8, origin: ?Origin) Error!Collection {
            if (purpose != .source) return error.InvalidRequiredAuthority;
            const candidate = switch (prior) {
                .accepted => |value| value.candidate,
                .pending => |value| value,
                .rejected => return error.InvalidRequiredAuthority,
            };
            const expected = try packetForLoss(allocator, inputs, context, candidate);
            defer packets.release(expected);
            try checkPacket(expected, packet);
            const owner = @import("source_omission.zig").comparisons;
            const assigned = try comparisonAssignment(allocator, inputs, context, candidate);
            const response = try @import("model_candidate_json.zig").decode(owner.Response, allocator, bytes);
            const proof: owner.Evidence = .{ .assignment = assigned, .response = response, .origin = origin };
            const attribution = owner.admit(allocator, assigned, assigned, context.inputs, response) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                const fixed = try lossFinding(allocator, inputs, context, candidate);
                const rule = try admission.requirements(allocator, inputs, context.inputs, fixed.target);
                const diagnostics = try allocator.dupe(Diagnostic, &.{.{ .issue = .invalid_evidence, .requirement = fixed.target, .ordinal = fixed.finding.requirement_ordinal, .revision = candidate.revision, .origin = origin, .entry_index = fixed.finding.requirement_ordinal - 1, .evidence = .{ .issue = .invalid_loss, .rule = rule.rule(.candidate_omission, .{ .unlocalized = .{} }) } }});
                var rejected = candidate;
                const rejected_entries = try allocator.dupe(Finding, candidate.review.entries);
                rejected_entries[fixed.finding.requirement_ordinal - 1].value.preservation = proof;
                rejected.review.entries = rejected_entries;
                return .{ .rejected = .{ .candidate = rejected, .rejection = .{ .diagnostics = diagnostics } } };
            };
            const ordinal = candidate.pending_localization orelse return error.InvalidRequiredAuthority;
            const ledger = try a.build(allocator, inputs);
            const required = try admission.requirements(allocator, inputs, context.inputs, ledger.requirements[ordinal - 1].seed.id);
            const entries = try allocator.dupe(Finding, candidate.review.entries);
            entries[ordinal - 1].value = try source_model.bindLoss(required, entries[ordinal - 1].value, owner.location(attribution), proof);
            var next = candidate;
            next.review.entries = entries;
            next.pending_localization = pendingLocalization(inputs, entries);
            next.revision = std.math.add(u64, candidate.revision, 1) catch return error.InvalidRequiredAuthority;
            return if (next.working) validateWorking(allocator, inputs, context.inputs, next) else validate(allocator, inputs, context.inputs, next);
        }

        pub fn nextSubject(allocator: std.mem.Allocator, inputs: a.Inputs, prior: ?Collection) Error!a.Id {
            const ledger = try a.build(allocator, inputs);
            const count: usize = if (prior) |value| switch (value) {
                .pending => |candidate| if (candidate.working and candidate.pending_localization == null) candidate.review.entries.len else return error.InvalidRequiredAuthority,
                .accepted, .rejected => return error.InvalidRequiredAuthority,
            } else 0;
            if (count >= ledger.requirements.len) return error.InvalidRequiredAuthority;
            return ledger.requirements[count].seed.id;
        }

        /// Select outstanding omissions from admitted findings, not a second
        /// queue. Each receives its own current complete comparison assignment.
        pub fn pendingLocalization(inputs: a.Inputs, entries: []const Finding) ?u32 {
            if (a.assessmentPolicy(inputs.projection) == .advisory) return null;
            if (purpose == .source) for (entries) |finding| {
                if (finding.value.kind == .candidate_omission and finding.value.preservation == null) return finding.requirement_ordinal;
            };
            return null;
        }

        /// Bind every produced finding before advancing. Record responses must
        /// name exactly the complete native assignment; the full validator owns
        /// individual finding/evidence admission and narrow repair diagnostics.
        pub fn collectFocused(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: ?Collection, packet: *const packets.Packet, bytes: []const u8, origin: ?Origin) Error!Collection {
            const id = try nextSubject(allocator, inputs, prior);
            const scope = assignmentScope(inputs, id);
            const grouped = scope == .assignment;
            const expected = try packetFor(allocator, inputs, context, scope);
            defer packets.release(expected);
            try checkPacket(expected, packet);
            const previous: ?Candidate = if (prior) |result| result.pending else null;
            const length: usize = if (previous) |candidate| candidate.review.entries.len else 0;
            const added = (if (grouped) decodeAssignment(allocator, inputs, context, id, length, bytes, origin) else decodeSingle(allocator, inputs, context, id, length, bytes)) catch |err| return switch (err) {
                error.InvalidJsonDocument => rejectedAssignment(allocator, id, .invalid_json, origin, if (previous) |old| old.revision else 1),
                else => err,
            };
            if (added == .rejected) return .{ .rejected = .{ .candidate = null, .rejection = added.rejected } };
            return appendAdmitted(allocator, inputs, context, prior, packet, added.findings, origin);
        }

        /// Current assignment membership and ordinary full admission are shared
        /// by model collection and execution-local retained native findings.
        pub fn appendAdmitted(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: ?Collection, packet: *const packets.Packet, findings: []const Finding, origin: ?Origin) Error!Collection {
            const id = try nextSubject(allocator, inputs, prior);
            const scope = assignmentScope(inputs, id);
            const grouped = scope == .assignment;
            const expected = try packetFor(allocator, inputs, context, scope);
            defer packets.release(expected);
            try checkPacket(expected, packet);
            const previous: ?Candidate = if (prior) |result| result.pending else null;
            const length: usize = if (previous) |candidate| candidate.review.entries.len else 0;
            const ledger = try a.build(allocator, inputs);
            const assigned = if (grouped) try assignmentSubjects(allocator, inputs, id) else try allocator.dupe(a.Id, &.{id});
            if (findings.len != assigned.len) return error.InvalidRequiredAuthority;
            for (findings, assigned, length..) |finding, subject, index| {
                if (finding.requirement_ordinal != index + 1 or !std.meta.eql(ledger.requirements[index].seed.id, subject)) return error.InvalidRequiredAuthority;
            }
            const entries = try allocator.alloc(Finding, length + findings.len);
            const origins = try allocator.alloc(?Origin, entries.len);
            if (previous) |candidate| {
                @memcpy(entries[0..length], candidate.review.entries);
                @memcpy(origins[0..length], candidate.origins);
            }
            @memcpy(entries[length..], findings);
            @memset(origins[length..], origin);
            var occurrences = if (previous) |old| old.occurrences else @import("repair_occurrences.zig").Set{};
            for (length..entries.len) |index| {
                occurrences = occurrences.inserting(allocator, index, index) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidRepairOccurrence => return error.InvalidRequiredAuthority,
                };
                if (previous) |old| for (old.occurrence_history) |retained| {
                    if (!std.meta.eql(retained.subject, ledger.requirements[index].seed.id)) continue;
                    if (retained.occurrence.ordinal == 0 or retained.occurrence.ordinal >= occurrences.next_ordinal) return error.InvalidRequiredAuthority;
                    for (occurrences.values[0..index]) |present| if (std.meta.eql(present, retained.occurrence)) return error.InvalidRequiredAuthority;
                    const stable = try allocator.dupe(@import("repair_occurrences.zig").Id, occurrences.values);
                    stable[index] = retained.occurrence;
                    occurrences.values = stable;
                    break;
                };
            }
            const candidate: Candidate = .{
                .review = .{ .entries = entries },
                .revision = if (previous) |old| std.math.add(u64, old.revision, 1) catch return error.InvalidRequiredAuthority else 1,
                .working = true,
                .pending_localization = pendingLocalization(inputs, entries),
                .origin = if (previous) |old| old.origin else origin,
                .origins = origins,
                .occurrences = occurrences,
                .occurrence_history = if (previous) |old| old.occurrence_history else &.{},
                .last_repair = if (previous) |old| old.last_repair else null,
                .omission_conflict_claims = if (previous) |old| old.omission_conflict_claims else if (purpose == .source) context.references.records.assignments.checked.prior.prior.source.omission_conflict_claims else &.{},
            };
            return validateWorking(allocator, inputs, context.inputs, candidate);
        }

        const Added = union(enum) { findings: []const Finding, rejected: Rejection };
        fn decodeSingle(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, id: a.Id, start: usize, bytes: []const u8) Error!Added {
            const value = if (purpose == .source) try source_model.decode(allocator, bytes, try admission.requirements(allocator, inputs, context.inputs, id)) else try @import("model_candidate_json.zig").decode(Value, allocator, bytes);
            return .{ .findings = try allocator.dupe(Finding, &.{.{ .requirement_ordinal = try r.ordinal(start), .value = value }}) };
        }
        fn rejectedAssignment(allocator: std.mem.Allocator, id: a.Id, issue: Issue, origin: ?Origin, revision: u64) Error!Collection {
            return .{ .rejected = .{ .candidate = null, .rejection = .{ .diagnostics = try allocator.dupe(Diagnostic, &.{.{ .issue = issue, .requirement = id, .ordinal = null, .revision = revision, .origin = origin }}) } } };
        }

        fn decodeAssignment(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, id: a.Id, start: usize, bytes: []const u8, origin: ?Origin) Error!Added {
            const ids = try assignmentSubjects(allocator, inputs, id);
            const Batch = if (purpose == .source) source_model.Batch else struct { findings: []const Finding };
            const response = try @import("model_candidate_json.zig").decode(Batch, allocator, bytes);
            var diagnostics: std.ArrayList(Diagnostic) = .empty;
            for (response.findings, 0..) |finding, index| {
                const ordinal = finding.requirement_ordinal;
                const authorized = ordinal > start and ordinal - start <= ids.len;
                if (!authorized) try diagnostics.append(allocator, .{ .issue = .unknown_requirement, .requirement = null, .ordinal = ordinal, .revision = inputs.revision, .origin = origin });
                for (response.findings[0..index]) |previous| if (previous.requirement_ordinal == ordinal) {
                    try diagnostics.append(allocator, .{ .issue = .duplicate_requirement, .requirement = if (authorized) ids[ordinal - start - 1] else null, .ordinal = ordinal, .revision = inputs.revision, .origin = origin });
                    break;
                };
            }
            for (ids, start..) |target, index| {
                const ordinal = try r.ordinal(index);
                for (response.findings) |finding| {
                    if (finding.requirement_ordinal == ordinal) break;
                } else try diagnostics.append(allocator, .{ .issue = .missing_finding, .requirement = target, .ordinal = ordinal, .revision = inputs.revision, .origin = origin });
            }
            if (diagnostics.items.len != 0) return .{ .rejected = .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) } };
            const findings = try allocator.alloc(Finding, ids.len);
            for (ids, findings, start..) |target, *finding, index| {
                const ordinal = try r.ordinal(index);
                const wire = for (response.findings) |entry| {
                    if (entry.requirement_ordinal == ordinal) break entry.value;
                } else return error.InvalidRequiredAuthority;
                finding.* = .{ .requirement_ordinal = ordinal, .value = if (purpose == .source) try source_model.canonical(wire, try admission.requirements(allocator, inputs, context.inputs, target)) else wire };
            }
            return .{ .findings = findings };
        }

        fn checkPacket(expected: *const packets.Packet, actual: *const packets.Packet) Error!void {
            const definition = actual.resultDefinition() orelse return error.InvalidRequiredAuthority;
            if (!std.mem.eql(u8, expected.body(), actual.body()) or
                !@import("model_request_identity.zig").unitOwnerEql(expected.unit(), actual.unit()) or
                !@import("model_request_identity.zig").purposeEqlBounded(expected.purpose(), actual.purpose(), 1) or
                !std.mem.eql(u8, expected.resultDefinition().?.bytes, definition.bytes)) return error.InvalidRequiredAuthority;
        }

        pub fn validateWorking(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, candidate: Candidate) Error!Collection {
            if (!candidate.working) return error.InvalidRequiredAuthority;
            const count = candidate.review.entries.len;
            const ledger = try a.build(allocator, inputs);
            if (count > ledger.requirements.len) return error.InvalidRequiredAuthority;
            for (candidate.review.entries, 0..) |finding, index| if (finding.requirement_ordinal != index + 1) return error.InvalidRequiredAuthority;
            const complete = try validate(allocator, inputs, sources, candidate);
            if (complete == .accepted) return complete;
            var diagnostics: std.ArrayList(Diagnostic) = .empty;
            for (complete.rejected.rejection.diagnostics) |issue| {
                if (issue.issue == .missing_finding and issue.ordinal != null and issue.ordinal.? > count) continue;
                try diagnostics.append(allocator, issue);
            }
            if (diagnostics.items.len != 0) return .{ .rejected = .{ .candidate = candidate, .rejection = .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) } } };
            if (count == ledger.requirements.len) return error.InvalidRequiredAuthority;
            return .{ .pending = candidate };
        }

        pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, proposed: Candidate) Error!Collection {
            if ((purpose == .principles) != (inputs.projection == .principle_assessment)) return error.InvalidRequiredAuthority;
            var unreviewed = inputs;
            unreviewed.advice_stop = null;
            const ledger = try a.build(allocator, unreviewed);
            if (inputs.evidence.len != 0 or inputs.candidates.len != 0 or proposed.revision == 0 or proposed.origins.len != proposed.review.entries.len) return error.InvalidRequiredAuthority;
            var diagnostics: std.ArrayList(Diagnostic) = .empty;
            // Preserve selection order: association defects in response order, then
            // missing/invalid findings in native requirement order. Inspect every sibling.
            for (proposed.review.entries, 0..) |finding, index| {
                if (finding.requirement_ordinal == 0 or finding.requirement_ordinal > ledger.requirements.len) {
                    try diagnostics.append(allocator, diagnostic(proposed, .unknown_requirement, null, finding.requirement_ordinal, index));
                    continue;
                }
                for (proposed.review.entries[0..index]) |prior| if (finding.requirement_ordinal == prior.requirement_ordinal) {
                    try diagnostics.append(allocator, diagnostic(proposed, .duplicate_requirement, ledger.requirements[finding.requirement_ordinal - 1].seed.id, finding.requirement_ordinal, index));
                    break;
                };
            }
            const evidence = try allocator.alloc(a.Evidence, ledger.requirements.len);
            const candidates = try allocator.alloc(a.Candidate, if (a.assessmentPolicy(inputs.projection) == .advisory or inputs.specification != null) ledger.requirements.len else 0);
            const origins = try allocator.alloc(?Origin, evidence.len);
            for (ledger.requirements, evidence, origins, 0..) |requirement, *entry, *entry_origin, index| {
                const ordinal = try r.ordinal(index);
                const required = try applicability(inputs, requirement.seed.id);
                var found = false;
                for (proposed.review.entries, 0..) |finding, position| {
                    if (finding.requirement_ordinal != ordinal) continue;
                    found = true;
                    const before = diagnostics.items.len;
                    if (purpose == .source) if (decisionOf(finding.value) == .not_applicable and !permitsNotApplicable(required)) try diagnostics.append(allocator, diagnostic(proposed, .invalid_decision, requirement.seed.id, ordinal, position));
                    const semantic = decisionOf(finding.value).finding();
                    var reviewed = if (purpose == .principles) try principles.admit(allocator, inputs, requirement.seed.id, finding.value) else try admission.admit(allocator, inputs, sources, requirement.seed.id, semantic, finding.value.provenance, finding.value.source_ids, finding.value.detail, finding.value.missing_obligation, finding.value.loss, finding.value.preservation, finding.value.authority_gap);
                    const rejection: ?Diagnostic = if (reviewed == .rejected) rejected: {
                        var invalid = diagnostic(proposed, .invalid_evidence, requirement.seed.id, ordinal, position);
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_finding) {
                            invalid.issue = .invalid_decision;
                        };
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_obligation) {
                            invalid.issue = .invalid_obligation;
                        };
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_gap_detail) {
                            invalid.issue = .invalid_detail;
                        };
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_gap_question) {
                            invalid.issue = .invalid_question;
                        };
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_loss) {
                            if (finding.value.preservation) |proof| invalid.origin = proof.origin;
                        };
                        invalid.evidence = reviewed.rejected;
                        break :rejected invalid;
                    } else null;
                    // A forbidden verdict cannot be made safe by repairing its text.
                    if (rejection) |invalid| if (invalid.issue == .invalid_decision) {
                        try diagnostics.append(allocator, invalid);
                        continue;
                    };
                    if (!admission.validDetail(semantic, finding.value.detail)) try diagnostics.append(allocator, diagnostic(proposed, .invalid_detail, requirement.seed.id, ordinal, position));
                    if (purpose == .source) if (try admission.questionIssueIn(allocator, sources, semantic, finding.value.question)) |issue| {
                        const text_issue: Issue = switch (issue) {
                            inline else => |value| @field(Issue, @tagName(value)),
                        };
                        try diagnostics.append(allocator, diagnostic(proposed, text_issue, requirement.seed.id, ordinal, position));
                    };
                    if (purpose == .source and reviewed == .accepted) {
                        reviewed.accepted.question = finding.value.question;
                    }
                    if (rejection) |invalid| try diagnostics.append(allocator, invalid);
                    if (diagnostics.items.len != before) continue;
                    const not_applicable: ?a.Rule = if (purpose == .principles) null else if (required == .not_applicable) required.not_applicable else if (decisionOf(finding.value) == .not_applicable) required.review else null;
                    if (candidates.len != 0) {
                        candidates[index] = .{ .id = .{ .ordinal = ordinal, .revision = inputs.revision }, .requirement = requirement.seed.id };
                    }
                    entry.* = .{
                        .id = .{ .ordinal = ordinal },
                        .requirement = requirement.seed.id,
                        .authorities = requirement.seed.input_authorities,
                        .resolution = if (a.assessmentPolicy(inputs.projection) == .advisory) .{ .assessment = .{ .candidate = candidates[index].id, .not_applicable = not_applicable } } else if (purpose == .principles) .{ .existing_authority = principles.policyAuthority(inputs.principle_context.?.registry) } else if (semantic == .candidate_invalid) .{ .existing_authority = .{ .reference = sources.corpus.state_id } } else if (not_applicable) |rule| .{ .not_applicable = rule } else if (inputs.specification != null and semantic != .candidate_omission) .{ .supported_candidate = candidates[index].id } else .{ .existing_authority = .{ .reference = sources.corpus.state_id } },
                        .finding = semantic,
                        .review = reviewed.accepted,
                        .method = .model_assisted,
                    };
                    entry_origin.* = proposed.origins[position];
                }
                if (!found) {
                    if (inputs.advice_stop) |stopped| if (a.contains(a.Id, stopped.unassessed, requirement.seed.id)) continue;
                    try diagnostics.append(allocator, diagnostic(proposed, .missing_finding, requirement.seed.id, ordinal, null));
                }
            }
            if (diagnostics.items.len != 0) return .{ .rejected = .{ .candidate = proposed, .rejection = .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) } } };
            var result = inputs;
            result.evidence = evidence;
            result.candidates = candidates;
            result.review_origin = proposed.origin;
            result.review_origins = origins;
            if (inputs.advice_stop != null) {
                const admitted_evidence = try allocator.alloc(a.Evidence, proposed.review.entries.len);
                const admitted_candidates = try allocator.alloc(a.Candidate, proposed.review.entries.len);
                const admitted_origins = try allocator.alloc(?Origin, proposed.review.entries.len);
                for (proposed.review.entries, admitted_evidence, admitted_candidates, admitted_origins) |finding, *entry, *candidate, *origin| {
                    const index = finding.requirement_ordinal - 1;
                    entry.* = evidence[index];
                    candidate.* = candidates[index];
                    origin.* = origins[index];
                }
                result.evidence = admitted_evidence;
                result.candidates = admitted_candidates;
                result.review_origins = admitted_origins;
                _ = try a.build(allocator, result);
                try validateAssignmentPrefix(allocator, result, proposed.review.entries.len);
            }
            return .{ .accepted = .{ .inputs = result, .candidate = proposed } };
        }
        fn diagnostic(candidate: Candidate, issue: Issue, requirement: ?a.Id, ordinal: ?u32, index: ?usize) Diagnostic {
            return .{ .issue = issue, .requirement = requirement, .ordinal = ordinal, .revision = candidate.revision, .origin = if (index) |position| candidate.origins[position] else candidate.origin, .entry_index = index };
        }

        /// Re-admit self-contained published findings without any prior call ledger.
        pub fn validateStored(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs) Error!void {
            const ledger = try a.build(allocator, inputs);
            if (inputs.advice_stop == null and inputs.evidence.len != ledger.requirements.len) return error.InvalidRequiredAuthority;
            if (inputs.advice_stop != null) try validateAssignmentPrefix(allocator, inputs, inputs.evidence.len);
            const findings = try allocator.alloc(Finding, inputs.evidence.len);
            const origins = try allocator.alloc(?Origin, findings.len);
            @memset(origins, null);
            var previous: u32 = 0;
            for (inputs.evidence, findings) |evidence, *finding| {
                const ordinal = evidence.id.ordinal;
                if (ordinal <= previous or ordinal > ledger.requirements.len) return error.InvalidRequiredAuthority;
                previous = ordinal;
                const requirement = ledger.requirements[ordinal - 1];
                if (!std.meta.eql(evidence.requirement, requirement.seed.id)) return error.InvalidRequiredAuthority;
                try evidence_admission.validate(allocator, inputs, sources, evidence);
                const review = evidence.review.?;
                const required = try applicability(inputs, requirement.seed.id);
                const decision = if (purpose == .source and permitsNotApplicable(required) and (evidence.resolution == .not_applicable or (evidence.resolution == .assessment and evidence.resolution.assessment.not_applicable != null))) blk: {
                    if (evidence.finding != .supported) return error.InvalidRequiredAuthority;
                    break :blk Decision.not_applicable;
                } else try Decision.fromFinding(evidence.finding);
                finding.* = .{ .requirement_ordinal = ordinal, .value = if (purpose == .principles) .{ .decision = decision, .citations = review.principle_citations, .detail = review.detail } else .{ .kind = decision, .provenance = .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, .source_ids = review.source_ids, .detail = review.detail, .missing_obligation = review.missing_obligation, .question = review.question, .authority_gap = review.authority_gap, .loss = review.loss orelse return error.InvalidRequiredAuthority, .preservation = review.preservation } };
            }
            var empty = inputs;
            empty.evidence = &.{};
            empty.candidates = &.{};
            const checked = try validate(allocator, empty, sources, .{ .review = .{ .entries = findings }, .origin = null, .origins = origins });
            if (checked != .accepted) return error.InvalidRequiredAuthority;
            if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.evidence, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.evidence, .{})) or
                !std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.candidates, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.candidates, .{}))) return error.InvalidRequiredAuthority;
        }

        fn validateAssignmentPrefix(allocator: std.mem.Allocator, inputs: a.Inputs, count: usize) Error!void {
            const ledger = try a.build(allocator, inputs);
            if (count > ledger.requirements.len) return error.InvalidRequiredAuthority;
            var position: usize = 0;
            while (position < count) {
                const assigned = try assignmentSubjects(allocator, inputs, ledger.requirements[position].seed.id);
                position = std.math.add(usize, position, assigned.len) catch return error.InvalidRequiredAuthority;
                if (position > count) return error.InvalidRequiredAuthority;
            }
        }
    };
}

pub const Source = Contract(.source);
