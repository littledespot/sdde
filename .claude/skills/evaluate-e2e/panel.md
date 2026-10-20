# Calibration mode: `--panel <spec.case.json>`

Calibration mode checks whether this skill tells good specimens from bad ones, before
you trust its findings on a run. It is not grader qualification under
[acceptance.md](../../../design/harness/acceptance.md).

`panel.json` stores each specimen's label next to its hash, and the specimen file
names give away the verdicts. Don't read either before you have scored.

1. Prepare blind copies:

   ```sh
   python3 -I .claude/skills/evaluate-e2e/scripts/prepare.py panel <spec.case.json> evaluations/panels/<case id>
   ```

   The script checks the rubric, source and specimen hashes. It writes numbered
   sources and `blind/specimen-NN.numbered.txt`. It prints no label or path, even on
   errors. If it reports a mismatch or an unreadable input, report that and stop.
2. Score every blind specimen from its content alone, using steps 2–4 of section 2
   in [SKILL.md](SKILL.md). Score against the case's rubric and the numbered
   sources; the script has verified both against the panel's hashes. Don't open
   `key.json`, `panel.json`, `README.md` or `REVIEW.md` yet. Record every score
   before continuing.
3. Then read `key.json` and the labels. Report pass/fail agreement for each specimen,
   and the confusion counts. Never revise a score after seeing a label. State every
   disagreement plainly, because each one shows where this evaluation is unreliable.

Write the results to `evaluations/panels/<case id>/`, in the formats from section 6
of SKILL.md.
