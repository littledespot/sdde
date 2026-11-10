---
name: preflight
description: Produce the AGENTS.md "Before editing" analysis for an SDDE engine change, naming its owning abstraction, governing authority, causal defect, and expected files, tests and approvals. Use before any code, schema, configuration, test or architecture change in this repository.
argument-hint: <task or defect description>
---

# Preflight: $ARGUMENTS

Produce the analysis AGENTS.md "Before editing" requires. Make no edits during this
skill.

1. **Classify the request.**
   - A request to run SDDE against a project: stop unless it names the target project
     and workflow.
   - An answer, review or plan request is read-only; a change request needs the
     analysis.
   - A small non-semantic documentation fix needs none. Say so and stop.
2. **Collect authority.** Give the `design-router` agent the task text and any files
   or symptoms already known. Don't read whole contract files into this conversation.
3. **Find the owning abstraction.** Search the code for the contract involved: its
   type, validator or normalizer, action or runner, and YAML operation entry. List its
   producers, consumers, transitions, repair and recovery paths, and sibling
   implementations. State the general invariant that is violated, not only the
   symptom.
4. **Check decisions.** Check the accepted ADRs and the open-work records under
   `fixes/` for a rule the change would break, or a decision that already covers this
   failure class. Name the published-output defect class the change should reduce
   (AGENTS.md "Model output, prompts and evidence").
5. **Report** under the seven AGENTS.md "Before editing" headings, in order. Under
   the seventh, list the tests with their accepted and rejected cases and an unrelated
   member of the failure class, the validation commands, and each approval needed: a
   production dependency change, an ADR or policy change, a material scope expansion,
   or a live run. Write "None" if no approval is needed.
6. **Stop conditions.** If authority conflicts, a decision is missing or the fix
   needs an unapproved architecture change, stop and report what AGENTS.md "Project
   authority" requires.
