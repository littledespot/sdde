//! Why a project's workflow definition was rejected at startup: a closed rule class, the inventory
//! ordinal of the file it belongs to and, where the rule is scoped to one, the step or resource it
//! names (F0005 §9). A Zig
//! error carries no payload, so an owner records this in a slot the startup routine owns, as a stage action
//! records its step (ADR 0031), and returns its unchanged error. None of it is a public code, a control
//! branch or authority: the public code stays the family's, and the display path is derived from the
//! inventory by ordinal.
const std = @import("std");
const workflow = @import("workflow.zig");

/// The class of invariant that rejected a definition, one per section or validation stage and never per
/// call site. The phase that produced it is the startup step the report names.
pub const Rule = enum {
    // The definition's own shape (`validate_workflow_schema`).
    definition_header,
    resources,
    steps,
    subgraphs,
    parameters,
    outcomes,
    // Resource binding (`resolve_workflow_resources`).
    resource_binding,
    // Compilation against the registered contracts (`compile_workflows`).
    subgraph_expansion,
    invocation,
    policy,
    start_step,
    step_operation,
    step_capabilities,
    step_parameters,
    retry_authority,
    declared_outcomes,
    request_stages,
    compiled_resources,
    execution_limit,
    data_schemas,
    // Graph validation (`validate_workflow_graphs`).
    operation_variants,
    graph_shape,
    step_contract,
    unreachable_step,
    no_terminal_path,
    unbounded_cycle,
    iteration_reset,
    outcome_flow,
    data_flow,
};

/// A bounded copy of display text, so the evidence outlives the startup arena and never grows.
pub fn Bounded(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        buffer: [capacity]u8 = undefined,
        len: usize = 0,

        /// Null when the text does not fit; text is never truncated.
        pub fn init(source: []const u8) ?Self {
            if (source.len > capacity) return null;
            var value: Self = .{ .len = source.len };
            @memcpy(value.buffer[0..source.len], source);
            return value;
        }

        pub fn text(self: *const Self) []const u8 {
            return self.buffer[0..self.len];
        }
    };
}

/// A step or resource identifier, bounded by the identifier grammar.
pub const Subject = Bounded(workflow.max_step_id_bytes);
/// A workflow-root-relative definition path, for display.
pub const Path = Bounded(512);

pub const Evidence = struct {
    rule: ?Rule = null,
    /// The inventory entry the failure belongs to: a definition's file, or a resource's.
    ordinal: ?u16 = null,
    subject: ?Subject = null,
    path: ?Path = null,
};

/// What the CLI prints after the public code: the startup step that failed and the evidence its owner
/// recorded. Holds no borrowed memory.
pub const Detail = struct {
    step: []const u8,
    evidence: Evidence,
};

/// Whether a rule's subject is a workflow step or a declared resource.
fn subjectLabel(rule: ?Rule) []const u8 {
    return switch (rule orelse return "step") {
        .resource_binding, .compiled_resources => "resource",
        else => "step",
    };
}

/// The text printed after the public code, `: <rule or step>[; <path>][; <step|resource>=<id>]`, so
/// the code stays the first token. An entry with no display path is named by its inventory ordinal.
pub fn write(detail: Detail, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const evidence = detail.evidence;
    try writer.writeAll(": ");
    if (evidence.rule) |rule| try writer.writeAll(@tagName(rule)) else try writer.writeAll(detail.step);
    if (evidence.path) |path| {
        try writer.print("; {s}", .{path.text()});
    } else if (evidence.ordinal) |ordinal| {
        try writer.print("; entry {d}", .{ordinal});
    }
    if (evidence.subject) |subject| try writer.print("; {s}={s}", .{ subjectLabel(evidence.rule), subject.text() });
}

/// Written by the innermost owner that knows more and completed by outer ones that know where: the first
/// rule recorded stays, and each of the other fields is filled once.
pub const Slot = struct {
    evidence: Evidence = .{},

    pub fn rule(self: *Slot, value: Rule) void {
        if (self.evidence.rule == null) self.evidence.rule = value;
    }

    pub fn within(self: *Slot, ordinal: ?u16, subject: ?[]const u8) void {
        if (self.evidence.ordinal == null) self.evidence.ordinal = ordinal;
        if (self.evidence.subject == null) if (subject) |bytes| {
            self.evidence.subject = Subject.init(bytes);
        };
    }
};

/// The slot of an owner's optional out-parameter: recording into no slot is a no-op.
pub fn record(slot: ?*Slot, value: Rule, ordinal: ?u16, subject: ?[]const u8) void {
    const present = slot orelse return;
    present.rule(value);
    present.within(ordinal, subject);
}

/// Fills a field an outer owner knows without changing the rule: the ordinal a loop is at, or the
/// step or resource it is checking.
pub fn locate(slot: ?*Slot, ordinal: ?u16, subject: ?[]const u8) void {
    const present = slot orelse return;
    present.within(ordinal, subject);
}

test "the first rule recorded stays and each other field is filled once" {
    var slot: Slot = .{};
    record(&slot, .outcomes, null, "step-a");
    record(&slot, .steps, 3, "step-b");
    locate(&slot, 5, "step-c");
    try std.testing.expectEqual(Rule.outcomes, slot.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 3), slot.evidence.ordinal.?);
    try std.testing.expectEqualStrings("step-a", slot.evidence.subject.?.text());
}

test "the detail prints after the code: the rule, the definition and the subject, each only when known" {
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var evidence: Evidence = .{ .rule = .outcomes, .ordinal = 2, .subject = Subject.init("assemble"), .path = Path.init("spec.workflow.yaml") };
    try write(.{ .step = "validate_workflow_schema", .evidence = evidence }, &writer);
    try std.testing.expectEqualStrings(": outcomes; spec.workflow.yaml; step=assemble", writer.buffered());
    // With no path the entry is named by its ordinal; with no rule the step stands in for it.
    writer = .fixed(&buffer);
    evidence = .{ .ordinal = 7 };
    try write(.{ .step = "parse_workflows", .evidence = evidence }, &writer);
    try std.testing.expectEqualStrings(": parse_workflows; entry 7", writer.buffered());
    writer = .fixed(&buffer);
    try write(.{ .step = "enumerate_workflow_resources", .evidence = .{} }, &writer);
    try std.testing.expectEqualStrings(": enumerate_workflow_resources", writer.buffered());
    // A resource's subject is labelled as one.
    writer = .fixed(&buffer);
    evidence = .{ .rule = .resource_binding, .subject = Subject.init("prompt") };
    try write(.{ .step = "resolve_workflow_resources", .evidence = evidence }, &writer);
    try std.testing.expectEqualStrings(": resource_binding; resource=prompt", writer.buffered());
}

test "recording into no slot does nothing" {
    record(null, .steps, 1, "x");
    locate(null, 1, "x");
}

test "bounded text is copied whole or not at all" {
    const fits = Bounded(4).init("abcd").?;
    try std.testing.expectEqualStrings("abcd", fits.text());
    try std.testing.expect(Bounded(4).init("abcde") == null);
    // A subject longer than an identifier can be is not recorded rather than cut.
    var slot: Slot = .{};
    const long = [_]u8{'a'} ** (workflow.max_step_id_bytes + 1);
    record(&slot, .steps, 1, &long);
    try std.testing.expect(slot.evidence.subject == null);
}
