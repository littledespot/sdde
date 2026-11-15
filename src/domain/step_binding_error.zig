//! Closed failure causes of operation bindings. A binding that finds what it was handed unusable names the
//! failed check by one of these causes, each stated in its owner's vocabulary, so a failed run names its
//! cause instead of a generic operation failure. A binding asserts an input the runner supplies (`.?`,
//! `unreachable`) only where the runner refuses the step first and a runner-level test pins that refusal;
//! every other check of such an input stays a typed cause. A set belongs to one owner area and every name
//! is declared once.
//! Repair owners declare their own set in `repair_owner.zig`.

/// A model request's preparation, composition, guidance and candidate handoff.
pub const RequestPreparation = error{
    /// A declared parameter of the request step is absent, the wrong kind, or conflicts with another.
    RequestDeclarationInvalid,
    /// The step requires a model binding the runner did not supply.
    RequestModelBindingMissing,
    /// A resource the request names is absent from the compiled step.
    RequestResourceMissing,
    /// The composition plan and the declared input disagree.
    RequestCompositionConflict,
    /// The request ledger does not hold the request, or belongs to another stage run.
    RequestLedgerForeign,
    /// The composition resource is absent or is not a JSON composition.
    CompositionResourceInvalid,
    /// The request names no composition part, or the retained part is absent.
    CompositionPartMissing,
    /// The retained composition state is not the state this operation consumes.
    CompositionStateMismatch,
    /// A value the composition retains is absent from the envelope.
    CompositionRetainedValueMissing,
    /// The guidance resource is absent or is not packet guidance.
    GuidanceResourceInvalid,
    /// The admitted candidate was built for another packet than the request's.
    CandidatePacketForeign,
    /// The candidate's origin is not in the request ledger.
    CandidateOriginUnavailable,
    /// The response was not admitted as a candidate (stopped, failed, rejected or not validated).
    CandidateNotAdmitted,
};

/// A request's provider-operation lifecycle, invocation, observation and admission stages.
pub const ProviderLifecycle = error{
    /// The runner supplied no provider-operation facts for this step.
    ProviderOperationFactsMissing,
    /// The runner supplied no provider-invocation facts for this step.
    ProviderInvocationFactsMissing,
    /// The runner supplied no provider-authorization facts for this step.
    ProviderAuthorizationFactsMissing,
    /// The authorization preparation produced no validated result.
    ProviderAuthorizationResultMissing,
    /// The runner supplied no model-attempt facts for this step.
    ModelAttemptFactsMissing,
    /// The runner supplied no request lifecycle ledger for this step.
    RequestLifecycleLedgerMissing,
    /// The step's declared lifecycle transition is not the one this operation applies.
    LifecycleTransitionInvalid,
    /// The lifecycle ledger holds no record for the operation or request.
    LifecycleRecordMissing,
    /// The record is not in the status this operation requires.
    LifecycleStatusConflict,
    /// The evidence belongs to another request or operation.
    LifecycleEvidenceForeign,
    /// The observation is not a validated one.
    ObservationNotValidated,
    /// The invocation result holds no raw outcome.
    ObservationOutcomeMissing,
    /// Model logging blocked the send before it happened.
    ObservationLoggingBlocked,
    /// The authorization result is not one this operation can complete or terminate.
    OperationOutcomeNotAdmitted,
    /// The request closure carries an outcome that is not terminal.
    RequestOutcomeNotTerminal,
    /// The response is not one a protocol retry applies to.
    ProtocolRetryNotApplicable,
    /// The request carries no protocol prompt.
    ProtocolPromptMissing,
    /// A protocol rejection carries no decoder diagnostic.
    ProtocolDiagnosticMissing,
    /// The decoded outcome and the response it decodes disagree.
    DecodeEvidenceInconsistent,
    /// The payload check and the decoded outcome disagree.
    PayloadCheckInconsistent,
};

/// Reference, specification and project-level bindings.
pub const StepBinding = error{
    /// A retained reference payload is not at the stage this operation consumes.
    ReferenceStageMismatch,
    /// Clarification state is not ready for this operation.
    ClarificationStateNotReady,
    /// The declared reconciliation phase is absent or is not the phase to run.
    ReconciliationPhaseInvalid,
    /// A reference candidate's producer or origin is unavailable.
    ReferenceCandidateUnavailable,
    /// A reference part the operation names is unavailable.
    ReferencePartUnavailable,
    /// The reconciliation layout has no size.
    ReconciliationSizeMissing,
    /// The path-token operation has no source text.
    PathTokenTextMissing,
    /// The specification has no brief.
    SpecificationBriefMissing,
    /// The run supplied no project authority to this step.
    ProjectAuthorityMissing,
    /// No feature-log activator is bound.
    FeatureLoggingActivatorUnbound,
    /// No required-authority policy is bound.
    RequiredAuthorityPolicyUnbound,
    /// The support review is not in the state this operation consumes.
    SupportReviewStateInvalid,
};

/// How an operation is invoked and how an invocation ends.
pub const Invocation = error{
    /// A step operation was invoked as an invocation, or the reverse.
    OperationWrongKind,
    /// The invocation carries arguments its operation does not take.
    InvocationArgumentsInvalid,
    /// A kernel binding was invoked directly: only the runner runs its stages.
    KernelBindingNotInvocable,
    /// The invocation ended without recording its failure.
    InvocationFailureUnrecorded,
    /// The harness stopped the request at a stage boundary.
    RequestStageStopped,
    /// The harness's own recording or gate failed, which stops the run; the harness reports that failure.
    HarnessFailureStopped,
};
