//! Offline projections of retained captures. Unknown historical metadata never
//! becomes workflow authority or an inferred requirement association. Every
//! returned allocation belongs to the caller's short-lived arena.
const std = @import("std");
const strict = @import("../../../src/domain/strict_json.zig");
const envelope = @import("../../../src/domain/model_envelope.zig");
const schema_owner = @import("../../../src/domain/model_result_schema.zig");
const field_owner = @import("../../../src/domain/model_text_field.zig");
const wire = @import("../../../src/domain/model_text_wire.zig");
const typed = @import("../../../src/domain/typed_text.zig");
const policy = @import("../../../src/domain/text_field_policy.zig");
const pointer = @import("../../../src/domain/json_pointer.zig");
pub const recognition = @import("recognition.zig");
pub const MetadataContract = enum { current_v7, historical_v3, historical_v4, historical_v5, unavailable };
pub const Input = struct {
    packet: []const u8,
    output: []const u8,
    schema: ?[]const u8 = null,
    field_policies: []const field_owner.Binding = &.{},
    prose_fields: []const wire.ProseField = &.{},
    original_sources: ?[]const wire.SourceText = null,
    metadata_contract: MetadataContract = .current_v7,
    exact_scope: ?@import("../../../src/domain/model_exact_values.zig").Scope = null,
};
pub const State = enum { measured, no_exact_context, invalid_packet, invalid_model_json, missing_schema, invalid_field_metadata, unsupported_schema, schema_invalid, no_declared_text_fields };
pub const Binding = enum { assigned_requirements, selected_groups, explicit_provenance, fixed_candidate, missing, invalid };
pub const ResultState = enum { matched, no_match, ambiguous, rejected, unavailable_boundary_context };
pub const Result = struct {
    state: ResultState,
    matches: []const recognition.Witness = &.{},
    unbound_matches: []const recognition.Witness = &.{},
    diagnostics: []const recognition.Diagnostic = &.{},
    rejection: ?recognition.Rejection = null,
};
pub const Run = struct { ordinal: usize, bytes_sha256: []const u8, byte_length: usize, result: Result };
pub const TypedReference = struct { occurrence: ?u32, resolved: bool };
pub const Composition = enum { valid, invalid, unavailable_field_metadata, unavailable_source_metadata, ambiguous, not_evaluated };
pub const Field = struct {
    path: []const u8,
    native_field: ?policy.Field,
    raw_value_sha256: []const u8,
    representation: enum { current_wire, historical_array },
    source_metadata: enum { native_description, packet_projection, unavailable },
    binding: Binding,
    bound_requirements: []const recognition.RequirementId,
    plain_runs: []const Run,
    typed_exact_references: []const TypedReference,
    // This is explicitly a derived rendering, never retained provider output.
    historical_typed_counterfactual: ?Run,
    original_composition: Composition,
    proposed_composition: Composition,
    proposed_composition_issue: ?@FieldType(typed.Issue, "reason"),
};
pub const Measurement = struct {
    metadata_contract: MetadataContract,
    native_exact_scope: ?@import("../../../src/domain/model_exact_values.zig").Scope = null,
    binding_policy: enum { selected_requirement_membership } = .selected_requirement_membership,
    state: State,
    occurrence_count: usize = 0,
    occurrence_ids: []const recognition.OccurrenceId = &.{},
    output_sha256: ?[]const u8 = null,
    normalization: envelope.Normalization = .none,
    fields: []const Field = &.{},
    semantic_quality_assessed: bool = false,
    workflow_authority: bool = false,
};
pub fn hash(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}
fn member(value: std.json.Value, key: []const u8) ?std.json.Value {
    return if (value == .object) value.object.get(key) else null;
}
fn text(value: std.json.Value) ?[]const u8 {
    return if (value == .string) value.string else null;
}
fn positive(value: std.json.Value) ?u32 {
    if (value != .number_string) return null;
    const parsed = @import("../../../src/domain/model_payload_schema.zig").exactInteger(value.number_string) catch return null;
    return if (parsed > 0 and parsed <= std.math.maxInt(u32)) @intCast(parsed) else null;
}
fn ids(a: std.mem.Allocator, value: std.json.Value) ![]const recognition.RequirementId {
    if (value != .array) return error.InvalidCaptureProjection;
    const result = try a.alloc(recognition.RequirementId, value.array.items.len);
    for (value.array.items, result, 0..) |raw, *id, index| {
        id.* = .{ .value = positive(raw) orelse return error.InvalidCaptureProjection };
        for (result[0..index]) |prior| if (prior.value == id.value) return error.InvalidCaptureProjection;
    }
    return result;
}
fn claims(a: std.mem.Allocator, requirements: std.json.Value) ![]const recognition.RequirementId {
    if (requirements != .array) return error.InvalidCaptureProjection;
    var result: std.ArrayList(recognition.RequirementId) = .empty;
    for (requirements.array.items) |requirement| {
        const id = positive(member(requirement, "claim_id") orelse return error.InvalidCaptureProjection) orelse return error.InvalidCaptureProjection;
        for (result.items) |prior| if (prior.value == id) return error.InvalidCaptureProjection;
        try result.append(a, .{ .value = id });
    }
    return result.toOwnedSlice(a);
}
const Bound = struct { kind: Binding, requirements: []const recognition.RequirementId };
fn binding(a: std.mem.Allocator, packet: std.json.Value, ancestors: []const std.json.Value) !Bound {
    // Returned selectors are candidate data: require an exact, nonempty join
    // to supplied groups, never a same-source or catalogue-availability match.
    var index = ancestors.len;
    while (index != 0) {
        index -= 1;
        if (member(ancestors[index], "signal_ids")) |selected| {
            const selections = try ids(a, selected);
            if (selections.len == 0) return error.InvalidCaptureProjection;
            const groups = member(packet, "source_groups") orelse return error.InvalidCaptureProjection;
            if (groups != .array) return error.InvalidCaptureProjection;
            var result: std.ArrayList(recognition.RequirementId) = .empty;
            for (selections) |selection| {
                var found: usize = 0;
                for (groups.array.items) |group| if (positive(member(group, "signal_id") orelse return error.InvalidCaptureProjection) == selection.value) {
                    found += 1;
                    for (try claims(a, member(group, "requirements") orelse return error.InvalidCaptureProjection)) |id| {
                        for (result.items) |prior| {
                            if (prior.value == id.value) break;
                        } else try result.append(a, id);
                    }
                };
                if (found != 1) return error.InvalidCaptureProjection;
            }
            return .{ .kind = .selected_groups, .requirements = try result.toOwnedSlice(a) };
        }
        if (member(ancestors[index], "provenance")) |provenance| if (member(provenance, "claim_ids")) |selected| return .{ .kind = .explicit_provenance, .requirements = try ids(a, selected) };
    }
    if (member(packet, "source_assignment")) |assignment| if (member(assignment, "requirements")) |requirements| return .{ .kind = .assigned_requirements, .requirements = try claims(a, requirements) };
    // Only a directly pinned candidate is usable here. A containing full
    // candidate/collection has no implicit selected repair target.
    if (member(packet, "candidate")) |candidate| if (member(candidate, "provenance")) |provenance| if (member(provenance, "claim_ids")) |selected| return .{ .kind = .fixed_candidate, .requirements = try ids(a, selected) };
    return .{ .kind = .missing, .requirements = &.{} };
}
pub fn measure(a: std.mem.Allocator, input: Input, classifier: recognition.LexicalClassifier) !Measurement {
    var result: Measurement = .{ .metadata_contract = input.metadata_contract, .state = .invalid_packet, .output_sha256 = try hash(a, input.output) };
    const parsed_packet = strict.parse(a, input.packet, .{ .maximum_depth = 128 }, false, null) catch |err| return if (err == error.OutOfMemory) err else result;
    var packet = parsed_packet.value;
    if (member(packet, "input")) |inner| if (inner == .object) {
        packet = inner;
    };
    var occurrences: []recognition.Occurrence = undefined;
    var occurrence_ids: []recognition.OccurrenceId = undefined;
    if (input.exact_scope) |scope| {
        if (input.metadata_contract != .current_v7 or !@import("../../../src/domain/model_exact_values.zig").valid(scope)) {
            result.state = .invalid_field_metadata;
            return result;
        }
        result.native_exact_scope = scope;
        occurrences = try a.alloc(recognition.Occurrence, scope.occurrences.len);
        occurrence_ids = try a.alloc(recognition.OccurrenceId, scope.occurrences.len);
        for (scope.occurrences, occurrences, occurrence_ids) |native, *occurrence, *id| {
            id.* = .{ .value = native.claim_id.ordinal };
            occurrence.* = .{ .id = id.*, .requirements = try a.dupe(recognition.RequirementId, &.{.{ .value = id.value }}), .bytes = native.bytes };
        }
    } else {
        const tokens = member(packet, "preserved_tokens") orelse {
            result.state = .no_exact_context;
            return result;
        };
        if (tokens != .array) return result;
        if (tokens.array.items.len == 0) {
            result.state = .no_exact_context;
            return result;
        }
        occurrences = try a.alloc(recognition.Occurrence, tokens.array.items.len);
        occurrence_ids = try a.alloc(recognition.OccurrenceId, tokens.array.items.len);
        for (tokens.array.items, occurrences, occurrence_ids, 0..) |token, *occurrence, *id, index| {
            id.* = .{ .value = positive(member(token, "claim_id") orelse return result) orelse return result };
            for (occurrence_ids[0..index]) |prior| if (prior.value == id.value) return result;
            const bytes = text(member(token, "value") orelse return result) orelse return result;
            occurrence.* = .{ .id = id.*, .requirements = try a.dupe(recognition.RequirementId, &.{.{ .value = id.value }}), .bytes = bytes };
        }
    }
    if (occurrences.len == 0) {
        result.state = .no_exact_context;
        return result;
    }
    result.occurrence_count = occurrences.len;
    result.occurrence_ids = occurrence_ids;
    result.state = .invalid_model_json;
    var document = envelope.parseContent(a, input.output, null) catch |err| return if (err == error.OutOfMemory) err else result;
    defer document.deinit();
    result.normalization = document.normalization;
    const schema_bytes = input.schema orelse {
        result.state = .missing_schema;
        return result;
    };
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = compiler.compiler().compileSelected(a, schema_bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        result.state = .unsupported_schema;
        return result;
    };
    if (@import("../../../src/domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), compiled.root()) != null) {
        result.state = .schema_invalid;
        return result;
    }
    const compatible_fields = if (input.field_policies.len == 0) true else switch (input.metadata_contract) {
        .current_v7 => field_owner.validSchema(compiled.root(), input.field_policies),
        .historical_v3, .historical_v4, .historical_v5 => capturedFieldsFit(compiled.root(), input.field_policies),
        .unavailable => false,
    };
    if (!field_owner.valid(input.field_policies) or !wire.compatibleProseSchema(input.prose_fields, compiled.root()) or !compatible_fields or (input.original_sources != null and !wire.validSources(input.original_sources.?))) {
        result.state = .invalid_field_metadata;
        return result;
    }
    var map: std.AutoHashMap(*const std.json.Value, policy.Field) = .init(a);
    for (input.field_policies) |selected| try selectNative(a, &document.parsed.value, selected.path, selected.field, &map);
    for (input.prose_fields) |selected| {
        const path = try a.alloc(field_owner.Step, selected.path.len);
        for (selected.path, path) |step, *destination| destination.* = switch (step) {
            .property => |name| .{ .property = name },
            .items => .items,
        };
        try selectNative(a, &document.parsed.value, path, selected.field, &map);
    }
    var output: std.ArrayList(Field) = .empty;
    var path: std.ArrayList(pointer.Segment) = .empty;
    var ancestors: std.ArrayList(std.json.Value) = .empty;
    const sources: Sources = if (input.original_sources) |known| .{ .kind = .native_description, .values = known } else try sourceWitnesses(a, packet);
    try walk(a, &document.parsed.value, compiled.root(), packet, occurrences, sources, classifier, &path, &ancestors, &map, &output);
    result.fields = try output.toOwnedSlice(a);
    result.state = if (result.fields.len == 0) .no_declared_text_fields else .measured;
    return result;
}

/// A frozen capture's selectors describe observations, not today's permitted
/// model alternatives. Check only that every captured text leaf has one typed
/// selector and every reached selector addresses text. Current metadata instead
/// passes the production validSchema owner above. This function never returns
/// an executable schema, admitted value, reconstructed source fact or approval.
fn capturedFieldsFit(root: *const schema_owner.Node, bindings: []const field_owner.Binding) bool {
    if (!field_owner.valid(bindings)) return false;
    var path: [schema_owner.max_depth * 2 + 2]field_owner.Step = undefined;
    return capturedFieldsAt(root, bindings, &path, 0);
}
fn capturedFieldsAt(node: *const schema_owner.Node, bindings: []const field_owner.Binding, path: []field_owner.Step, depth: usize) bool {
    var length = depth;
    if (schema_owner.discriminator(node)) |tag| {
        if (length == path.len) return false;
        path[length] = .{ .variant = tag };
        length += 1;
    }
    var selected = false;
    for (bindings) |declared_field| if (field_owner.samePath(declared_field.path, path[0..length])) {
        selected = true;
        break;
    };
    if (wire.textContract(node) or legacyText(node)) return selected;
    if (selected) return node.* == .string;
    switch (node.*) {
        .object => |properties| for (properties) |property| {
            if (length == path.len) return false;
            path[length] = .{ .property = property.name };
            if (!capturedFieldsAt(property.schema, bindings, path, length + 1)) return false;
        },
        .array => |array| {
            if (length == path.len) return false;
            path[length] = .items;
            return capturedFieldsAt(array.items, bindings, path, length + 1);
        },
        .one_of => |variants| for (variants) |variant| if (!capturedFieldsAt(variant, bindings, path, length)) return false,
        else => {},
    }
    return true;
}
fn selectNative(a: std.mem.Allocator, value: *const std.json.Value, path: []const field_owner.Step, native_field: policy.Field, map: *std.AutoHashMap(*const std.json.Value, policy.Field)) !void {
    if (path.len == 0) {
        if (value.* != .null) {
            if (map.get(value)) |prior| if (prior != native_field) return error.InvalidCaptureProjection;
            try map.put(value, native_field);
        }
        return;
    }
    switch (path[0]) {
        .variant => |kind| if (member(value.*, "kind")) |tag| {
            if (tag == .string and std.mem.eql(u8, tag.string, kind)) try selectNative(a, value, path[1..], native_field, map);
        },
        .property => |name| if (value.* == .object) {
            if (value.object.getPtr(name)) |child| try selectNative(a, child, path[1..], native_field, map);
        },
        .items => if (value.* == .array) {
            for (value.array.items) |*child| try selectNative(a, child, path[1..], native_field, map);
        },
    }
}
fn legacyText(node: *const schema_owner.Node) bool {
    if (node.* != .array) return false;
    const items = node.array.items;
    if (items.* != .one_of) return false;
    var prose = false;
    var insertion = false;
    for (items.one_of) |variant| switch (variant.*) {
        .string => prose = true,
        .object => if (schema_owner.discriminator(variant)) |tag| {
            if (std.mem.eql(u8, tag, "exact_copy") or std.mem.eql(u8, tag, "passive") or std.mem.eql(u8, tag, "source")) insertion = true else return false;
        } else return false,
        else => return false,
    };
    return prose and insertion;
}
fn constructedCopy(node: *const schema_owner.Node) bool {
    switch (node.*) {
        .object => |properties| {
            if (schema_owner.discriminator(node)) |tag| if (std.mem.eql(u8, tag, "exact_copy") and schema_owner.findProperty(properties, "claim_id") == null) return true;
            for (properties) |property| if (constructedCopy(property.schema)) return true;
        },
        .array => |array| return constructedCopy(array.items),
        .one_of => |variants| for (variants) |variant| if (constructedCopy(variant)) return true,
        else => {},
    }
    return false;
}
const Sources = struct { kind: @FieldType(Field, "source_metadata"), values: []const wire.SourceText };
fn sourceWitnesses(a: std.mem.Allocator, packet: std.json.Value) !Sources {
    const raw = member(packet, "sources") orelse return .{ .kind = .unavailable, .values = &.{} };
    if (raw != .array) return .{ .kind = .unavailable, .values = &.{} };
    var result: std.ArrayList(wire.SourceText) = .empty;
    for (raw.array.items) |source| {
        const id = positive(member(source, "id") orelse return .{ .kind = .unavailable, .values = &.{} }) orelse return .{ .kind = .unavailable, .values = &.{} };
        const bytes = text(member(source, "text") orelse return .{ .kind = .unavailable, .values = &.{} }) orelse return .{ .kind = .unavailable, .values = &.{} };
        try result.append(a, .{ .source_id = .{ .ordinal = id }, .bytes = bytes });
    }
    return .{ .kind = .packet_projection, .values = try result.toOwnedSlice(a) };
}
fn walk(a: std.mem.Allocator, value: *const std.json.Value, node: *const schema_owner.Node, packet: std.json.Value, occurrences: []const recognition.Occurrence, sources: Sources, classifier: recognition.LexicalClassifier, path: *std.ArrayList(pointer.Segment), ancestors: *std.ArrayList(std.json.Value), map: *std.AutoHashMap(*const std.json.Value, policy.Field), output: *std.ArrayList(Field)) !void {
    if (wire.textContract(node) or legacyText(node) or map.contains(value)) {
        const bound = binding(a, packet, ancestors.items) catch |err| bound: {
            if (err == error.OutOfMemory) return err;
            break :bound Bound{ .kind = .invalid, .requirements = &.{} };
        };
        try output.append(a, try field(a, value.*, try pointer.render(a, path.items), map.get(value), legacyText(node), constructedCopy(node), bound, occurrences, sources, classifier));
        return;
    }
    try ancestors.append(a, value.*);
    defer _ = ancestors.pop();
    switch (node.*) {
        .object => |properties| if (value.* == .object) {
            for (properties) |property| if (value.object.getPtr(property.name)) |child| {
                try path.append(a, .{ .property = property.name });
                defer _ = path.pop();
                try walk(a, child, property.schema, packet, occurrences, sources, classifier, path, ancestors, map, output);
            };
        },
        .array => |array| if (value.* == .array) {
            for (value.array.items, 0..) |*child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try walk(a, child, array.items, packet, occurrences, sources, classifier, path, ancestors, map, output);
            }
        },
        .one_of => |variants| for (variants) |variant| {
            if (@import("../../../src/domain/model_payload_schema.zig").validateValue(envelope.value(value), variant) == null) {
                try walk(a, value, variant, packet, occurrences, sources, classifier, path, ancestors, map, output);
                break;
            }
        },
        else => {},
    }
}
fn summarize(outcome: recognition.Outcome) Result {
    return switch (outcome) {
        .rejected => |reason| .{ .state = .rejected, .rejection = reason },
        .evaluated => |report| .{ .state = switch (report.state) {
            .matched => .matched,
            .no_match => .no_match,
            .ambiguous => .ambiguous,
        }, .matches = report.matches, .unbound_matches = report.unbound_matches, .diagnostics = report.diagnostics },
    };
}
fn field(a: std.mem.Allocator, value: std.json.Value, path: []const u8, native: ?policy.Field, legacy: bool, constructed: bool, bound: Bound, occurrences: []const recognition.Occurrence, sources: Sources, classifier: recognition.LexicalClassifier) !Field {
    const raw = try std.json.Stringify.valueAlloc(a, value, .{});
    const fragments: []const std.json.Value = if (value == .string) &.{value} else if (legacy and value == .array) value.array.items else (member(value, "fragments") orelse return error.InvalidCaptureProjection).array.items;
    var runs: std.ArrayList(Run) = .empty;
    var exact: std.ArrayList(TypedReference) = .empty;
    var old_nodes: std.ArrayList(typed.CompositionNode) = .empty;
    var proposed: std.ArrayList(typed.CompositionNode) = .empty;
    var rendered: std.ArrayList(u8) = .empty;
    var renderable = true;
    var ambiguous = false;
    var boundary_unavailable = false;
    var index: usize = 0;
    while (index < fragments.len) {
        if (fragments[index] == .string) {
            const run_start = index;
            var prose: std.ArrayList(u8) = .empty;
            while (index < fragments.len and fragments[index] == .string) : (index += 1) try prose.appendSlice(a, fragments[index].string);
            const bytes = try prose.toOwnedSlice(a);
            try old_nodes.append(a, .{ .literal = .{ .value = bytes } });
            try rendered.appendSlice(a, bytes);
            const scored: Result = if (run_start != 0 or index != fragments.len) unavailable: {
                boundary_unavailable = true;
                break :unavailable .{ .state = .unavailable_boundary_context };
            } else summarize(try recognition.recognize(a, .{ .prose = bytes, .bound_requirements = bound.requirements, .occurrences = occurrences }, classifier));
            try runs.append(a, .{ .ordinal = runs.items.len, .bytes_sha256 = try hash(a, bytes), .byte_length = bytes.len, .result = scored });
            if (scored.state == .unavailable_boundary_context) {
                try proposed.append(a, .{ .literal = .{ .value = bytes } });
                continue;
            }
            if (scored.state == .ambiguous or scored.state == .rejected) {
                ambiguous = true;
                continue;
            }
            var previous: usize = 0;
            for (scored.matches) |match| {
                if (previous < match.start_byte) try proposed.append(a, .{ .literal = .{ .value = bytes[previous..match.start_byte] } });
                try proposed.append(a, .exact_copy);
                previous = match.end_byte;
            }
            if (previous < bytes.len) try proposed.append(a, .{ .literal = .{ .value = bytes[previous..] } });
            continue;
        }
        const fragment = fragments[index];
        index += 1;
        const tag = text(member(fragment, "kind") orelse return error.InvalidCaptureProjection) orelse return error.InvalidCaptureProjection;
        if (std.mem.eql(u8, tag, "exact_copy")) {
            const selected = if (member(fragment, "claim_id")) |id| positive(id) else if (constructed and occurrences.len == 1) occurrences[0].id.value else null;
            const occurrence = if (selected) |id| for (occurrences) |candidate| {
                if (candidate.id.value == id) break candidate;
            } else null else null;
            try exact.append(a, .{ .occurrence = selected, .resolved = occurrence != null });
            try old_nodes.append(a, .exact_copy);
            try proposed.append(a, .exact_copy);
            if (occurrence) |known| try rendered.appendSlice(a, known.bytes) else {
                renderable = false;
            }
        } else {
            const atom: typed.CompositionNode = if (std.mem.eql(u8, tag, "passive")) .passive else if (std.mem.eql(u8, tag, "source")) .source else return error.InvalidCaptureProjection;
            try old_nodes.append(a, atom);
            try proposed.append(a, atom);
            renderable = false;
        }
    }
    var counterfactual: ?Run = null;
    if (exact.items.len != 0 and renderable) {
        counterfactual = .{ .ordinal = 0, .bytes_sha256 = try hash(a, rendered.items), .byte_length = rendered.items.len, .result = summarize(try recognition.recognize(a, .{ .prose = rendered.items, .bound_requirements = bound.requirements, .occurrences = occurrences }, classifier)) };
    }
    const old_wire_issue = if (native) |known| try typed.wireCompositionSources(typed.CompositionNode, a, sources.values, known, old_nodes.items) else null;
    const old_issue = if (native) |known| typed.composition(typed.CompositionNode, known, old_nodes.items) orelse old_wire_issue else null;
    const proposed_issue = if (native) |known| if (!ambiguous and !boundary_unavailable) old_wire_issue orelse typed.composition(typed.CompositionNode, known, proposed.items) orelse try typed.wireCompositionSources(typed.CompositionNode, a, sources.values, known, proposed.items) else null else null;
    return .{
        .path = path,
        .native_field = native,
        .raw_value_sha256 = try hash(a, raw),
        .representation = if (legacy) .historical_array else .current_wire,
        .source_metadata = sources.kind,
        .binding = bound.kind,
        .bound_requirements = bound.requirements,
        .plain_runs = try runs.toOwnedSlice(a),
        .typed_exact_references = try exact.toOwnedSlice(a),
        .historical_typed_counterfactual = counterfactual,
        .original_composition = if (old_issue != null and old_issue.?.reason == .embedded_insertion_syntax and sources.kind == .unavailable) .unavailable_source_metadata else if (native == null) .unavailable_field_metadata else if (old_issue != null) .invalid else .valid,
        .proposed_composition = if (ambiguous) .ambiguous else if (boundary_unavailable) .not_evaluated else if (proposed_issue != null and proposed_issue.?.reason == .embedded_insertion_syntax and sources.kind == .unavailable) .unavailable_source_metadata else if (native == null) .unavailable_field_metadata else if (proposed_issue != null) .invalid else .valid,
        .proposed_composition_issue = if (proposed_issue) |issue| issue.reason else null,
    };
}
