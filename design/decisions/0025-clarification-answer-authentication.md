# ADR 0025: Authenticate clarification answers before they become authority

- **Status:** Proposed. It needs the user's decision before any implementation.
- **Date:** 2026-10-20
- **Decision authority:** None yet. The user asked for a proposal rather than code
  (20 October 2026).
- **Would amend:** Design §17.4 and the clarification sections of §§23.2 and 24, and
  F0100's clarification lifecycle. It would leave ADR 0017's incomplete
  publication and ADR 0009's fresh-invocation rule unchanged. The overall design
  remains **Proposed design**.

## Problem

§17.4 requires every closed clarification form to be "associated with an
authenticated actor" before its answer can become authority. Nothing defines who
that actor is or how the engine knows. Fresh answers therefore cannot complete the
registered recovery path:

- refresh rejects every new nonempty submission with `AuthenticationRequired`
  (`src/domain/clarification_refresh.zig`);
- specification provenance rejects nonempty clarification-response IDs
  (`src/domain/specification_provenance.zig`);
- workflow preparation validates forms but never authenticates answers, and the
  resolved-needs action constructs empty needs;
- generation never consumes accepted answers;
- passive literal origins are source-only (`src/domain/passive_literals.zig`).

The stored shape already exists. The clarification state persists each response
with its clarification ID, input state and record revisions, exact submitted form
bytes, typed answer, `actor_id`, `authentication_evidence_id` and `answered_at`
(`src/domain/clarification_inputs.zig`). What is missing is the trusted source for
`actor_id` and its evidence, and the lifecycle that consumes them.

## Constraints

- A form file is untrusted project data. Editing it proves nothing about who
  edited it, and a closed form is not an authenticated answer.
- Explicit human approvals own workflow authority, and approvals bind to exact
  current state IDs (AGENTS.md).
- A user answer never receives fabricated reference citations (§17.4); it is its
  own authority with response provenance.
- A fresh invocation starts at `start` (ADR 0009). Answers are published before
  refresh, and accepted responses are preserved (§23.2).
- The engine is a local native CLI. It has no identity provider or network
  account.

## Options for the trusted authentication source

### A. Invocation-bound confirmation (recommended)

The user confirms the closed answers in the invocation that consumes them.

- On a run that finds closed forms, the engine parses each one and prints its
  clarification ID, the answer as parsed and a digest of the form bytes, the state
  revision and the invocation.
- The run consumes the answers only when the invocation carries an explicit
  confirmation of exactly that set: a CLI argument naming the current clarification
  state revision and the answer digest. Otherwise it pauses again with a typed
  "confirmation required" outcome, and nothing is published.
- `actor_id` is the operating-system account of the invoking process, read through
  a narrow system adapter. `authentication_evidence_id` is the confirmation digest,
  so any change to a form after confirmation invalidates it.

This binds each answer to a deliberate act by whoever runs the engine, against
exact current state, as plan and task approvals already require. Its limit: it
authenticates the invoking account, not a person, so anyone who can run the engine
as that account can answer.

### B. Configured actor allowlist

Configuration lists the accounts that may answer, and the invoking OS account must
be on it. No per-run confirmation is needed. It is simpler to use but weaker,
because an edited form is consumed without a deliberate confirmation, and it adds a
configuration field.

### C. Operating-system owner of the form file

The owner of the edited form is the actor. This is the simplest option and the
weakest: anyone with write access can answer, and ownership is easy to change. It
does not satisfy "a closed form is not an authenticated answer".

### D. Signed answers

Answers carry a signature from a key the user controls. This is strongest, but it
needs key management and tooling that a local CLI does not have. It is out of scope
for the initial suite.

## Persistence model (recommended)

Keep the existing clarification state as the single store, with no second ledger.

1. Parse each closed form against the last committed clarification and reference
   binding. Reject stale revisions, schema mismatches and empty closes; `defer`
   stays open, and `cancel` cancels the run.
2. Authenticate it under the chosen option, then append one response with its
   `actor_id`, evidence, `answered_at` and the exact form bytes.
3. Scan path-shaped answer text into the inert passive registry under the response
   ID, which gives passive literals a response-owned origin.
4. Publish the complete response before refresh, as §17.4 requires.
5. Refresh, then let generation cite current resolved response IDs as authority.
   Provenance accepts response IDs that resolve to current responses. Review treats
   a response as authority and never as a reference citation.
6. Upstream changes invalidate dependent responses through the ordinary rework
   contract. A changed reference never carries a stale response.

## Consequences if accepted

- New: a system adapter for the invoking account, a confirmation argument and its
  typed outcome, and response-owned passive literals.
- Changed: refresh, provenance, the resolved-needs action, generation inputs,
  review authority and readback. Each change needs accepted and rejected tests,
  including forged evidence, stale revisions, an edited form after confirmation,
  and a replayed confirmation in a later invocation.
- `specification-state` and the clarification state version advance, with no
  compatibility readers.
- E2E coverage needs a clarification-expected case with two invocations.

## Decision needed

1. Which authentication source: A (recommended), B, C or D.
2. Whether the persistence model above is accepted as written.
3. Whether answers may also resolve plan- and tasks-stage clarifications now, or
   whether the scope stays Specify-only until those workflows exist.
