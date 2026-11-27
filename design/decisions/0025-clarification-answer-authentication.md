# ADR 0025: Accept valid clarification answers in the run that reads them

- **Status:** Accepted. Not built: generation's use of answers other than a reference conflict's, and
  response-owned passive literals ([SPEC01 E7](../../fixes/SPEC01.md#e7-clarification-answer-recovery-r2-adr-0025)).
- **Date:** 2026-10-21
- **Decision authority:** User decisions, 21 October and 23, 24 and 27 November 2026. The approval covers
  clarification answers. It does not choose the provider for plan or task review approvals.
- **Amends:**
  - §17.4, by defining the authenticated actor and the act of acceptance;
  - the §13 catalogue, by giving `AuthenticateActorAction`'s `AuthenticationPort`
    its first provider, and by making `ValidateClarificationUserSubmissionAction`
    report a typed reason for each rejected form;
  - F0100 §3.2, by selecting its authentication mechanism;
  - [ADR 0006](0006-minimal-model-response.md)'s rule that only data the model must supply is in its response, by one
    exception: the records clarification's `record_kind` (Decision 6);
  - the §13.03 catalogue, by `ApplyClarificationAnswersAction`, and [§13.05](../contracts/actions/13-05-artifacts-rendering-traceability.md)'s
    authority need builder, by the selection form of a conflict (Decision 7).

  - §17.3, for the source text generation receives after an answered conflict.

  It leaves §23.2's protection of user-closed forms, ADR 0017's incomplete
  publication and ADR 0009's fresh-invocation rule unchanged.

## Decision

### The flow

1. **Run 1** finds a gap, publishes the `SNN` forms and pauses in
   `spec_clarification_pending`. This is unchanged.
2. **The user** answers a form by changing only `requestedStatus` and the answer
   region (§17.4).
3. **Run 2** checks every registered form before any model call. Each closed form
   must:
   - parse against the last committed clarification and reference binding;
   - name the current state and record revisions;
   - change nothing outside `requestedStatus` and the answer region;
   - carry a nonempty answer that matches its select-one, select-many or bounded-text
     schema.
4. **If any closed form fails**, run 2 accepts none of the answers. It stops
   `blocked`, makes no model call, writes nothing and leaves every form as the user
   left it (§23.2). Its report lists each failing form with its clarification ID,
   path and typed reason, and what a valid answer needs: the expected revision, the
   offered options or the text bound.
5. **If every closed form passes**, run 2 accepts them all and continues in the same
   run. For each closed form it:
   - authenticates the invoking account and records the evidence;
   - builds the response with the exact form bytes, actor, evidence ID and
     `answered_at`;
   - scans path-shaped answer text into the inert passive registry under the
     response ID, which gives passive literals a response-owned origin (not built).

   The responses stay in memory through refresh and generation, and the run
   publishes them with its own publication (§25, ADR 0009): the complete output, the
   incomplete publication, or a cancel's. Generation reads the answer to a reference
   conflict through the answered reconciliation below, and no record cites a response
   ID. The run's report lists each accepted answer as the engine read it, with its
   response ID.
6. **A form left open**, unanswered or deferred, is not a failure. A deferral takes
   no account and records nothing; the record stays open and its form is rendered
   afresh. If a required record is still open after refresh, the run pauses again
   under the existing residual open-registry pause.
7. **A `cancel` with its reason** is a form of the run like a closed one: it is
   authenticated, its response is recorded and its record becomes
   `cancelled_by_user`, and the other valid forms are accepted with it. The run then
   ends `cancelled` before any model call, having published the forms, the actor
   evidence and the clarification state, and no specification, reference context or
   workflow state. An invalid form beside it blocks the run with nothing accepted
   (Decision 2).
8. **If the run fails, is blocked or is interrupted after acceptance**, it publishes
   nothing. The closed forms still name the current revisions, so the next run
   authenticates and accepts them again: running is the act of acceptance, and the
   user never answers twice. Responses that an earlier run published are reused
   without a second authentication (§24).

### The actor and the act of acceptance

- The actor is the operating-system account that the engine process runs as. A
  narrow system adapter reads it behind `AuthenticationPort`. It is the port's first
  provider, with one assurance level for the invoking account.
- Running Specify with valid closed forms is the act of acceptance. No confirmation
  argument, interactive prompt or configuration is involved.
- The runner issues one single-use authentication lease for each closed form that
  passed step 3, and `AuthenticateActorAction` consumes it. A stale or malformed
  submission is rejected before any lease is consumed, as §14.5 already requires
  for review submissions.
- The evidence records the provider, account, assurance level, run and trusted
  time. It holds no credential and no digest of the form. The accepted response is
  already the sole durable owner of the exact submitted bytes, and §23.2 forbids a
  second byte authority or fingerprint.

### The authentication contract

- **Where it runs.** After feature logging activates and before extraction, so the
  input checks and their `blocked` outcome come first and no model call has run.
  The chain loads the registry, plans the forms that await an account, observes the
  account once for each, then accepts them all in one stage that records the
  evidence and the responses together, so the registry and the responses cannot
  diverge.
- **The lease.** The runner alone issues a lease, one for each invocation of a step
  that declares the `actor_authentication` side effect and the `actor-authentication`
  capability, which come together. It issues it before the step runs, the port
  consumes it once before reading the account, and the runner ends it on every path
  of the step. A step that reports `ok` without having consumed it is rejected
  (`authentication_unconsumed`), and an execution issues at most one lease for each
  form it can accept (`authentication_lease_unavailable`). The step takes no
  retry, repair or accounting, and it runs on success paths only.
- **The observation.** The account is the operating-system account the process runs
  as, read behind `AuthenticationPort` by a narrow system adapter on Linux, macOS and
  the BSDs. Any other platform, an unreadable account or a failing clock is a typed
  failure that ends the run `failed`, since the user cannot fix it by editing
  forms. The time is the trusted log clock's UTC reading, which becomes the
  response's `answered_at`, and the run is the feature log's run.
- **The account name.** It must fit the one stored-identifier syntax: ASCII
  letters, digits and `-_.@`, at most 128 bytes. A name outside it is rejected with a
  typed outcome, never widened.

### The clarification subject

An accepted answer belongs to one record, and a rerun must name that record again for the same gap (design.md §3.3, item
31). The engine therefore derives a record's subject from its accounted evidence, the citations of the claims a need
concerns. No field the model fills in for the clarification, no per-run ID, no wording, no contract version and no hash
enters it. The claims, their citations and a signal's grouping are model output that the engine validated, so a subject
is stable only while they are (Limits this accepts).

- **The tuple.** `{requirement, unit, slot, sources}`. `requirement` and `slot` name the kind and slot of the authority
  requirement (`specification` and `content` for a generation need), and `unit` names the kind of unit with no ordinal.
- **The selector.** `sources` is the canonical list of the text the need is about: each source's normalized relative path
  in the reference directory, with the exact lines (one-based, inclusive) or the whole source. It is canonical when paths
  ascend, line ranges ascend within a path, and ranges that overlap or touch are one. The engine derives it from its own
  citations, so how a need's evidence was split into citations does not change it:
  - a records need names the lines cited by the claims of the signal the engine bound to the call;
  - an authority gap on a source names the whole source, and one on a signal, a conflict or a token names the lines its
    claims cite;
  - the feature, and the brief and entities units of a specification, name no text: each has one need, so their unit
    names them. A record or a decision, which no workflow owns yet, keeps its ordinal until its workflow is built.
- **One subject, one need.** The subject is the lines, so a claim quoted from inside a sentence's line is the same subject
  as the sentence. Two needs of one stage with one subject are an ambiguous subject, which the refresh rejects
  (`InvalidClarificationInput`; [§14.14](../contracts/14-orchestration.md#1414-authorityreconciliationorchestrator),
  [§24.3](../contracts/24-workflow-state.md#243-gate-behavior)).
- **The model's record family is not part of it.** A records clarification is a reason, a question and the closed `record_kind`
  it is about; every other step's names none. The engine validates the family (a records unit names one, never the entity,
  and no other unit names any) and never reads it for identity. It is an exception to the model supplying only what the
  engine needs (ADR 0006, AGENTS.md "Project authority"), kept by user decision on an inconclusive replay of the records
  call with and without the field ([Z_SPEC01](../../fixes/Z_SPEC01.md) "E7 stage 5 screen" holds the figures). Its accepted
  and rejected cases are the tests "the generation schema defines every record family and lets a
  clarification name each family the records step authors" (`src/specification_contract_test.zig`), "independent wire cases cover
  every selected specification result and nested content variant" (`src/model_candidate_json_test.zig`) and "a records
  clarification names the source text of its bound signal, and the other units name their unit"
  (`src/specification_generation_test.zig`), which also proves that every family names the same subject.
- **Bounds.** A subject names at most 128 spans (`max_subject_spans`). A need whose citations merge into more, or into
  none the corpus holds, is no subject: the builder fails with `InvalidSpecification` or `InvalidRequiredAuthority`.
- **Persistence.** `clarification-state/v4` carries the selector in each record's subject, and a v3 state, whose subjects
  match no current need, is rejected without a reader. The specification state binds the clarification state by ordinal
  and revision only, so it does not change.

### The answer to a conflict

A reference conflict is a gap that only the user can close, and the user closes it by choosing among its claims.

- **The form.** The need of a reference conflict is a select-one form with one option for each claim of the conflict. An
  option's key names the lines its claim cites (the source path with `/` as `.`, then `.<line>` or `.<first>-<last>`), so it
  is the same on every run over the same sources and no per-run ordinal names a claim. Its label is the claim's quotation.
  Two claims that cite the same lines, a key or label the form cannot hold, or more than 32 options are not a form: the run
  ends `blocked` with `InvalidRequiredAuthority`, and nothing is shortened or renamed. Only editing the sources recovers
  such a conflict; there is no fallback to a text answer (Decision 8). Every other gap is still answered in bounded text.
- **The answered reconciliation.** After the reconciliation is validated and before anything reads it, the engine applies
  each resolved choice. The chosen claim becomes retained and is given a signal of its own, the other claims of the conflict
  become superseded by it, and the conflict is dropped. The result is an ordinary reconciliation: every reconciliation rule
  holds for it, the persisted reference snapshot validates on readback, and generation, review, scenarios and rendering read
  the chosen claim as they read any retained claim. The engine applies the choice by its option key. No model reads the
  answer and no code judges its prose. The source text generation and scenarios receive leaves out the lines only the
  superseded claims cite ([§17](../contracts/17-specify.md)), since with them the model asked the decided question again.
- **What it applies to.** A conflict is answered only when every claim is a model claim of one kind and the claim the
  answer keeps is in no other conflict, whose disposition would then have to stay `conflicting`. A claim the answer
  supersedes may also be in another conflict, but only when that conflict is left with one claim, a model claim in no
  further conflict: the other conflict is then dropped too, and its last claim is retained with a signal of its own, as
  the chosen claim is. A conflict that would be left with no claim or with two or more stays,
  and the answer applies nothing, because its summary was written for claims it would no longer hold; so do two answers
  that change one conflict, and an answer that would drop a conflict the user also answered. The choice is matched by the conflict's subject (the lines) and by the option the form showed, its
  key and its label, so the text under the lines is the text the user chose. An answer whose option no claim of the conflict offers any
  more or offers under another quotation (the sources changed under a protected form), a key that two claims carry, an answer
  of another kind and an answer to any other gap apply nothing: the form stays protected and unused, and a rerun that raises
  the need again ends `blocked` with `ProtectedClarification` as before. If a rerun finds no such conflict at all (the model
  grouped the claims differently, which Limits this accepts), the choice is unused and the report does not say so.
- **What is not recorded.** No record cites the response. The published specification cites the chosen claim's lines, and
  the clarification state, published beside it, holds the response and its option key. A user who rejects every option
  cancels the form, which ends the run `cancelled` (flow, step 7).

### Persistence

- Evidence goes in the catalogue's actor-evidence registry, not in a store local to
  clarifications: `actor-evidence-registry/v1` at
  `<paths.workflows>/features/<feature>/state/actor-evidence.json`, beside the
  clarification state. Each response's `authentication_evidence_id` (`AE-<ordinal>`)
  references its registry entry, and the clarification state (`clarification-state/v4`)
  is valid only when every response joins an entry with the same account and time,
  each entry joined once. An entry no response names is tolerated: the registry is
  written before the state, so a run that stops between them leaves evidence and
  never a response without it. One revision appends all of a run's accepted forms.
  The registry records clarification responses only, and only Specify writes it
  (Decision 4).
- After acceptance, the closed form is protected byte-for-byte. A later edit to it,
  or its removal, blocks (§23.2).
- Upstream changes invalidate dependent responses through the ordinary rework
  contract. If a required subject can no longer use its answer, the engine
  preserves the form and response and blocks for explicit user direction (§23.2).
- Review treats a response as authority and never as a reference citation. A user
  answer never receives fabricated reference citations (§17.4). The answer to a conflict reaches review and generation as
  the answered reconciliation, not as a cited response.

### Limits this accepts

- It authenticates the account, not a person. Any process running as that account,
  including scripts and coding agents, can answer forms and run the engine.
- It does not show that the invoker wrote the answers. A valid edit by another
  process, or one merged from another branch, is accepted. The report of accepted
  answers is the check, and it comes after acceptance.
- The checks are strict: a selected option must be offered, and a text answer must
  fit its bound. A misread answer is therefore unlikely. But no option defines how to
  withdraw or revise an accepted response, so an answer the user regrets cannot be
  changed. That stays out of scope here.
- A subject is stable only while its inputs are. A claim's citation and a signal's grouping come from the model and are
  validated by the engine, so a rerun that draws another grouping of the same sources names another subject and mints another
  record. A source edited above a cited line moves its lines the same way. A protected answer on the earlier record then
  stays protected and unused, and the new form asks again.
- Gaps of one stage whose requirement kind, unit kind and slot agree and whose cited lines coincide, such as two signals
  over one line or two conflicts over the same lines, are one subject, and ordinals no longer keep them apart. A signal and
  a token never share one, since their requirement kinds differ. The authority
  builder consolidates them into one need, which §12.7 allows, and adds no new blocked reason. The need asks every
  distinct question, gives every distinct reason, binds the union of the gaps' authorities and cites the union of their
  evidence; the refresh still rejects two needs of one subject. One form therefore carries several questions and takes one
  answer. Two conflicts over the same lines offer the union of their options, once each, and a choice applies to the
  conflict whose claims carry its key; what an answer decides for each gap of any other merged form is open, since only a
  conflict's answer is applied (the answer to a conflict). A merged question or reason beyond the
  form's text bound, or authorities beyond a record's, ends the run `blocked` with `InvalidRequiredAuthority`, the
  builder's existing mapping (`clarification_refresh_workflow.zig`); nothing is truncated.

## Options considered and rejected

- **Confirmation argument.** Run 2 shows each parsed answer and a digest, then stops,
  and a third run passes the digest. It costs an extra run every round and protects
  little more: anyone who can edit the forms can also run the engine as that account
  and pass the printed digest. The digest would also be a second fingerprint of bytes
  the response already owns.
- **Interactive prompt in run 2.** It keeps one run, but needs a terminal-input
  adapter, and runs without a terminal (launchers, CI, agents) would fall back to an
  extra run. It still identifies the account, not a person.
- **Configured allowlist.** Configuration lists the accounts that may answer. It
  adds a configuration field and doesn't change who can edit the forms. It could
  later become an assurance policy if more than one account runs the engine.
- **Owner of the form file.** Ownership is easy to change, and it identifies
  neither who edited the file nor who ran the engine.
- **Signed answers.** This is strongest, but it needs key management and tooling
  that a local CLI does not have.
- **A subject keyed by a source's ordinal.** The ordinal is its position among the sorted paths, so adding a source that
  sorts earlier moves every later one, and an answer would attach to the wrong source. `validateQuestions` rejects only a
  question that copies source text, and does not check coordinates, so nothing else would catch it.
- **A subject keyed by a claim, signal, conflict or citation ID.** Each is a per-run ordinal, and §16 says a snapshot-local
  ID is not a clarification subject. A signal's claims also differ from run to run.
- **A subject keyed by a hash of the text.** §16 and §24 allow no fingerprint, and a hash names no source a reader can check.
- **A subject keyed by a model-picked record family.** It was the earlier rule. A rerun that picks another family mints
  another record, which is the failure this decision removes. The field itself stays in the model's schema (the subject
  section), outside the key.
- **Removing the field from the schema.** The engine does not need it, but the replay above found a lower claim coverage in
  hello-world without it, between requests that differed only in this field.

## Consequences

- New:
  - the invoking-account system adapter behind `AuthenticationPort`, with its
    provider and assurance-policy entries;
  - the catalogue's authentication chain and actor-evidence registry;
  - a typed rejection reason for each invalid form, replacing the single
    `InvalidClarificationInput` error, and a blocked outcome that reports them: the
    inputs stage names each rejected form with the rule it broke, the run ends `blocked`
    before any model call, and the CLI prints the outcome, its `InvalidClarificationInput`
    cause and one line for each form. Every workflow that uses `prepare-inputs` routes
    `blocked` to a blocked end, which `core.feature-input-read@1` allows;
  - response-owned passive literals (not built);
  - the answered reconciliation (`ApplyClarificationAnswersAction`), which the pipeline reads through
    `answered_reference_reconciliation_records`.
- Changed: refresh, provenance, the resolved-needs action, generation inputs,
  review authority and readback. The answered reconciliation replaces the changes to provenance, generation inputs and
  review authority for a conflict (Decision 7); they remain open for every other answer.
- Each change needs accepted and rejected tests, including:
  - every rejection reason;
  - valid and invalid forms together, which accepts none;
  - an unanswered or deferred form beside a valid one;
  - a protected form edited or removed after acceptance;
  - forged, duplicate or missing evidence;
  - a response that references evidence absent from the registry;
  - a run that fails after acceptance and publishes nothing, followed by a run that
    accepts the same forms again, and a run that reuses published responses;
  - a `cancel` beside an answered form, and a deferral.
- The actor-evidence registry is a new persisted state, and the specification and clarification states
  that changed with it have no compatibility readers.
- E2E coverage needs a clarification-expected case run twice, with the forms
  answered between the runs.

## Decisions

The sections above state each decision in full; other records cite these numbers.

1. The invoking account is the authenticated actor, and running Specify with valid
   closed forms is the act of acceptance, with no separate confirmation.
2. One invalid closed form stops the run, and none of the answers are accepted.
3. Evidence is recorded in the catalogue's shared actor-evidence registry.
4. The scope is Specify only. Plan- and tasks-stage clarifications are decided when
   those workflows are built.
5. A clarification's subject is the engine-derived source selector above, and the model's record family is not part of it.
6. The model's `record_kind` stays in the records response schema as a validated field the subject does not use, an
   exception recorded above.
7. The answer to a reference conflict is a choice among its claims, applied by the engine as an answered reconciliation, and
   no record cites a response. A chosen claim that stays conflicting, or a record that cites a response, cannot be
   validated on readback, because the persisted reference snapshot is checked against the reconciliation rules and the
   specification state binds the clarification state by ordinal and revision only. Answers to every other gap, and
   answer-derived passive literals, are not built.
8. Three decisions on the conflict form:
   - A conflict whose options cannot be built (two claims citing the same lines, a path character a key cannot hold, a key
     over 128 bytes) ends the run `blocked` with `InvalidRequiredAuthority`. There is no fallback to free text, which the
     project rules prohibit.
   - The runner's rule for a replacement's self-input covers the prior revision of any other key the same step replaced,
     while that key still holds what the step wrote, and the authentication progress is `execution_control`
     ([§12.8](../contracts/12-model-boundary.md#128-closed-authority-reconciliation-boundary)). Both exist so that a value
     derived from the accepted clarification inputs is current authority.
   - An offline scenario runs run 1 (the form), run 2 (the accepted choice), the authority gate, generation, publication
     and, in a rerun, the readback of the published state through the production composition. It scripts the model, so it
     proves the engine's chain and not the model's behaviour.
9. The harness answers a conflict form. It answers
   the form of a case that declares an answer: the case's `answers` is the user's input, written by the launcher as the user
   would, and the second leg's run is the act of accepting it under the invoking account. A launch of such a case is two
   legs, two run directories and two reports, under one approval and one attempted workload
   ([e2e.md](../harness/e2e.md#case-and-publication-contract)).
