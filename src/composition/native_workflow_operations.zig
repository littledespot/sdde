const reconciliation_stage = @import("../application/reference_reconciliation_stage_workflow.zig");
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
const input_preparation = @import("../application/input_preparation_workflow.zig");
const invocation = @import("../application/specify_invocation_runner.zig");
const invocation_values = @import("../application/specify_invocation_values.zig");
const reference_values = @import("../application/reference_workflow_values.zig");
const normalizer = @import("../ports/unicode_normalizer.zig");
const reference_source = @import("../ports/reference_directory_inspector.zig");
const logging = @import("../application/feature_logging_workflow.zig");
const feature = @import("../application/feature_directory_workflow.zig");
const feature_source = @import("../ports/feature_directory_inspector.zig");
const clarification = @import("../application/clarification_input_workflow.zig");
const input_source = @import("../ports/feature_input_source.zig");
const input_parser = @import("../ports/clarification_input_parser.zig");
const evidence_preparation = @import("../application/reference_evidence_preparation_workflow.zig");
const token_preparation = @import("../application/reference_token_preparation_workflow.zig");
const corpus_source = @import("../ports/reference_corpus_source.zig");
const corpus_decoder = @import("../ports/reference_decoder.zig");
const evidence = @import("../application/reference_evidence_workflow.zig");
const identity_source = @import("../ports/reference_state_identity.zig");
const extraction = @import("../application/reference_extraction_workflow.zig");
const path_tokens = @import("../application/path_token_workflow.zig");
const passive_literals = @import("../application/passive_literal_workflow.zig");
const text_repair = @import("../application/reference_text_repair_workflow.zig");
const generic_repair = @import("../application/repair_workflow.zig");
const reconciliation_repair = @import("../application/reference_reconciliation_repair_workflow.zig");
const extraction_repair = @import("../application/reference_extraction_repair_workflow.zig");
const structured_tokens = @import("../application/structured_token_workflow.zig");
const reconciliation = @import("../application/reference_reconciliation_workflow.zig");
const authority = @import("../application/required_authority_workflow.zig");
const reference_model = @import("../application/reference_model_workflow.zig");
const specification = @import("../application/specification_workflow.zig");
const scenario_link = @import("../application/scenario_link_workflow.zig");
const scenario_generation = @import("../application/scenario_generation_workflow.zig");
const source_omission = @import("../application/source_omission_repair_workflow.zig");
const support_repair = @import("../application/specification_support_repair_workflow.zig");
const specification_support = @import("../application/specification_support_workflow.zig");
const specification_repair = @import("../application/specification_repair_workflow.zig");
const specification_rendering = @import("../application/specification_rendering_workflow.zig");
const output = @import("../application/workflow_output_binding.zig");
const clarification_refresh = @import("../application/clarification_refresh_workflow.zig");
const principles = @import("../application/principle_workflow.zig");
const packet_guidance = @import("../application/packet_guidance_workflow.zig");
const incomplete = @import("../application/incomplete_specification_workflow.zig");
const publication = @import("../application/specification_publication_workflow.zig");

/// The native operation implementations, one field each. A field is one registered operation, in the order the
/// registry lists them: `registered` derives every entry and the entry count from these fields, so declaring an
/// operation here registers it exactly once, at its own address.
pub const Operations = struct {
    capture_principle_registry: principles.CaptureRegistry,
    capture_packet_guidance: packet_guidance.Capture,
    prepare_toolchain: runners.PrepareToolchain,
    invocation: invocation.Invocation,
    parse_invocation: invocation.ParseInvocation,
    validate_arguments: invocation.ValidateArguments,
    prepare_inputs: input_preparation.PrepareInputs,
    activate_feature_logging: logging.Activate,
    prepare_reference_evidence: evidence_preparation.PrepareReferenceEvidence,
    parse_reference_extraction: extraction.Parse,
    initialize_extraction: reference_model.Initialize,
    check_extraction: reference_model.CheckExtraction,
    build_extraction_packet: reference_model.BuildExtractionInput,
    force_classifications: reference_model.ForceClassifications,
    collect_extraction: reference_model.CollectExtraction,
    finish_extraction: reference_model.FinishExtraction,
    build_dispositions: reconciliation_stage.Build(.dispositions),
    collect_dispositions: reconciliation_stage.Collect(.dispositions),
    build_signals: reconciliation_stage.Build(.signals),
    collect_signals: reconciliation_stage.Collect(.signals),
    build_conflicts: reconciliation_stage.Build(.conflicts),
    collect_conflicts: reconciliation_stage.Collect(.conflicts),
    check_reconciliation_phase: reconciliation_stage.Check,
    build_reconciliation_packet: reference_model.BuildReconciliationInput,
    check_reconciliation: reference_model.CheckReconciliation,
    collect_reconciliation: reference_model.CollectReconciliation,
    specification_source_readiness: specification.SourceReadiness,
    source_preservation_policy: authority.SourcePreservationPolicy,
    project_source_preservation: authority.ProjectSourcePreservation,
    initialize_specification: specification.Initialize,
    compose_specification_story: specification.ComposeStory,
    check_specification: specification.Check,
    build_specification_packet: specification.BuildInput,
    collect_specification: specification.Collect,
    parse_specification: specification.Parse,
    validate_specification: specification.Validate,
    advance_specification: specification.Advance,
    plan_scenario_generation: scenario_generation.Plan,
    check_scenario_generation: scenario_generation.Check,
    advance_scenario_generation: scenario_generation.Advance,
    complete_scenario_generation: scenario_generation.Complete,
    plan_scenario_links: scenario_link.Plan,
    check_scenario_links: scenario_link.Check,
    build_scenario_link_packet: scenario_link.BuildInput,
    admit_scenario_link: scenario_link.Admit,
    assemble_specification: specification.Assemble,
    validate_specification_coverage: specification.ValidateCoverage,
    build_specification_support: specification_support.BuildInput,
    collect_specification_support: specification_support.Collect,
    check_specification_support_localization: specification_support.CheckLocalization,
    build_specification_support_loss: specification_support.BuildLossInput,
    collect_specification_support_loss: specification_support.CollectLoss,
    apply_specification_support: specification_support.Apply,
    initialize_specification_review: specification_support.Initialize,
    build_authority_observations: authority.BuildObservations,
    retire_authority: authority.Retire,
    validate_token_classifications: extraction.ValidateTokenClassifications,
    // The four generic repair operations (ADR 0033). Each holds its owners' bindings, so an owner's
    // rules exist once, and a repair step names its owner (`owner:`), not a per-owner operation.
    authorize_repair: generic_repair.AuthorizeRepair,
    build_repair_input: generic_repair.BuildRepairInput,
    parse_repair: generic_repair.ParseRepair,
    merge_repair: generic_repair.MergeRepair,
    assign_preserved_tokens: structured_tokens.AssignTokens,
    build_preserved_claims: structured_tokens.BuildClaims,
    build_reconciliation_items: reconciliation.BuildItems,
    partition_reconciliation: reconciliation.Partition,
    assign_reconciliation_partitions: reconciliation.AssignPartitions,
    validate_reconciliation_partitions: reconciliation.ValidatePartitions,
    build_reconciliation_input: reconciliation.BuildInput,
    check_summary_reuse: reconciliation.CheckSummaryReuse,
    reuse_reconciliation_summary: reconciliation.ReuseSummary,
    parse_reconciliation: reconciliation.Parse,
    validate_reconciliation_summary: reconciliation.ValidateSummary,
    assign_reconciliation_summary: reconciliation.AssignSummary,
    build_reconciliation_summary: reconciliation.BuildSummary,
    validate_reconciliation_dispositions: reconciliation.ValidateDispositions,
    validate_reconciliation_signals: reconciliation.ValidateSignals,
    validate_reconciliation_conflicts: reconciliation.ValidateConflicts,
    assign_reconciliation_records: reconciliation.AssignRecords,
    build_reconciliation_records: reconciliation.BuildRecords,
    account_reconciliation: reconciliation.Account,
    project_specification_authority: authority.ProjectSpecification,
    build_required_authority: authority.Build,
    reconcile_required_authority: authority.Reconcile,
    validate_required_authority: authority.Validate,
    validate_extraction_text: extraction.ValidateText,
    validate_reference_claims: extraction.Validate,
    assign_reference_claims: extraction.Assign,
    build_reference_extraction: extraction.Build,
    account_reference_extraction: extraction.Account,
    compile_naming: path_tokens.Compile,
    prepare_reference_tokens: token_preparation.PrepareReferenceTokens,
    project_specification_document: specification_rendering.Project,
    render_specification: specification_rendering.Render,
    validate_specification_rendering: specification_rendering.Validate,
    build_authority_needs: clarification_refresh.BuildAuthorityNeeds,
    build_specification_need: clarification_refresh.BuildSpecificationNeed,
    refresh_clarifications: clarification_refresh.Refresh,
    render_clarifications: clarification_refresh.Render,
    check_clarifications: clarification_refresh.Check,
    publish_output: output.Publish,
    build_resolved_needs: publication.ResolvedNeeds,
    build_specification_state: publication.Build,
    build_incomplete_specification: incomplete.Build,
    render_incomplete_specification: incomplete.Render,
    prepare_incomplete_specification_output: incomplete.Prepare,
    build_reference_snapshot: publication.BuildSnapshot,
    render_reference_context: publication.RenderReference,
    prepare_specification_output: publication.Prepare,
};

/// Composition of native implementations, not a workflow graph. No setup action
/// executes until the selected YAML reaches its registered operation.
pub const Assembly = struct {
    ops: Operations,
    model_requests: model_request.Assembly,
    entries: [core.entries.len + std.meta.fields(Operations).len + model_request.count]operations.Entry,
    registry: operations.Registry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator, project_source: source.ProjectCapturer, preset_source: source.PresetEnumerator, preset_capture: source.PresetCapturer, document_parser: parser.Parser, policies: toolchain.PolicyRegistry, unicode: normalizer.Normalizer, directory_inspector: reference_source.Inspector, feature_inspector: feature_source.Inspector, input_capture: input_source.Capturer, state_parser: input_parser.StateParser, form_parser: input_parser.FormParser, reference_inventory: corpus_source.Enumerator, reference_capture: corpus_source.Capturer, reference_decoder: corpus_decoder.Decoder, case_folder: normalizer.CaseFolder, reference_identity: identity_source.Source, classifier: normalizer.LexicalClassifier) void {
        self.ops = .{
            .capture_principle_registry = .{ .allocator = allocator, .action = .{} },
            .capture_packet_guidance = .{ .allocator = allocator },
            .prepare_toolchain = .{ .allocator = allocator, .action = .{ .project_source = project_source, .preset_source = preset_source, .preset_capture = preset_capture, .parser = document_parser, .policies = policies } },
            .invocation = .{ .allocator = allocator },
            .parse_invocation = .{ .allocator = allocator },
            .validate_arguments = .{ .allocator = allocator },
            .prepare_inputs = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .feature_inspector = feature_inspector, .reference_inspector = directory_inspector, .input_source = input_capture, .state_parser = state_parser, .form_parser = form_parser } },
            .activate_feature_logging = .{ .allocator = allocator },
            .prepare_reference_evidence = .{ .allocator = allocator, .action = .{ .enumerator = reference_inventory, .normalizer = unicode, .case_folder = case_folder, .capturer = reference_capture, .decoder = reference_decoder, .identities = reference_identity } },
            .parse_reference_extraction = .{ .allocator = allocator },
            .initialize_extraction = .{ .allocator = allocator },
            .check_extraction = .{},
            .build_extraction_packet = .{ .allocator = allocator },
            .force_classifications = .{ .allocator = allocator },
            .collect_extraction = .{ .allocator = allocator },
            .finish_extraction = .{ .allocator = allocator },
            .build_dispositions = .{ .allocator = allocator },
            .collect_dispositions = .{ .allocator = allocator },
            .build_signals = .{ .allocator = allocator },
            .collect_signals = .{ .allocator = allocator },
            .build_conflicts = .{ .allocator = allocator },
            .collect_conflicts = .{ .allocator = allocator },
            .check_reconciliation_phase = .{},
            .build_reconciliation_packet = .{ .allocator = allocator },
            .check_reconciliation = .{},
            .collect_reconciliation = .{ .allocator = allocator },
            .validate_token_classifications = .{ .allocator = allocator },
            .assign_preserved_tokens = .{ .allocator = allocator },
            .build_preserved_claims = .{ .allocator = allocator },
            .build_reconciliation_items = .{ .allocator = allocator },
            .partition_reconciliation = .{ .allocator = allocator },
            .assign_reconciliation_partitions = .{ .allocator = allocator },
            .validate_reconciliation_partitions = .{ .allocator = allocator },
            .build_reconciliation_input = .{ .allocator = allocator },
            .check_summary_reuse = .{ .allocator = allocator, .action = .{} },
            .reuse_reconciliation_summary = .{ .allocator = allocator, .action = .{} },
            .parse_reconciliation = .{ .allocator = allocator },
            .validate_reconciliation_summary = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .assign_reconciliation_summary = .{ .allocator = allocator },
            .build_reconciliation_summary = .{ .allocator = allocator },
            .validate_reconciliation_dispositions = .{ .allocator = allocator, .action = .{} },
            .validate_reconciliation_signals = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .validate_reconciliation_conflicts = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .assign_reconciliation_records = .{ .allocator = allocator },
            .build_reconciliation_records = .{ .allocator = allocator },
            .account_reconciliation = .{ .allocator = allocator },
            .project_specification_authority = .{ .allocator = allocator },
            .build_required_authority = .{ .allocator = allocator },
            .reconcile_required_authority = .{ .allocator = allocator },
            .validate_required_authority = .{ .allocator = allocator },
            .validate_extraction_text = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .validate_reference_claims = .{ .allocator = allocator },
            .assign_reference_claims = .{ .allocator = allocator },
            .build_reference_extraction = .{ .allocator = allocator },
            .account_reference_extraction = .{ .allocator = allocator },
            .compile_naming = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .folder = case_folder } },
            .prepare_reference_tokens = .{ .allocator = allocator, .action = .{ .normalizer = unicode, .case_folder = case_folder, .classifier = classifier } },
            .specification_source_readiness = .{ .allocator = allocator },
            .source_preservation_policy = .{ .allocator = allocator },
            .project_source_preservation = .{ .allocator = allocator },
            .initialize_specification = .{ .allocator = allocator },
            .compose_specification_story = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .project_specification_document = .{ .allocator = allocator },
            .build_authority_needs = .{ .allocator = allocator },
            .build_specification_need = .{ .allocator = allocator },
            .refresh_clarifications = .{ .allocator = allocator },
            .render_clarifications = .{ .allocator = allocator },
            .check_clarifications = .{},
            .publish_output = .{ .allocator = allocator },
            .build_resolved_needs = .{ .allocator = allocator },
            .build_specification_state = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .build_incomplete_specification = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .render_incomplete_specification = .{ .allocator = allocator },
            .prepare_incomplete_specification_output = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .build_reference_snapshot = .{ .allocator = allocator },
            .render_reference_context = .{ .allocator = allocator },
            .prepare_specification_output = .{ .allocator = allocator, .action = .{ .normalizer = unicode } },
            .render_specification = .{ .allocator = allocator },
            .validate_specification_rendering = .{ .allocator = allocator },
            .validate_specification_coverage = .{ .allocator = allocator, .action = .{} },
            .build_specification_support = .{ .allocator = allocator },
            .collect_specification_support = .{ .allocator = allocator },
            .check_specification_support_localization = .{},
            .build_specification_support_loss = .{ .allocator = allocator },
            .collect_specification_support_loss = .{ .allocator = allocator },
            .apply_specification_support = .{ .allocator = allocator },
            .initialize_specification_review = .{ .allocator = allocator },
            .build_authority_observations = .{ .allocator = allocator },
            .retire_authority = .{},
            .check_specification = .{},
            .build_specification_packet = .{ .allocator = allocator },
            .collect_specification = .{ .allocator = allocator },
            .parse_specification = .{ .allocator = allocator },
            .validate_specification = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .advance_specification = .{ .allocator = allocator },
            .plan_scenario_generation = .{ .allocator = allocator },
            .check_scenario_generation = .{},
            .advance_scenario_generation = .{ .allocator = allocator },
            .complete_scenario_generation = .{ .allocator = allocator },
            .plan_scenario_links = .{ .allocator = allocator },
            .check_scenario_links = .{ .allocator = allocator },
            .build_scenario_link_packet = .{ .allocator = allocator },
            .admit_scenario_link = .{ .allocator = allocator },
            .assemble_specification = .{ .allocator = allocator, .action = .{ .validator = .{ .normalizer = unicode, .folder = case_folder } } },
            .authorize_repair = .{
                .reference_text = .{ .allocator = allocator },
                .reference_extraction = .{ .allocator = allocator },
                .reference_summary = .{ .allocator = allocator },
                .reference_dispositions = .{ .allocator = allocator },
                .reference_signals = .{ .allocator = allocator },
                .reference_conflicts = .{ .allocator = allocator },
                .source_omission = .{ .allocator = allocator },
                .specification_unit = .{ .allocator = allocator },
                .specification_support = .{ .allocator = allocator },
            },
            .build_repair_input = .{
                .reference_text = .{ .allocator = allocator },
                .reference_extraction = .{ .allocator = allocator },
                .reference_reconciliation = .{ .allocator = allocator },
                .source_omission = .{ .allocator = allocator },
                .specification_unit = .{ .allocator = allocator },
                .specification_support = .{ .allocator = allocator },
            },
            .parse_repair = .{
                .reference_text = .{ .allocator = allocator },
                .reference_extraction = .{ .allocator = allocator },
                .reference_reconciliation = .{ .allocator = allocator },
                .source_omission = .{ .allocator = allocator },
                .specification_unit = .{ .allocator = allocator },
                .specification_support = .{ .allocator = allocator },
            },
            .merge_repair = .{
                .reference_text = .{ .allocator = allocator, .normalizer = unicode },
                .reference_extraction = .{ .allocator = allocator, .normalizer = unicode },
                .reference_reconciliation = .{ .allocator = allocator, .normalizer = unicode },
                .source_omission_extraction = .{ .allocator = allocator, .text = .{ .normalizer = unicode, .folder = case_folder } },
                .source_omission_reconciliation = .{ .allocator = allocator, .text = unicode },
                .specification_unit = .{ .allocator = allocator, .normalizer = unicode },
                .specification_support = .{ .allocator = allocator, .normalizer = unicode },
            },
        };
        self.model_requests.init(allocator);
        self.entries = core.entries ++ self.model_requests.entries ++ registered(&self.ops);
        self.registry = .{ .operations = &self.entries, .policies = &profiles, .data_schemas = &schemas, .gates = &.{} };
    }

    pub fn bindPrinciples(self: *Assembly, root: *const roots.ConfiguredBaseRootCapability, reader: @import("../ports/principle_source.zig").Reader) void {
        self.ops.capture_principle_registry.action.source = reader;
        self.ops.capture_principle_registry.action.source.?.capability = root;
    }
    pub fn bindConfiguration(self: *Assembly, config: *const @import("../domain/config.zig").SDDToolKitConfig) void {
        self.ops.source_preservation_policy.policy = &config.validation;
    }
    pub fn bindWorkflows(self: *Assembly, registry: *const @import("../domain/workflow_registry.zig").ValidatedWorkflowDefinitionRegistry) void {
        const contracts = registry.contractSource();
        self.ops.prepare_inputs.action.contracts = contracts;
        self.ops.build_specification_state.action.contracts = contracts;
        self.ops.build_incomplete_specification.action.contracts = contracts;
        self.ops.prepare_incomplete_specification_output.action.contracts = contracts;
        self.ops.prepare_specification_output.action.contracts = contracts;
    }
    pub fn bindRoots(self: *Assembly, registry: *const roots.BootstrapRootRegistry) void {
        self.ops.prepare_toolchain.action.project_source.capability = registry.projectPrinciples();
        self.ops.prepare_toolchain.action.preset_source.capability = registry.toolchainPresetRegistry();
        self.ops.prepare_toolchain.action.preset_capture.capability = registry.toolchainPresetRegistry();
        self.ops.prepare_inputs.action.reference_inspector.capability = registry.referenceSources();
        self.ops.prepare_inputs.action.feature_roots = registry.featureDirectoryRoots();
        self.ops.prepare_inputs.action.feature_inspector.capability = registry.featureDirectoryRead();
        self.ops.prepare_inputs.action.artifact_roots = registry.featureArtifactRoots();
        self.ops.prepare_inputs.action.input_source.capability = registry.featureInputRead();
        if (self.ops.prepare_inputs.action.state_source) |*reader| reader.capability = registry.featureInputRead();
        if (self.ops.publish_output.action.writer) |*writer| writer.capability = registry.featureOutputWrite();
        self.ops.prepare_reference_evidence.action.enumerator.capability = registry.referenceContentRead();
        self.ops.prepare_reference_evidence.action.capturer.capability = registry.referenceContentRead();
    }
};

pub const schemas = principles.schemas ++ packet_guidance.schemas ++ values.schemas ++ invocation_values.schemas ++ reference_values.schemas ++ feature.schemas ++ logging.schemas ++ clarification.schemas ++ evidence.schemas ++ extraction.schemas ++ path_tokens.schemas ++ passive_literals.schemas ++ structured_tokens.schemas ++ reconciliation_repair.schemas ++ text_repair.schemas ++ extraction_repair.schemas ++ reconciliation.schemas ++ authority.schemas ++ specification_support.schemas ++ support_repair.schemas ++ source_omission.schemas ++ reference_model.schemas ++ model_request.schemas ++ specification.schemas ++ scenario_generation.schemas ++ scenario_link.schemas ++ specification_repair.schemas ++ specification_rendering.schemas ++ clarification_refresh.schemas ++ output.schemas ++ publication.schemas ++ incomplete.schemas;
const profiles = core.profiles ++ [_]@import("../domain/workflow_operation.zig").PolicyProfile{ .{
    .id = "core.specification-output@1",
    .allowed_capabilities = &.{ capabilities.principle_read, capabilities.reference_read, capabilities.feature_read, capabilities.feature_input_read, capabilities.reference_content_read, capabilities.reference_decode, capabilities.reference_identity, capabilities.toolchain_read, capabilities.toolchain_parser, capabilities.model_provider, capabilities.provider_authorization, capabilities.feature_output_write, capabilities.feature_logging },
    .allowed_terminal_outcomes = &.{ .ok, .invalid, .needs_user, .blocked, .failed, .cancelled },
}, .{
    .id = "core.toolchain@1",
    .allowed_capabilities = &.{ capabilities.toolchain_read, capabilities.toolchain_parser },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
}, .{
    .id = "core.reference-read@1",
    .allowed_capabilities = &.{capabilities.reference_read},
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
}, .{
    .id = "core.directory-read@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
}, .{
    .id = "core.feature-input-read@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read, capabilities.feature_input_read },
    .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
}, .{
    .id = "core.reference-ingestion@1",
    .allowed_capabilities = &.{ capabilities.reference_read, capabilities.feature_read, capabilities.feature_input_read, capabilities.reference_content_read, capabilities.reference_decode, capabilities.reference_identity, capabilities.toolchain_read, capabilities.toolchain_parser },
    .allowed_terminal_outcomes = &.{ .ok, .invalid, .blocked, .failed, .cancelled },
} };

/// How an operation type states its registered contract. An `Action` states it through the action's own
/// contract (`entry`); a type with `contract` states it itself, as closed variants (`variantEntry`, which admits only a
/// shell) or in full. A type with neither has no contract to register.
const Shape = enum { action, shell, direct };

pub fn shapeOf(comptime T: type) ?Shape {
    if (@hasDecl(T, "Action")) return .action;
    if (@hasDecl(T, "contract")) return if (T.contract.hasVariants()) .shell else .direct;
    return null;
}

/// The entry of one `Operations` field, by the shape its type declares.
fn register(comptime T: type, context: *T) operations.Entry {
    return switch (comptime shapeOf(T) orelse @compileError(@typeName(T) ++ " declares neither an Action nor a contract, so it registers no operation")) {
        .action => entry(T, context),
        .shell => variantEntry(T, context),
        .direct => .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) },
    };
}

/// One entry per `Operations` field, in field order, each bound to its own field.
fn registered(ops: *Operations) [std.meta.fields(Operations).len]operations.Entry {
    var rows: [std.meta.fields(Operations).len]operations.Entry = undefined;
    inline for (std.meta.fields(Operations), 0..) |field, index| rows[index] = register(field.type, &@field(ops, field.name));
    return rows;
}

/// An operation whose one registered contract is made of closed variants (ADR 0030 "Contract
/// variants"). The type declares that contract, a shell holding only its id, selector and variants,
/// and its one binding; the registry admits each variant independently and a step's selector picks
/// one at compile time. The four generic repair operations register this way (ADR 0033).
pub fn variantEntry(comptime T: type, context: *T) operations.Entry {
    comptime if (!T.contract.isShell()) @compileError("a contract with variants states every other field in its variants");
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}

pub fn entry(comptime T: type, context: *T) operations.Entry {
    const contract = T.Action.contract;
    return .{
        .contract = .{
            .id = contract.id,
            .kind = if (@hasDecl(T, "kind")) T.kind else .step,
            .parameters = if (@hasDecl(T, "parameters")) &T.parameters else &.{},
            .requires = contract.requires,
            .optional = contract.optional,
            .produces = contract.produces,
            .replaces = contract.replaces,
            .invalidates = contract.invalidates,
            .side_effect = contract.side_effect,
            .outcomes = if (@hasDecl(T, "outcomes")) &T.outcomes else &.{ .ok, .failed },
            .gates = if (@hasDecl(T, "gates")) &T.gates else &.{},
            .iteration = if (@hasDecl(T, "iteration")) T.iteration else null,
            .repair_role = if (@hasDecl(T, "repair_role")) T.repair_role else T.Action.contract.repair_role,
            .outcome_association = if (@hasDecl(T, "outcome_association")) T.outcome_association else if (@hasField(@TypeOf(contract), "outcome_association")) contract.outcome_association else .independent,
        },
        .binding = binding.bind(T, context, T.invoke),
    };
}
