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
        const spec = @import("specification.zig");
        const packets = @import("model_input_packet.zig");
        const r = @import("reference_reconciliation.zig");
        const admission = @import("specification_support_evidence.zig");
        const source_model = @import("specification_support_model.zig");
        const principles = @import("principle_assessment.zig");
        const evidence_admission = if (purpose == .source) admission else principles;
        const Origin = @import("model_candidate_origin.zig").Origin;
        pub const Error = @import("strict_json.zig").Error || a.Error || p.Error || packets.Error || principles.Error;
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
        };
        pub const Issue = enum {
            invalid_json,
            unknown_requirement,
            duplicate_requirement,
            missing_finding,
            invalid_detail,
            missing_question,
            invalid_question,
            forbidden_question,
            invalid_evidence,
            invalid_decision,

            pub fn isText(self: Issue) bool {
                return switch (self) {
                    .invalid_detail, .missing_question, .invalid_question, .forbidden_question => true,
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

        // Correlate responses by ordinal; native identity/version and revision remain
        // in the retained ledger. Only the applicable review subject reaches the model.
        const Requirement = struct { ordinal: u32, task: []const u8, permitted_not_applicable: ?a.Rule, evidence: admission.Requirements.Guidance };
        const Subject = union(enum) {
            source_preservation: struct {},
            candidate_support: struct { candidate: ?spec.IdentifiedContent, brief: ?spec.Brief },
        };

        pub const Applicability = union(enum) { required, not_applicable: a.Rule, review: a.Rule };

        /// One projection of registered policy and current candidate facts, shared by
        /// requests, admission, insertion repair and persisted evidence re-admission.
        pub fn applicability(inputs: a.Inputs, id: a.Id) Error!Applicability {
            if (purpose == .principles) return .required;
            const policy = a.policy(id) orelse return error.InvalidRequiredAuthority;
            const rule = policy.not_applicable orelse return .required;
            return switch (rule) {
                .no_business_data => if (inputs.specification) |content|
                    if (content.entities.disposition == .not_applicable) .{ .not_applicable = rule } else .required
                else
                    .{ .review = rule },
                .authenticated_exact_scope => error.InvalidRequiredAuthority,
            };
        }

        pub const Scope = union(enum) { finding: a.Id, correction: a.Id };
        pub fn acceptsProjection(projection: @FieldType(a.Inputs, "projection")) bool {
            return switch (purpose) {
                .source => projection == .specification or projection == .source_preservation,
                .principles => projection == .principle_assessment,
            };
        }
        pub fn packetFor(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, scope: Scope) Error!*packets.Packet {
            if (purpose == .principles) return principles.packet(allocator, inputs, context, scope);
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const ledger = try a.build(scratch, inputs);
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            const all = try p.items(context);
            if (!acceptsProjection(inputs.projection) or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id }) or !records.items.state_id.eql(all.state_id)) return error.InvalidRequiredAuthority;
            const target: a.Id = switch (scope) {
                .finding, .correction => |id| id,
            };
            const index = for (ledger.requirements, 0..) |requirement, ordinal| {
                if (std.meta.eql(target, requirement.seed.id)) break ordinal;
            } else return error.InvalidRequiredAuthority;
            const required = try applicability(inputs, target);
            const evidence_rule = try admission.requirements(scratch, inputs, context.inputs, target);
            const assigned = [_]Requirement{.{ .ordinal = try r.ordinal(index), .task = try @import("required_authority_description.zig").task(scratch, target), .permitted_not_applicable = if (required == .review) required.review else null, .evidence = evidence_rule.guidance() }};
            const projected = try @import("model_evidence.zig").project(scratch, all.entries);
            const sources = try @import("model_evidence.zig").sources(scratch, context.inputs);
            const subject: Subject = if (inputs.specification != null or inputs.brief != null) .{ .candidate_support = .{ .candidate = inputs.specification, .brief = inputs.brief } } else .{ .source_preservation = .{} };
            const payload = .{ .subject = subject, .evidence_rules = .{ .instruction = admission.selection_instruction, .eligible_source_ids = evidence_rule.eligible_source_ids, .supported = evidence_rule.rule(.supported, .{ .unlocalized = .{} }).minimum, .not_applicable = evidence_rule.rule(Decision.not_applicable.finding(), .{ .unlocalized = .{} }).minimum, .candidate_omission = evidence_rule.rule(.candidate_omission, .{ .unlocalized = .{} }).minimum, .negative = evidence_rule.rule(.unsupported, .{ .unlocalized = .{} }).minimum }, .requirements = @as([]const Requirement, &assigned), .sources = sources, .extraction = try @import("model_evidence.zig").extractionReview(scratch, context.inputs, all.extraction), .dispositions = records.dispositions, .claims = projected.claims, .citations = projected.citations, .preserved_tokens = projected.preserved_tokens, .signals = try @import("model_evidence.zig").signals(scratch, records.signals), .conflicts = try @import("model_evidence.zig").conflicts(scratch, records.conflicts) };
            const encoded = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
            var projected_input = try @import("strict_json.zig").decode(std.json.Value, scratch, encoded, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
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
                _ = rules.orderedRemove("not_applicable");
                _ = rules.orderedRemove("negative");
            }
            const body = try std.json.Stringify.valueAlloc(scratch, projected_input, .{});
            const slot = try reviewSlot(scratch, inputs, target);
            const definition: ?@import("model_result_schema.zig").DefinitionId = .{ .bytes = if (inputs.projection == .source_preservation) "preservation_finding" else if (required == .review) "applicability_finding" else "finding" };
            return packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = all.state_id.bytes }, .feature_id = inputs.feature, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = slot } } }, .{ .semantic_review = .{ .bytes = slot } }, definition);
        }

        /// A source omission's producer is a separate semantic assignment.
        /// Its result cannot revise the already admitted finding.
        pub fn packetForLoss(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, candidate: Candidate) Error!*packets.Packet {
            if (purpose != .source) return error.InvalidRequiredAuthority;
            var arena: std.heap.ArenaAllocator = .init(allocator);
            defer arena.deinit();
            const scratch = arena.allocator();
            const ordinal = candidate.pending_localization orelse return error.InvalidRequiredAuthority;
            if (ordinal == 0 or ordinal > candidate.review.entries.len) return error.InvalidRequiredAuthority;
            const finding = candidate.review.entries[ordinal - 1];
            if (finding.requirement_ordinal != ordinal or finding.value.kind != .candidate_omission) return error.InvalidRequiredAuthority;
            const ledger = try a.build(scratch, inputs);
            if (ordinal > ledger.requirements.len) return error.InvalidRequiredAuthority;
            const base = try packetFor(allocator, inputs, context, .{ .finding = ledger.requirements[ordinal - 1].seed.id });
            defer packets.release(base);
            const fixed = .{ .finding = .{ .kind = finding.value.kind, .detail = finding.value.detail, .source_ids = finding.value.source_ids } };
            const contextual = try packets.withContext(@TypeOf(fixed), allocator, base, "fixed_review", fixed);
            defer packets.release(contextual);
            const slot = try std.fmt.allocPrint(scratch, "{s}-loss", .{base.unit().semantic_review.review_slot_id.bytes});
            var unit = base.unit();
            unit.semantic_review.review_slot_id.bytes = slot;
            return packets.create(allocator, contextual.body(), unit, .{ .semantic_review = .{ .bytes = slot } }, .{ .bytes = "loss" });
        }

        pub fn collectLoss(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: Collection, packet: *const packets.Packet, bytes: []const u8) Error!Collection {
            if (purpose != .source) return error.InvalidRequiredAuthority;
            const candidate = switch (prior) {
                .accepted => |value| value.candidate,
                .pending => |value| value,
                .rejected => return error.InvalidRequiredAuthority,
            };
            const expected = try packetForLoss(allocator, inputs, context, candidate);
            defer packets.release(expected);
            if (!std.mem.eql(u8, expected.body(), packet.body()) or !@import("model_request_identity.zig").unitOwnerEql(expected.unit(), packet.unit()) or packet.purpose() != .semantic_review or !std.mem.eql(u8, expected.resultDefinition().?.bytes, (packet.resultDefinition() orelse return error.InvalidRequiredAuthority).bytes)) return error.InvalidRequiredAuthority;
            const location = try @import("model_candidate_json.zig").decode(@import("source_omission.zig").Location, allocator, bytes);
            const ordinal = candidate.pending_localization orelse return error.InvalidRequiredAuthority;
            const ledger = try a.build(allocator, inputs);
            const required = try admission.requirements(allocator, inputs, context.inputs, ledger.requirements[ordinal - 1].seed.id);
            const entries = try allocator.dupe(Finding, candidate.review.entries);
            entries[ordinal - 1].value = try source_model.bindLoss(required, entries[ordinal - 1].value, location);
            var next = candidate;
            next.review.entries = entries;
            next.pending_localization = null;
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

        /// Bind the selected native subject to one semantic value. The full
        /// validator remains the sole authority for findings and evidence; only
        /// still-pending membership diagnostics are deferred.
        pub fn collectFocused(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, prior: ?Collection, selected: a.Id, bytes: []const u8, origin: ?Origin) Error!Collection {
            const id = try nextSubject(allocator, inputs, prior);
            if (!std.meta.eql(id, selected)) return error.InvalidRequiredAuthority;
            const value = (if (purpose == .source) source_model.decode(allocator, bytes, try admission.requirements(allocator, inputs, context.inputs, id)) else @import("model_candidate_json.zig").decode(Value, allocator, bytes)) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidJsonDocument => .{ .rejected = .{ .candidate = null, .rejection = .{ .diagnostics = try allocator.dupe(Diagnostic, &.{.{ .issue = .invalid_json, .requirement = id, .ordinal = null, .revision = 1, .origin = origin }}) } } },
            };
            const previous: ?Candidate = if (prior) |result| result.pending else null;
            const length: usize = if (previous) |candidate| candidate.review.entries.len else 0;
            const entries = try allocator.alloc(Finding, length + 1);
            const origins = try allocator.alloc(?Origin, length + 1);
            if (previous) |candidate| {
                @memcpy(entries[0..length], candidate.review.entries);
                @memcpy(origins[0..length], candidate.origins);
            }
            entries[length] = .{ .requirement_ordinal = try r.ordinal(length), .value = value };
            origins[length] = origin;
            const candidate: Candidate = .{
                .review = .{ .entries = entries },
                .revision = if (previous) |old| std.math.add(u64, old.revision, 1) catch return error.InvalidRequiredAuthority else 1,
                .working = true,
                .pending_localization = if (purpose == .source and value.kind == .candidate_omission) try r.ordinal(length) else null,
                .origin = if (previous) |old| old.origin else origin,
                .origins = origins,
                .occurrences = (if (previous) |old| old.occurrences.inserting(allocator, length, length) else (@import("repair_occurrences.zig").Set{}).inserting(allocator, 0, 0)) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidRepairOccurrence => return error.InvalidRequiredAuthority,
                },
                .omission_conflict_claims = if (previous) |old| old.omission_conflict_claims else if (purpose == .source) context.references.records.assignments.checked.prior.prior.source.omission_conflict_claims else &.{},
            };
            return validateWorking(allocator, inputs, context.inputs, candidate);
        }

        pub fn validateWorking(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, candidate: Candidate) Error!Collection {
            if (!candidate.working) return error.InvalidRequiredAuthority;
            const count = candidate.review.entries.len;
            const ledger = try a.build(allocator, inputs);
            if (count == 0 or count > ledger.requirements.len) return error.InvalidRequiredAuthority;
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
            const ledger = try a.build(allocator, inputs);
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
            const candidates = try allocator.alloc(a.Candidate, if (inputs.specification != null) ledger.requirements.len else 0);
            const origins = try allocator.alloc(?Origin, evidence.len);
            for (ledger.requirements, evidence, origins, 0..) |requirement, *entry, *entry_origin, index| {
                const ordinal = try r.ordinal(index);
                const required = try applicability(inputs, requirement.seed.id);
                var found = false;
                for (proposed.review.entries, 0..) |finding, position| {
                    if (finding.requirement_ordinal != ordinal) continue;
                    found = true;
                    const before = diagnostics.items.len;
                    if (purpose == .source) if (decisionOf(finding.value) == .not_applicable and required != .review) try diagnostics.append(allocator, diagnostic(proposed, .invalid_decision, requirement.seed.id, ordinal, position));
                    const semantic = decisionOf(finding.value).finding();
                    var reviewed = if (purpose == .principles) try principles.admit(allocator, inputs, requirement.seed.id, finding.value) else try admission.admit(allocator, inputs, sources, requirement.seed.id, semantic, finding.value.provenance, finding.value.source_ids, finding.value.detail, finding.value.loss);
                    const rejection: ?Diagnostic = if (reviewed == .rejected) rejected: {
                        var invalid = diagnostic(proposed, .invalid_evidence, requirement.seed.id, ordinal, position);
                        if (purpose == .source) if (reviewed.rejected.issue == .invalid_finding) {
                            invalid.issue = .invalid_decision;
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
                    if (purpose == .source) if (admission.questionIssue(semantic, finding.value.question)) |issue| {
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
                    if (inputs.specification != null) {
                        candidates[index] = .{ .id = .{ .ordinal = ordinal, .revision = inputs.revision }, .requirement = requirement.seed.id };
                    }
                    entry.* = .{
                        .id = .{ .ordinal = ordinal },
                        .requirement = requirement.seed.id,
                        .authorities = requirement.seed.input_authorities,
                        .resolution = if (purpose == .principles) .{ .existing_authority = principles.policyAuthority(inputs.principle_context.?.registry) } else if (not_applicable) |rule| .{ .not_applicable = rule } else if (inputs.specification != null and semantic != .candidate_omission) .{ .supported_candidate = candidates[index].id } else .{ .existing_authority = .{ .reference = sources.corpus.state_id } },
                        .finding = semantic,
                        .review = reviewed.accepted,
                        .method = .model_assisted,
                    };
                    entry_origin.* = proposed.origins[position];
                }
                if (!found) try diagnostics.append(allocator, diagnostic(proposed, .missing_finding, requirement.seed.id, ordinal, null));
            }
            if (diagnostics.items.len != 0) return .{ .rejected = .{ .candidate = proposed, .rejection = .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) } } };
            var result = inputs;
            result.evidence = evidence;
            result.candidates = candidates;
            result.review_origin = proposed.origin;
            result.review_origins = origins;
            return .{ .accepted = .{ .inputs = result, .candidate = proposed } };
        }
        fn diagnostic(candidate: Candidate, issue: Issue, requirement: ?a.Id, ordinal: ?u32, index: ?usize) Diagnostic {
            return .{ .issue = issue, .requirement = requirement, .ordinal = ordinal, .revision = candidate.revision, .origin = if (index) |position| candidate.origins[position] else candidate.origin, .entry_index = index };
        }

        /// Re-admit self-contained published findings without any prior call ledger.
        pub fn validateStored(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs) Error!void {
            const ledger = try a.build(allocator, inputs);
            if (inputs.evidence.len != ledger.requirements.len) return error.InvalidRequiredAuthority;
            const findings = try allocator.alloc(Finding, ledger.requirements.len);
            const origins = try allocator.alloc(?Origin, findings.len);
            @memset(origins, null);
            for (ledger.requirements, inputs.evidence, findings, 0..) |requirement, evidence, *finding, index| {
                if (evidence.id.ordinal != index + 1 or !std.meta.eql(evidence.requirement, requirement.seed.id)) return error.InvalidRequiredAuthority;
                try evidence_admission.validate(allocator, inputs, sources, evidence);
                const review = evidence.review.?;
                const required = try applicability(inputs, requirement.seed.id);
                const decision = if (purpose == .source and required == .review and evidence.resolution == .not_applicable) blk: {
                    if (evidence.finding != .supported) return error.InvalidRequiredAuthority;
                    break :blk Decision.not_applicable;
                } else try Decision.fromFinding(evidence.finding);
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = if (purpose == .principles) .{ .decision = decision, .citations = review.principle_citations, .detail = review.detail } else .{ .kind = decision, .provenance = .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, .source_ids = review.source_ids, .detail = review.detail, .question = review.question, .loss = review.loss orelse return error.InvalidRequiredAuthority } };
            }
            var empty = inputs;
            empty.evidence = &.{};
            empty.candidates = &.{};
            const checked = try validate(allocator, empty, sources, .{ .review = .{ .entries = findings }, .origin = null, .origins = origins });
            if (checked != .accepted) return error.InvalidRequiredAuthority;
            if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.evidence, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.evidence, .{})) or
                !std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.candidates, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.candidates, .{}))) return error.InvalidRequiredAuthority;
        }
    };
}

pub const Source = Contract(.source);
