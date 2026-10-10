# Phase 1 presentation comparison — gate failed

Executed on **10 October 2026, 09:27–09:31 UTC**, under the user's explicit
12-call approval. All **12/12** calls completed, with no retries, corrections,
repairs, model judges or E2E execution. The approval is consumed. The production
presentation remains unchanged.

[Scorecard](scorecard.json) contains every parsed response, native attribution,
semantic assessment, identifiers, normalization, usage and timing. The immutable
[execution ledger](../../../../../zig-out/source-loss-presentation-comparison/2026-10-10T09-27-32Z/results/execution.json)
and adjacent files retain the actual requests, raw provider bodies, native reports
and offline-check logs. The frozen [manifest](comparison.json) and unscored
[template](scorecard.template.json) remain unchanged.

## Result against the frozen gate

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| Completed / schema admitted / native admitted | 6/6 each | 6/6 each |
| Correct attribution with adequate explanation | 1/6 | 2/6 |
| Captured greeting story correct | 1/2 | 0/2 |
| Unrelated loan story correct | 0/2 | 0/2 |
| Genuine story-role loss correct | 0/2 | 2/2 |
| False upstream attribution, including false role loss | 5 | 3 |
| False candidate attribution | 0 | 0 |
| Unnecessary unresolved attribution | 0 | 1 |
| Input tokens | 10,470 | 9,122 |
| Output tokens | 2,030 | 2,004 |
| Median replay round trip | 1,556 ms | 1,592.5 ms |

The candidate exceeded baseline by one correct trial, but failed the required
**6/6 correct and adequately explained responses**, **zero false attribution**
and **no paired-case regression** conditions. Its improvement on genuine role
loss does not justify accepting failures on complete upstream collections.

The 23,626 total tokens remained below the frozen 100,000-accounted-token stop.
All actual provider requests matched their frozen bodies; all 31 pinned hashes
were checked before dispatch and before each trial. Each response passed the
existing `Source.admitComparisons` path through
`zig build test-specification-generation --summary all` (**288/288** each run).
These tests establish admission mechanics, not semantic correctness.

## What the responses demonstrate

1. **Representation still gets mistaken for meaning.** Both greeting and loan
   comparison 2 contain member 2 explicitly requiring the display literal.
   Candidate greeting repetition 1 nevertheless says that the collection omits
   `Hello, World!`; both loan repetitions say the confirmation text is missing.
   The absent element is a *separate literal-only member*, not the obligation.
   Native code admits the supplied references and derives false story-role loss.
2. **A final-field requirement still contaminates upstream review.** Candidate
   greeting repetition 2 demands an actor/action/result narrative from the
   upstream collection, despite instructions not to require final-field form.
   It also introduces confirmation of startup as a required result. Both
   collections already express the display behavior. Native attribution remains
   unresolved rather than selecting a unique upstream repair, but the judgments
   are still wrong.
3. **The allegation can be mistaken for the obligation.** Both baseline
   wrong-role trials say the extraction collection should express that the story
   *omits* notification. The collection correctly requires notification; the
   downstream omission is the premise of diagnosis, not the meaning to preserve.
   Both candidate trials correctly distinguish preserved extraction from loss
   in the story's assigned role collection.

These are observations from returned explanations and supplied evidence. They
identify failure classes; they do not establish the model's internal cause or
prove that one removed field reliably causes either improvement or regression.
The same baseline captured request produced one correct and one incorrect trial.

## Decision and remaining work

**Do not promote this one-field removal.** Request size decreased, but the
experiment did not demonstrate acceptable semantic attribution. Keep the existing
schema, shared admission and repair permissions. Do not default to candidate
repair when comparisons are incorrect or unresolved.

Phase 1's experiment and assessment are complete; its candidate-selection goal
is unmet. Phase 2's independent rejection reporting and Phase 4's offline recovery
integration remain implemented. Their production-presentation, qualification and
live output gates remain open. The conditional greeting E2E approval remains
unused because Phase 3 has not passed.

Before further implementation, select and freeze a new bounded investigation:
for example, test the plan's unchanged-input effort comparison, or investigate a
shared way to distinguish the missing obligation from the finding's allegation
without inventing semantic authority in native code. This comparison does not
select either approach, authorize additional calls, or justify another prompt
change by itself. FIX02's independent assessment binding remains relevant only
if controlled evidence supports changing the assessment configuration.

## Limits

Assessment was an **unblinded manual review by the coding agent** of all responses
against frozen sources and comparison members. Three development cases and two
repetitions do not estimate general reliability. No model judges were called.
Every response used the existing Bedrock `removed_leading_brace_quote`
normalization; none required a second request. Provider latency was unavailable,
so the table uses measured replay round trip, excluding offline checks. The
response-body chat-completion ID and engine call/run IDs are retained; the
debugger export exposes no HTTP AWS request ID. Seed/top-p were absent, and
provider cache behavior was not controlled. The diagnostic workspace was scanned
for the credential and debugger-session token with no matches; its server was
terminated after execution.
