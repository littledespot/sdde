//! Development-only evaluation data. These values never authorize engine work.
const std = @import("std");
const strict_json = @import("../../src/domain/strict_json.zig");
const relative = @import("../../src/domain/relative_directory_path.zig");
pub const ModelId = @import("../../src/domain/llm_provider_identity.zig").ModelId;
const ProviderId = @import("../../src/domain/llm_provider_identity.zig").ProviderId;

pub const Error = std.mem.Allocator.Error || error{InvalidEvaluationContract};
pub const Source = struct { id: []const u8, path: []const u8 };
pub const Origin = enum { supplied, recorded, scripted_generation, live_generation };
pub const WorkflowStatus = enum { not_run, completed, needs_user, failed, blocked, cancelled };
pub const Generation = struct {
    origin: Origin,
    workflow_status: WorkflowStatus,
    execution_id: ?[]const u8,
    provider: ?[]const u8,
    model: ?[]const u8,
};
pub const Case = struct {
    schema: []const u8,
    id: []const u8,
    sources: []const Source,
    rubric: []const u8,
};
pub const Anchor = struct { score: u16, description: []const u8 };
pub const Criterion = struct {
    id: []const u8,
    description: []const u8,
    evidence: []const u8,
    weight: u16,
    anchors: []const Anchor,
    allow_not_applicable: bool,
};
pub const Rubric = struct {
    schema: []const u8,
    id: []const u8,
    revision: u32,
    minimum_score: u16,
    maximum_score: u16,
    pass_threshold_percent: ?f64,
    criteria: []const Criterion,
};
pub const Document = struct { id: []const u8, text: []const u8 };
pub const Capture = struct {
    evaluation_id: []const u8,
    case: Case,
    case_bytes: []const u8,
    rubric: Rubric,
    rubric_bytes: []const u8,
    sources: []const Document,
    specification: []const u8,
    generation: Generation,
};

/// Arena-owned closed decoding. No unknown fields, duplicate keys or coercion
/// of malformed document syntax; callers retain the arena for every result.
pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8) Error!T {
    return strict_json.decode(T, allocator, bytes, .{ .maximum_depth = 32 }) catch |err| return map(err);
}
pub fn parseCase(allocator: std.mem.Allocator, bytes: []const u8) Error!Case {
    const value = try decode(Case, allocator, bytes);
    if (!std.mem.eql(u8, value.schema, "evaluation-case/v1") or !id(value.id) or value.sources.len == 0) return error.InvalidEvaluationContract;
    try path(value.rubric);
    for (value.sources, 0..) |source, index| {
        if (!id(source.id) or std.mem.eql(u8, source.id, "specification")) return error.InvalidEvaluationContract;
        try path(source.path);
        for (value.sources[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, source.id) or std.mem.eql(u8, prior.path, source.path)) return error.InvalidEvaluationContract;
        }
    }
    return value;
}
pub fn parseRubric(allocator: std.mem.Allocator, bytes: []const u8) Error!Rubric {
    const value = try decode(Rubric, allocator, bytes);
    if (!std.mem.eql(u8, value.schema, "evaluation-rubric/v1") or !id(value.id) or value.revision == 0 or
        value.minimum_score >= value.maximum_score or value.criteria.len == 0) return error.InvalidEvaluationContract;
    if (value.pass_threshold_percent) |threshold| {
        if (!std.math.isFinite(threshold) or threshold < 0 or threshold > 100) return error.InvalidEvaluationContract;
    }
    for (value.criteria, 0..) |criterion, index| {
        if (!id(criterion.id) or !text(criterion.description) or !text(criterion.evidence) or criterion.weight == 0 or
            criterion.anchors.len != @as(usize, value.maximum_score) - value.minimum_score + 1) return error.InvalidEvaluationContract;
        for (value.criteria[0..index]) |prior| if (std.mem.eql(u8, prior.id, criterion.id)) return error.InvalidEvaluationContract;
        for (criterion.anchors, 0..) |anchor, offset| {
            if (anchor.score != @as(usize, value.minimum_score) + offset or !text(anchor.description)) return error.InvalidEvaluationContract;
        }
    }
    return value;
}
pub fn validateCapture(value: Capture) Error!void {
    if (!id(value.evaluation_id) or !text(value.specification) or value.sources.len != value.case.sources.len) return error.InvalidEvaluationContract;
    for (value.sources, value.case.sources) |document, source| {
        if (!std.mem.eql(u8, document.id, source.id) or !text(document.text)) return error.InvalidEvaluationContract;
    }
    const g = value.generation;
    if (g.origin == .supplied) {
        if (g.workflow_status != .not_run or g.execution_id != null or g.provider != null or g.model != null) return error.InvalidEvaluationContract;
    } else if (g.origin == .live_generation or g.origin == .scripted_generation) {
        if (g.workflow_status != .completed or g.execution_id == null or !id(g.execution_id.?)) return error.InvalidEvaluationContract;
        if (g.origin == .live_generation and (g.provider == null or g.model == null)) return error.InvalidEvaluationContract;
    }
    if (g.execution_id) |v| if (!id(v)) return error.InvalidEvaluationContract;
    if (g.provider) |v| if (ProviderId.parse(v) == null) return error.InvalidEvaluationContract;
    if (g.model) |v| if (ModelId.parse(v) == null) return error.InvalidEvaluationContract;
}
pub fn path(value: []const u8) Error!void {
    relative.validate(value) catch return error.InvalidEvaluationContract;
}
pub fn id(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |c| if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.') return false;
    return true;
}
pub fn text(value: []const u8) bool {
    return std.mem.trim(u8, value, " \r\n\t").len != 0 and std.unicode.utf8ValidateSlice(value) and std.mem.indexOfScalar(u8, value, 0) == null;
}
fn map(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidEvaluationContract;
}
