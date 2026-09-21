# 21. Deterministic validation catalogue

Part of the [proposed design](../design.md#21-deterministic-validation-catalogue). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

This catalogue is normative for the first engine version. A project may add validators or raise severity. It may not disable locked safety validators.

### 21.1 Cross-stage validators

| Validator | Method | Blocking condition | Repair owner |
| --- | --- | --- | --- |
| Config schema | JSON Schema plus semantic rules | Missing/unknown/invalid config | User/environment |
| Preset schema | JSON Schema, resource checks, placeholder rejection | Invalid/unresolved preset | User/environment |
| Environment resolution | Manifest adapters and root specificity | Zero/multiple project owners | User/environment |
| Stage order | Workflow state enum | Requested predecessor not complete | User/workflow |
| Artifact presence | Engine artifact registry and filesystem | Required artifact absent/unreadable | User/workflow |
| Predecessor validity | Reparse editable spec; load canonical generated state; compare deterministic views; run stage validators | Current predecessor no longer passes | Prior-stage repair |
| Path containment | Canonical path and symlink resolution | Escape/absolute/forbidden path | Usually not model-repairable; path field may be repaired only when otherwise safe |
| Model protocol | Exact runner-bound call association, then closed compact result schema | Unbound/stale observation or malformed result | Invalid association fails closed; malformed bound content follows only explicit YAML protocol retry/repair. |
| Placeholder | Template/model sentinel scan | Unresolved placeholder remains | Model atomic |
| Authority reconciliation | Closed required-slot ledger, current evidence, admitted gap and candidate-defect classification under §12.8.1 | Unresolved required authority or candidate/review defect | Shared §12.8.1 precedence: authorized candidate repair, terminal rejection, admitted earliest-owner clarification, upstream rework or administrative block |
| Publication boundary | Staged-set path and membership checks | Missing/extra/outside write | Engine/workflow |

### 21.2 Specify validators

| Validator | Deterministic rule | Semantic remainder |
| --- | --- | --- |
| Argument contract | Required non-empty `--feature` and `--reference`; reject duplicate, unknown and positional inputs | None |
| Feature directory | Exact supplied target; shared normalization, containment, archive exclusion and no-follow validation; no ownership lookup | Display title quality |
| Reference root | Configured-root containment, readable directory, no symlink escape | None |
| Reference accounting | Stable inventory equals processed-status inventory | Relevance of content |
| Reader support | MIME sniff plus installed reader | Meaning of decoded content |
| Citation | Source ID, bounds, and verbatim text exist | Whether citation proves claim |
| Required sections | Typed required fields and renderer contract | Whether prose is adequate |
| Requirement IDs | Engine-assigned type/uniqueness; stable surviving IDs and monotonic new IDs | Whether the requirement is substantively correct |
| Acceptance form | Exactly one nonempty typed `given`/`when`/`then` value; `spec.md` uses only the canonical compact `Given`/`When`/`Then` labels in that order | Whether scenario is truly testable |
| Clarification state | Only admitted needs reach forms; no unresolved typed clarification at success | Whether a proposed decision is genuinely absent and every ambiguity was discovered |
| Business-only lint | No obvious code/path/framework/CSS leakage | Nuanced business/technical classification |
| Exact-copy propagation | Byte-for-byte value from source ledger | Whether source copy is actually required |
| Visual-token propagation | Every required token ID/value rendered in sidecar | Semantic classification of required token |
| Reference conflict gate | Every candidate conflict has current subject-bound assessment; only admitted source conflicts reach questions | Whether the source meanings are incompatible; discovery of all semantic conflicts |

### 21.3 Plan validators

| Validator | Deterministic rule | Semantic remainder |
| --- | --- | --- |
| Repo-fact consistency | Typed fact ID/value exists in repository/preset facts | Prose relevance and design interpretation |
| Artifact manifest | Required/not-applicable enums match actual outputs | Whether applicability choice is wise |
| Project path | Full preset path algorithm | Whether a new file is justified |
| Existing touched area | File exists and has accepted ID/kind | Whether it is the minimal surface |
| Research record | Required fields and fact/source references exist | Quality of rationale/trade-off |
| Data-model integrity | Unique entities/fields; relationship targets resolve | Correct domain modeling |
| Contract syntax | Registered schema validator passes | Whether contract captures full intent |
| Quickstart integrity | Required typed steps plus real requirement/scenario/command IDs | Scenario adequacy unless executed |
| Coverage | Every obligation ID mapped; no unknown ID | Whether mapping is semantically sufficient |
| Visual obligation | Exact token appears in design and manual verification | Quality of chosen design |
| Scope | Only feature artifacts staged; no `tasks.md`/source writes | None |
| Progress | Phase/gate status derived from evidence | None |

### 21.4 Tasks validators

| Validator | Deterministic rule | Semantic remainder |
| --- | --- | --- |
| Task definition | Closed schema and allowed phase/kind/mode; no model-owned runtime status | Task wording/minimality |
| Source reference | Known obligation IDs only | Whether links are substantively correct |
| Executability | Concrete write, command, or manual scenario exists | Whether work will achieve desired result |
| Path authorization | Every path has `fileId`, plan authorization, preset pass | None |
| Test kind/placement | Preset root/name/extension/mapping | Test-case quality |
| Command availability | Known available command ID and typed arguments | Whether command is the best validation |
| Required checks | Preset evidence policy derives mandatory checks from task/file/diff | Whether optional extra checks add value |
| TDD evidence | Expected-red diagnostic is exact and same check is bound to a later green task | Whether the test captures all desired behavior |
| Dependency integrity | Known nodes, DAG, valid phase direction | Missing semantic dependencies |
| Parallel eligibility | No dependency/path/lock/command conflict | Hidden external shared resources not declared |
| ID/order/render | Engine topological order and gap-free `TNNN` | None |
| Coverage | Obligation-specific required task kinds exist | Semantic sufficiency of task content |
| No placeholder task | No placeholder values; typed executable operation | Overly vague but syntactically concrete wording |

### 21.5 Implement validators

| Validator | Deterministic rule | Semantic remainder |
| --- | --- | --- |
| Runnable task | Pending, dependencies complete, locks free | None |
| Change schema | Closed operation schema and current task ID | None |
| Write scope | Target belongs to declared task write set | None |
| Operation validity | Create/update/replace/copy/delete state matches filesystem and policy | None |
| Copy source | Engine source ID, provenance, media type, size, and permission pass | Whether copied code is the best design choice |
| Patch scope/apply | Patch affects one declared target and applies | Whether change is desirable |
| Filename/path | Full preset path algorithm | Filename meaningfulness within valid rules |
| Source parse | Configured parser accepts code | Runtime behavior |
| Language semantic name | Configured Java/type/namespace rules | Domain naming quality |
| Import resolution | Resolver finds allowed targets | Architectural appropriateness where not mechanically encoded |
| Manifest/dependency | Declared package/project and configured validator | Necessity/security suitability of dependency |
| Tool checks | Exit code/output from formatter, compile, lint, test | Coverage of untested behavior |
| Unexpected change | Overlay delta subset of authorized writes | None |
| Command effects | Post-command delta subset of task plus declared command effects | None |
| Evidence | All task evidence predicates satisfied | Manual observation when required |
| Completion | Commit plus evidence plus status persistence | None |

### 21.6 Validators that must not be overstated

The following remain LLM-assisted or human-reviewed unless an executable/domain-specific rule exists:

- whether a requirement is completely testable and unambiguous;
- whether every behavior was extracted from arbitrary prose, images, or diagrams;
- whether two arbitrary references conflict semantically;
- whether a specification introduced an unsupported but plausible behavior;
- whether a plan is truly the smallest viable implementation;
- whether a task is optimally sized;
- whether code fully satisfies intent beyond executable assertions;
- subjective visual quality beyond exact token/layout checks.

The engine records such findings with their real evidence class.
