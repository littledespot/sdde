const std = @import("std");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const config = @import("../domain/config.zig");
const contracts = @import("../domain/llm_provider_contracts.zig");
const document = @import("../domain/llm_provider_document.zig");
const llm_provider_config = @import("../domain/llm_provider_config.zig");
const model_controls = @import("../domain/model_controls.zig");
const provider_registry = @import("../domain/llm_provider_registry.zig");
const repository_allowlist = @import("../domain/repository_model_allowlist.zig");
const requirement = @import("../domain/model_provider_requirement.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const decoding = @import("../domain/llm_provider_document_decode.zig");
const registry_building = @import("../domain/llm_provider_registry_build.zig");
const derivation = @import("../domain/provider_requirement_derivation.zig");
const config_port = @import("../ports/llm_provider_config_source.zig");

// ADR 0032: provider bootstrap after workflow selection as one engine routine. It derives the
// requirement from the selected workflow and, only when the workflow needs a provider, captures
// the provider document once, decodes it, builds and validates the registry and the allowlist.
// Public error codes are unchanged: every failure of a step, including allocation failure and
// deadline exhaustion, maps to that step's fixed code, and explicit cancellation stays distinct.

/// The closed set of steps, in execution order. A failure or a stop at a checkpoint records the
/// step it belongs to in the caller's `Diagnostic`.
pub const Step = enum {
    derive_requirement,
    locate_config,
    read_config,
    decode_config,
    build_registry,
    validate_registry,
    validate_allowlist,
};

pub const Diagnostic = struct { step: ?Step = null };

/// The only port: where the provider document is located and read.
pub const Ports = struct { locator: config_port.Locator };

/// Closed values the routine reads; none is a capability beyond the root registry's provider
/// document path capability, which the locate step alone uses.
pub const Inputs = struct {
    selected: *const execution.SelectedWorkflow,
    models: *const config.ModelsConfig,
    temperatures: model_controls.Temperatures,
    capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    registered: *const contracts.Registry,
};

/// The validated owners a run publishes, built only after every step has validated.
pub const Ready = struct {
    provider_registry: *provider_registry.Owner,
    allowlist: *repository_allowlist.Owner,

    pub fn deinit(self: *Ready) void {
        repository_allowlist.deinitOwner(self.allowlist);
        provider_registry.deinitOwner(self.provider_registry);
        self.* = undefined;
    }
};

pub const Outcome = union(enum) {
    not_required,
    ready: Ready,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*value| value.deinit(),
            .not_required, .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

/// The entry function only sequences the steps and passes the port on. It checks the runtime before
/// the first step and after each step, as the runners did, and reports the step each stop belongs to.
pub fn run(
    ports: Ports,
    allocator: std.mem.Allocator,
    runtime: pipeline.NodeRuntime,
    diagnostic: *Diagnostic,
    inputs: Inputs,
) Outcome {
    if (checkpoint(runtime, diagnostic, .derive_requirement)) |stop| return stop;
    const needed = steps.deriveRequirement(inputs.selected);
    if (checkpoint(runtime, diagnostic, .derive_requirement)) |stop| return stop;
    switch (needed) {
        .not_required => return .not_required,
        .required => {},
    }

    var exact = steps.locateConfig(ports.locator, inputs.capability, allocator, runtime) catch |failure| return configFailure(diagnostic, .locate_config, failure);
    defer exact.deinit(allocator);
    if (checkpoint(runtime, diagnostic, .locate_config)) |stop| return stop;
    var raw = steps.readConfig(&exact, allocator, runtime) catch |failure| return configFailure(diagnostic, .read_config, failure);
    defer raw.deinit(allocator);
    if (checkpoint(runtime, diagnostic, .read_config)) |stop| return stop;
    var decoded = steps.decodeConfig(allocator, raw.bytes) catch return failed(diagnostic, .decode_config);
    defer decoded.deinit();
    if (checkpoint(runtime, diagnostic, .decode_config)) |stop| return stop;
    var candidate = steps.buildRegistry(inputs.registered, allocator, decoded.value()) catch return failed(diagnostic, .build_registry);
    defer candidate.deinit();
    if (checkpoint(runtime, diagnostic, .build_registry)) |stop| return stop;
    const registry_owner = steps.validateRegistry(inputs.registered, allocator, candidate) catch return failed(diagnostic, .validate_registry);
    var published = false;
    defer if (!published) provider_registry.deinitOwner(registry_owner);
    if (checkpoint(runtime, diagnostic, .validate_registry)) |stop| return stop;
    const allowlist_owner = steps.validateAllowlist(allocator, inputs.models, inputs.temperatures, provider_registry.registry(registry_owner)) catch return failed(diagnostic, .validate_allowlist);
    if (checkpoint(runtime, diagnostic, .validate_allowlist)) |stop| {
        repository_allowlist.deinitOwner(allowlist_owner);
        return stop;
    }
    published = true;
    return .{ .ready = .{ .provider_registry = registry_owner, .allowlist = allowlist_owner } };
}

/// The public code a step's failure maps to.
fn code(step: Step) bootstrap_error.PublicError {
    return switch (step) {
        .derive_requirement, .build_registry, .validate_registry => .LLM_PROVIDER_REGISTRY_INVALID,
        .locate_config, .read_config => .LLM_PROVIDER_CONFIG_READ_ERROR,
        .decode_config => .LLM_PROVIDER_CONFIG_PARSE_ERROR,
        .validate_allowlist => .LLM_PROVIDER_MODEL_BINDING_INVALID,
    };
}

fn failed(diagnostic: *Diagnostic, step: Step) Outcome {
    diagnostic.step = step;
    return .{ .failed = code(step) };
}

fn configFailure(diagnostic: *Diagnostic, step: Step, failure: config_port.Error) Outcome {
    diagnostic.step = step;
    return switch (failure) {
        error.Cancelled => .cancelled,
        error.DeadlineExhausted, error.LLMProviderConfigReadFailure => .{ .failed = code(step) },
    };
}

/// Stops on cancellation, and on deadline exhaustion with `step`'s code: the step the checkpoint
/// follows, or the first step for the opening checkpoint.
fn checkpoint(runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, step: Step) ?Outcome {
    return switch (runtime.status()) {
        .active => null,
        .cancelled => stopped(diagnostic, step, .cancelled),
        .deadline_exhausted => stopped(diagnostic, step, .{ .failed = code(step) }),
    };
}

fn stopped(diagnostic: *Diagnostic, step: Step, outcome: Outcome) Outcome {
    diagnostic.step = step;
    return outcome;
}

/// The seven steps. Each is one typed function; a step that reaches the port takes exactly that
/// port, and none takes the port set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn deriveRequirement(selected: *const execution.SelectedWorkflow) requirement.Requirement {
        return derivation.derive(selected);
    }

    pub fn locateConfig(
        locator: config_port.Locator,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) config_port.Error!config_port.ExactFile {
        return locator.locate(capability, allocator, runtime);
    }

    /// Reads the located file's one capture within the compiler's byte limit; it never parses.
    pub fn readConfig(
        exact: *config_port.ExactFile,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) config_port.Error!llm_provider_config.Raw {
        return exact.read(allocator, llm_provider_config.max_bytes, runtime);
    }

    pub fn decodeConfig(allocator: std.mem.Allocator, bytes: []const u8) decoding.Error!document.Owned {
        return decoding.decode(allocator, bytes);
    }

    pub fn buildRegistry(
        registered: *const contracts.Registry,
        allocator: std.mem.Allocator,
        raw: *const document.RawLLMProviderDocument,
    ) registry_building.Error!provider_registry.Candidate {
        return registry_building.build(registered, allocator, raw);
    }

    pub fn validateRegistry(
        registered: *const contracts.Registry,
        allocator: std.mem.Allocator,
        candidate: provider_registry.Candidate,
    ) error{LLMProviderRegistryInvalid}!*provider_registry.Owner {
        return provider_registry.createValidated(allocator, candidate, registered.*) catch {
            return error.LLMProviderRegistryInvalid;
        };
    }

    pub fn validateAllowlist(
        allocator: std.mem.Allocator,
        models: *const config.ModelsConfig,
        temperatures: model_controls.Temperatures,
        validated: *const provider_registry.ValidatedLLMProviderRegistry,
    ) error{LLMProviderModelBindingInvalid}!*repository_allowlist.Owner {
        return repository_allowlist.createValidated(allocator, models, temperatures, validated) catch {
            return error.LLMProviderModelBindingInvalid;
        };
    }
};
