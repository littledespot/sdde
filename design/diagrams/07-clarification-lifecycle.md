```mermaid
flowchart TD
    RECONGAP[Validated AuthorityReconciliationOutcome clarification_required<br/>structural requirement ID earliest owner closed gap reason and current evidence] --> GNEED[BuildAuthorityGapClarificationNeedAction<br/>compiler-registered subject question why and answer schema]
    GNEED --> NEED[Validated stage-compatible clarification need]
    MODELNEED[Validated clarification_needed operation result<br/>genuine current authority gap; no model-owned ID, path or status] --> NEED[Validated stage-compatible clarification need]
    RCONFLICT[Validated unresolved behavior-changing SourceConflict<br/>after complete ReferenceSnapshot validation] --> RCNEED[BuildReferenceConflictClarificationNeedAction<br/>closed engine claim-ID choices; no model or preferred answer]
    RCNEED --> NEED
    NEED --> KEY[Build deterministic ClarificationSubjectKey<br/>stable target, earliest owning stage, structural subject selector and required slot;<br/>exclude run IDs, authority revisions, gap kind and question wording]
    KEY --> LOOKUP[Lookup exact subject key across open and resolved clarification history]
    LOOKUP --> FOUND{Record already exists}
    FOUND -- Yes --> REUSE[Reuse the same record, stage prefix, ordinal and engine path]
    FOUND -- No --> PREFIX[Select fixed prefix by stage<br/>spec S, plan P, tasks T]
    PREFIX --> LIMIT{Next monotonic stage ordinal is at most 99}
    LIMIT -- No --> BLOCK[Blocking clarification-capacity diagnostic<br/>no partial stage artifact]
    LIMIT -- Yes --> ALLOC[Allocate S01-S99, P01-P99 or T01-T99<br/>retired IDs are never reused]
    ALLOC --> NEWREC[Build new open canonical record and advance only that stage's ID ledger]
    REUSE --> PROTECTED{Would refresh or reopen replace a user-closed form}
    PROTECTED -- Yes --> PBLOCKC[Block for explicit user direction;<br/>retain user-closed bytes, answer and identity; never allocate a duplicate]
    PROTECTED -- No --> EXISTING[Retain the existing ID and ledger;<br/>only an unprotected record may reopen through a new revision]
    NEWREC --> UNIQUE[Validate one record per exact subject key and one subject per ID]
    EXISTING --> UNIQUE
    UNIQUE --> NREG[AssignClarificationStateIdAction, BuildNextClarificationRegistryAction<br/>and ValidateClarificationRegistryAction for the prospective open/reused record]
    NREG --> PATH[Resolve engine-owned path<br/>featureDir/clarify/clarificationId.md]
    PATH --> VIEW[Render controlled form only beneath featureDir/clarify/<br/>immutable question/why/schema; only requestedStatus and answer editable;<br/>never place a clarification marker, question or partial answer in spec.md]
    VIEW --> PSTAGE{Owning clarification stage}
    PSTAGE -- Plan --> PPINPUT[AssignPlanInputAuthorityStateIdAction then BuildPlanInputAuthorityStateAction<br/>and ValidatePlanInputAuthorityStateAction after the exact next clarification ID/revision exists;<br/>persist all consumed path/research IDs and tombstones, but no candidate records or PlanState]
    PPINPUT --> PAUSE
    PSTAGE -- Spec or tasks --> PAUSE[Assemble complete stage-specific clarification-pause inputs:<br/>current/staged authority set, next registry, all forms and matching pending state;<br/>retain protected forms byte-for-byte; the plan variant includes its exact successor<br/>PlanInputAuthorityState; no incomplete SpecificationIR, PlanState or TaskDefinitionState]
    PAUSE --> PVALID[Validate exact paths, revisions, prefixes and open-ID projection]
    PVALID --> PWAL[Invoke diagram 09 feature-storage lifecycle: acquire/recover feature storage,<br/>reserve/fsync transaction ID, build/validate ClarificationPauseStageTransaction<br/>with DurableTransactionMember, journal/mark, commit or retire and release exactly once]
    PWAL --> PLOG{Transaction adopted a successor bootstrap whose<br/>changePlan.obligations.transitionFeatureLogging is true}
    PLOG -- No --> PENDING{Committed pending stage}
    PLOG -- Yes --> PLOGTX[Invoke diagram 06 complete policy transition before user wait or any normal node]
    PLOGTX --> PENDING
    PENDING -- SNN --> SPEND[spec_clarification_pending]
    PENDING -- PNN --> PPEND[plan_clarification_pending]
    PENDING -- TNN --> TPEND[tasks_clarification_pending]

    SPEND --> SGATE[plan launch exits nonzero while any SNN is open]
    SPEND --> PGATE[tasks launch exits nonzero while any SNN or PNN is open]
    PPEND --> PGATE
    SPEND --> TGATE[implement launch exits nonzero while any SNN PNN or TNN is open]
    PPEND --> TGATE
    TPEND --> TGATE
    SGATE --> WAIT[Workflow state and record remain unchanged]
    PGATE --> WAIT
    TGATE --> WAIT

    SPEND --> RERUN[Subsequent invocation of the owning stage]
    PPEND --> RERUN
    TPEND --> RERUN
    WAIT --> RERUN
    RERUN --> LOAD[Load and validate current registry, all forms, workflow state and passive-literal revision;<br/>protect user-closed bytes before ingestion; retain all records and answers]
    LOAD --> ANSWERS[Revalidate relevant resolved answers against current authority;<br/>consume applicable validated answers before proposing questions]
    ANSWERS --> APROTECTED{Changed applicability would refresh or reopen a user-closed form}
    APROTECTED -- Yes --> PBLOCKC
    APROTECTED -- No --> ORDER[Visit open records in stage-rank then ordinal order;<br/>only unprotected records may refresh or reopen]
    ORDER --> FORM[ParseClarificationViewAction only for a registered open_submission view;<br/>project its two editable fields and immutable form content against the last commit;<br/>accepted retained user-closed and closed_audit views have no submission route]
    FORM --> PRESENT{Current editable submission present}
    PRESENT -- Yes --> STATIC[ValidateClarificationViewStaticProjectionAction<br/>filename, IDs, revisions and immutable content equal the current record]
    STATIC --> SUBMIT{ValidateClarificationUserSubmissionAction<br/>before authentication: freshness, closed answer, select cardinality/order,<br/>and bounded defer or cancel reason shape}
    SUBMIT -- Invalid --> UERR[Nonzero user-input error; stale or invalid closed submission stays byte-exact;<br/>no authentication lease consumed, evidence ID allocated,<br/>model repair, form replacement or state mutation]
    SUBMIT -- Valid cancel --> AUTHC[AuthenticateActorAction then ValidateAuthenticationObservationAction,<br/>AssignAuthenticationEvidenceIdAction, BuildAuthenticatedActorEvidenceAction<br/>and ValidateAuthenticatedActorEvidenceAction]
    AUTHC --> BINDC[BindAuthenticatedClarificationSubmissionAction<br/>bind the already valid cancel event to fresh actor evidence]
    BINDC --> CANCEL[AssignClarificationResponseIdAction and assemble the cancelled response,<br/>next actor/clarification registries and immutable resolved form]
    CANCEL --> CTX09[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>build/validate ClarificationResponseStageTransaction, atomically close as cancelled_by_user<br/>and release the feature lock]
    CTX09 --> CANCELLED[cancelled workflow; resolved form has no editable region]

    SUBMIT -- Valid defer --> AUTHD[AuthenticateActorAction then ValidateAuthenticationObservationAction;<br/>assign, build and validate fresh actor evidence without appending its registry yet]
    AUTHD --> BINDD[BindAuthenticatedClarificationSubmissionAction<br/>bind the already valid defer event to fresh actor evidence]
    BINDD --> DEFER[AssignClarificationResponseIdAction and assemble response plus actor evidence;<br/>keep the same clarification ID open and increment state/record revisions]
    DEFER --> DTX09[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>build/validate ClarificationResponseStageTransaction, commit defer and release feature lock]
    DTX09 --> BLANK[Rerender a fresh blank requestedStatus open answer region<br/>replay of the consumed defer form is stale]
    BLANK --> PENDING

    SUBMIT -- Valid closed answer --> AUTHA[AuthenticateActorAction then ValidateAuthenticationObservationAction;<br/>assign, build and validate fresh actor evidence without appending its registry yet]
    AUTHA --> BINDA[BindAuthenticatedClarificationSubmissionAction<br/>bind the already schema-valid canonical answer to fresh actor evidence]
    BINDA --> URESP[AssignClarificationResponseIdAction then build response and<br/>next actor/clarification registries with resolved_by_user lifecycle]
    URESP --> UTX[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>build/validate ClarificationResponseStageTransaction and commit response, actor evidence,<br/>registry, optional passive update and next workflow state while retaining the submitted<br/>form byte-for-byte; release feature lock; remain pending when another record is open]
    UTX --> RESOLVED[Resolution committed before regeneration]

    PRESENT -- No --> REFRESH[Refresh stage-authorized sources; compare typed current states directly<br/>no fingerprint and no unsupported model recall]
    REFRESH --> BREFRESH[Run diagram 08 Compare -> Classify/Validate change plan -> Route/Validate route;<br/>retain any OwningSpecification/OwningPlanning typed successor handoff and all obligations<br/>for this clarification pause/authority-resolution transaction; persist no standalone authority]
    BREFRESH --> ASTAGE{Clarification stage}
    ASTAGE -- Spec --> SAUTH[Reingest the current selected directory through the complete diagram 05<br/>preactivation/canonical/extraction/reconciliation flow and validate current specification authorities;<br/>principles cannot supply missing business facts]
    ASTAGE -- Plan --> PAUTH[Load the bound current PlanInputAuthorityState; refresh normalized spec,<br/>bootstrap/reference, RepositoryFactRegistryState, baseline FileRegistryState<br/>and ResearchEvidenceRegistry; select every raw principle chunk in configured<br/>eligible filename-category hints; do not build the successor before resolution]
    ASTAGE -- Tasks --> TAUTH[Reload current PlanState/spec, presets and repository facts;<br/>select every raw principle chunk in configured eligible filename-category hints]
    PAUTH --> PFIT{Complete category-selected raw chunks fit the compiled operation budget}
    TAUTH --> PFIT
    PFIT -- No --> PBLOCK[Blocking principle-context budget diagnostic<br/>no ranking, summary or silent omission]
    PFIT -- Yes --> PHINT[Principle filename supplies only a category hint;<br/>resolution must cite supporting source-located free text]
    SAUTH --> SREFCHANGE{Freshly validated ReferenceSnapshot candidate<br/>differs from the durable current snapshot}
    SREFCHANGE -- No --> DIRECT[Run deterministic subject-specific authority resolvers]
    SREFCHANGE -- Yes --> SREFOWNER[Return the candidate and same open SNN to diagram 05;<br/>only its ReferenceRevision or atomic specification clarification-pause route may<br/>commit descendant mutation, reference view, refreshed authorities and workflow state;<br/>do not use ClarificationAuthorityResolutionStageTransaction for this raw-reference change]
    PHINT --> DIRECT
    DIRECT --> COVER{Current non-conflicting authority directly covers exact subject and required slot}
    COVER -- Yes --> ARES[AssignClarificationResolutionIdAction then<br/>BuildClarificationAuthorityResolutionAction with exact current authority IDs<br/>and a self-contained validation-contract binding; no transient evidence ID]
    COVER -- Semantic interpretation required --> CRES[YAML-declared clarification-resolution operation<br/>receives bounded current authority IDs only]
    CRES --> CVALID{Deterministic validation proves cited current IDs cover exact subject without conflict}
    CVALID -- Yes --> ARES
    CVALID -- No --> STILL
    COVER -- No --> STILL[Keep same record and ID open; do not invent an answer]
    ARES --> ANEXT[AssignClarificationStateIdAction, BuildNextClarificationRegistryAction<br/>and ValidateClarificationRegistryAction with the prospective resolution]
    ANEXT --> ARSTAGE{Owning clarification stage}
    ARSTAGE -- Plan --> APINPUT[AssignPlanInputAuthorityStateIdAction then BuildPlanInputAuthorityStateAction<br/>and ValidatePlanInputAuthorityStateAction bound to the exact next clarification ID/revision,<br/>refreshed normalized-spec/repository/baseline-file/research/principle bundle<br/>and successor plan ledger with every consumed ID/tombstone]
    APINPUT --> ATX
    ARSTAGE -- Spec or tasks --> ATX[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>BuildClarificationAuthorityResolutionStageTransactionAction, validate and commit atomically;<br/>the plan variant binds the exact successor PlanInputAuthorityState;<br/>release feature lock and remain pending when another record is open]
    ATX --> ALOG{Transaction adopted a successor bootstrap whose<br/>changePlan.obligations.transitionFeatureLogging is true}
    ALOG -- No --> RESOLVED
    ALOG -- Yes --> ALOGTX[Invoke diagram 06 complete policy transition before regeneration or user wait]
    ALOGTX --> RESOLVED
    STILL --> ACHANGE{Stage-authorized authority set changed}
    ACHANGE -- No --> SAME[No state mutation; retain the same open record, ID,<br/>authority bindings and pending workflow revision]
    SAME --> PENDING
    ACHANGE -- Yes --> UCSTAGE{Owning clarification stage}
    UCSTAGE -- Plan --> POPENREFRESH[AssignClarificationStateIdAction and build/validate the next registry<br/>with the same PNN still open; then AssignPlanInputAuthorityStateIdAction,<br/>BuildPlanInputAuthorityStateAction and ValidatePlanInputAuthorityStateAction<br/>against that exact next clarification ID/revision and the refreshed<br/>normalized-spec/repository/baseline-file/research/principle bundle]
    POPENREFRESH --> POPENTX[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>BuildClarificationPauseStageTransactionAction with PlanClarificationPauseEntries,<br/>successor PlanInput ledger/IDs/tombstones, next registry/forms and pending workflow;<br/>commit and release feature lock; persist no candidate PlanState unit/view]
    POPENTX --> POLOG{Adopted change plan requires logging transition}
    POLOG -- No --> PENDING
    POLOG -- Yes --> POLOGTX[Invoke diagram 06 complete policy transition before user wait]
    POLOGTX --> PENDING
    UCSTAGE -- Spec or tasks --> OOPENREFRESH[Invoke diagram 09 feature-storage lifecycle; after transaction-ID reservation<br/>build/validate the next same-ID open registry and stage-specific authority pause transaction;<br/>commit atomically and release feature lock]
    OOPENREFRESH --> OOLOG{Adopted change plan requires logging transition}
    OOLOG -- No --> PENDING
    OOLOG -- Yes --> OOLOGTX[Invoke diagram 06 complete policy transition before user wait]
    OOLOGTX --> PENDING

    RESOLVED --> NEXT{Another open clarification for this owning stage}
    NEXT -- Yes; workflow remains clarification_pending --> ORDER
    NEXT -- No --> RTYPE{Committed resolution is a closed user response<br/>for a conflict-bound specification SNN}
    RTYPE -- Yes --> SCREFRESH[Return the durable closed response and prior registry/reference bindings<br/>to diagram 05; rerun target-context bootstrap and the complete selected-directory flow:<br/>fresh no-follow preactivation/canonical ingestion, extraction and reconciliation;<br/>do not reuse any prior-snapshot blob]
    SCREFRESH --> SCPRIOR[BuildPriorReferenceConflictClarificationSubjectSetAction then<br/>ValidatePriorReferenceConflictClarificationSubjectSetAction for the complete canonical P]
    SCPRIOR --> SCCURRENT[BuildCurrentUnresolvedReferenceConflictSubjectSetAction then<br/>ValidateCurrentUnresolvedReferenceConflictSubjectSetAction for every unresolved<br/>behavior-changing conflict in the complete validated fresh snapshot C]
    SCCURRENT --> SCRECON[ReconcileReferenceConflictSubjectSetsAction then<br/>ValidateReferenceConflictSubjectSetReconciliationAction;<br/>prove the exact disjoint exhaustive P intersection C, P minus C and C minus P partitions]
    SCRECON --> SCSAME[For each equal-key P intersection C entry only, use<br/>BuildFreshReferenceConflictCorrespondenceAction and ValidateFreshReferenceConflictCorrespondenceAction]
    SCSAME --> SCPROTECTED{Stale or unusable answer would refresh a protected user-closed form}
    SCPROTECTED -- Yes --> PBLOCKC
    SCPROTECTED -- No --> SCAPPLY[Current answer may allocate/build/validate a decision and rebuild the fresh snapshot;<br/>otherwise RefreshReferenceConflictClarificationAction refreshes only an unprotected form<br/>and preserves the same SNN identity]
    SCAPPLY --> SCOBSOLETE[For every P minus C entry, retain existing user closure and protected bytes;<br/>otherwise AssignClarificationResolutionIdAction then<br/>BuildObsoleteReferenceConflictAuthorityResolutionAction with exhaustive C-absence proof;<br/>close that prior key without naming or pairing any introduced key]
    SCOBSOLETE --> SCINTRO[For every C minus P entry, BuildReferenceConflictClarificationNeedAction,<br/>FindExistingClarificationBySubjectAction and ValidateClarificationSubjectUniquenessAction]
    SCINTRO --> SIPROTECTED{Opening would replace an existing user-closed form}
    SIPROTECTED -- Yes --> PBLOCKC
    SIPROTECTED -- No --> SIOPEN[Globally reuse the exact existing key or AssignClarificationIdAction only after<br/>exact absence, then BuildIntroducedReferenceConflictOpeningAction]
    SIOPEN --> SCSET[BuildReferenceConflictClarificationSetTransitionAction once;<br/>AssignClarificationStateIdAction and BuildNextClarificationRegistryAction once;<br/>assemble the complete view set from retained protected forms and writable rendered views;<br/>ValidateReferenceConflictClarificationSetTransitionAction and ValidateClarificationRegistryAction<br/>require exact unresolved-key/open-key/submittable-view-key equality]
    SCSET --> SOWNED[Diagram 05 owns one atomic clarification-pause transaction when the expected open-key set<br/>is nonempty, or one reference-revision transaction with a validated empty submittable-view projection<br/>otherwise; each commits the complete set transition, complete view set and fresh snapshot with any<br/>bootstrap/logging transition; this lifecycle performs no pairwise subject mutation or second<br/>retained-snapshot transaction]
    RTYPE -- No --> RSTAGE{Owning stage to regenerate}
    RSTAGE -- Spec --> REGENS[Regenerate every specification unit in deterministic order<br/>from current reference and answer authority]
    RSTAGE -- Plan --> PREADY{Workflow PlanInputAuthorityState already binds<br/>the just-closed clarification state and revision}
    PREADY -- Yes; authority-resolution transaction staged it --> REGENP[Regenerate every plan unit in deterministic order<br/>with the current complete category-based principle selection]
    PREADY -- No; user response committed first --> PRINPUT[AssignPlanInputAuthorityStateIdAction, BuildPlanInputAuthorityStateAction<br/>and ValidatePlanInputAuthorityStateAction bound to the newly closed response state;<br/>invoke diagram 09 feature-storage lifecycle, then after transaction-ID reservation<br/>BuildPlanInputAuthorityStageTransactionAction, validate/commit planning-to-planning<br/>and release the feature lock]
    PRINPUT --> PRLOG{Adopted change plan requires logging transition}
    PRLOG -- No --> REGENP
    PRLOG -- Yes --> PRLOGTX[Invoke diagram 06 complete policy transition before any plan model call]
    PRLOGTX --> REGENP
    RSTAGE -- Tasks --> REGENT[Regenerate every tasks unit in deterministic order<br/>with the current complete category-based principle selection]
    REGENS --> FULL[Run complete stage validation and require no open upstream/current clarification]
    REGENP --> FULL
    REGENT --> FULL
    FULL -- New genuine authority gap --> NEED
    FULL -- Valid spec --> SPECOK[Commit specified state and replace its registered outputs;<br/>retain protected clarifications]
    FULL -- Valid plan --> PLANOK[Commit read-only PlanState and replace its registered views;<br/>retain protected clarifications, then await exact-state approval]
    FULL -- Valid tasks --> TASKOK[Commit read-only TaskDefinitionState and replace its registered view;<br/>retain protected clarifications, then await exact-state approval]

    TX09REF[Diagram 09 is the sole durable clarification/stage persistence subroutine;<br/>reruns MUST overwrite existing selected-workflow outputs at the same registered paths;<br/>no separate overwrite approval and no feature-directory clearing;<br/>user-closed clarification files MUST remain byte-for-byte unchanged;<br/>state/ownership recovery remains required; no feature collection lock spans<br/>user wait, authority refresh, model resolution or regeneration]
    PWAL -. common lifecycle .-> TX09REF
    CTX09 -. common lifecycle .-> TX09REF
    DTX09 -. common lifecycle .-> TX09REF
    UTX -. common lifecycle .-> TX09REF
    ATX -. common lifecycle .-> TX09REF
    POPENTX -. common lifecycle .-> TX09REF
    OOPENREFRESH -. common lifecycle .-> TX09REF
    PRINPUT -. common lifecycle .-> TX09REF
```
