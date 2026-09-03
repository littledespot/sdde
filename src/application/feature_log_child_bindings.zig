const event_registry = @import("../domain/log_event_registry.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt_log = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");
const result = @import("feature_log_result.zig");

pub const StepOutcome = union(enum) { ok, failed: log_stream.FailureCode };
pub const EventValidationOutcome = union(enum) {
    valid: event_registry.EventDefinition,
    failed: log_stream.FailureCode,
};
pub const ClockOutcome = union(enum) {
    ready: log_stream.ClockReading,
    failed: log_stream.FailureCode,
};
pub const PersistenceOutcome = union(enum) {
    persisted: log_stream.PersistedEvidence,
    failed: log_stream.FailureCode,
};
pub const Decision = enum { emit, drop };
pub const RuntimeIdentity = *const anyopaque;

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        identity: *const fn (*const anyopaque) RuntimeIdentity,
        retired: *const fn (*const anyopaque) bool,
        validate_event: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact) EventValidationOutcome,
        evaluate_event: *const fn (*const anyopaque, event_registry.EventDefinition) Decision,
        validate_prompt: *const fn (*anyopaque, prompt_log.SanitizedPromptFragment) StepOutcome,
        evaluate_prompt: *const fn (*const anyopaque, prompt_log.SanitizedPromptFragment) Decision,
        read_clock: *const fn (*anyopaque) ClockOutcome,
        acquire: *const fn (*anyopaque, log_stream.Stream) StepOutcome,
        persist_event: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact, event_registry.EventDefinition, log_stream.ClockReading) PersistenceOutcome,
        persist_prompt: *const fn (*anyopaque, prompt_log.SanitizedPromptFragment, log_stream.ClockReading) PersistenceOutcome,
        release: *const fn (*anyopaque) StepOutcome,
        prepare: *const fn (*anyopaque, telemetry.WorkflowShortcode) result.Outcome,
        close: *const fn (*anyopaque, telemetry.WorkflowShortcode) result.Outcome,
        report_failure: *const fn (*anyopaque, telemetry.WorkflowShortcode, log_stream.FailureCode) log_stream.FailureCode,
    };

    pub fn identity(self: ChildBindings) RuntimeIdentity {
        return self.vtable.identity(self.context);
    }
    pub fn retired(self: ChildBindings) bool {
        return self.vtable.retired(self.context);
    }
    pub fn invokeValidateEvent(self: ChildBindings, fact: telemetry.WorkflowTelemetryFact) EventValidationOutcome {
        return self.vtable.validate_event(self.context, fact);
    }
    pub fn invokeEvaluateEvent(self: ChildBindings, definition: event_registry.EventDefinition) Decision {
        return self.vtable.evaluate_event(self.context, definition);
    }
    pub fn invokeValidatePrompt(self: ChildBindings, fragment: prompt_log.SanitizedPromptFragment) StepOutcome {
        return self.vtable.validate_prompt(self.context, fragment);
    }
    pub fn invokeEvaluatePrompt(self: ChildBindings, fragment: prompt_log.SanitizedPromptFragment) Decision {
        return self.vtable.evaluate_prompt(self.context, fragment);
    }
    pub fn invokeReadClock(self: ChildBindings) ClockOutcome {
        return self.vtable.read_clock(self.context);
    }
    pub fn invokeAcquire(self: ChildBindings, stream: log_stream.Stream) StepOutcome {
        return self.vtable.acquire(self.context, stream);
    }
    pub fn invokePersistEvent(self: ChildBindings, fact: telemetry.WorkflowTelemetryFact, definition: event_registry.EventDefinition, reading: log_stream.ClockReading) PersistenceOutcome {
        return self.vtable.persist_event(self.context, fact, definition, reading);
    }
    pub fn invokePersistPrompt(self: ChildBindings, fragment: prompt_log.SanitizedPromptFragment, reading: log_stream.ClockReading) PersistenceOutcome {
        return self.vtable.persist_prompt(self.context, fragment, reading);
    }
    pub fn invokeRelease(self: ChildBindings) StepOutcome {
        return self.vtable.release(self.context);
    }
    pub fn invokePrepare(self: ChildBindings, shortcode: telemetry.WorkflowShortcode) result.Outcome {
        return self.vtable.prepare(self.context, shortcode);
    }
    pub fn invokeClose(self: ChildBindings, shortcode: telemetry.WorkflowShortcode) result.Outcome {
        return self.vtable.close(self.context, shortcode);
    }
    pub fn invokeReportFailure(self: ChildBindings, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.FailureCode {
        return self.vtable.report_failure(self.context, shortcode, failure);
    }
};
