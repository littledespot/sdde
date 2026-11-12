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
const startup_routine = @import("../application/startup_routine.zig");
const bootstrap_services = @import("../application/bootstrap_services.zig");
const sddtoolkit_config_service = @import("../application/sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("../application/bootstrap_root_registry_service.zig");
const log_service = @import("../application/log_service.zig");
const workflow_definition_registry_service = @import("../application/workflow_definition_registry_service.zig");
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
    boot: bootstrap_services.Outcome,
    providers: model_provider_bootstrap.Assembly,
    clock: @import("../adapters/system/provider_operation_clock.zig").Adapter,
    provider_runtime: @import("model_provider_runtime.zig").Assembly,

    logging: ?@import("feature_logging_runtime.zig").Assembly = null,
    invocation_created: bool = false,

    pub const Credentials = union(enum) {
        environment: *const std.process.Environ.Map,
        /// Harness-supplied keys; ownership of each snapshot transfers here.
        snapshots: @import("../adapters/provider/provider_api_key.zig").Supplied,
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
        self.native.prepare_inputs.action.state_source = self.inputs.workflowStateCapturer();
        self.boot = runInProjectWithRegistry(io, allocator, project, control, &self.native.registry);
        if (self.boot == .ready) {
            self.logging = .{ .allocator = allocator, .io = io, .project = project, .roots = self.boot.ready.roots.registry(), .logs = &self.boot.ready.logs, .inputs = &self.inputs, .outputs = &self.outputs };
            self.native.activate_feature_logging.activator = self.logging.?.activator();
            self.native.bindRoots(self.boot.ready.roots.registry());
            self.native.bindWorkflows(self.boot.ready.workflows.registry());
            self.native.bindConfiguration(self.boot.ready.config.config());
            self.native.bindPrinciples(self.boot.ready.roots.registry().projectPrinciples(), self.principle_source.reader(), self.principle_source.enumerator(), self.principle_source.capturer());
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
    /// of supplied snapshots; environment capture stays in provider preparation.
    pub fn invocation(self: *Runtime, arguments: []const []const u8, credentials: Credentials) engine_invocation.Assembly {
        std.debug.assert(self.boot == .ready and !self.invocation_created);
        self.invocation_created = true;
        switch (credentials) {
            .environment => |environment| self.provider_runtime.environment = environment,
            .snapshots => |supplied| for (std.enums.values(@import("../adapters/provider/provider_api_key.zig").Family)) |family| {
                if (supplied.get(family)) |value| self.provider_runtime.authorization.materials.set(family, .{ .ready = value });
            },
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
            var invocation = assembly.invocation(arguments, if (environment) |map| .{ .environment = map } else .{ .snapshots = .initFill(null) });
            defer invocation.deinit();
            const outcome = workflow_engine.run(invocation.bindings());
            if (outcome.executionStatus() == .needs_user) if (invocation.pipeline_runner) |*runner| {
                report.clarifications = try @import("../application/workflow_clarification_report.zig").capture(report.arena.allocator(), &.{ .slots = runner.envelope.slots });
            };
            if (invocation.pipeline_runner) |*runner| {
                report.last_operation_rejection = runner.last_operation_rejection;
                if (try @import("../application/candidate_validation_diagnostics.zig").read(&.{ .slots = runner.envelope.slots })) |diagnostic|
                    report.candidate_error = try diagnostic.copy(report.arena.allocator());
            }
            break :execute outcome;
        },
    };
    return report;
}

/// Build the startup routine's ports and run it with the supplied registered operation contracts.
/// The routine publishes validated owners; each service is built here, after its complete validation.
pub fn runInProjectWithRegistry(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_root: std.Io.Dir,
    runtime: pipeline.NodeRuntime,
    operation_registry: *const workflow_operation_registry.Registry,
) bootstrap_services.Outcome {
    var source_adapter = engine_config_source.Adapter.init(io, project_root);
    var root_adapter = bootstrap_root_inspector.Adapter.init(io, project_root);
    var workflow_source_adapter = workflow_authority_source.Adapter.init(io, project_root);
    var workflow_parser_adapter: workflow_definitions.Adapter = .{};
    var result_schema_adapter: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const policy_resolver = workspace_path_policy.Resolver.init(io, project_root);
    const active_path_policy = policy_resolver.resolve(allocator) catch {
        return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
    };
    var diagnostic: startup_routine.Diagnostic = .{};
    const outcome = startup_routine.run(
        .{
            .config_locator = source_adapter.locator(),
            .root_inspector = root_adapter.inspector(),
            .workflow_enumerator = workflow_source_adapter.enumerator(),
            .workflow_capturer = workflow_source_adapter.capturer(),
            .workflow_parser = workflow_parser_adapter.parser(),
            .result_schema_compiler = result_schema_adapter.compiler(),
        },
        allocator,
        runtime,
        &diagnostic,
        .{ .path_policy = active_path_policy, .operations = operation_registry },
    );
    return switch (outcome) {
        .ready => |ready| .{ .ready = .{
            .config = sddtoolkit_config_service.SDDToolKitConfigService.init(ready.config),
            .roots = bootstrap_root_registry_service.BootstrapRootRegistryService.init(ready.roots),
            .logs = log_service.LogService.init(ready.logging_policy),
            .workflows = workflow_definition_registry_service.WorkflowDefinitionRegistryService.init(ready.workflows),
        } },
        .failed => |failure| .{ .failed = failure },
        .cancelled => .cancelled,
    };
}

const policy_registry = @import("toolchain_policy_registry.zig").registry;
