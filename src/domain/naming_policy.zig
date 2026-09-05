const std = @import("std");
const naming = @import("naming_rule.zig");
const safety = @import("toolchain_safety.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
pub const Error = std.mem.Allocator.Error || error{ InvalidNamingPolicy, StaleNamingPolicy };
pub const BoundRule = struct { policy_id: []const u8, rule: naming.Rule };
pub const Compiled = struct {
    contract: enum { naming_policy_v1 },
    toolchain_identity: @import("execution_reference.zig").Ref,
    policy_ids: []const []const u8,
    rules: []const BoundRule,
};

/// Caller arena owns normalized rules. The input owner retains the identity
/// until the runner's ordinary immutable value constructor retains its copy.
pub fn compile(allocator: std.mem.Allocator, current: *const safety.ValidToolchain, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!Compiled {
    const policies = current.policies();
    const ids = try allocator.alloc([]const u8, policies.len);
    var rules: std.ArrayList(BoundRule) = .empty;
    for (policies, ids) |policy, *id| {
        id.* = try allocator.dupe(u8, policy.id);
        for (policy.naming) |rule| {
            var compiled = rule;
            compiled.id.bytes = try allocator.dupe(u8, rule.id.bytes);
            compiled.value = try normalize(allocator, rule.value, rule.case_sensitive, normalizer, folder);
            naming.validate(&.{compiled}) catch return error.InvalidNamingPolicy;
            try rules.append(allocator, .{ .policy_id = id.*, .rule = compiled });
        }
    }
    return .{ .contract = .naming_policy_v1, .toolchain_identity = current.identity(), .policy_ids = ids, .rules = try rules.toOwnedSlice(allocator) };
}

pub fn validateBinding(allocator: std.mem.Allocator, compiled: Compiled, current: *const safety.ValidToolchain, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!void {
    if (!compiled.toolchain_identity.eql(current.identity())) return error.StaleNamingPolicy;
    const policies = current.policies();
    if (compiled.policy_ids.len != policies.len) return error.InvalidNamingPolicy;
    var index: usize = 0;
    for (policies, compiled.policy_ids) |policy, id| {
        if (!std.mem.eql(u8, id, policy.id)) return error.InvalidNamingPolicy;
        for (policy.naming) |rule| {
            if (index >= compiled.rules.len) return error.InvalidNamingPolicy;
            const bound = compiled.rules[index];
            index += 1;
            if (!std.mem.eql(u8, bound.policy_id, id) or !std.mem.eql(u8, bound.rule.id.bytes, rule.id.bytes) or bound.rule.kind != rule.kind or bound.rule.case_sensitive != rule.case_sensitive) return error.InvalidNamingPolicy;
            const expected = try normalize(allocator, rule.value, rule.case_sensitive, normalizer, folder);
            defer allocator.free(expected);
            if (!std.mem.eql(u8, expected, bound.rule.value)) return error.InvalidNamingPolicy;
        }
    }
    if (index != compiled.rules.len) return error.InvalidNamingPolicy;
}

/// Workspace is derived from input length and Unicode expansion, not a policy
/// limit on model input/output. Source/resource readers retain their own bounds.
pub fn normalize(allocator: std.mem.Allocator, bytes: []const u8, case_sensitive: bool, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error![]const u8 {
    const capacity = std.math.add(usize, std.math.mul(usize, bytes.len, 4) catch return error.OutOfMemory, 4) catch return error.OutOfMemory;
    return (if (case_sensitive) normalizer.nfc(allocator, bytes, capacity) else folder.key(allocator, bytes, capacity)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidNamingPolicy;
}
