const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const source = @import("../ports/toolchain_authority_source.zig");
const parser = @import("../ports/toolchain_document_parser.zig");
const runners = @import("../application/toolchain_workflow_runner.zig");
const values = @import("../application/toolchain_workflow_values.zig");
const binding = @import("../application/workflow_operation_binding.zig");
const core = @import("core_workflow_operations.zig");
const toolchain = @import("../domain/toolchain.zig");
const roots = @import("../domain/bootstrap_root_registry.zig");
const capabilities = @import("../domain/workflow_capability.zig");
const reference = @import("../application/reference_workflow_runner.zig");
const invocation = @import("../application/specify_invocation_runner.zig");
const invocation_values = @import("../application/specify_invocation_values.zig");
const reference_values = @import("../application/reference_workflow_values.zig");
const normalizer = @import("../ports/unicode_normalizer.zig");
const reference_source = @import("../ports/reference_directory_inspector.zig");
const feature = @import("../application/feature_directory_workflow.zig");
const feature_source = @import("../ports/feature_directory_inspector.zig");

/// Composition of native implementations, not a workflow graph. No setup action
/// executes until the selected YAML reaches its registered operation.
pub const Assembly = struct {
    capture_project: runners.CaptureProject,
    inventory_presets: runners.InventoryPresets,
    capture_presets: runners.CapturePresets,
    parse_documents: runners.ParseDocuments,
    validate_project: runners.ValidateProject,
    validate_registry: runners.ValidateRegistry,
    resolve_inheritance: runners.ResolveInheritance,
    compose: runners.Compose,
    validate_safety: runners.ValidateSafety,
    invocation: invocation.Invocation,
    parse_invocation: invocation.ParseInvocation,
    validate_arguments: invocation.ValidateArguments,
    normalize_selector: reference.NormalizeSelector,
    validate_selector: reference.ValidateSelector,
    inspect_directory: reference.InspectDirectory,
    normalize_feature: feature.Normalize,
    validate_feature: feature.Validate,
    inspect_feature: feature.Inspect,
    entries: [core.entries.len + 18]operations.Entry,
    registry: operations.Registry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator, project_source: source.ProjectCapturer, preset_source: source.PresetEnumerator, preset_capture: source.PresetCapturer, document_parser: parser.Parser, policies: toolchain.PolicyRegistry, unicode: normalizer.Normalizer, directory_inspector: reference_source.Inspector, feature_inspector: feature_source.Inspector) void {
        self.* = .{
            .capture_project = .{ .allocator = allocator, .action = .{ .source = project_source } },
            .inventory_presets = .{ .allocator = allocator, .action = .{ .source = preset_source } },
            .capture_presets = .{ .allocator = allocator, .action = .{ .source = preset_capture } },
            .parse_documents = .{ .allocator = allocator, .action = .{ .parser = document_parser } },
            .validate_project = .{ .allocator = allocator },
            .validate_registry = .{ .allocator = allocator },
            .resolve_inheritance = .{ .allocator = allocator },
            .compose = .{ .allocator = allocator },
            .validate_safety = .{ .allocator = allocator, .action = .{ .registry = policies } },
            .invocation = .{ .allocator = allocator },
            .parse_invocation = .{ .allocator = allocator },
            .validate_arguments = .{ .allocator = allocator },
            .normalize_selector = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .validate_selector = .{ .allocator = allocator },
            .inspect_directory = .{ .allocator = allocator, .action = .{ .inspector = directory_inspector } },
            .normalize_feature = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .validate_feature = .{ .allocator = allocator },
            .inspect_feature = .{ .allocator = allocator, .action = .{ .inspector = feature_inspector } },
            .entries = undefined,
            .registry = undefined,
        };
        self.entries = core.entries ++ [_]operations.Entry{
            entry(runners.CaptureProject, &self.capture_project),
            entry(runners.InventoryPresets, &self.inventory_presets),
            entry(runners.CapturePresets, &self.capture_presets),
            entry(runners.ParseDocuments, &self.parse_documents),
            entry(runners.ValidateProject, &self.validate_project),
            entry(runners.ValidateRegistry, &self.validate_registry),
            entry(runners.ResolveInheritance, &self.resolve_inheritance),
            entry(runners.Compose, &self.compose),
            entry(runners.ValidateSafety, &self.validate_safety),
            .{ .contract = invocation.Invocation.contract, .binding = binding.bind(invocation.Invocation, &self.invocation, invocation.Invocation.invoke) },
            invocationEntry(invocation.ParseInvocation, &self.parse_invocation),
            entry(invocation.ValidateArguments, &self.validate_arguments),
            entry(reference.NormalizeSelector, &self.normalize_selector),
            entry(reference.ValidateSelector, &self.validate_selector),
            entry(reference.InspectDirectory, &self.inspect_directory),
            entry(feature.Normalize, &self.normalize_feature),
            entry(feature.Validate, &self.validate_feature),
            entry(feature.Inspect, &self.inspect_feature),
        };
        self.registry = .{ .operations = &self.entries, .policies = &profiles, .data_schemas = &schemas, .gates = &.{} };
    }

    pub fn bindRoots(self: *Assembly, registry: *const roots.BootstrapRootRegistry) void {
        self.capture_project.action.source.capability = registry.projectPrinciples();
        self.inventory_presets.action.source.capability = registry.toolchainPresetRegistry();
        self.capture_presets.action.source.capability = registry.toolchainPresetRegistry();
        self.inspect_directory.action.inspector.capability = registry.referenceSources();
        self.validate_feature.action.roots = registry.featureDirectoryRoots();
        self.inspect_feature.action.inspector.capability = registry.featureDirectoryRead();
    }
};

const schemas = values.schemas ++ invocation_values.schemas ++ reference_values.schemas ++ feature.schemas;
const profiles = core.profiles ++ [_]@import("../domain/workflow_operation.zig").PolicyProfile{ .{
    .id = "core.toolchain@1",
    .allowed_capabilities = &.{ capabilities.toolchain_read, capabilities.toolchain_parser },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
    .total_model_token_budget = .{ .value = 100_000 },
}, .{
    .id = "core.reference-read@1",
    .allowed_capabilities = &.{capabilities.reference_read},
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
    .total_model_token_budget = .{ .value = 100_000 },
}, .{
    .id = "core.directory-read@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
    .total_model_token_budget = .{ .value = 100_000 },
} };

fn invocationEntry(comptime T: type, context: *T) operations.Entry {
    var result = entry(T, context);
    result.contract.kind = .invocation;
    result.contract.outcomes = &.{.ok};
    return result;
}

fn entry(comptime T: type, context: *T) operations.Entry {
    const contract = T.Action.contract;
    return .{
        .contract = .{
            .id = contract.id,
            .kind = .step,
            .parameters = if (@hasDecl(T, "parameters")) &T.parameters else &.{},
            .requires = contract.requires,
            .optional = contract.optional,
            .produces = contract.produces,
            .replaces = contract.replaces,
            .invalidates = contract.invalidates,
            .side_effect = contract.side_effect,
            .outcomes = &.{ .ok, .failed },
        },
        .binding = binding.bind(T, context, T.invoke),
    };
}
