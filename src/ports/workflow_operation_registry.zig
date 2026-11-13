const std = @import("std");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const operation = @import("../domain/workflow_operation.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const workflow_retry = @import("../domain/workflow_retry.zig");
const data = @import("../domain/pipeline_data.zig");
const gate = @import("../domain/workflow_gate.zig");
const capability_contract = @import("../domain/workflow_capability.zig");
const kernel = @import("../domain/model_request_kernel.zig");

pub const Stage = kernel.Stage;
pub const Error = execution.OperationError;

pub const InvocationInput = struct {
    arguments: []const []const u8,
};

pub const StepInput = struct {
    /// The runner's current immutable compiled metadata, never execution capability.
    authority: ?*const compilation.SemanticAuthority = null,
    data: data.View,
    step: *const compilation.CompiledStep,
    resources: []const compilation.CompiledResource,
    model_binding: ?*const provider_binding.ValidatedProviderModelBinding,
    repair_permit: ?workflow_retry.Permit = null,
    log: pipeline.WorkflowLog,
    /// The runner's capability-free status handle, which a stage action checks between its
    /// internal steps (ADR 0031). A caller that invokes a binding outside the runner has none to
    /// supply, so it stays always active.
    runtime: pipeline.NodeRuntime = .{},
    /// The runner's slot for the internal step a stage action stopped at; absent outside the runner.
    stage_step: ?*pipeline.StageStepSlot = null,
    model_request_lifecycle: ?*const @import("../domain/provider_operation_lifecycle.zig").Ledger = null,
    provider_invocation: ?@import("../domain/provider_invocation_validation.zig").Call = null,
    model_attempt: ?struct {
        accounting: *const @import("../domain/model_attempt_accounting.zig").RunnerModelAttemptAccounting,
        operations: *const @import("../domain/provider_operation_lifecycle.zig").Ledger,
        attempt: @import("../domain/model_attempt_accounting.zig").Attempt,
    } = null,
    provider_operation: ?struct {
        ledger: *const @import("../domain/provider_operation_lifecycle.zig").Ledger,
        authority: @import("../domain/provider_operation_lifecycle.zig").Authority,
        invocation: ?@import("../domain/provider_operation_lifecycle.zig").Invocation = null,
    } = null,
    provider_authorization: ?struct {
        facts: @import("provider_operation_authorization.zig").Facts,
        slot: @import("provider_operation_authorization.zig").AllocatedSlot,
        runtime: pipeline.NodeRuntime,
    } = null,
};

pub const Input = union(enum) {
    invocation: InvocationInput,
    step: StepInput,
};

pub const Binding = struct {
    context: ?*anyopaque = null,
    implementation: *const Implementation,

    pub const Implementation = struct {
        invoke_fn: *const fn (?*anyopaque, Input) Error!execution.Candidate,
        capabilities: []const []const u8,
        context_required: bool,
    };

    pub fn capabilities(self: Binding) []const []const u8 {
        return self.implementation.capabilities;
    }

    pub fn invoke(self: Binding, input: Input) Error!execution.Candidate {
        return self.implementation.invoke_fn(self.context, input);
    }
};

/// One fixed stage of the `request-model` kernel operation (ADR 0030): the stage's own contract
/// and binding. A stage is no registered operation; no workflow selects it.
pub const StageEntry = struct {
    stage: Stage,
    contract: operation.Contract,
    binding: Binding,
};

pub const Entry = struct {
    contract: operation.Contract,
    binding: Binding,
    /// Only the `request-model` kernel entry has stages. Its binding's capabilities are exactly
    /// the union of its stages', and only the runner runs it, through the orchestrator.
    request_stages: []const StageEntry = &.{},

    pub fn invoke(self: Entry, input: Input) Error!execution.Candidate {
        return self.binding.invoke(input);
    }

    pub fn requestStage(self: *const Entry, stage: Stage) ?*const StageEntry {
        for (self.request_stages) |*entry| if (entry.stage == stage) return entry;
        return null;
    }

    /// The one contract a step with these compiled parameters runs against: the registered contract,
    /// or the variant its selector picks (ADR 0030 "Contract variants"). Null when the contract has
    /// variants and the step carries no selector value that picks one.
    pub fn contractFor(self: Entry, parameters: []const compilation.CompiledParameter) ?operation.Contract {
        return compilation.selectedContract(self.contract, parameters);
    }
};

pub const Registry = struct {
    operations: []const Entry,
    data_schemas: []const data.Schema = &.{},
    policies: []const operation.PolicyProfile,
    gates: []const gate.Contract,

    pub fn resolveOperation(self: *const Registry, id: workflow.OperationId) ?*const Entry {
        if (workflow.OperationId.parse(id.bytes) == null) return null;
        var found: ?*const Entry = null;
        for (self.operations) |*entry| {
            if (!std.mem.eql(u8, entry.contract.id, id.bytes)) continue;
            if (found != null) return null;
            found = entry;
        }
        return found;
    }

    pub fn resolvePolicy(self: *const Registry, id: workflow.RegisteredRef) ?*const operation.PolicyProfile {
        var found: ?*const operation.PolicyProfile = null;
        for (self.policies) |*profile| {
            if (!std.mem.eql(u8, profile.id, id.bytes)) continue;
            if (found != null) return null;
            found = profile;
        }
        return found;
    }

    pub fn resolveGate(self: *const Registry, id: workflow.RegisteredRef) ?*const gate.Contract {
        var found: ?*const gate.Contract = null;
        for (self.gates) |*contract| {
            if (!std.mem.eql(u8, contract.id.bytes, id.bytes)) continue;
            if (found != null) return null;
            found = contract;
        }
        return found;
    }

    pub fn validate(self: *const Registry) bool {
        // Rebuild on every call: registry backing slices and bindings can change.
        // Indexing the closed key set avoids rescanning every schema for every
        // operation input/output, without caching any validation authority.
        var schemas: SchemaIndex = @splat(null);
        for (self.data_schemas) |*schema| {
            const slot = &schemas[@intFromEnum(schema.key)];
            if (!schema.valid() or slot.* != null) return false;
            slot.* = schema;
        }
        if (!self.validGates(&schemas)) return false;
        for (self.operations, 0..) |entry, index| {
            if (entry.binding.implementation.context_required and entry.binding.context == null) return false;
            if (workflow.OperationId.parse(entry.contract.id) == null) return false;
            if (entry.request_stages.len != 0) {
                // A kernel entry is one fixed contract with stages; it has no variants.
                if (entry.contract.hasVariants() or entry.contract.selector != null) return false;
                if (!validRequestKernel(entry, &schemas)) return false;
            } else if (entry.contract.hasVariants() or entry.contract.selector != null) {
                if (!self.validVariants(entry, &schemas)) return false;
            } else if (!validContract(entry.contract, entry.binding.capabilities())) return false;
            inline for (.{ entry.contract.requires, entry.contract.optional, entry.contract.produces, entry.contract.replaces, entry.contract.invalidates }) |keys| {
                for (keys) |key| if (schemas[@intFromEnum(key)] == null) return false;
            }
            for (self.operations[0..index]) |prior| {
                if (std.mem.eql(u8, prior.contract.id, entry.contract.id)) return false;
            }
            for (entry.contract.gates) |id| if (self.resolveGate(.{ .bytes = id }) == null) return false;
        }
        for (self.policies, 0..) |profile, index| {
            if (workflow.RegisteredRef.parse(profile.id) == null or
                !uniqueStrings(profile.allowed_capabilities) or
                !uniqueOutcomes(profile.allowed_terminal_outcomes) or
                std.mem.indexOfScalar(workflow.OutcomeTag, profile.allowed_terminal_outcomes, .more) != null) return false;
            for (self.policies[0..index]) |prior| {
                if (std.mem.eql(u8, prior.id, profile.id)) return false;
            }
            for (profile.allowed_capabilities) |capability| if (!capability_contract.known(capability)) return false;
        }
        return true;
    }

    const SchemaIndex = [data.key_count]?*const data.Schema;

    /// A contract with variants (ADR 0030 "Contract variants"): one registered contract made of
    /// closed variants, selected per step at compile time. The contract itself is a shell with no
    /// shape of its own; each variant is admitted independently, with the same checks as any
    /// registered contract, against the entry's one binding.
    fn validVariants(self: *const Registry, entry: Entry, schemas: *const SchemaIndex) bool {
        const shell = entry.contract;
        const selector = shell.selector orelse return false;
        if (!shell.isShell() or shell.kind != .step or workflow.WorkflowParameterId.parse(selector) == null) return false;
        for (shell.variants, 0..) |variant, index| {
            if (variant.value.len == 0 or variant.value.len > 128) return false;
            for (shell.variants[0..index]) |prior| if (std.mem.eql(u8, prior.value, variant.value)) return false;
        }
        for (shell.variants) |variant| {
            const flat = shell.resolve(variant.value) orelse return false;
            // The selector is the one closed enumeration parameter of every variant, and its allowed
            // values are exactly the variants: a value outside them, or one without a variant, has no
            // way to reach compilation.
            const descriptor = findParameter(flat.parameters, selector) orelse return false;
            if (descriptor.kind != .enumeration or !descriptor.required or !descriptor.workflow_definition_safe or
                descriptor.allowed_values.len != shell.variants.len) return false;
            for (shell.variants) |other| if (!containsString(descriptor.allowed_values, other.value)) return false;
            if (!validContract(flat, entry.binding.capabilities())) return false;
            inline for (.{ flat.requires, flat.optional, flat.produces, flat.replaces, flat.invalidates }) |keys| {
                for (keys) |key| if (schemas[@intFromEnum(key)] == null) return false;
            }
            for (flat.gates) |id| if (self.resolveGate(.{ .bytes = id }) == null) return false;
        }
        return true;
    }

    /// Whether every step of `steps` that runs a contract with variants carries the selector value of
    /// one of its variants and exactly that variant's effects, outcomes, role, association and retry
    /// authority. Graph validation and registry publication both recheck compiled steps with it
    /// (ADR 0030 "Contract variants"). A step of an operation this registry does not hold is the
    /// compiler's to reject, as before; a step of a single-shape operation is checked by the runner.
    pub fn stepsMatchVariants(self: *const Registry, steps: []const compilation.CompiledStep) bool {
        for (steps) |step| {
            const entry = self.resolveOperation(step.operation_id) orelse continue;
            if (!entry.contract.hasVariants()) continue;
            const selected = entry.contractFor(step.parameters) orelse return false;
            if (!compilation.matchesContract(selected, step)) return false;
        }
        return true;
    }

    fn validGates(self: *const Registry, schemas: *const SchemaIndex) bool {
        for (self.gates, 0..) |contract, index| {
            if (workflow.RegisteredRef.parse(contract.id.bytes) == null or
                contract.authority.len == 0 or !uniqueKeys(contract.authority) or
                containsKey(contract.authority, contract.evidence)) return false;
            for (self.gates[0..index]) |prior| {
                if (prior.evidence == contract.evidence or std.mem.eql(u8, prior.id.bytes, contract.id.bytes)) return false;
            }
            const issuer = self.resolveOperation(contract.issuer) orelse return false;
            // A gate names its issuer by operation, so an issuer is a single-shape contract: with
            // variants, "the issuer's effects" would be ambiguous.
            if (issuer.contract.hasVariants() or issuer.contract.selector != null) return false;
            if (issuer.contract.kind != .step or issuer.binding.capabilities().len != 0 or issuer.contract.side_effect != .none or
                (!containsKey(issuer.contract.produces, contract.evidence) and !containsKey(issuer.contract.replaces, contract.evidence))) return false;
            for (contract.authority) |key| if (!containsKey(issuer.contract.requires, key)) return false;
            for (contract.authority) |key| {
                const authority_schema = schemas[@intFromEnum(key)] orelse return false;
                if (authority_schema.retention != .current) return false;
            }
            const schema = schemas[@intFromEnum(contract.evidence)] orelse return false;
            if (schema.version != 1 or !std.mem.eql(u8, schema.type_name, @typeName(gate.Decision))) return false;
            for (self.operations) |entry| {
                if (std.mem.eql(u8, entry.contract.id, contract.issuer.bytes)) continue;
                if (containsKey(entry.contract.produces, contract.evidence) or containsKey(entry.contract.replaces, contract.evidence)) return false;
                // Every variant is a contract too: none, first or later, may write another issuer's evidence.
                for (entry.contract.variants) |variant| {
                    if (containsKey(variant.produces, contract.evidence) or containsKey(variant.replaces, contract.evidence)) return false;
                }
                // A kernel entry's stages are contracts too: none may write another issuer's evidence.
                for (entry.request_stages) |stage| {
                    if (containsKey(stage.contract.produces, contract.evidence) or containsKey(stage.contract.replaces, contract.evidence)) return false;
                }
            }
        }
        return true;
    }
};

/// The `request-model` kernel entry (ADR 0030). The operation's contract is the one the domain
/// fixes; its capabilities are the exact union of its stages', never an asserted list; and its
/// parameters are the preparation stage's and the accounting stage's `retry-limit`, so no
/// workflow-visible parameter exists that no stage consumes. Each stage is checked as any
/// registered contract is.
fn validRequestKernel(entry: Entry, schemas: *const [data.key_count]?*const data.Schema) bool {
    if (!kernel.validContract(entry.contract) or entry.binding.implementation.context_required or entry.binding.context != null) return false;
    const stage_values = std.enums.values(Stage);
    if (entry.request_stages.len != stage_values.len) return false;
    var model_provider_stages: usize = 0;
    for (stage_values, entry.request_stages) |expected, stage| {
        if (stage.stage != expected or stage.contract.kind != .step or stage.contract.retry_limit != null and expected != kernel.accounting_stage) return false;
        if ((stage.binding.implementation.context_required and stage.binding.context == null) or
            !validContract(stage.contract, stage.binding.capabilities()) or
            !kernel.sameStageOutcomes(expected, stage.contract.outcomes)) return false;
        inline for (.{ stage.contract.requires, stage.contract.optional, stage.contract.produces, stage.contract.replaces, stage.contract.invalidates }) |keys| {
            for (keys) |key| if (schemas[@intFromEnum(key)] == null) return false;
        }
        for (stage.contract.gates) |_| return false;
        for (entry.request_stages[0..@intFromEnum(expected)]) |prior| {
            if (std.mem.eql(u8, prior.contract.id, stage.contract.id)) return false;
        }
        // ADR 0030: no stage both invokes and interprets the model, and none holds both the
        // `model-provider` and `provider-authorization` capabilities.
        if (containsString(stage.binding.capabilities(), capability_contract.model_provider) and
            containsString(stage.binding.capabilities(), capability_contract.provider_authorization)) return false;
        for (stage.binding.capabilities()) |capability| {
            if (!containsString(entry.binding.capabilities(), capability)) return false;
            if (std.mem.eql(u8, capability, capability_contract.model_provider)) model_provider_stages += 1;
        }
        for (stage.contract.parameters) |descriptor| {
            if (kernel.fixedParameter(expected)) |fixed| if (std.mem.eql(u8, fixed.id, descriptor.id)) continue;
            const declared = findParameter(entry.contract.parameters, descriptor.id) orelse return false;
            if (!sameDescriptor(declared, descriptor)) return false;
        }
    }
    for (entry.binding.capabilities()) |capability| {
        const provided = for (entry.request_stages) |stage| {
            if (containsString(stage.binding.capabilities(), capability)) break true;
        } else false;
        if (!provided) return false;
    }
    const prepare = (entry.requestStage(.prepare_request) orelse return false).contract.parameters;
    const accounting = (entry.requestStage(kernel.accounting_stage) orelse return false).contract.parameters;
    const limit = findParameter(accounting, workflow_retry.parameter_id) orelse return false;
    if (entry.contract.parameters.len != prepare.len + 1 or !uniqueStrings(entry.binding.capabilities()) or model_provider_stages != 1) return false;
    for (prepare, entry.contract.parameters[0..prepare.len]) |expected, declared| if (!sameDescriptor(expected, declared)) return false;
    if (!sameDescriptor(limit, entry.contract.parameters[prepare.len])) return false;
    if (!@import("../domain/workflow_model.zig").validDescriptors(entry.contract.parameters)) return false;
    var model_slots: usize = 0;
    for (entry.contract.parameters, 0..) |descriptor, index| {
        if (workflow.WorkflowParameterId.parse(descriptor.id) == null or !descriptor.workflow_definition_safe or
            descriptor.integer_min > descriptor.integer_max or descriptor.string_max_bytes == 0 or descriptor.string_max_bytes > 128 or
            (descriptor.kind == .resource) != (descriptor.resource_kind != null) or !uniqueStrings(descriptor.allowed_values)) return false;
        for (entry.contract.parameters[0..index]) |prior| if (std.mem.eql(u8, prior.id, descriptor.id)) return false;
        if (descriptor.kind == .model_slot) {
            if (!descriptor.required or descriptor.allowed_values.len != 0 or descriptor.resource_kind != null) return false;
            model_slots += 1;
        }
    }
    if (model_slots != 1) return false;
    return limit.kind == .integer and limit.required and limit.integer_min == 0 and limit.integer_max == std.math.maxInt(u32);
}

fn sameDescriptor(left: operation.ParameterDescriptor, right: operation.ParameterDescriptor) bool {
    if (!std.mem.eql(u8, left.id, right.id) or left.kind != right.kind or left.required != right.required or
        left.workflow_definition_safe != right.workflow_definition_safe or left.integer_min != right.integer_min or
        left.integer_max != right.integer_max or left.string_max_bytes != right.string_max_bytes or
        left.resource_kind != right.resource_kind or left.allowed_values.len != right.allowed_values.len) return false;
    for (left.allowed_values, right.allowed_values) |a, b| if (!std.mem.eql(u8, a, b)) return false;
    return true;
}

fn containsString(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, expected)) return true;
    return false;
}

fn validContract(contract: operation.Contract, capabilities: []const []const u8) bool {
    if (!@import("../domain/workflow_outcome_association.zig").validDescriptor(contract.outcome_association, contract.requires, contract.optional, contract.produces, contract.replaces, contract.repair_role)) return false;
    if (!@import("../domain/workflow_iteration.zig").validContract(contract, capabilities)) return false;
    if (!operation.validRepair(contract.repair_role, if (contract.retry_limit) |limit| limit.scope else null, contract.runner_accounting, contract.side_effect)) return false;
    if (contract.repair_role != .none and (contract.kind != .step or capabilities.len != 0)) return false;
    if (!@import("../domain/workflow_model_invocation.zig").validContract(contract, capabilities)) return false;
    if (!@import("../domain/workflow_model_request_lifecycle.zig").validContract(contract, capabilities)) return false;
    if (!@import("../domain/workflow_provider_authorization.zig").validContract(contract, capabilities)) return false;
    if (!operation.validAccounting(contract.runner_accounting, contract.requires, contract.produces, contract.side_effect, contract.retry_limit != null)) return false;
    if (!@import("../domain/workflow_provider_operation.zig").validContract(contract, capabilities)) return false;
    if (contract.outcomes.len == 0 or !uniqueOutcomes(contract.outcomes) or
        !uniqueStrings(contract.gates) or !uniqueStrings(capabilities) or
        !validDataContract(contract)) return false;
    for (capabilities) |capability| if (!capability_contract.known(capability)) return false;
    if (contract.kind == .invocation and
        (contract.parameters.len != 0 or contract.requires.len != 0 or contract.optional.len != 0 or contract.replaces.len != 0 or
            contract.invalidates.len != 0 or contract.side_effect != .none or contract.gates.len != 0 or
            capabilities.len != 0 or contract.retry_limit != null or contract.runner_accounting != .none or
            contract.outcome_association != .independent or
            contract.outcomes.len != 1 or contract.outcomes[0] != .ok)) return false;
    for (contract.parameters, 0..) |descriptor, index| {
        if (workflow.WorkflowParameterId.parse(descriptor.id) == null or
            !descriptor.workflow_definition_safe or descriptor.integer_min > descriptor.integer_max or
            descriptor.string_max_bytes == 0 or descriptor.string_max_bytes > 128 or
            (descriptor.kind == .resource) != (descriptor.resource_kind != null) or
            !uniqueStrings(descriptor.allowed_values)) return false;
        for (contract.parameters[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, descriptor.id)) return false;
        }
    }
    const model_capable = containsExactlyOnce(capabilities, "model-provider");
    var model_slot_count: usize = 0;
    for (contract.parameters) |descriptor| {
        if (descriptor.kind != .model_slot) continue;
        if (!descriptor.required or descriptor.allowed_values.len != 0 or descriptor.resource_kind != null) return false;
        model_slot_count += 1;
    }
    const requires_model_binding = contract.requiresModelBinding();
    if (model_slot_count > 1) return false;
    const consumes_request = contract.consumesPreparedRequest();
    if (model_capable and !requires_model_binding and !consumes_request) return false;
    if (consumes_request and !@import("../domain/workflow_model.zig").validConsumerDescriptors(contract.parameters)) return false;
    if (requires_model_binding and !@import("../domain/workflow_model.zig").validDescriptors(contract.parameters)) return false;
    if (contract.retry_limit) |limit| {
        if (contract.kind != .step or limit.maximum == 0) return false;
        const descriptor = findParameter(contract.parameters, workflow_retry.parameter_id) orelse return false;
        if (descriptor.kind != .integer or !descriptor.required or descriptor.integer_min != 0 or
            descriptor.integer_max > limit.maximum) return false;
    } else if (findParameter(contract.parameters, workflow_retry.parameter_id) != null) {
        return false;
    }
    return true;
}

fn validDataContract(contract: operation.Contract) bool {
    for ([_]pipeline.DataKey{ .assigned_provider_operation, .invoked_provider_operation, .terminal_provider_operation }) |key| {
        if (containsKey(contract.replaces, key) or
            ((containsKey(contract.requires, key) or containsKey(contract.optional, key)) and
                (!contract.consumesPreparedRequest() or !containsKey(contract.requires, .accounted_model_attempt)))) return false;
    }
    if (containsKey(contract.replaces, .accounted_model_attempt) or
        ((containsKey(contract.requires, .accounted_model_attempt) or containsKey(contract.optional, .accounted_model_attempt)) and !contract.consumesPreparedRequest())) return false;
    if (!uniqueKeys(contract.requires) or !uniqueKeys(contract.optional) or !uniqueKeys(contract.produces) or
        !uniqueKeys(contract.replaces) or !uniqueKeys(contract.invalidates)) return false;
    for (contract.optional) |key| if (containsKey(contract.requires, key)) return false;
    for (contract.produces) |key| {
        if (containsKey(contract.requires, key) or containsKey(contract.replaces, key) or
            containsKey(contract.invalidates, key)) return false;
    }
    for (contract.replaces) |key| if (containsKey(contract.invalidates, key)) return false;
    return true;
}

fn uniqueKeys(values: []const pipeline.DataKey) bool {
    for (values, 0..) |value, index| {
        for (values[0..index]) |prior| if (prior == value) return false;
    }
    return true;
}

fn containsKey(values: []const pipeline.DataKey, expected: pipeline.DataKey) bool {
    for (values) |value| if (value == expected) return true;
    return false;
}

fn findParameter(parameters: []const operation.ParameterDescriptor, id: []const u8) ?operation.ParameterDescriptor {
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.id, id)) return parameter;
    return null;
}

fn uniqueStrings(values: []const []const u8) bool {
    for (values, 0..) |value, index| {
        if (value.len == 0) return false;
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior, value)) return false;
    }
    return true;
}

fn uniqueOutcomes(values: []const workflow.OutcomeTag) bool {
    for (values, 0..) |value, index| {
        for (values[0..index]) |prior| if (prior == value) return false;
    }
    return true;
}

fn containsExactlyOnce(values: []const []const u8, expected: []const u8) bool {
    var count: usize = 0;
    for (values) |value| {
        if (std.mem.eql(u8, value, expected)) count += 1;
    }
    return count == 1;
}
