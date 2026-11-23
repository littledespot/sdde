# ADR 0025: Accept valid clarification answers in the run that reads them

- **Status:** Accepted amendment. The authentication chain, the actor-evidence registry, acceptance, publication and the
  valid cancel are implemented. Generation's use of accepted answers, and the response-owned passive literals, are not
  ([SPEC01 E7](../../fixes/SPEC01.md#e7-clarification-answer-recovery-r2-adr-0025)).
- **Date:** 2026-10-20, rewritten and accepted 2026-10-21
- **Decision authority:** The user's decisions of 21 October 2026. The user first
  asked for the proposal to be rewritten around this flow: run 1 generates
  clarifications; the user reviews and answers them; run 2 parses the answered forms
  and continues if they pass, or stops with the reason and the missing information
  if they fail. The user then approved the actor rule: "Whoever runs run 2 is
  treated as the person answering. Running it means 'I accept these answers.' The
  engine records your computer account name ... next to each answer and carries
  on." Finally the user answered "yes to all" to the other three decisions below.
  The approval covers clarification answers. It does not choose the provider for
  plan or task review approvals.
- **Amends:**
  - §17.4, by defining the authenticated actor and the act of acceptance;
  - the §13 catalogue, by giving `AuthenticateActorAction`'s `AuthenticationPort`
    its first provider, and by making `ValidateClarificationUserSubmissionAction`
    report a typed reason for each rejected form;
  - F0100 §3.2, by selecting its authentication mechanism.

  It leaves §23.2's protection of user-closed forms, ADR 0017's incomplete
  publication and ADR 0009's fresh-invocation rule unchanged. The overall design
  remains **Proposed design**.

## Problem

§17.4 requires every closed clarification form to be "associated with an
authenticated actor" before its answer can become authority. Nothing defines who
that actor is or how the engine knows. The §13 catalogue defines the chain that
would record it, from `ValidateClarificationUserSubmissionAction` through
`AuthenticateActorAction`, the actor-evidence registry actions,
`BindAuthenticatedClarificationSubmissionAction` and
`BuildClarificationResponseAction`. It names no provider behind
`AuthenticationPort`, and none of the chain is implemented, so fresh answers cannot
complete the registered recovery path. SPEC01 E7 lists where each one stops.

The clarification state already persists each response with its clarification ID,
input state and record revisions, exact submitted form bytes, typed answer,
`actor_id`, `authentication_evidence_id` and `answered_at`
(`src/domain/clarification_inputs.zig`). What is missing is the trusted source for
`actor_id` and its evidence, and the lifecycle that consumes them.

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
     response ID, which gives passive literals a response-owned origin.

   The responses stay in memory through refresh and generation, and the run
   publishes them with its own publication (§25, ADR 0009): the complete output, the
   incomplete publication, or a cancel's. Generation cites current resolved response
   IDs as authority. The run's report lists each accepted answer as the engine read
   it, with its response ID.
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

### Persistence

- Evidence goes in the catalogue's actor-evidence registry, not in a store local to
  clarifications: `actor-evidence-registry/v1` at
  `<paths.workflows>/features/<feature>/state/actor-evidence.json`, beside the
  clarification state. Each response's `authentication_evidence_id` (`AE-<ordinal>`)
  references its registry entry, and the clarification state (`clarification-state/v3`)
  is valid only when every response joins an entry with the same account and time,
  each entry joined once. An entry no response names is tolerated: the registry is
  written before the state, so a run that stops between them leaves evidence and
  never a response without it. One revision appends all of a run's accepted forms.
  Specification edits (§18), user review (§14.5) and reference feedback use the same
  registry.
- After acceptance, the closed form is protected byte-for-byte. A later edit to it,
  or its removal, blocks (§23.2).
- Upstream changes invalidate dependent responses through the ordinary rework
  contract. If a required subject can no longer use its answer, the engine
  preserves the form and response and blocks for explicit user direction (§23.2).
- Review treats a response as authority and never as a reference citation. A user
  answer never receives fabricated reference citations (§17.4).

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

## Consequences

- New:
  - the invoking-account system adapter behind `AuthenticationPort`, with its
    provider and assurance-policy entries;
  - the catalogue's authentication chain and actor-evidence registry;
  - a typed rejection reason for each invalid form, replacing the single
    `InvalidClarificationInput` error, and a blocked outcome that reports them. Both are
    built (22 November 2026): the inputs stage names each rejected form with the rule it
    broke, the run ends `blocked` before any model call, and the CLI prints the outcome,
    its `InvalidClarificationInput` cause and one line for each form. Every workflow that
    uses `prepare-inputs` routes `blocked` to a blocked end, which `core.feature-input-read@1`
    now allows;
  - response-owned passive literals.
- Changed: refresh, provenance, the resolved-needs action, generation inputs,
  review authority and readback.
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
- `specification-state` and the clarification state version advance, and the
  actor-evidence registry is a new persisted state, with no compatibility readers.
- E2E coverage needs a clarification-expected case run twice, with the forms
  answered between the runs.

## Decisions

The user approved all four on 21 October 2026.

1. The invoking account is the authenticated actor, and running Specify with valid
   closed forms is the act of acceptance, with no separate confirmation.
2. One invalid closed form stops the run, and none of the answers are accepted.
3. Evidence is recorded in the catalogue's shared actor-evidence registry.
4. The scope is Specify only. Plan- and tasks-stage clarifications are decided when
   those workflows are built.
