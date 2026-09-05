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
            .capabilities = &(if (derived.model_provider) [_][]const u8{@import("../domain/workflow_capability.zig").model_provider} else [_][]const u8{}) ++
                (if (derived.toolchain_read) [_][]const u8{@import("../domain/workflow_capability.zig").toolchain_read} else [_][]const u8{}) ++
                (if (derived.toolchain_parser) [_][]const u8{@import("../domain/workflow_capability.zig").toolchain_parser} else [_][]const u8{}) ++
                (if (derived.reference_read) [_][]const u8{@import("../domain/workflow_capability.zig").reference_read} else [_][]const u8{}) ++
                (if (derived.feature_read) [_][]const u8{@import("../domain/workflow_capability.zig").feature_read} else [_][]const u8{}) ++
                (if (derived.feature_input_read) [_][]const u8{@import("../domain/workflow_capability.zig").feature_input_read} else [_][]const u8{}) ++
                (if (derived.reference_content_read) [_][]const u8{@import("../domain/workflow_capability.zig").reference_content_read} else [_][]const u8{}) ++
                (if (derived.reference_decode) [_][]const u8{@import("../domain/workflow_capability.zig").reference_decode} else [_][]const u8{}),
        };
        fn call(erased: ?*anyopaque, input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const typed: ?*T = if (erased) |pointer| @ptrCast(@alignCast(pointer)) else null;
            return invoke(typed, input);
        }
    };
    return .{ .context = @ptrCast(context), .implementation = &compiled.implementation };
}

pub const Inspection = struct { valid: bool = true, model_provider: bool = false, toolchain_read: bool = false, toolchain_parser: bool = false, reference_read: bool = false, feature_read: bool = false, feature_input_read: bool = false, reference_content_read: bool = false, reference_decode: bool = false };

pub fn inspect(comptime T: type, comptime ancestors: []const type) Inspection {
    if (T == provider.LLMProviderInterface) return .{ .model_provider = true };
    if (T == @import("../ports/unicode_normalizer.zig").Normalizer) return .{};
    if (T == @import("../ports/unicode_normalizer.zig").CaseFolder) return .{};
    const reference_source = @import("../ports/reference_corpus_source.zig");
    if (T == reference_source.Enumerator or T == reference_source.Capturer) return .{ .reference_content_read = true };
    if (T == @import("../ports/reference_decoder.zig").Decoder) return .{ .reference_decode = true };
    if (T == @import("../ports/reference_directory_inspector.zig").Inspector) return .{ .reference_read = true };
    if (T == @import("../ports/feature_directory_inspector.zig").Inspector) return .{ .feature_read = true };
    if (T == @import("../ports/feature_input_source.zig").Capturer) return .{ .feature_input_read = true };
    const clarification_parser = @import("../ports/clarification_input_parser.zig");
    if (T == clarification_parser.StateParser or T == clarification_parser.FormParser) return .{};
    const toolchain_source = @import("../ports/toolchain_authority_source.zig");
    if (T == toolchain_source.ProjectCapturer or T == toolchain_source.PresetEnumerator or T == toolchain_source.PresetCapturer) return .{ .toolchain_read = true };
    if (T == @import("../ports/toolchain_document_parser.zig").Parser) return .{ .toolchain_parser = true };
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
                result.toolchain_read = result.toolchain_read or child.toolchain_read;
                result.toolchain_parser = result.toolchain_parser or child.toolchain_parser;
                result.reference_read = result.reference_read or child.reference_read;
                result.feature_read = result.feature_read or child.feature_read;
                result.feature_input_read = result.feature_input_read or child.feature_input_read;
                result.reference_content_read = result.reference_content_read or child.reference_content_read;
                result.reference_decode = result.reference_decode or child.reference_decode;
            }
            break :result result;
        },
        else => .{ .valid = false },
    };
}
