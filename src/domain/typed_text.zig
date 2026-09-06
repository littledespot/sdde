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
pub const Context = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scope: evidence.Scope };
pub const ScopeSetContext = struct { registry: literals.Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: evidence.Inputs, scopes: []const evidence.Scope };
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
        return .{ .value = .{ .segments = try self.nodes(BusinessSegment, allocator, context, candidate.segments) } };
    }
    pub fn referenceIn(self: Validator, allocator: std.mem.Allocator, context: ScopeSetContext, candidate: ReferenceSemanticText) Error!ValidatedReferenceSemanticText {
        return .{ .value = .{ .nodes = try self.nodes(ReferenceNode, allocator, context, candidate.nodes) } };
    }
    fn nodes(self: Validator, comptime Node: type, allocator: std.mem.Allocator, context: ScopeSetContext, candidates: []const Node) Error![]const Node {
        comptime std.debug.assert(Node == BusinessSegment or Node == ReferenceNode);
        try @import("path_token_grammar.zig").validateBinding(allocator, context.registry.grammar, context.current, context.inputs, self.normalizer, self.folder);
        if (context.scopes.len == 0) return error.InvalidTypedText;
        for (context.scopes) |scope| _ = try evidence.resolve(context.inputs, scope);
        if (candidates.len == 0) return error.InvalidTypedText;
        var result: std.ArrayList(Node) = .empty;
        var index: usize = 0;
        var visible = false;
        while (index < candidates.len) {
            switch (candidates[index]) {
                inline else => |node, tag| if (comptime tag == .literal) {
                    var joined: std.ArrayList(u8) = .empty;
                    // Adjacent segments are one lexical surface: splitting a
                    // filename into two strings cannot evade the shared lexer.
                    while (index < candidates.len and candidates[index] == .literal) : (index += 1) {
                        const bytes = candidates[index].literal.value;
                        if (!validScalar(bytes) or bytes.len == 0) return error.InvalidTypedText;
                        try joined.appendSlice(allocator, bytes);
                    }
                    const text = try naming.normalize(allocator, joined.items, true, self.normalizer, self.folder);
                    const matches = try scan.scan(allocator, context.registry.grammar, text, self.normalizer, self.folder, self.classifier);
                    defer scan.destroy(matches);
                    if (matches.matches.len != 0) return error.UnboundPathReference;
                    visible = visible or std.mem.trim(u8, text, " \t\r\n").len != 0;
                    try result.append(allocator, .{ .literal = .{ .value = text } });
                } else if (comptime tag == .passive) {
                    _ = try literals.resolveIn(context.registry, context.inputs, context.scopes, node.passive_literal_id);
                    try result.append(allocator, .{ .passive = node });
                    visible = true;
                    index += 1;
                } else {
                    for (context.scopes) |scope| {
                        const unit = try evidence.resolve(context.inputs, scope);
                        if (node.source_id.ordinal == unit.source.id.ordinal) break;
                    } else return error.InvalidTypedText;
                    try result.append(allocator, .{ .source = node });
                    visible = true;
                    index += 1;
                },
            }
        }
        if (!visible) return error.InvalidTypedText;
        return result.toOwnedSlice(allocator);
    }
};

fn validScalar(bytes: []const u8) bool {
    const view = std.unicode.Utf8View.init(bytes) catch return false;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |scalar| {
        if ((scalar < 0x20 and scalar != '\t' and scalar != '\n' and scalar != '\r') or (scalar >= 0x7f and scalar <= 0x9f)) return false;
    }
    return true;
}
