---
name: preflight
description: Produce the AGENTS.md "Before editing" analysis for an SDDE engine change. It covers the observable outcome and non-goals; the owning abstraction; the governing design sections, invariants and acceptance criteria; affected producers, consumers and siblings; persistence, security, packaging and recovery impact; the causal defect or planned contract change; and expected files, tests and approvals. Use before any code, schema, configuration, test or architecture change in this repository.
argument-hint: <task or defect description>
---

# Preflight: $ARGUMENTS

Produce the analysis AGENTS.md requires before editing. Make no edits during this
skill.

1. **Classify the request.**
   - Engine development or engine execution? If it asks to run SDDE against a
     project, stop unless the target project and workflow are named explicitly.
   - Answer, review or plan only (read-only), or a change request?
   - A small, non-semantic documentation correction needs only a proportional note.
     Say so and stop.
2. **Collect authority.** Delegate to the `design-router` agent with the task text
   and any files or symptoms already known. Don't read whole contract files into this
   conversation.
3. **Find the owning abstraction.** Search the code for the contract involved: its
   type, validator or normalizer, action or runner, and YAML operation entry. List its
   producers, consumers, transitions, repair and recovery paths, and sibling
   implementations. State the general violated invariant, not only the symptom.
4. **Check known work.** Note any item in CLAUDE.md "Known failure classes and open
   work" that already covers this failure class, with its status and approval. A
   contract change follows that file's rules for deciding a contract change.
5. **Report** under the AGENTS.md "Before editing" headings:
   1. Observable outcome and explicit non-goals.
   2. Owning abstraction: the narrowest shared contract that owns the whole failure
      class.
   3. Governing authority: sections, invariants and acceptance criteria, with
      citations.
   4. Producers, consumers, transitions and siblings inspected.
   5. Persistence, security, packaging and recovery impact.
   6. Causal defect or planned contract change.
   7. Expected files; tests, with accepted and rejected cases and unrelated
      representatives of the failure class; validation commands; required approvals.
6. **Stop conditions.** If authority conflicts, a required decision is missing, or the
   correct fix needs an unapproved architecture change, report what AGENTS.md
   requires and stop:
   - the conflicting or missing authority;
   - the affected design sections and invariants;
   - why a local interpretation would be unsafe;
   - the smallest decision or scope change that would let work continue.

   Don't choose a convenient interpretation.

List the required approvals explicitly: production dependency changes, ADR or policy
changes, material scope expansion, and any live or E2E run. If none apply, write
"None".
