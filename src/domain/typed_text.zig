//! Shared prose syntax and validation. Valid text is not semantic proof and
//! display references never become file, command, import or fetch capabilities.
const std = @import("std");
const literals = @import("passive_literals.zig");
const evidence = @import("reference_evidence.zig");
const naming = @import("naming_policy.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const field_policy = @import("text_field_policy.zig");
pub const Error = literals.Error || error{InvalidTypedText};
pub const Literal = struct { value: []const u8 };
pub const PassiveReference = struct { passive_literal_id: literals.Id };
pub const SourceReference = struct { source_id: evidence.identity.SourceId };
pub const ExactCopy = struct { claim_id: @import("reference_identity.zig").ClaimId };
pub const BusinessSegment = union(enum) {
    pub const model_inline = .{ .literal = "value" };
    literal: Literal,
    passive: PassiveReference,
    exact_copy: ExactCopy,
};
pub const ReferenceNode = union(enum) {
    pub const model_inline = .{ .literal = "value" };
    literal: Literal,
    passive: PassiveReference,
    source: SourceReference,
};
pub const BusinessText = struct {
    pub const model_text = "segments";
    segments: []const BusinessSegment,
};
pub const ReferenceSemanticText = struct {
    pub const model_text = "nodes";
    nodes: []const ReferenceNode,
};
/// Pure canonical-text operations borrow exact captured source bytes. Only the
/// witness array is owned; no validation or continuation authority is granted.
pub const CanonicalText = struct {
    normalizer: unicode.Normalizer,
    original_sources: []const @import("model_text_wire.zig").SourceText,

    pub fn fromInputs(a: std.mem.Allocator, normalizer: unicode.Normalizer, inputs: evidence.Inputs) std.mem.Allocator.Error!CanonicalText {
        const wire = @import("model_text_wire.zig");
        const sources = try a.alloc(wire.SourceText, inputs.corpus.sources.len);
        for (inputs.corpus.sources, sources) |source, *target| target.* = .{ .source_id = source.id, .bytes = source.bytes };
        return .{ .normalizer = normalizer, .original_sources = sources };
    }

    pub fn matchesInputs(self: CanonicalText, inputs: evidence.Inputs) bool {
        if (!@import("model_text_wire.zig").validSources(self.original_sources) or self.original_sources.len != inputs.corpus.sources.len) return false;
        for (self.original_sources, inputs.corpus.sources) |source, captured| {
            if (source.source_id.ordinal != captured.id.ordinal or !std.mem.eql(u8, source.bytes, captured.bytes)) return false;
        }
        return true;
    }

    pub fn deinit(self: *CanonicalText, a: std.mem.Allocator) void {
        a.free(self.original_sources);
        self.* = undefined;
    }
};

const CanonicalRun = struct { next: usize, bytes: []const u8 };
fn canonicalRun(comptime Node: type, a: std.mem.Allocator, context: CanonicalText, nodes: []const Node, start: usize) naming.Error!CanonicalRun {
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(a);
    var index = start;
    while (index < nodes.len and nodes[index] == .literal) : (index += 1) try joined.appendSlice(a, nodes[index].literal.value);
    return .{ .next = index, .bytes = try @import("model_text_wire.zig").normalizeProse(a, joined.items, context.original_sources, context.normalizer) };
}

/// Canonical representation only: join adjacent literal runs, normalize their
/// prose, and preserve every typed insertion and its order. This does not admit
/// invalid text, infer support, or replace any field's validator.
pub fn canonicalNodes(comptime Node: type, a: std.mem.Allocator, context: CanonicalText, nodes: []const Node) naming.Error![]const Node {
    comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
    var result: std.ArrayList(Node) = .empty;
    errdefer {
        for (result.items) |node| if (node == .literal) a.free(node.literal.value);
        result.deinit(a);
    }
    var index: usize = 0;
    while (index < nodes.len) {
        if (nodes[index] == .literal) {
            const run = try canonicalRun(Node, a, context, nodes, index);
            errdefer a.free(run.bytes);
            try result.append(a, .{ .literal = .{ .value = run.bytes } });
            index = run.next;
        } else {
            try result.append(a, nodes[index]);
            index += 1;
        }
    }
    return result.toOwnedSlice(a);
}
pub const ValidatedBusinessText = struct { value: BusinessText };
pub const ValidatedReferenceSemanticText = struct { value: ReferenceSemanticText };
pub fn equivalentBusiness(left: ValidatedBusinessText, right: ValidatedBusinessText) bool {
    return equivalentNodes(BusinessSegment, left.value.segments, right.value.segments);
}
pub fn equivalentReference(left: ValidatedReferenceSemanticText, right: ValidatedReferenceSemanticText) bool {
    return equivalentNodes(ReferenceNode, left.value.nodes, right.value.nodes);
}
fn equivalentNodes(comptime Node: type, left: []const Node, right: []const Node) bool {
    if (left.len != right.len) return false;
    for (left, right) |first, second| {
        if (std.meta.activeTag(first) != std.meta.activeTag(second)) return false;
        switch (first) {
            .literal => |value| if (!std.mem.eql(u8, value.value, second.literal.value)) return false,
            inline else => |value, tag| if (!std.meta.eql(value, @field(second, @tagName(tag)))) return false,
        }
    }
    return true;
}
pub const Context = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scope: evidence.Scope, field: field_policy.Field };
pub const ScopeSetContext = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scopes: []const evidence.Scope, exact_copies: []const ExactCopy = &.{}, field: field_policy.Field };
/// Native read dependencies, independent of model packet presentation. Runtime
/// toolchain identity is checked before capture; no capability enters a snapshot.
pub const Dependencies = struct {
    inputs: evidence.Inputs,
    grammar_contract: @FieldType(@import("path_token_grammar.zig").Grammar, "contract"),
    policy_contract: @FieldType(naming.Compiled, "contract"),
    policy_ids: []const []const u8,
    rules: []const naming.BoundRule,
    reference_state_id: evidence.identity.StateId,
    feature_id: @import("feature_identity.zig").FeatureId,
    reference_names: []const @import("path_token_grammar.zig").ReferenceName,
    records: []const literals.Record,
    occurrences: []const literals.Occurrence,
};
pub fn dependencies(inputs: evidence.Inputs, registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain) naming.Error!Dependencies {
    if (!registry.grammar.policy.toolchain_identity.eql(current.identity())) return error.StaleNamingPolicy;
    const grammar = registry.grammar;
    return .{ .inputs = inputs, .grammar_contract = grammar.contract, .policy_contract = grammar.policy.contract, .policy_ids = grammar.policy.policy_ids, .rules = grammar.policy.rules, .reference_state_id = grammar.reference_state_id, .feature_id = grammar.feature_id, .reference_names = grammar.reference_names, .records = registry.records, .occurrences = registry.occurrences };
}
pub const Issue = struct {
    reason: enum { empty, invalid_scalar, unknown_exact, unknown_passive, unknown_source, blank, reference_only, prohibited_exact, prohibited_passive, prohibited_source, embedded_insertion_syntax },
    first_node: usize,
    last_node: usize,
    rejected_passive: ?literals.Id = null,
    rejected_exact: ?ExactCopy = null,
    field: ?field_policy.Field = null,
    pub fn description(self: Issue) []const u8 {
        return switch (self.reason) {
            .empty, .blank => "Supply nonblank content using the supplied typed text choices.",
            .invalid_scalar => "Literal text must be nonempty valid Unicode without forbidden control characters.",
            .unknown_exact => "Select an eligible preserved-token claim supplied for this evidence scope; do not invent or rewrite an exact value.",
            .unknown_passive => "Use only passive reference IDs supplied for this source scope.",
            .unknown_source => "Use only source IDs supplied for this source scope.",
            .reference_only => field_policy.referenceOnlyExplanation(self.field.?),
            .prohibited_exact => "This field does not permit exact-copy insertions.",
            .prohibited_passive => "This field does not permit passive insertions.",
            .prohibited_source => "This field does not permit source insertions.",
            .embedded_insertion_syntax => "Use actual typed insertion nodes rather than encoded insertion objects inside prose. Such object bytes may occur in prose only when exactly present in an original source.",
        };
    }
    pub fn failure(self: Issue) Error {
        return switch (self.reason) {
            .unknown_passive => error.InvalidPassiveLiteral,
            else => error.InvalidTypedText,
        };
    }
};
pub fn Result(comptime T: type) type {
    return union(enum) { valid: T, invalid: Issue };
}
pub const Validator = struct {
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,

    pub fn business(self: Validator, allocator: std.mem.Allocator, context: Context, candidate: BusinessText) Error!ValidatedBusinessText {
        return self.businessIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = &.{context.scope}, .field = context.field }, candidate);
    }
    pub fn reference(self: Validator, allocator: std.mem.Allocator, context: Context, candidate: ReferenceSemanticText) Error!ValidatedReferenceSemanticText {
        return self.referenceIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = &.{context.scope}, .field = context.field }, candidate);
    }
    pub fn businessIn(self: Validator, allocator: std.mem.Allocator, context: ScopeSetContext, candidate: BusinessText) Error!ValidatedBusinessText {
        return switch (try self.checkBusinessIn(allocator, context, candidate)) {
            .valid => |value| value,
            .invalid => |issue| issue.failure(),
        };
    }
    pub fn referenceIn(self: Validator, allocator: std.mem.Allocator, context: ScopeSetContext, candidate: ReferenceSemanticText) Error!ValidatedReferenceSemanticText {
        return switch (try self.checkReferenceIn(allocator, context, candidate)) {
            .valid => |value| value,
            .invalid => |issue| issue.failure(),
        };
    }
    pub fn checkBusinessIn(self: Validator, allocator: std.mem.Allocator, context: ScopeSetContext, candidate: BusinessText) Error!Result(ValidatedBusinessText) {
        var issue: ?Issue = null;
        const checked = self.nodes(BusinessSegment, allocator, context, candidate.segments, &issue) catch |err| return if (issue) |value| .{ .invalid = value } else err;
        return .{ .valid = .{ .value = .{ .segments = checked } } };
    }
    pub fn checkReferenceIn(self: Validator, allocator: std.mem.Allocator, context: ScopeSetContext, candidate: ReferenceSemanticText) Error!Result(ValidatedReferenceSemanticText) {
        var issue: ?Issue = null;
        const checked = self.nodes(ReferenceNode, allocator, context, candidate.nodes, &issue) catch |err| return if (issue) |value| .{ .invalid = value } else err;
        return .{ .valid = .{ .value = .{ .nodes = checked } } };
    }
    fn nodes(self: Validator, comptime Node: type, allocator: std.mem.Allocator, context: ScopeSetContext, candidates: []const Node, issue: *?Issue) Error![]const Node {
        comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
        try @import("path_token_grammar.zig").validateBinding(allocator, context.registry.grammar, context.current, context.inputs, self.normalizer, self.folder);
        if (context.scopes.len == 0) return error.InvalidTypedText;
        for (context.scopes) |scope| _ = try evidence.resolve(context.inputs, scope);
        if (candidates.len == 0) return reject(issue, .empty, 0, 0);
        if (try wireComposition(Node, allocator, context.inputs, context.field, candidates)) |failure| {
            issue.* = failure;
            return failure.failure();
        }
        var canonical = try CanonicalText.fromInputs(allocator, self.normalizer, context.inputs);
        defer canonical.deinit(allocator);
        var result: std.ArrayList(Node) = .empty;
        errdefer {
            for (result.items) |node| if (node == .literal) allocator.free(node.literal.value);
            result.deinit(allocator);
        }
        var index: usize = 0;
        var visible = false;
        while (index < candidates.len) {
            switch (candidates[index]) {
                inline else => |node, tag| if (comptime tag == .literal) {
                    const first = index;
                    // Prose is inert content. Normalize adjacent text without
                    // inferring a reference or capability from its punctuation.
                    while (index < candidates.len and candidates[index] == .literal) : (index += 1) {
                        const bytes = candidates[index].literal.value;
                        if (!validScalar(bytes) or bytes.len == 0) return reject(issue, .invalid_scalar, index, index);
                    }
                    const run = try canonicalRun(Node, allocator, canonical, candidates, first);
                    const text = run.bytes;
                    errdefer allocator.free(text);
                    visible = visible or std.mem.trim(u8, text, " \t\r\n").len != 0;
                    try result.append(allocator, .{ .literal = .{ .value = text } });
                } else if (comptime std.mem.eql(u8, @tagName(tag), "exact_copy")) {
                    if (!permitsExact(context.exact_copies, node)) {
                        issue.* = .{ .reason = .unknown_exact, .first_node = index, .last_node = index, .rejected_exact = node };
                        return error.InvalidTypedText;
                    }
                    try result.append(allocator, .{ .exact_copy = node });
                    visible = true;
                    index += 1;
                } else if (comptime tag == .passive) {
                    _ = literals.resolveIn(context.registry, context.inputs, context.scopes, node.passive_literal_id) catch |err| {
                        if (err != error.InvalidPassiveLiteral) return err;
                        issue.* = .{ .reason = .unknown_passive, .first_node = index, .last_node = index, .rejected_passive = node.passive_literal_id };
                        return error.InvalidPassiveLiteral;
                    };
                    try result.append(allocator, .{ .passive = node });
                    visible = true;
                    index += 1;
                } else {
                    for (context.scopes) |scope| {
                        const unit = try evidence.resolve(context.inputs, scope);
                        if (node.source_id.ordinal == unit.source.id.ordinal) break;
                    } else return reject(issue, .unknown_source, index, index);
                    try result.append(allocator, .{ .source = node });
                    visible = true;
                    index += 1;
                },
            }
        }
        if (!visible) return reject(issue, .blank, 0, candidates.len - 1);
        if (try wireComposition(Node, allocator, context.inputs, context.field, result.items)) |failure| {
            issue.* = failure;
            return failure.failure();
        }
        if (composition(Node, context.field, result.items)) |failure| {
            issue.* = failure;
            return failure.failure();
        }
        return result.toOwnedSlice(allocator);
    }
};

/// Capability-free structural check shared by admission, stored readback,
/// collection coverage and diagnostic observation. No rendering or inference.
pub fn composition(comptime Node: type, field: field_policy.Field, nodes: []const Node) ?Issue {
    comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
    const policy = field_policy.get(field);
    if (nodes.len == 0) return .{ .reason = .empty, .first_node = 0, .last_node = 0, .field = field };
    var prose = false;
    var visible = false;
    for (nodes, 0..) |node, index| switch (node) {
        .literal => |value| {
            if (value.value.len == 0 or !validScalar(value.value)) return .{ .reason = .invalid_scalar, .first_node = index, .last_node = index, .field = field };
            prose = prose or std.mem.trim(u8, value.value, " \t\r\n").len != 0;
            visible = visible or prose;
        },
        .passive => {
            if (policy.passive == .prohibited) return .{ .reason = .prohibited_passive, .first_node = index, .last_node = index, .field = field };
            visible = true;
        },
        inline else => |_, tag| {
            const prohibited = if (comptime std.mem.eql(u8, @tagName(tag), "exact_copy")) policy.exact_copy == .prohibited else policy.source == .prohibited;
            if (prohibited) return .{ .reason = if (comptime std.mem.eql(u8, @tagName(tag), "exact_copy")) .prohibited_exact else .prohibited_source, .first_node = index, .last_node = index, .field = field };
            visible = true;
        },
    };
    if (!visible) return .{ .reason = .blank, .first_node = 0, .last_node = nodes.len - 1, .field = field };
    if (policy.prose == .required and !prose) return .{ .reason = .reference_only, .first_node = 0, .last_node = nodes.len -| 1, .field = field };
    return null;
}

/// The same canonical wire grammar checks native admission and stored readback.
/// Adjacent literal fragments form one prose run; typed insertions end a run.
pub fn wireComposition(comptime Node: type, a: std.mem.Allocator, inputs: evidence.Inputs, field: field_policy.Field, nodes: []const Node) std.mem.Allocator.Error!?Issue {
    comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
    const wire = @import("model_text_wire.zig");
    const sources = try a.alloc(wire.SourceText, inputs.corpus.sources.len);
    defer a.free(sources);
    for (inputs.corpus.sources, sources) |source, *target| target.* = .{ .source_id = source.id, .bytes = source.bytes };
    return wireCompositionSources(Node, a, sources, field, nodes);
}
pub fn wireCompositionSources(comptime Node: type, a: std.mem.Allocator, sources: []const @import("model_text_wire.zig").SourceText, field: field_policy.Field, nodes: []const Node) std.mem.Allocator.Error!?Issue {
    comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
    const wire = @import("model_text_wire.zig");
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(a);
    var index: usize = 0;
    while (index < nodes.len) {
        if (nodes[index] != .literal) {
            index += 1;
            continue;
        }
        const first = index;
        joined.clearRetainingCapacity();
        while (index < nodes.len and nodes[index] == .literal) : (index += 1) try joined.appendSlice(a, nodes[index].literal.value);
        if (try wire.checkProse(a, joined.items, sources) != null) return .{ .reason = .embedded_insertion_syntax, .first_node = first, .last_node = index - 1, .field = field };
    }
    return null;
}

/// Intrinsic persisted text checks reuse the admission policy and wire grammar.
/// Captured references are resolved against the owner's exact evidence scope.
pub const StoredContext = struct { inputs: evidence.Inputs, passive: literals.Captured, scopes: []const evidence.Scope, field: field_policy.Field, exact_copies: []const ExactCopy = &.{} };
pub fn stored(comptime Node: type, a: std.mem.Allocator, context: StoredContext, nodes: []const Node) Error!void {
    if (composition(Node, context.field, nodes) != null or try wireComposition(Node, a, context.inputs, context.field, nodes) != null) return error.InvalidTypedText;
    for (nodes) |node| switch (node) {
        .literal => {},
        .passive => |value| {
            _ = try literals.resolveCaptured(context.passive, context.inputs, context.scopes, value.passive_literal_id);
        },
        inline else => |value, tag| {
            if (comptime std.mem.eql(u8, @tagName(tag), "exact_copy")) {
                if (!permitsExact(context.exact_copies, value)) return error.InvalidTypedText;
            } else {
                for (context.scopes) |scope| {
                    const unit = try evidence.resolve(context.inputs, scope);
                    if (value.source_id.ordinal == unit.source.id.ordinal) break;
                } else return error.InvalidTypedText;
            }
        },
    };
}

pub fn permitsExact(choices: []const ExactCopy, selected: ExactCopy) bool {
    for (choices) |choice| if (std.meta.eql(choice, selected)) return true;
    return false;
}

fn reject(target: *?Issue, reason: @FieldType(Issue, "reason"), first: usize, last: usize) Error {
    const issue: Issue = .{ .reason = reason, .first_node = first, .last_node = last };
    target.* = issue;
    return issue.failure();
}

/// Shared scalar syntax only; this is not normalized/validated text authority.
pub fn validScalar(bytes: []const u8) bool {
    const view = std.unicode.Utf8View.init(bytes) catch return false;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |scalar| {
        if ((scalar < 0x20 and scalar != '\t' and scalar != '\n' and scalar != '\r') or (scalar >= 0x7f and scalar <= 0x9f)) return false;
    }
    return true;
}
