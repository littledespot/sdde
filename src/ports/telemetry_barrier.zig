const telemetry = @import("../domain/telemetry.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt = @import("../domain/sanitized_prompt_log.zig");

pub const Barrier = struct {
    context: *anyopaque,
    process_fn: *const fn (*anyopaque, telemetry.WorkflowTelemetryFact) log_stream.Outcome,
    select_prompt_fn: ?*const fn (*anyopaque, prompt.SanitizedPromptFragment) bool = null,
    process_prompt_fn: ?*const fn (*anyopaque, prompt.SanitizedPromptFragment) log_stream.Outcome = null,
    report_failure_fn: ?*const fn (*anyopaque, telemetry.WorkflowShortcode, log_stream.FailureCode) void = null,

    pub fn process(self: Barrier, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
        return self.process_fn(self.context, fact);
    }
    pub fn selectPrompt(self: Barrier, fragment: prompt.SanitizedPromptFragment) bool {
        return if (self.select_prompt_fn) |select| select(self.context, fragment) else false;
    }
    pub fn processPrompt(self: Barrier, fragment: prompt.SanitizedPromptFragment) log_stream.Outcome {
        return if (self.process_prompt_fn) |process_prompt| process_prompt(self.context, fragment) else .{ .blocked = .LOG_SINK_FAILURE };
    }
    pub fn reportFailure(self: Barrier, workflow: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) void {
        if (self.report_failure_fn) |report| report(self.context, workflow, failure);
    }
};
