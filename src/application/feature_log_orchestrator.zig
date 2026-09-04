const bindings = @import("feature_log_child_bindings.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const prompt_log = @import("../domain/sanitized_prompt_log.zig");
const telemetry = @import("../domain/telemetry.zig");

pub fn processEvent(children: bindings.ChildBindings, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
    if (children.retired()) return block(children, fact.workflow_shortcode, .LOG_SINK_FAILURE);
    const definition = switch (children.invokeValidateEvent(fact)) {
        .valid => |value| value,
        .failed => |failure| return block(children, fact.workflow_shortcode, failure),
    };
    if (children.invokeEvaluateEvent(definition) == .drop) return .dropped;
    const reading = switch (children.invokeReadClock()) {
        .ready => |value| value,
        .failed => |failure| return block(children, fact.workflow_shortcode, failure),
    };
    switch (children.invokeAcquire(.event)) {
        .ok => {},
        .failed => |failure| return block(children, fact.workflow_shortcode, failure),
    }
    var failure: ?log_stream.FailureCode = null;
    const evidence = switch (children.invokePersistEvent(fact, definition, reading)) {
        .persisted => |value| value,
        .failed => |value| failed: {
            failure = value;
            break :failed null;
        },
    };
    switch (children.invokeRelease()) {
        .ok => {},
        .failed => |value| failure = value,
    }
    if (failure) |value| return block(children, fact.workflow_shortcode, value);
    return .{ .persisted = evidence.? };
}

pub fn processPrompt(children: bindings.ChildBindings, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
    if (children.retired()) return block(children, fragment.workflow_shortcode, .LOG_SINK_FAILURE);
    switch (children.invokeValidatePrompt(fragment)) {
        .ok => {},
        .failed => |failure| return block(children, fragment.workflow_shortcode, failure),
    }
    if (children.invokeEvaluatePrompt(fragment) == .drop) return .dropped;
    const reading = switch (children.invokeReadClock()) {
        .ready => |value| value,
        .failed => |failure| return block(children, fragment.workflow_shortcode, failure),
    };
    switch (children.invokeAcquire(.prompt)) {
        .ok => {},
        .failed => |failure| return block(children, fragment.workflow_shortcode, failure),
    }
    var failure: ?log_stream.FailureCode = null;
    const evidence = switch (children.invokePersistPrompt(fragment, reading)) {
        .persisted => |value| value,
        .failed => |value| failed: {
            failure = value;
            break :failed null;
        },
    };
    switch (children.invokeRelease()) {
        .ok => {},
        .failed => |value| failure = value,
    }
    if (failure) |value| return block(children, fragment.workflow_shortcode, value);
    return .{ .persisted = evidence.? };
}

pub fn prepare(children: bindings.ChildBindings, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    return children.invokePrepare(shortcode);
}

pub fn close(children: bindings.ChildBindings, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    return children.invokeClose(shortcode);
}

fn block(children: bindings.ChildBindings, shortcode: telemetry.WorkflowShortcode, failure: log_stream.FailureCode) log_stream.Outcome {
    return .{ .blocked = children.invokeReportFailure(shortcode, failure) };
}
