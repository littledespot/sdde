const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const provider = @import("../ports/llm_provider_interface.zig");

/// Composition supplies a typed context. The runner-facing erasure retains
/// exactly the capabilities derived from its reachable registered narrow ports.
pub fn bind(comptime T: type, context: ?*T, comptime invoke: *const fn (?*T, operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate) operations.Binding {
    const derived = comptime inspect(T, &.{});
    if (!derived.valid) @compileError("operation contexts require typed data and registered narrow ports; erased capabilities and callbacks are forbidden");
    const compiled = struct {
        const implementation: operations.Binding.Implementation = .{
            .invoke_fn = call,
            .context_required = T != void,
            .capabilities = if (derived.model_provider) &.{@import("../domain/workflow_capability.zig").model_provider} else &.{},
        };
        fn call(erased: ?*anyopaque, input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const typed: ?*T = if (erased) |pointer| @ptrCast(@alignCast(pointer)) else null;
            return invoke(typed, input);
        }
    };
    return .{ .context = @ptrCast(context), .implementation = &compiled.implementation };
}

pub const Inspection = struct { valid: bool = true, model_provider: bool = false };

pub fn inspect(comptime T: type, comptime ancestors: []const type) Inspection {
    if (T == provider.LLMProviderInterface) return .{ .model_provider = true };
    if (T == std.mem.Allocator) return .{}; // Allocation is runner-local, not an operational port.
    inline for (ancestors) |ancestor| if (T == ancestor) return .{};
    const next = ancestors ++ &[_]type{T};
    return switch (@typeInfo(T)) {
        .void, .bool, .int, .float, .@"enum" => .{},
        inline .optional, .array => |info| inspect(info.child, next),
        .pointer => |info| if (info.size == .one or info.size == .slice) inspect(info.child, next) else .{ .valid = false },
        inline .@"struct", .@"union" => |info| result: {
            var result: Inspection = .{};
            inline for (info.fields) |field| {
                const child = inspect(field.type, next);
                result.valid = result.valid and child.valid;
                result.model_provider = result.model_provider or child.model_provider;
            }
            break :result result;
        },
        else => .{ .valid = false },
    };
}
