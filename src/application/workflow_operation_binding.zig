const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const provider = @import("../ports/llm_provider_interface.zig");
const capability = @import("../domain/workflow_capability.zig");

/// Composition supplies a typed context. The runner-facing erasure retains
/// exactly the capabilities derived from its reachable registered narrow ports.
pub fn bind(comptime T: type, context: ?*T, comptime invoke: *const fn (?*T, operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate) operations.Binding {
    @setEvalBranchQuota(10000);
    const derived = comptime inspect(T, &.{});
    if (!derived.valid) @compileError("operation contexts require typed data and registered narrow ports; erased capabilities and callbacks are forbidden");
    const compiled = struct {
        const implementation: operations.Binding.Implementation = .{
            .invoke_fn = call,
            .context_required = T != void,
            .capabilities = Capabilities(derived).list,
        };
        fn call(erased: ?*anyopaque, input: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            const typed: ?*T = if (erased) |pointer| @ptrCast(@alignCast(pointer)) else null;
            return invoke(typed, input);
        }
    };
    return .{ .context = @ptrCast(context), .implementation = &compiled.implementation };
}

/// The binding of the `request-model` kernel operation (ADR 0030). Its capabilities are the exact
/// union of what the stage contexts' reachable ports derive to, never an asserted list. Only the
/// runner runs the operation, through its orchestrator, so invoking the binding directly fails.
pub fn bindRequestKernel(comptime stage_types: []const type) operations.Binding {
    @setEvalBranchQuota(100000);
    const derived = comptime union_of: {
        var result: Inspection = .{};
        for (stage_types) |T| result.absorb(inspect(T, &.{}));
        break :union_of result;
    };
    if (!derived.valid) @compileError("operation contexts require typed data and registered narrow ports; erased capabilities and callbacks are forbidden");
    const compiled = struct {
        const implementation: operations.Binding.Implementation = .{
            .invoke_fn = refuse,
            .context_required = false,
            .capabilities = Capabilities(derived).list,
        };
        fn refuse(_: ?*anyopaque, _: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
            return error.KernelBindingNotInvocable;
        }
    };
    return .{ .context = null, .implementation = &compiled.implementation };
}

fn Capabilities(comptime derived: Inspection) type {
    return struct {
        const held = listed(derived.capabilities);
        const list: []const capability.Capability = &held;
    };
}

fn listed(comptime set: capability.Set) [set.count()]capability.Capability {
    var result: [set.count()]capability.Capability = undefined;
    var index: usize = 0;
    var members = set.iterator();
    while (members.next()) |member| : (index += 1) result[index] = member;
    return result;
}

/// What a context type reaches: the capabilities its registered narrow ports grant, and whether
/// every field is typed data or such a port. The set is closed by `capability.Capability`.
pub const Inspection = struct {
    valid: bool = true,
    capabilities: capability.Set = .initEmpty(),

    pub fn has(self: Inspection, held: capability.Capability) bool {
        return self.capabilities.contains(held);
    }

    fn grants(comptime held: capability.Capability) Inspection {
        var result: Inspection = .{};
        result.capabilities.insert(held);
        return result;
    }

    fn absorb(self: *Inspection, other: Inspection) void {
        self.valid = self.valid and other.valid;
        self.capabilities.setUnion(other.capabilities);
    }
};

pub fn inspect(comptime T: type, comptime ancestors: []const type) Inspection {
    if (T == @import("../ports/feature_log_activation.zig").Activator) return .grants(.feature_logging);
    if (T == provider.LLMProviderInterface) return .grants(.model_provider);
    if (T == @import("../ports/provider_operation_authorization.zig").Port) return .grants(.provider_authorization);
    if (T == @import("../ports/actor_authentication.zig").Port) return .grants(.actor_authentication);
    if (T == @import("../ports/unicode_normalizer.zig").Normalizer) return .{};
    if (T == @import("../ports/unicode_normalizer.zig").CaseFolder) return .{};
    if (T == @import("../ports/unicode_normalizer.zig").LexicalClassifier) return .{};
    const principle_source = @import("../ports/principle_source.zig");
    if (T == principle_source.Reader) return .grants(.principle_read);
    const reference_source = @import("../ports/reference_corpus_source.zig");
    if (T == reference_source.Enumerator or T == reference_source.Capturer) return .grants(.reference_content_read);
    if (T == @import("../ports/reference_decoder.zig").Decoder) return .grants(.reference_decode);
    if (T == @import("../ports/reference_state_identity.zig").Source) return .grants(.reference_identity);
    if (T == @import("../ports/reference_directory_inspector.zig").Inspector) return .grants(.reference_read);
    if (T == @import("../ports/feature_directory_inspector.zig").Inspector) return .grants(.feature_read);
    if (T == @import("../ports/feature_input_source.zig").Capturer) return .grants(.feature_input_read);
    if (T == @import("../ports/workflow_state_source.zig").Capturer) return .grants(.feature_input_read);
    if (T == @import("../ports/workflow_output.zig").Port) return .grants(.feature_output_write);
    const clarification_parser = @import("../ports/clarification_input_parser.zig");
    if (T == clarification_parser.StateParser or T == clarification_parser.FormParser) return .{};
    if (T == @import("../ports/actor_evidence_parser.zig").Parser) return .{};
    const toolchain_source = @import("../ports/toolchain_authority_source.zig");
    if (T == toolchain_source.ProjectCapturer or T == toolchain_source.PresetEnumerator or T == toolchain_source.PresetCapturer) return .grants(.toolchain_read);
    if (T == @import("../ports/toolchain_document_parser.zig").Parser) return .grants(.toolchain_parser);
    if (T == @import("../ports/workflow_contract_source.zig").Source) return .{}; // Immutable compiled metadata only.
    if (T == std.mem.Allocator) return .{}; // Allocation is runner-local, not an operational port.
    inline for (ancestors) |ancestor| if (T == ancestor) return .{};
    const next = ancestors ++ &[_]type{T};
    return switch (@typeInfo(T)) {
        .void, .bool, .int, .float, .@"enum" => .{},
        inline .optional, .array => |info| inspect(info.child, next),
        .pointer => |info| if (info.size == .one or info.size == .slice) inspect(info.child, next) else .{ .valid = false },
        inline .@"struct", .@"union" => |info| result: {
            var result: Inspection = .{};
            inline for (info.fields) |field| result.absorb(inspect(field.type, next));
            break :result result;
        },
        else => .{ .valid = false },
    };
}
