//! The contract-variant mechanism (ADR 0030 "Contract variants", acceptance list): one registered
//! contract made of closed variants, selected per step at compile time by one closed enumeration
//! parameter. The test contract `variant.shape` has variants that differ in data effects, outcomes,
//! retry authority (required and forbidden, with different maximums and scopes) and repair role, and
//! passes through the same admission, compiler, graph-validation, publication and runner paths that
//! ADR 0033's repair operations will use. No operation-specific branch exists in the mechanism.
const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const operation = @import("domain/workflow_operation.zig");
const gate = @import("domain/workflow_gate.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const inventory = @import("domain/workflow_inventory.zig");
const definition_schema = @import("domain/workflow_definition_schema.zig");
const resource_binding = @import("domain/workflow_resource_binding.zig");
const graph_compilation = @import("domain/workflow_graph_compilation.zig");
const graph_validation = @import("domain/workflow_graph_validation.zig");
const result_schema_parser = @import("adapters/parsers/model_result_schemas.zig");
const parser_adapter = @import("adapters/parsers/workflow_definitions.zig");
const operation_registry = @import("ports/workflow_operation_registry.zig");
const bindings = @import("application/workflow_operation_binding.zig");
const values = @import("application/pipeline_values.zig");
const startup = @import("application/startup_routine.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");

const Registry = operation_registry.Registry;
const Entry = operation_registry.Entry;

const raw_schema = values.schema(.raw_engine_config, u32, 1, 64);
const engine_schema = values.schema(.engine_config, u32, 1, 64);
const evidence_schema = values.schema(.workflow_operation_registry_evidence, gate.Decision, 1, 32);
const schemas = [_]data.Schema{ raw_schema, engine_schema, evidence_schema };
const policies = [_]operation.PolicyProfile{.{ .id = "variant.policy@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = &.{ .ok, .failed, .invalid } }};

fn unused(_: ?*void, _: operation_registry.Input) operation_registry.Error!execution.Candidate {
    return error.InvocationFailureUnrecorded;
}

/// The test contract's variants. Each one is a complete contract.
const Shape = enum { plain, retrying, validating, merging };

fn variantFor(a: std.mem.Allocator, shape: Shape, values_in_use: []const []const u8) !operation.Variant {
    const mode: operation.ParameterDescriptor = .{ .id = "mode", .kind = .enumeration, .required = true, .workflow_definition_safe = true, .allowed_values = values_in_use };
    const limit = struct {
        fn descriptor(maximum: i64) operation.ParameterDescriptor {
            return .{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = maximum };
        }
    };
    return switch (shape) {
        // No retry authority: a `retry-limit` parameter is forbidden.
        .plain => .{
            .value = "plain",
            .parameters = try a.dupe(operation.ParameterDescriptor, &.{mode}),
            .requires = &.{.raw_engine_config},
            .optional = &.{},
            .produces = &.{.engine_config},
            .replaces = &.{},
            .invalidates = &.{},
            .outcomes = &.{.ok},
            .side_effect = .none,
            .runner_accounting = .none,
            .repair_role = .none,
            .outcome_association = .independent,
            .gates = &.{},
            .retry_limit = null,
            .iteration = null,
        },
        // Operation-scope retry authority, required, with its own maximum.
        .retrying => .{
            .value = "retrying",
            .parameters = try a.dupe(operation.ParameterDescriptor, &.{ mode, limit.descriptor(3) }),
            .requires = &.{.raw_engine_config},
            .optional = &.{},
            .produces = &.{.engine_config},
            .replaces = &.{},
            .invalidates = &.{},
            .outcomes = &.{ .ok, .failed },
            .side_effect = .none,
            .runner_accounting = .none,
            .repair_role = .none,
            .outcome_association = .independent,
            .gates = &.{},
            .retry_limit = .{ .maximum = 3, .scope = .operation },
            .iteration = null,
        },
        // A repair role without retry authority.
        .validating => .{
            .value = "validating",
            .parameters = try a.dupe(operation.ParameterDescriptor, &.{mode}),
            .requires = &.{ .raw_engine_config, .engine_config },
            .optional = &.{},
            .produces = &.{},
            .replaces = &.{},
            .invalidates = &.{},
            .outcomes = &.{ .ok, .invalid },
            .side_effect = .none,
            .runner_accounting = .none,
            .repair_role = .validate,
            .outcome_association = .independent,
            .gates = &.{},
            .retry_limit = null,
            .iteration = null,
        },
        // Another repair role, with repair-scope retry authority and a different maximum.
        .merging => .{
            .value = "merging",
            .parameters = try a.dupe(operation.ParameterDescriptor, &.{ mode, limit.descriptor(5) }),
            .requires = &.{ .raw_engine_config, .engine_config },
            .optional = &.{},
            .produces = &.{},
            .replaces = &.{.engine_config},
            .invalidates = &.{},
            .outcomes = &.{ .ok, .invalid, .failed },
            .side_effect = .none,
            .runner_accounting = .none,
            .repair_role = .merge,
            .outcome_association = .independent,
            .gates = &.{},
            .retry_limit = .{ .maximum = 5, .scope = .repair },
            .iteration = null,
        },
    };
}

/// The variants of `shapes`, each stating the values the selector allows (exactly these shapes).
fn variantsOf(a: std.mem.Allocator, shapes: []const Shape) ![]operation.Variant {
    const names = try a.alloc([]const u8, shapes.len);
    for (shapes, names) |shape, *name| name.* = @tagName(shape);
    const result = try a.alloc(operation.Variant, shapes.len);
    for (shapes, result) |shape, *variant| variant.* = try variantFor(a, shape, names);
    return result;
}

const all_shapes = [_]Shape{ .plain, .retrying, .validating, .merging };

fn shell(variants: []const operation.Variant) operation.Contract {
    return .{ .id = "variant.shape", .kind = .step, .outcomes = &.{}, .side_effect = .none, .selector = "mode", .variants = variants };
}

const input_entry: Entry = .{
    .contract = .{ .id = "variant.input", .kind = .invocation, .produces = &.{.raw_engine_config}, .outcomes = &.{.ok}, .side_effect = .none },
    .binding = bindings.bind(void, null, unused),
};

fn registryOf(a: std.mem.Allocator, contract: operation.Contract) !Registry {
    const entries = try a.dupe(Entry, &.{ input_entry, .{ .contract = contract, .binding = bindings.bind(void, null, unused) } });
    return .{ .operations = entries, .data_schemas = &schemas, .policies = &policies, .gates = &.{} };
}

fn registryWithVariants(a: std.mem.Allocator, shapes: []const Shape) !Registry {
    return registryOf(a, shell(try variantsOf(a, shapes)));
}

test "a contract made of closed variants is admitted variant by variant" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect((try registryWithVariants(a, &all_shapes)).validate());
    // Every variant stands alone as a registered contract too.
    for (all_shapes) |shape| try std.testing.expect((try registryWithVariants(a, &.{shape})).validate());
    // A variant is a complete contract: its type has no defaulted field, so each one states every field.
    inline for (std.meta.fields(operation.Variant)) |field| try std.testing.expect(field.default_value_ptr == null);
}

test "a variant resolves to its own flat contract and never to a union" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contract = shell(try variantsOf(a, &all_shapes));
    try std.testing.expect(contract.isShell());
    const retrying = contract.resolve("retrying").?;
    try std.testing.expectEqualStrings("variant.shape", retrying.id);
    try std.testing.expectEqualSlices(workflow.OutcomeTag, &.{ .ok, .failed }, retrying.outcomes);
    try std.testing.expectEqual(@as(u32, 3), retrying.retry_limit.?.maximum);
    const merging = contract.resolve("merging").?;
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Scope.repair, merging.retry_limit.?.scope);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.merge, merging.repair_role);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.engine_config}, merging.replaces);
    try std.testing.expect(contract.resolve("plain").?.retry_limit == null);
    // No selector, or a selector no variant has, resolves nothing: no variant is selected by absence.
    try std.testing.expect(contract.resolve(null) == null);
    try std.testing.expect(contract.resolve("nope") == null);
    try std.testing.expect(contract.resolve("") == null);
    // A contract without variants takes no selector value and is its own contract.
    const single: operation.Contract = .{ .id = "single", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none };
    try std.testing.expectEqualStrings("single", single.resolve(null).?.id);
    try std.testing.expect(single.resolve("plain") == null);
    try std.testing.expect(!single.isShell());
}

test "registry admission rejects a variant that fails a per-contract check while its sibling is valid" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try variantsOf(a, &.{ .plain, .retrying });
    try std.testing.expect((try registryOf(a, shell(base))).validate());
    // The sibling `plain` stays valid; each fault below breaks `retrying` alone.
    for (0..6) |fault| {
        const changed = try a.dupe(operation.Variant, base);
        const target = &changed[1];
        switch (fault) {
            // The `retry-limit` parameter without the retry authority it belongs to.
            0 => target.retry_limit = null,
            // A retry authority without its parameter.
            1 => target.parameters = target.parameters[0..1],
            // An operation-scope retry cannot be a merge role's.
            2 => {
                target.repair_role = .merge;
                target.retry_limit = .{ .maximum = 3, .scope = .operation };
            },
            // A repair-scope retry needs a merge role.
            3 => target.retry_limit = .{ .maximum = 3, .scope = .repair },
            // No outcome at all.
            4 => target.outcomes = &.{},
            // A data effect the registry has no schema for.
            5 => target.produces = &.{.model_request_identity_ledger},
            else => unreachable,
        }
        try std.testing.expect(!(try registryOf(a, shell(changed))).validate());
    }
    // The valid sibling alone is admitted: each fault is in the variant, not in the contract.
    try std.testing.expect((try registryWithVariants(a, &.{.plain})).validate());
}

test "registry admission rejects an ambiguous, unselectable or shapeless contract with variants" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try variantsOf(a, &.{ .plain, .retrying });
    for (0..9) |fault| {
        var changed = try a.dupe(operation.Variant, base);
        var contract = shell(changed);
        switch (fault) {
            // Two variants with the same selector value.
            0 => changed[1].value = "plain",
            // A value no variant could be selected by.
            1 => changed[1].value = "",
            // The selector's allowed values are not exactly the variants: `retrying` could not be selected.
            2 => {
                const allowed = try a.dupe([]const u8, &.{"plain"});
                for (changed) |*variant| {
                    const parameters = try a.dupe(operation.ParameterDescriptor, variant.parameters);
                    parameters[0].allowed_values = allowed;
                    variant.parameters = parameters;
                }
            },
            // A variant that does not declare the selector at all.
            3 => changed[0].parameters = &.{},
            // The selector parameter is not a closed enumeration.
            4 => {
                const parameters = try a.dupe(operation.ParameterDescriptor, changed[0].parameters);
                parameters[0].kind = .string;
                changed[0].parameters = parameters;
            },
            // The selector is optional: a step could leave it out.
            5 => {
                const parameters = try a.dupe(operation.ParameterDescriptor, changed[0].parameters);
                parameters[0].required = false;
                changed[0].parameters = parameters;
            },
            // Variants without a selector.
            6 => contract.selector = null,
            // The contract states a shape of its own beside its variants.
            7 => contract.requires = &.{.raw_engine_config},
            // A contract with a selector and no variant to select.
            8 => {
                contract.variants = &.{};
                contract.outcomes = &.{.ok};
            },
            else => unreachable,
        }
        try std.testing.expect(!(try registryOf(a, contract)).validate());
    }
}

test "variants live inside one entry: the one-id rule is unchanged" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try variantsOf(a, &all_shapes);
    const entries = try a.dupe(Entry, &.{
        input_entry,
        .{ .contract = shell(base), .binding = bindings.bind(void, null, unused) },
        .{ .contract = shell(base), .binding = bindings.bind(void, null, unused) },
    });
    const duplicated: Registry = .{ .operations = entries, .data_schemas = &schemas, .policies = &policies, .gates = &.{} };
    try std.testing.expect(!duplicated.validate());
    try std.testing.expect(duplicated.resolveOperation(workflow.OperationId.parse("variant.shape").?) == null);
    const single = try registryWithVariants(a, &all_shapes);
    const entry = single.resolveOperation(workflow.OperationId.parse("variant.shape").?).?;
    try std.testing.expect(entry.contract.hasVariants());
    // A kernel entry has one fixed contract with stages, never variants.
    var kernel_like = entry.*;
    kernel_like.request_stages = &.{.{ .stage = .prepare_request, .contract = entry.contract.resolve("plain").?, .binding = entry.binding }};
    const mixed: Registry = .{ .operations = &.{ input_entry, kernel_like }, .data_schemas = &schemas, .policies = &policies, .gates = &.{} };
    try std.testing.expect(!mixed.validate());
}

const gate_contract: gate.Contract = .{
    .id = .{ .bytes = "variant.gate@1" },
    .issuer = .{ .bytes = "variant.issuer" },
    .evidence = evidence_schema.key,
    .authority = &.{raw_schema.key},
};

const issuer_entry: Entry = .{
    .contract = .{ .id = "variant.issuer", .kind = .step, .requires = &.{.raw_engine_config}, .produces = &.{.workflow_operation_registry_evidence}, .outcomes = &.{.ok}, .side_effect = .none },
    .binding = bindings.bind(void, null, unused),
};

fn gatedRegistry(a: std.mem.Allocator, variants: []const operation.Variant) !Registry {
    const entries = try a.dupe(Entry, &.{ input_entry, issuer_entry, .{ .contract = shell(variants), .binding = bindings.bind(void, null, unused) } });
    return .{ .operations = entries, .data_schemas = &schemas, .policies = &policies, .gates = &.{gate_contract} };
}

test "registry-wide checks cover every variant of every contract" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try variantsOf(a, &.{ .plain, .retrying });
    try std.testing.expect((try gatedRegistry(a, base)).validate());
    // Gate-evidence exclusivity: no variant, first or later, produces or replaces another
    // operation's gate evidence key.
    for (0..2) |index| for ([_]bool{ false, true }) |replaces| {
        const changed = try a.dupe(operation.Variant, base);
        if (replaces) {
            changed[index].replaces = &.{.workflow_operation_registry_evidence};
        } else {
            changed[index].produces = &.{.workflow_operation_registry_evidence};
        }
        try std.testing.expect(!(try gatedRegistry(a, changed)).validate());
    };
    // Schema registration: a key a variant touches must have a schema, for each of its five key lists.
    for (0..5) |list| {
        const changed = try a.dupe(operation.Variant, base);
        const unknown: []const pipeline.DataKey = &.{.model_request_identity_ledger};
        switch (list) {
            0 => changed[1].requires = unknown,
            1 => changed[1].optional = unknown,
            2 => changed[1].produces = unknown,
            3 => changed[1].replaces = unknown,
            4 => changed[1].invalidates = unknown,
            else => unreachable,
        }
        try std.testing.expect(!(try registryOf(a, shell(changed))).validate());
    }
    // A variant may name a gate only if the registry holds it.
    const gated = try a.dupe(operation.Variant, base);
    gated[1].gates = &.{"variant.gate@1"};
    try std.testing.expect(!(try registryOf(a, shell(gated))).validate());
    try std.testing.expect((try gatedRegistry(a, gated)).validate());
    gated[1].gates = &.{"variant.other@1"};
    try std.testing.expect(!(try gatedRegistry(a, gated)).validate());
    // The gate-issuer check: an issuer is a single-shape operation, so a gate cannot name a contract
    // with variants as its issuer.
    const named: Registry = .{
        .operations = try a.dupe(Entry, &.{ input_entry, .{ .contract = shell(base), .binding = bindings.bind(void, null, unused) } }),
        .data_schemas = &schemas,
        .policies = &policies,
        .gates = &.{.{ .id = .{ .bytes = "variant.gate@1" }, .issuer = .{ .bytes = "variant.shape" }, .evidence = evidence_schema.key, .authority = &.{raw_schema.key} }},
    };
    try std.testing.expect(!named.validate());
}

const workflow_head =
    \\schema: workflow/v1
    \\id: variant-flow
    \\version: 1
    \\shortcode: VARF
    \\invoke: variant.input
    \\policy: variant.policy@1
    \\
;

const plain_workflow = workflow_head ++
    \\start: run
    \\steps:
    \\  run:
    \\    use: variant.shape
    \\    with: {mode: plain}
    \\    on: {ok: end.ok}
;

const retrying_workflow = workflow_head ++
    \\start: run
    \\steps:
    \\  run:
    \\    use: variant.shape
    \\    with: {mode: retrying, retry-limit: 2}
    \\    on: {ok: end.ok, failed: end.failed}
;

const repair_workflow = workflow_head ++
    \\start: first
    \\steps:
    \\  first:
    \\    use: variant.shape
    \\    with: {mode: plain}
    \\    on: {ok: check}
    \\  check:
    \\    use: variant.shape
    \\    with: {mode: validating}
    \\    on: {ok: fix, invalid: end.invalid}
    \\  fix:
    \\    use: variant.shape
    \\    with: {mode: merging, retry-limit: 4}
    \\    on: {ok: end.ok, invalid: end.invalid, failed: end.failed}
;

/// The selector and a limit reach the step through a subgraph's `{param}` references, which the
/// expansion resolves before compilation reads them.
const forwarded_workflow = workflow_head ++
    \\start: once
    \\steps:
    \\  once:
    \\    call: shape-step
    \\    with: {kind: retrying, limit: 3}
    \\    on: {ok: end.ok, failed: end.failed}
    \\subgraphs:
    \\  shape-step:
    \\    start: run
    \\    steps:
    \\      run:
    \\        use: variant.shape
    \\        with: {mode: {param: kind}, retry-limit: {param: limit}}
    \\        on: {ok: end.ok, failed: end.failed}
;

fn emptyInventory() inventory.Inventory {
    return .{ .capability = undefined, .descriptors = &.{}, .accounts = &.{}, .definition_ordinals = &.{}, .resource_ordinals = &.{} };
}

fn compileYaml(a: std.mem.Allocator, registry: *const Registry, yaml: []const u8) ![]const compilation.CompiledWorkflow {
    var parser: parser_adapter.Adapter = .{};
    var result_schema: result_schema_parser.Adapter = .{};
    const raw = try startup.steps.parseWorkflows(parser.parser(), a, &.{.{ .ordinal = 1, .bytes = yaml }});
    const definitions = try definition_schema.validate(a, raw);
    const manifest = try resource_binding.resolve(a, emptyInventory(), definitions);
    return graph_compilation.compile(registry, result_schema.compiler(), a, definitions, emptyInventory(), manifest, &.{});
}

fn stepNamed(graph: compilation.CompiledWorkflow, call_site_suffix: []const u8) compilation.CompiledStep {
    for (graph.authority.steps) |step| {
        const chain = step.source_chain;
        if (chain.len != 0 and std.mem.endsWith(u8, chain[chain.len - 1].id, call_site_suffix)) return step;
    }
    unreachable;
}

test "a step whose selector picks a variant compiles against that variant alone" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const registry = try registryWithVariants(a, &all_shapes);
    const entry = registry.resolveOperation(workflow.OperationId.parse("variant.shape").?).?;

    const plain = (try compileYaml(a, &registry, plain_workflow))[0].authority.steps[0];
    try std.testing.expect(compilation.matchesContract(entry.contract.resolve("plain").?, plain));
    try std.testing.expectEqualStrings("plain", compilation.selectorValue(entry.contract, plain.parameters).?);
    try std.testing.expect(plain.retry_authority == null);
    try std.testing.expectEqualSlices(workflow.OutcomeTag, &.{.ok}, plain.outcomes);

    const retrying = (try compileYaml(a, &registry, retrying_workflow))[0].authority.steps[0];
    try std.testing.expect(compilation.matchesContract(entry.contract.resolve("retrying").?, retrying));
    try std.testing.expectEqualSlices(workflow.OutcomeTag, &.{ .ok, .failed }, retrying.outcomes);
    try std.testing.expectEqual(@as(u32, 2), retrying.retry_authority.?.limit.value);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Scope.operation, retrying.retry_authority.?.scope);
    // The same operation compiled as another variant shares nothing but its id.
    try std.testing.expect(!compilation.matchesContract(entry.contract.resolve("plain").?, retrying));

    // Variants with different repair roles and retry authority, in one workflow.
    const graph = (try compileYaml(a, &registry, repair_workflow))[0];
    const check = stepNamed(graph, "check");
    const fix = stepNamed(graph, "fix");
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.validate, check.repair_role);
    try std.testing.expect(check.retry_authority == null);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.merge, fix.repair_role);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Scope.repair, fix.retry_authority.?.scope);
    try std.testing.expectEqual(@as(u32, 4), fix.retry_authority.?.limit.value);
    try std.testing.expect(compilation.matchesContract(entry.contract.resolve("validating").?, check));
    try std.testing.expect(compilation.matchesContract(entry.contract.resolve("merging").?, fix));
    _ = try graph_validation.validate(a, &.{graph}, &registry);
}

test "a selector forwarded through a subgraph parameter selects the same variant" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const registry = try registryWithVariants(a, &all_shapes);
    const entry = registry.resolveOperation(workflow.OperationId.parse("variant.shape").?).?;
    const graph = (try compileYaml(a, &registry, forwarded_workflow))[0];
    const step = graph.authority.steps[0];
    try std.testing.expectEqualStrings("retrying", compilation.selectorValue(entry.contract, step.parameters).?);
    try std.testing.expectEqual(@as(u32, 3), step.retry_authority.?.limit.value);
    try std.testing.expect(compilation.matchesContract(entry.contract.resolve("retrying").?, step));
    _ = try graph_validation.validate(a, &.{graph}, &registry);
    // The forwarded value is checked as a declared one is: an unknown mode rejects.
    const unknown = try std.mem.replaceOwned(u8, a, forwarded_workflow, "kind: retrying", "kind: nope");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, unknown));
}

test "compilation rejects every step the selected variant does not allow" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const registry = try registryWithVariants(a, &all_shapes);
    const changes = [_][3][]const u8{
        // A selector value with no variant.
        .{ plain_workflow, "{mode: plain}", "{mode: nope}" },
        .{ plain_workflow, "{mode: plain}", "{mode: Plain}" },
        // A missing required selector.
        .{ retrying_workflow, "{mode: retrying, retry-limit: 2}", "{retry-limit: 2}" },
        .{ plain_workflow, "with: {mode: plain}\n    ", "" },
        // A selector of another kind.
        .{ plain_workflow, "{mode: plain}", "{mode: 3}" },
        .{ plain_workflow, "{mode: plain}", "{mode: true}" },
        // The retry-limit where the selected variant forbids it, and where it requires it.
        .{ plain_workflow, "{mode: plain}", "{mode: plain, retry-limit: 1}" },
        .{ retrying_workflow, "{mode: retrying, retry-limit: 2}", "{mode: retrying}" },
        // A retry-limit above the selected variant's own maximum (3 here; 5 for `merging`).
        .{ retrying_workflow, "retry-limit: 2", "retry-limit: 4" },
        .{ retrying_workflow, "retry-limit: 2", "retry-limit: -1" },
        // An outcome the selected variant does not declare, and a declared one left unmapped.
        .{ plain_workflow, "on: {ok: end.ok}", "on: {ok: end.ok, failed: end.failed}" },
        .{ retrying_workflow, "on: {ok: end.ok, failed: end.failed}", "on: {ok: end.ok}" },
        .{ repair_workflow, "on: {ok: fix, invalid: end.invalid}", "on: {ok: fix}" },
        // Another variant's parameter.
        .{ repair_workflow, "{mode: validating}", "{mode: validating, retry-limit: 1}" },
    };
    var parser: parser_adapter.Adapter = .{};
    for (changes) |change| {
        const yaml = try std.mem.replaceOwned(u8, a, change[0], change[1], change[2]);
        try std.testing.expect(!std.mem.eql(u8, change[0], yaml));
        // Every change here is well-formed YAML the definition schema accepts: only the compiler,
        // reading the registered contract's variants, rejects it.
        const raw = try startup.steps.parseWorkflows(parser.parser(), a, &.{.{ .ordinal = 1, .bytes = yaml }});
        _ = try definition_schema.validate(a, raw);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileYaml(a, &registry, yaml));
    }
    // The same limit 4 that `retrying` rejects is within `merging`'s maximum: the bound is the variant's.
    _ = try compileYaml(a, &registry, repair_workflow);
}

test "graph validation and publication recheck each step against its own variant" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const registry = try registryWithVariants(a, &all_shapes);
    const compiled = (try compileYaml(a, &registry, plain_workflow))[0];
    try std.testing.expect(registry.stepsMatchVariants(compiled.authority.steps));
    _ = try graph_validation.validate(a, &.{compiled}, &registry);

    const retrying_effects = (try compileYaml(a, &registry, retrying_workflow))[0].authority.steps[0];
    for (0..6) |fault| {
        const steps = try a.dupe(compilation.CompiledStep, compiled.authority.steps);
        var tampered = compiled;
        tampered.authority.steps = steps;
        switch (fault) {
            // The effects of a variant the step did not select, under its own selector.
            0 => steps[0].outcomes = retrying_effects.outcomes,
            // The retry authority of another variant.
            1 => steps[0].retry_authority = retrying_effects.retry_authority,
            // The repair role of another variant.
            2 => steps[0].repair_role = .validate,
            // A data effect of another variant.
            3 => steps[0].replaces = &.{.engine_config},
            // The selector switched to another variant while the effects stay.
            4 => steps[0].parameters = retrying_effects.parameters,
            // The selector removed.
            5 => steps[0].parameters = &.{},
            else => unreachable,
        }
        try std.testing.expect(!registry.stepsMatchVariants(steps));
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, graph_validation.validate(a, &.{tampered}, &registry));
    }
}

const Script = struct {
    outcome: workflow.OutcomeTag = .ok,
    write: bool = true,
    replace: bool = false,
    shape_calls: usize = 0,
    status: pipeline.RuntimeStatus = .active,

    fn input(_: ?*Script, _: operation_registry.Input) operation_registry.Error!execution.Candidate {
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(raw_schema.key)] = values.create(std.testing.allocator, raw_schema, u32, 7) catch return error.InvocationFailureUnrecorded;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn shape(context: ?*Script, _: operation_registry.Input) operation_registry.Error!execution.Candidate {
        const self = context.?;
        self.shape_calls += 1;
        var delta: pipeline.NodeDelta = .{};
        if (self.write) delta.data_writes[@intFromEnum(engine_schema.key)] = values.create(std.testing.allocator, engine_schema, u32, 9) catch return error.InvocationFailureUnrecorded;
        if (self.replace) delta.data_replacements[@intFromEnum(engine_schema.key)] = values.create(std.testing.allocator, engine_schema, u32, 11) catch return error.InvocationFailureUnrecorded;
        return .{ .outcome = self.outcome, .delta = delta };
    }

    fn runtimeStatus(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Script = @ptrCast(@alignCast(context.?));
        return self.status;
    }

    fn log(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        return .dropped;
    }
};

/// The registry whose `variant.shape` entry binds the script, for runner tests.
fn runnable(a: std.mem.Allocator, script: *Script) !Registry {
    const entries = try a.dupe(Entry, &.{
        .{ .contract = input_entry.contract, .binding = bindings.bind(Script, script, Script.input) },
        .{ .contract = shell(try variantsOf(a, &all_shapes)), .binding = bindings.bind(Script, script, Script.shape) },
    });
    return .{ .operations = entries, .data_schemas = &schemas, .policies = &policies, .gates = &.{} };
}

fn startRunner(registry: *const Registry, graph: *const compilation.CompiledWorkflow, script: *Script) runner_module.Runner {
    return runner_module.Runner.init(
        std.testing.allocator,
        .{ .graph = graph, .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} } },
        registry,
        .{ .context = script, .process_fn = Script.log },
        .{ .context = script, .status_fn = Script.runtimeStatus },
        null,
        .{ .budget = .{ .value = 100 } },
    );
}

test "the runner checks every delta, outcome and retry authority against the compiled variant" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var script: Script = .{};
    const registry = try runnable(a, &script);
    const plain = try compileYaml(a, &registry, plain_workflow);
    const retrying = try compileYaml(a, &registry, retrying_workflow);

    const Case = struct { graph: *const compilation.CompiledWorkflow, outcome: workflow.OutcomeTag, write: bool, replace: bool, expected: execution.Applied };
    const undeclared: execution.Applied = .{ .rejected = .{ .authority = .outcome_undeclared } };
    const rejected: execution.Applied = .{ .rejected = .{ .authority = .candidate_delta } };
    const cases = [_]Case{
        // What the selected variant allows runs, and nothing else.
        .{ .graph = &plain[0], .outcome = .ok, .write = true, .replace = false, .expected = .{ .outcome = .ok } },
        .{ .graph = &retrying[0], .outcome = .ok, .write = true, .replace = false, .expected = .{ .outcome = .ok } },
        .{ .graph = &retrying[0], .outcome = .failed, .write = true, .replace = false, .expected = .{ .outcome = .failed } },
        // An outcome that fits another variant (`retrying` declares `failed`) but not the compiled one.
        .{ .graph = &plain[0], .outcome = .failed, .write = true, .replace = false, .expected = undeclared },
        // An outcome no variant declares for it.
        .{ .graph = &retrying[0], .outcome = .invalid, .write = true, .replace = false, .expected = undeclared },
        // A delta that fits another variant (`merging` replaces `engine_config`) but not the compiled one.
        .{ .graph = &plain[0], .outcome = .ok, .write = false, .replace = true, .expected = rejected },
        .{ .graph = &retrying[0], .outcome = .ok, .write = true, .replace = true, .expected = rejected },
    };
    for (cases) |case| {
        script = .{ .outcome = case.outcome, .write = case.write, .replace = case.replace };
        var runner = startRunner(&registry, case.graph, &script);
        defer runner.deinit();
        try std.testing.expectEqual(execution.Applied{ .outcome = .ok }, runner.bindings().invokeInvocation());
        const applied = runner.bindings().invokeStep(case.graph.authority.steps[0].id);
        try std.testing.expectEqualDeep(case.expected, applied);
        try std.testing.expectEqual(@as(usize, 1), script.shape_calls);
    }
}

test "the runner rejects a compiled step whose effects or authority fit another variant, without invoking it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var script: Script = .{};
    const registry = try runnable(a, &script);
    const plain = (try compileYaml(a, &registry, plain_workflow))[0];
    const retrying = (try compileYaml(a, &registry, retrying_workflow))[0];
    for (0..5) |fault| {
        const source = if (fault == 1) retrying else plain;
        const steps = try a.dupe(compilation.CompiledStep, source.authority.steps);
        var tampered = source;
        tampered.authority.steps = steps;
        switch (fault) {
            // The selector names another variant while the compiled effects stay.
            0 => steps[0].parameters = retrying.authority.steps[0].parameters,
            // A retry authority removed from a step compiled as a variant that requires one.
            1 => steps[0].retry_authority = null,
            // A retry authority granted to a step compiled as a variant that forbids one.
            2 => steps[0].retry_authority = retrying.authority.steps[0].retry_authority,
            // No selector at all.
            3 => steps[0].parameters = &.{},
            // A selector no variant has.
            4 => steps[0].parameters = &.{.{ .id = .{ .bytes = "mode" }, .value = .{ .enumeration = "nope" } }},
            else => unreachable,
        }
        script = .{};
        var runner = startRunner(&registry, &tampered, &script);
        defer runner.deinit();
        try std.testing.expectEqual(execution.Applied{ .outcome = .ok }, runner.bindings().invokeInvocation());
        // A selector no variant has resolves no contract; every other fault leaves a resolved variant that disagrees with the step.
        const reason: execution.AuthorityReason = switch (fault) {
            3, 4 => .step_unresolved,
            else => .step_contract_mismatch,
        };
        try std.testing.expectEqualDeep(execution.Applied{ .rejected = .{ .authority = reason } }, runner.bindings().invokeStep(steps[0].id));
        try std.testing.expectEqual(@as(usize, 0), script.shape_calls);
    }
}
