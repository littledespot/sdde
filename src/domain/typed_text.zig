//! Shared prose syntax and validation. Valid text is not semantic proof and
//! display references never become file, command, import or fetch capabilities.
const std = @import("std");
const literals = @import("passive_literals.zig");
const evidence = @import("reference_evidence.zig");
const scan = @import("path_token_scan.zig");
const naming = @import("naming_policy.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Error = literals.Error || error{ InvalidTypedText, UnboundPathReference };
pub const Literal = struct { value: []const u8 };
pub const PassiveReference = struct { passive_literal_id: literals.Id };
pub const SourceReference = struct { source_id: evidence.identity.SourceId };
pub const BusinessSegment = union(enum) { literal: Literal, passive: PassiveReference };
pub const ReferenceNode = union(enum) { literal: Literal, passive: PassiveReference, source: SourceReference };
pub const BusinessText = struct { segments: []const BusinessSegment };
pub const ReferenceSemanticText = struct { nodes: []const ReferenceNode };
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
pub const Context = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scope: evidence.Scope };
pub const ScopeSetContext = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scopes: []const evidence.Scope };
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
    reason: enum { empty, invalid_scalar, unbound_path, unknown_passive, unknown_source, blank },
    first_node: usize,
    last_node: usize,
    /// Byte offsets address the normalized concatenation of first_node..last_node.
    /// The lexeme is owned by the validation allocator, not the lexer result.
    path_match: ?struct { normalized_literal_run: scan.Match, lexeme: []const u8 } = null,
    pub fn description(self: Issue) []const u8 {
        return switch (self.reason) {
            .empty, .blank => "Supply nonblank content using the supplied typed text choices.",
            .invalid_scalar => "Literal text must be nonempty valid Unicode without forbidden control characters.",
            .unbound_path => "Represent filenames, paths and URIs with supplied passive reference IDs, outside literal text.",
            .unknown_passive => "Use only passive reference IDs supplied for this source scope.",
            .unknown_source => "Use only source IDs supplied for this source scope.",
        };
    }
    pub fn failure(self: Issue) Error {
        return switch (self.reason) {
            .unbound_path => error.UnboundPathReference,
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
    classifier: unicode.LexicalClassifier,

    pub fn business(self: Validator, allocator: std.mem.Allocator, context: Context, candidate: BusinessText) Error!ValidatedBusinessText {
        return self.businessIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = &.{context.scope} }, candidate);
    }
    pub fn reference(self: Validator, allocator: std.mem.Allocator, context: Context, candidate: ReferenceSemanticText) Error!ValidatedReferenceSemanticText {
        return self.referenceIn(allocator, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scopes = &.{context.scope} }, candidate);
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
        var result: std.ArrayList(Node) = .empty;
        var index: usize = 0;
        var visible = false;
        while (index < candidates.len) {
            switch (candidates[index]) {
                inline else => |node, tag| if (comptime tag == .literal) {
                    const first = index;
                    var joined: std.ArrayList(u8) = .empty;
                    // Adjacent segments are one lexical surface: splitting a
                    // filename into two strings cannot evade the shared lexer.
                    while (index < candidates.len and candidates[index] == .literal) : (index += 1) {
                        const bytes = candidates[index].literal.value;
                        if (!validScalar(bytes) or bytes.len == 0) return reject(issue, .invalid_scalar, index, index);
                        try joined.appendSlice(allocator, bytes);
                    }
                    const text = try naming.normalize(allocator, joined.items, true, self.normalizer, self.folder);
                    const matches = try scan.scan(allocator, context.registry.grammar, text, self.normalizer, self.folder, self.classifier);
                    defer scan.destroy(matches);
                    if (matches.matches.len != 0) {
                        const match = matches.matches[0];
                        issue.* = .{ .reason = .unbound_path, .first_node = first, .last_node = index - 1, .path_match = .{
                            .normalized_literal_run = match,
                            .lexeme = try allocator.dupe(u8, matches.text[match.start_byte..match.end_byte]),
                        } };
                        return error.UnboundPathReference;
                    }
                    visible = visible or std.mem.trim(u8, text, " \t\r\n").len != 0;
                    try result.append(allocator, .{ .literal = .{ .value = text } });
                } else if (comptime tag == .passive) {
                    _ = literals.resolveIn(context.registry, context.inputs, context.scopes, node.passive_literal_id) catch |err| return switch (err) {
                        error.InvalidPassiveLiteral => reject(issue, .unknown_passive, index, index),
                        else => err,
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
        return result.toOwnedSlice(allocator);
    }
};

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
