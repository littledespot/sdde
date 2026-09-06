const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const source = @import("../ports/toolchain_authority_source.zig");
const parser = @import("../ports/toolchain_document_parser.zig");
const runners = @import("../application/toolchain_workflow_runner.zig");
const values = @import("../application/toolchain_workflow_values.zig");
const binding = @import("../application/workflow_operation_binding.zig");
const core = @import("core_workflow_operations.zig");
const model_request = @import("model_request_operations.zig");
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
const clarification = @import("../application/clarification_input_workflow.zig");
const input_source = @import("../ports/feature_input_source.zig");
const input_parser = @import("../ports/clarification_input_parser.zig");
const ingestion = @import("../application/reference_ingestion_workflow.zig");
const corpus_source = @import("../ports/reference_corpus_source.zig");
const corpus_decoder = @import("../ports/reference_decoder.zig");
const evidence = @import("../application/reference_evidence_workflow.zig");
const identity_source = @import("../ports/reference_state_identity.zig");
const extraction = @import("../application/reference_extraction_workflow.zig");
const path_tokens = @import("../application/path_token_workflow.zig");
const passive_literals = @import("../application/passive_literal_workflow.zig");
const structured_tokens = @import("../application/structured_token_workflow.zig");

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
    resolve_feature_paths: clarification.ResolvePaths,
    capture_clarifications: clarification.Capture,
    parse_clarification_state: clarification.ParseState,
    validate_clarification_state: clarification.ValidateState,
    validate_clarification_forms: clarification.ValidateForms,
    inventory_references: ingestion.Inventory,
    validate_reference_inventory: ingestion.ValidateInventory,
    capture_references: ingestion.Capture,
    decode_references: ingestion.Decode,
    validate_reference_accounting: ingestion.ValidateAccounting,
    assign_reference_identities: evidence.Assign,
    build_reference_chunks: evidence.BuildChunks,
    validate_reference_chunks: evidence.ValidateChunks,
    validate_source_citations: evidence.ValidateCitations,
    parse_reference_extraction: extraction.Parse,
    validate_extraction_text: extraction.ValidateText,
    validate_reference_claims: extraction.Validate,
    assign_reference_claims: extraction.Assign,
    build_reference_extraction: extraction.Build,
    account_reference_extraction: extraction.Account,
    compile_naming: path_tokens.Compile,
    build_path_grammar: path_tokens.Build,
    scan_path_tokens: path_tokens.Scan,
    scan_passive_literals: passive_literals.Scan,
    assign_passive_literals: passive_literals.Assign,
    validate_passive_literals: passive_literals.Validate,
    extract_structured_facts: structured_tokens.Extract,
    assign_token_candidates: structured_tokens.AssignCandidates,
    validate_token_classifications: structured_tokens.Validate,
    assign_preserved_tokens: structured_tokens.AssignTokens,
    build_preserved_claims: structured_tokens.BuildClaims,
    model_requests: model_request.Assembly,
    entries: [core.entries.len + 49 + model_request.count]operations.Entry,
    registry: operations.Registry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator, project_source: source.ProjectCapturer, preset_source: source.PresetEnumerator, preset_capture: source.PresetCapturer, document_parser: parser.Parser, policies: toolchain.PolicyRegistry, unicode: normalizer.Normalizer, directory_inspector: reference_source.Inspector, feature_inspector: feature_source.Inspector, input_capture: input_source.Capturer, state_parser: input_parser.StateParser, form_parser: input_parser.FormParser, reference_inventory: corpus_source.Enumerator, reference_capture: corpus_source.Capturer, reference_decoder: corpus_decoder.Decoder, case_folder: normalizer.CaseFolder, reference_identity: identity_source.Source, classifier: normalizer.LexicalClassifier) void {
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
            .resolve_feature_paths = .{ .allocator = allocator },
            .capture_clarifications = .{ .allocator = allocator, .action = .{ .source = input_capture } },
            .parse_clarification_state = .{ .allocator = allocator, .action = .{ .parser = state_parser } },
            .validate_clarification_state = .{ .allocator = allocator },
            .validate_clarification_forms = .{ .allocator = allocator, .action = .{ .parser = form_parser } },
            .inventory_references = .{ .allocator = allocator, .action = .{ .source = reference_inventory } },
            .validate_reference_inventory = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .case_folder = case_folder } },
            .capture_references = .{ .allocator = allocator, .action = .{ .source = reference_capture } },
            .decode_references = .{ .allocator = allocator, .action = .{ .decoder = reference_decoder } },
            .validate_reference_accounting = .{ .allocator = allocator },
            .assign_reference_identities = .{ .allocator = allocator, .action = .{ .identities = reference_identity } },
            .build_reference_chunks = .{ .allocator = allocator },
            .validate_reference_chunks = .{ .allocator = allocator },
            .validate_source_citations = .{ .allocator = allocator },
            .parse_reference_extraction = .{ .allocator = allocator },
            .extract_structured_facts = .{ .allocator = allocator },
            .assign_token_candidates = .{ .allocator = allocator },
            .validate_token_classifications = .{ .allocator = allocator },
            .assign_preserved_tokens = .{ .allocator = allocator },
            .build_preserved_claims = .{ .allocator = allocator },
            .validate_extraction_text = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder, .classifier = classifier } } },
            .validate_reference_claims = .{ .allocator = allocator },
            .assign_reference_claims = .{ .allocator = allocator },
            .build_reference_extraction = .{ .allocator = allocator },
            .account_reference_extraction = .{ .allocator = allocator },
            .compile_naming = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder } },
            .build_path_grammar = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder } },
            .scan_path_tokens = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder, .classifier = classifier } },
            .scan_passive_literals = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder, .classifier = classifier } },
            .assign_passive_literals = .{ .allocator = allocator },
            .validate_passive_literals = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder, .classifier = classifier } },
            .model_requests = undefined,
            .entries = undefined,
            .registry = undefined,
        };
        self.model_requests.init(allocator);
        self.entries = core.entries ++ self.model_requests.entries ++ [_]operations.Entry{
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
            entry(clarification.ResolvePaths, &self.resolve_feature_paths),
            entry(clarification.Capture, &self.capture_clarifications),
            entry(clarification.ParseState, &self.parse_clarification_state),
            entry(clarification.ValidateState, &self.validate_clarification_state),
            entry(clarification.ValidateForms, &self.validate_clarification_forms),
            entry(ingestion.Inventory, &self.inventory_references),
            entry(ingestion.ValidateInventory, &self.validate_reference_inventory),
            entry(ingestion.Capture, &self.capture_references),
            entry(ingestion.Decode, &self.decode_references),
            entry(ingestion.ValidateAccounting, &self.validate_reference_accounting),
            entry(evidence.Assign, &self.assign_reference_identities),
            entry(evidence.BuildChunks, &self.build_reference_chunks),
            entry(evidence.ValidateChunks, &self.validate_reference_chunks),
            entry(evidence.ValidateCitations, &self.validate_source_citations),
            entry(extraction.Parse, &self.parse_reference_extraction),
            entry(structured_tokens.Extract, &self.extract_structured_facts),
            entry(structured_tokens.AssignCandidates, &self.assign_token_candidates),
            entry(structured_tokens.Validate, &self.validate_token_classifications),
            entry(structured_tokens.AssignTokens, &self.assign_preserved_tokens),
            entry(structured_tokens.BuildClaims, &self.build_preserved_claims),
            entry(extraction.ValidateText, &self.validate_extraction_text),
            entry(extraction.Validate, &self.validate_reference_claims),
            entry(extraction.Assign, &self.assign_reference_claims),
            entry(extraction.Build, &self.build_reference_extraction),
            entry(extraction.Account, &self.account_reference_extraction),
            entry(path_tokens.Compile, &self.compile_naming),
            entry(path_tokens.Build, &self.build_path_grammar),
            entry(path_tokens.Scan, &self.scan_path_tokens),
            entry(passive_literals.Scan, &self.scan_passive_literals),
            entry(passive_literals.Assign, &self.assign_passive_literals),
            entry(passive_literals.Validate, &self.validate_passive_literals),
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
        self.resolve_feature_paths.action.roots = registry.featureArtifactRoots();
        self.capture_clarifications.action.source.capability = registry.featureInputRead();
        self.inventory_references.action.source.capability = registry.referenceContentRead();
        self.capture_references.action.source.capability = registry.referenceContentRead();
    }
};

const schemas = values.schemas ++ invocation_values.schemas ++ reference_values.schemas ++ feature.schemas ++ clarification.schemas ++ ingestion.schemas ++ evidence.schemas ++ extraction.schemas ++ path_tokens.schemas ++ passive_literals.schemas ++ structured_tokens.schemas ++ model_request.schemas;
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
}, .{
    .id = "core.feature-input-read@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read, capabilities.feature_input_read },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
    .total_model_token_budget = .{ .value = 100_000 },
}, .{
    .id = "core.reference-ingestion@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read, capabilities.feature_input_read, capabilities.reference_content_read, capabilities.reference_decode, capabilities.reference_identity, capabilities.toolchain_read, capabilities.toolchain_parser },
    .allowed_terminal_outcomes = &.{ .ok, .blocked, .failed, .cancelled },
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
            .outcomes = if (@hasDecl(T, "outcomes")) &T.outcomes else &.{ .ok, .failed },
        },
        .binding = binding.bind(T, context, T.invoke),
    };
}
