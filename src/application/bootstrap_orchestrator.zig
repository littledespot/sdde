const std = @import("std");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const bootstrap_services = @import("bootstrap_services.zig");

pub const Outcome = union(enum) {
    ready: bootstrap_services.BootstrapServices,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*services| services.deinit(),
            .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

pub fn run(children: child_bindings.ChildBindings) Outcome {
    if (terminal(children.invokeLocate())) |outcome| return outcome;
    if (terminal(children.invokeRead())) |outcome| return outcome;
    if (terminal(children.invokeDecode())) |outcome| return outcome;
    if (terminal(children.invokeCanonicalizeLogLevel())) |outcome| return outcome;
    if (terminal(children.invokeValidateLoggingPolicy())) |outcome| return outcome;
    if (terminal(children.invokeValidateRootPaths())) |outcome| return outcome;
    if (terminal(children.invokeValidateProviderPath())) |outcome| return outcome;
    if (terminal(children.invokeResolveRoots())) |outcome| return outcome;
    if (terminal(children.invokeResolveProviderPath())) |outcome| return outcome;
    if (terminal(children.invokeValidateRoots())) |outcome| return outcome;
    if (terminal(children.invokeBuildRegistryId())) |outcome| return outcome;
    if (terminal(children.invokeBuildRegistry())) |outcome| return outcome;
    if (terminal(children.invokeValidateRegistry())) |outcome| return outcome;
    if (terminal(children.invokeBuildWorkflowLayout())) |outcome| return outcome;
    if (terminal(children.invokeEnumerateWorkflowResources())) |outcome| return outcome;
    if (terminal(children.invokeNormalizeWorkflowEntries())) |outcome| return outcome;
    if (terminal(children.invokeBuildWorkflowAccounts())) |outcome| return outcome;
    if (terminal(children.invokeBuildWorkflowInventory())) |outcome| return outcome;
    if (terminal(children.invokeValidateWorkflowInventory())) |outcome| return outcome;
    if (terminal(children.invokeCaptureWorkflows())) |outcome| return outcome;
    if (terminal(children.invokeParseWorkflows())) |outcome| return outcome;
    if (terminal(children.invokeValidateWorkflowSchema())) |outcome| return outcome;
    if (terminal(children.invokeResolveWorkflowResources())) |outcome| return outcome;
    if (terminal(children.invokeCaptureWorkflowResources())) |outcome| return outcome;
    if (terminal(children.invokeValidateWorkflowOperations())) |outcome| return outcome;
    if (terminal(children.invokeCompileWorkflows())) |outcome| return outcome;
    if (terminal(children.invokeValidateWorkflowGraphs())) |outcome| return outcome;
    if (terminal(children.invokeBuildWorkflowRegistry())) |outcome| return outcome;
    if (terminal(children.invokeValidateWorkflowRegistry())) |outcome| return outcome;

    return .{ .ready = children.takeServices() };
}

fn terminal(step: child_bindings.StepOutcome) ?Outcome {
    return switch (step) {
        .ok => null,
        .failed => |failure| .{ .failed = failure },
        .cancelled => .cancelled,
    };
}

test "coordinates child bindings in order and preserves a decode failure" {
    var spy: SpyBindings = .{ .fail_at = .decode };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expectEqual(
        bootstrap_error.PublicError.ENGINE_CONFIG_PARSE_ERROR,
        outcome.failed,
    );
    try std.testing.expectEqualSlices(
        Step,
        &.{ .locate, .read, .decode },
        spy.calls[0..spy.call_count],
    );
}

test "stops after a failed root binding" {
    var spy: SpyBindings = .{ .fail_at = .validate_roots };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expectEqual(
        bootstrap_error.PublicError.BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        outcome.failed,
    );
    try std.testing.expectEqualSlices(
        Step,
        &.{
            .locate,
            .read,
            .decode,
            .canonicalize_log_level,
            .validate_logging_policy,
            .validate_root_paths,
            .validate_provider_path,
            .resolve_roots,
            .resolve_provider_path,
            .validate_roots,
        },
        spy.calls[0..spy.call_count],
    );
}

test "stops after a failed locate binding" {
    var spy: SpyBindings = .{ .fail_at = .locate };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expectEqual(
        bootstrap_error.PublicError.ENGINE_CONFIG_READ_ERROR,
        outcome.failed,
    );
    try std.testing.expectEqualSlices(
        Step,
        &.{.locate},
        spy.calls[0..spy.call_count],
    );
}

test "preserves explicit cancellation and stops later children" {
    var spy: SpyBindings = .{ .cancel_at = .resolve_roots };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expect(outcome == .cancelled);
    try std.testing.expectEqualSlices(
        Step,
        &.{
            .locate,
            .read,
            .decode,
            .canonicalize_log_level,
            .validate_logging_policy,
            .validate_root_paths,
            .validate_provider_path,
            .resolve_roots,
        },
        spy.calls[0..spy.call_count],
    );
}

const Step = enum {
    locate,
    read,
    decode,
    canonicalize_log_level,
    validate_logging_policy,
    validate_root_paths,
    validate_provider_path,
    resolve_roots,
    resolve_provider_path,
    validate_roots,
    build_registry_id,
    build_registry,
    validate_registry,
    build_workflow_layout,
    enumerate_workflow_resources,
    normalize_workflow_entries,
    build_workflow_accounts,
    build_workflow_inventory,
    validate_workflow_inventory,
    capture_workflows,
    parse_workflows,
    validate_workflow_schema,
    resolve_workflow_resources,
    capture_workflow_resources,
    validate_workflow_operations,
    compile_workflows,
    validate_workflow_graphs,
    build_workflow_registry,
    validate_workflow_registry,
};

const SpyBindings = struct {
    fail_at: ?Step = null,
    cancel_at: ?Step = null,
    calls: [38]Step = undefined,
    call_count: usize = 0,

    fn bindings(self: *SpyBindings) child_bindings.ChildBindings {
        return .{
            .context = self,
            .vtable = &spy_vtable,
        };
    }

    fn record(self: *SpyBindings, step: Step) child_bindings.StepOutcome {
        self.calls[self.call_count] = step;
        self.call_count += 1;
        if (self.cancel_at == step) return .cancelled;
        if (self.fail_at != step) return .ok;
        return .{ .failed = switch (step) {
            .locate, .read => .ENGINE_CONFIG_READ_ERROR,
            .decode => .ENGINE_CONFIG_PARSE_ERROR,
            .canonicalize_log_level, .validate_logging_policy => .LOGGING_POLICY_INVALID,
            .validate_root_paths,
            .validate_provider_path,
            .resolve_roots,
            .resolve_provider_path,
            .validate_roots,
            => .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
            .build_registry_id, .build_registry, .validate_registry => .BOOTSTRAP_ROOT_REGISTRY_INVALID,
            .build_workflow_layout,
            .enumerate_workflow_resources,
            .normalize_workflow_entries,
            .build_workflow_accounts,
            .build_workflow_inventory,
            .validate_workflow_inventory,
            .resolve_workflow_resources,
            => .WORKFLOW_AUTHORITY_INVENTORY_INVALID,
            .capture_workflows, .capture_workflow_resources => .WORKFLOW_DEFINITION_READ_ERROR,
            .parse_workflows => .WORKFLOW_DEFINITION_PARSE_ERROR,
            .validate_workflow_schema => .WORKFLOW_DEFINITION_SCHEMA_INVALID,
            .validate_workflow_operations, .compile_workflows, .validate_workflow_graphs => .WORKFLOW_GRAPH_COMPILE_INVALID,
            .build_workflow_registry, .validate_workflow_registry => .WORKFLOW_REGISTRY_INVALID,
        } };
    }
};

const spy_vtable: child_bindings.ChildBindings.VTable = .{
    .locate = spyLocate,
    .read = spyRead,
    .decode = spyDecode,
    .canonicalize_log_level = spyCanonicalizeLogLevel,
    .validate_logging_policy = spyValidateLoggingPolicy,
    .validate_root_paths = spyValidateRootPaths,
    .validate_provider_path = spyValidateProviderPath,
    .resolve_roots = spyResolveRoots,
    .resolve_provider_path = spyResolveProviderPath,
    .validate_roots = spyValidateRoots,
    .build_registry_id = spyBuildRegistryId,
    .build_registry = spyBuildRegistry,
    .validate_registry = spyValidateRegistry,
    .build_workflow_layout = spyBuildWorkflowLayout,
    .enumerate_workflow_resources = spyEnumerateWorkflowResources,
    .normalize_workflow_entries = spyNormalizeWorkflowEntries,
    .build_workflow_accounts = spyBuildWorkflowAccounts,
    .build_workflow_inventory = spyBuildWorkflowInventory,
    .validate_workflow_inventory = spyValidateWorkflowInventory,
    .capture_workflows = spyCaptureWorkflows,
    .parse_workflows = spyParseWorkflows,
    .validate_workflow_schema = spyValidateWorkflowSchema,
    .resolve_workflow_resources = spyResolveWorkflowResources,
    .capture_workflow_resources = spyCaptureWorkflowResources,
    .validate_workflow_operations = spyValidateWorkflowOperations,
    .compile_workflows = spyCompileWorkflows,
    .validate_workflow_graphs = spyValidateWorkflowGraphs,
    .build_workflow_registry = spyBuildWorkflowRegistry,
    .validate_workflow_registry = spyValidateWorkflowRegistry,
    .take_services = spyTakeServices,
};

fn spyLocate(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.locate);
}

fn spyRead(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.read);
}

fn spyDecode(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.decode);
}

fn spyCanonicalizeLogLevel(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.canonicalize_log_level);
}

fn spyValidateLoggingPolicy(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.validate_logging_policy);
}

fn spyValidateRootPaths(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.validate_root_paths);
}

fn spyValidateProviderPath(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_provider_path);
}

fn spyResolveRoots(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.resolve_roots);
}

fn spyResolveProviderPath(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.resolve_provider_path);
}

fn spyValidateRoots(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.validate_roots);
}

fn spyBuildRegistryId(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.build_registry_id);
}

fn spyBuildRegistry(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.build_registry);
}

fn spyValidateRegistry(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.validate_registry);
}

fn spyBuildWorkflowLayout(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.build_workflow_layout);
}
fn spyEnumerateWorkflowResources(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.enumerate_workflow_resources);
}
fn spyNormalizeWorkflowEntries(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.normalize_workflow_entries);
}
fn spyBuildWorkflowAccounts(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.build_workflow_accounts);
}
fn spyBuildWorkflowInventory(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.build_workflow_inventory);
}
fn spyValidateWorkflowInventory(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_workflow_inventory);
}
fn spyCaptureWorkflows(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.capture_workflows);
}
fn spyParseWorkflows(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.parse_workflows);
}
fn spyValidateWorkflowSchema(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_workflow_schema);
}
fn spyResolveWorkflowResources(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.resolve_workflow_resources);
}
fn spyCaptureWorkflowResources(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.capture_workflow_resources);
}
fn spyValidateWorkflowOperations(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_workflow_operations);
}
fn spyCompileWorkflows(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.compile_workflows);
}
fn spyValidateWorkflowGraphs(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_workflow_graphs);
}
fn spyBuildWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.build_workflow_registry);
}
fn spyValidateWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
    return castSpy(context).record(.validate_workflow_registry);
}

fn castSpy(context: *anyopaque) *SpyBindings {
    return @ptrCast(@alignCast(context));
}

fn spyTakeServices(_: *anyopaque) bootstrap_services.BootstrapServices {
    unreachable;
}
