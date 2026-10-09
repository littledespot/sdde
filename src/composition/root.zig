const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const config = @import("../domain/config.zig");
const engine_config_source = @import("../adapters/filesystem/engine_config_source.zig");
const bootstrap_root_inspector = @import("../adapters/filesystem/bootstrap_root_inspector.zig");
const workflow_authority_source = @import("../adapters/filesystem/workflow_authority_source.zig");
const workflow_definitions = @import("../adapters/parsers/workflow_definitions.zig");
const toolchain_authority_source = @import("../adapters/filesystem/toolchain_authority_source.zig");
const toolchain_documents = @import("../adapters/parsers/toolchain_documents.zig");
const workspace_path_policy = @import("../adapters/filesystem/workspace_path_policy.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const canonicalize_log_level = @import("../actions/log/canonicalize_log_level.zig");
const validate_logging_policy = @import("../actions/log/validate_logging_policy.zig");
const validate_path_policy = @import("../actions/bootstrap/validate_configured_root_path_policy.zig");
const validate_provider_path_policy = @import("../actions/bootstrap/validate_llm_provider_config_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const resolve_provider_path = @import("../actions/bootstrap/resolve_llm_provider_config_path.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const build_workflow_layout = @import("../actions/workflow/build_workflow_authority_layout.zig");
const enumerate_workflow_resources = @import("../actions/workflow/enumerate_workflow_authority_resources.zig");
const normalize_workflow_entries = @import("../actions/workflow/normalize_workflow_authority_entries.zig");
const build_workflow_accounts = @import("../actions/workflow/build_workflow_authority_entry_accounts.zig");
const build_workflow_inventory = @import("../actions/workflow/build_workflow_authority_inventory.zig");
const validate_workflow_inventory = @import("../actions/workflow/validate_workflow_authority_inventory.zig");
const capture_workflows = @import("../actions/workflow/capture_workflow_definitions.zig");
const parse_workflows = @import("../actions/workflow/parse_workflow_definitions.zig");
const validate_workflow_schema = @import("../actions/workflow/validate_workflow_definition_schema.zig");
const resolve_workflow_resources = @import("../actions/workflow/resolve_workflow_resources.zig");
const capture_workflow_resources = @import("../actions/workflow/capture_workflow_resources.zig");
const validate_workflow_operations = @import("../actions/workflow/validate_workflow_operation_registry.zig");
const compile_workflows = @import("../actions/workflow/compile_workflow_graphs.zig");
const validate_workflow_graphs = @import("../actions/workflow/validate_compiled_workflow_graphs.zig");
const build_workflow_registry = @import("../actions/workflow/build_workflow_definition_registry.zig");
const validate_workflow_registry = @import("../actions/workflow/validate_workflow_definition_registry.zig");
const bootstrap_orchestrator = @import("../application/bootstrap_orchestrator.zig");
const bootstrap_runner = @import("../application/bootstrap_runner.zig");
const bootstrap_execution = @import("../application/bootstrap_execution.zig");
const bootstrap_config_runner = @import("../application/bootstrap_config_runner.zig");
const bootstrap_root_runner = @import("../application/bootstrap_root_runner.zig");
const bootstrap_workflow_runner = @import("../application/bootstrap_workflow_runner.zig");
const run_outcome = @import("../domain/run_outcome.zig");
const workflow_engine = @import("../application/workflow_engine_orchestrator.zig");
const model_provider_bootstrap = @import("model_provider_bootstrap.zig");
const engine_invocation = @import("engine_invocation.zig");
const workflow_operation_registry = @import("../ports/workflow_operation_registry.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8, environment: *const std.process.Environ.Map) !run_outcome.Report {
    return reportInvocation(io, allocator, .cwd(), arguments, .{}, environment);
}

/// Owns production adapters, their bindings and bootstrap lifetimes. Initialize
/// in place; an invocation borrows this owner and must be deinitialized first.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    control: pipeline.NodeRuntime,
    principle_source: @import("../adapters/filesystem/principle_source.zig").Adapter,
    toolchain_source: toolchain_authority_source.Adapter,
    toolchain_parser: toolchain_documents.Adapter,
    reference: @import("../adapters/filesystem/reference_directory_inspector.zig").Adapter,
    feature: @import("../adapters/filesystem/feature_directory_inspector.zig").Adapter,
    inputs: @import("../adapters/filesystem/feature_input_source.zig").Adapter,
    outputs: @import("../adapters/filesystem/workflow_output.zig").Adapter,
    corpus: @import("../adapters/filesystem/reference_corpus_source.zig").Adapter,
    markdown: @import("../adapters/parsers/markdown_reference.zig").Adapter,
    identities: @import("../adapters/system/reference_state_identity.zig").Adapter,
    native: @import("native_workflow_operations.zig").Assembly,
    boot: bootstrap_orchestrator.Outcome,
    providers: model_provider_bootstrap.Assembly,
    clock: @import("../adapters/system/provider_operation_clock.zig").Adapter,
    provider_runtime: @import("model_provider_runtime.zig").Assembly,

    logging: ?@import("feature_logging_runtime.zig").Assembly = null,
    invocation_created: bool = false,

    pub const Credentials = union(enum) {
        environment: *const std.process.Environ.Map,
        snapshot: ?@import("../adapters/provider/bedrock_api_key.zig").Snapshot,
    };

    pub fn init(self: *Runtime, io: std.Io, allocator: std.mem.Allocator, project: std.Io.Dir, control: pipeline.NodeRuntime) void {
        self.* = .{
            .allocator = allocator,
            .control = control,
            .principle_source = .{ .io = io, .project_root = project },
            .toolchain_source = toolchain_authority_source.Adapter.init(io, project),
            .toolchain_parser = .{},
            .reference = .{ .io = io, .project_root = project },
            .feature = .{ .io = io, .project_root = project },
            .inputs = .{ .io = io, .project_root = project },
            .outputs = .{ .io = io, .project_root = project },
            .corpus = .{ .io = io, .project_root = project },
            .markdown = .{ .io = io },
            .identities = .{ .io = io },
            .native = undefined,
            .boot = undefined,
            .providers = model_provider_bootstrap.Assembly.init(io, allocator, project, .{}, &@import("provider_model_contracts.zig").registry),
            .clock = .{ .io = io },
            .provider_runtime = undefined,
        };
        self.native.init(allocator, self.toolchain_source.projectCapturer(), self.toolchain_source.presetEnumerator(), self.toolchain_source.presetCapturer(), self.toolchain_parser.parser(), policy_registry, .{ .normalize_fn = @import("unicode_normalization").nfc }, self.reference.inspector(), self.feature.inspector(), self.inputs.capturer(), @import("../adapters/parsers/clarification_inputs.zig").stateParser(), @import("../adapters/parsers/clarification_inputs.zig").formParser(), self.corpus.enumerator(), self.corpus.capturer(), self.markdown.decoderPort(), .{ .fold_fn = @import("unicode_normalization").caseFold }, self.identities.source(), .{ .boundary_fn = @import("unicode_normalization").lexicalBoundary });
        self.native.publish_output.action.writer = self.outputs.port();
        self.native.capture_workflow_state.action.source = self.inputs.workflowStateCapturer();
        self.boot = runInProjectWithRegistry(io, allocator, project, control, &self.native.registry);
        if (self.boot == .ready) {
            self.logging = .{ .allocator = allocator, .io = io, .project = project, .roots = self.boot.ready.roots.registry(), .logs = &self.boot.ready.logs, .inputs = &self.inputs, .outputs = &self.outputs };
            self.native.activate_feature_logging.activator = self.logging.?.activator();
            self.native.bindRoots(self.boot.ready.roots.registry());
            self.native.bindWorkflows(self.boot.ready.workflows.registry());
            self.native.bindConfiguration(self.boot.ready.config.config());
            self.native.bindPrinciples(self.boot.ready.roots.registry().projectPrinciples(), self.boot.ready.config.config(), self.principle_source.reader(), self.principle_source.enumerator(), self.principle_source.capturer());
        }
        self.provider_runtime = .{
            .environment = null,
            .operations = &self.native.model_requests,
            .authorization = .{ .allocator = allocator },
            .transport = .{ .io = io, .clock = self.clock.clock(), .runtime = control },
        };
    }

    pub fn deinit(self: *Runtime) void {
        if (self.logging) |*logging| logging.deinit();
        self.provider_runtime.deinit();
        self.boot.deinit();
        self.* = undefined;
    }

    /// Construct the single invocation after successful bootstrap. Takes ownership
    /// of a supplied snapshot; environment capture stays in provider preparation.
    pub fn invocation(self: *Runtime, arguments: []const []const u8, credentials: Credentials) engine_invocation.Assembly {
        std.debug.assert(self.boot == .ready and !self.invocation_created);
        self.invocation_created = true;
        switch (credentials) {
            .environment => |environment| self.provider_runtime.environment = environment,
            .snapshot => |snapshot| self.provider_runtime.authorization.material = if (snapshot) |value| .{ .ready = value } else .unavailable,
        }
        var result = engine_invocation.Assembly.init(self.allocator, &self.boot.ready, arguments, &self.native.registry, self.providers.bind(), self.control);
        result.provider_clock = self.clock.clock();
        result.provider_runtime = &self.provider_runtime;
        result.finalizer = self.logging.?.finalizer();
        return result;
    }
};

/// Run the production invocation against the supplied project and retain its report.
pub fn reportInvocation(io: std.Io, allocator: std.mem.Allocator, project_root: std.Io.Dir, arguments: []const []const u8, runtime: pipeline.NodeRuntime, environment: ?*const std.process.Environ.Map) !run_outcome.Report {
    var assembly: Runtime = undefined;
    assembly.init(io, allocator, project_root, runtime);
    defer assembly.deinit();
    var report: run_outcome.Report = .{ .outcome = .invocation_invalid, .arena = .init(allocator) };
    errdefer report.deinit();
    report.outcome = switch (assembly.boot) {
        .failed => |failure| .{ .bootstrap_failed = failure },
        .cancelled => .{ .execution = .cancelled },
        .ready => execute: {
            var invocation = assembly.invocation(arguments, if (environment) |map| .{ .environment = map } else .{ .snapshot = null });
            defer invocation.deinit();
            const outcome = workflow_engine.run(invocation.bindings());
            if (outcome.executionStatus() == .needs_user) if (invocation.pipeline_runner) |*runner| {
                report.clarifications = try @import("../application/workflow_clarification_report.zig").capture(report.arena.allocator(), &.{ .slots = runner.envelope.slots });
            };
            if (invocation.pipeline_runner) |*runner| {
                if (try @import("../application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })) |diagnostic|
                    report.candidate_error = try diagnostic.copy(report.arena.allocator());
            }
            break :execute outcome;
        },
    };
    return report;
}

/// Assemble the fixed startup graph with the supplied registered operation contracts.
pub fn runInProjectWithRegistry(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    runtime: pipeline.NodeRuntime,
    operation_registry: *const workflow_operation_registry.Registry,
) bootstrap_orchestrator.Outcome {
    var source_adapter = engine_config_source.Adapter.init(io, project_root);
    var root_adapter = bootstrap_root_inspector.Adapter.init(io, project_root);
    var workflow_source_adapter = workflow_authority_source.Adapter.init(io, project_root);
    var workflow_parser_adapter: workflow_definitions.Adapter = .{};
    var result_schema_adapter: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const policy_resolver = workspace_path_policy.Resolver.init(io, project_root);
    const active_path_policy = policy_resolver.resolve(allocator) catch {
        return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
    };
    var execution_state: bootstrap_execution.State = .{ .runtime = runtime };
    var config_pipeline = bootstrap_config_runner.Runner.init(
        allocator,
        &execution_state,
        locate.Action{ .locator = source_adapter.locator() },
        read.Action{},
        decode.Action{},
        canonicalize_log_level.Action{},
        validate_logging_policy.Action{},
    );
    defer config_pipeline.deinit();
    var root_pipeline = bootstrap_root_runner.Runner.init(
        allocator,
        &execution_state,
        &config_pipeline,
        validate_path_policy.Action{ .policy = active_path_policy },
        validate_provider_path_policy.Action{ .policy = active_path_policy },
        resolve_root.Action{ .policy = active_path_policy },
        resolve_provider_path.Action{ .policy = active_path_policy },
        validate_root.Action{ .inspector = root_adapter.inspector() },
        build_registry_id.Action{},
        build_registry.Action{},
        validate_registry.Action{},
    );
    defer root_pipeline.deinit();
    var workflow_pipeline = bootstrap_workflow_runner.Runner.init(
        allocator,
        &execution_state,
        &root_pipeline,
        build_workflow_layout.Action{},
        enumerate_workflow_resources.Action{ .source = workflow_source_adapter.enumerator() },
        normalize_workflow_entries.Action{},
        build_workflow_accounts.Action{},
        build_workflow_inventory.Action{},
        validate_workflow_inventory.Action{},
        capture_workflows.Action{ .source = workflow_source_adapter.capturer() },
        parse_workflows.Action{ .parser = workflow_parser_adapter.parser() },
        validate_workflow_schema.Action{},
        resolve_workflow_resources.Action{},
        capture_workflow_resources.Action{ .source = workflow_source_adapter.capturer() },
        validate_workflow_operations.Action{},
        compile_workflows.Action{ .registry = operation_registry, .result_schema_compiler = result_schema_adapter.compiler() },
        validate_workflow_graphs.Action{},
        build_workflow_registry.Action{},
        validate_workflow_registry.Action{},
    );
    defer workflow_pipeline.deinit();

    var runner: bootstrap_runner.Runner = .{
        .config = &config_pipeline,
        .roots = &root_pipeline,
        .workflows = &workflow_pipeline,
    };

    return bootstrap_orchestrator.run(runner.bindings());
}

const policy_registry = @import("toolchain_policy_registry.zig").registry;
