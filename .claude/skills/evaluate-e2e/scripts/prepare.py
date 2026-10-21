"""Offline preparation for /evaluate-e2e. Run from the repository root with python3 -I.

  prepare.py number <run>/report.json <output-dir>
      Write the run's captured rubric (rubric.json) and line-numbered copies of its
      captured sources and specification.
  prepare.py panel <spec.case.json> <output-dir>
      Verify a calibration panel's hashes and write numbered verified sources and
      blind specimen copies. Prints no label or specimen path; key.json maps opaque
      names back to specimens.
"""
import hashlib
import json
import os
import random
import re
import sys

NUMBERED = ".numbered.txt"


def numbered(text):
    """Number lines as the rubric-judgment contract does: CR, LF and CRLF each end a
    line, a final terminator starts no extra line, empty text has no lines, and
    lines are 1-based."""
    if not text:
        return ""
    lines = re.split(r"\r\n|\r|\n", text)
    if text.endswith(("\n", "\r")):
        lines = lines[:-1]
    return "".join(f"{n:4d}  {line}\n" for n, line in enumerate(lines, 1))


def write(path, text):
    with open(path, "w", encoding="utf-8") as out:
        out.write(text)


def number(report_path, out):
    inputs = json.load(open(report_path, encoding="utf-8")).get("evaluation_inputs")
    if inputs is None:
        sys.exit("No evaluation_inputs: this run has no completed specification.")
    os.makedirs(out, exist_ok=True)
    write(os.path.join(out, "rubric.json"), json.dumps(inputs["rubric"], indent=2, ensure_ascii=False) + "\n")
    for doc_id, text in [(s["id"], s["text"]) for s in inputs["sources"]] + [("specification", inputs["specification"])]:
        write(os.path.join(out, doc_id + NUMBERED), numbered(text))
    print(f"Wrote the captured rubric and {len(inputs['sources']) + 1} numbered documents in {out}")


def read_bytes(path):
    try:
        return open(path, "rb").read()
    except OSError:
        return None


def sha(data):
    return hashlib.sha256(data).hexdigest()


def checked(entries, path_of, label, problems):
    """Return (entry, path, bytes) for entries whose file matches its sha256, and add
    a label for every other entry to problems."""
    matched = []
    for n, entry in enumerate(entries, 1):
        path = path_of(entry)
        data = read_bytes(path) if path else None
        if data is not None and sha(data) == entry["sha256"]:
            matched.append((entry, path, data))
        else:
            problems.append(label(n, entry))
    return matched


def verified(case, selected):
    """Return hash-verified sources and specimens, or exit naming problems by panel
    position only, because specimen paths reveal verdicts."""
    paths = {source["id"]: source["path"] for source in case["sources"]}
    rubric = read_bytes(case["rubric"])
    problems = [] if rubric is not None and sha(rubric) == selected["rubric_sha256"] else ["rubric"]
    sources = checked(selected["sources"], lambda s: paths.get(s["id"]), lambda n, s: f"source {s['id']}", problems)
    specimens = checked(selected["specimens"], lambda s: s["path"], lambda n, s: f"specimen {n}", problems)
    if not problems and {entry["id"] for entry, _, _ in sources} != set(paths):
        problems.append("case sources not covered by the panel")
    if problems:
        sys.exit(f"Hash mismatch or unreadable input: {', '.join(problems)}. Stop; the panel no longer matches its inputs.")
    return {entry["id"]: data for entry, _, data in sources}, [(path, data) for _, path, data in specimens]


def panel(case_path, out):
    case = json.load(open(case_path, encoding="utf-8"))
    selected = json.load(open(case["grading_qualification"]["panel"], encoding="utf-8"))
    sources, specimens = verified(case, selected)
    blind = os.path.join(out, "blind")
    os.makedirs(blind, exist_ok=True)
    for source_id, data in sources.items():
        write(os.path.join(blind, source_id + NUMBERED), numbered(data.decode("utf-8")))
    # Blinding order, not security: an unpredictable shuffle hides panel order.
    random.SystemRandom().shuffle(specimens)
    key = {}
    for n, (path, data) in enumerate(specimens, 1):
        name = f"specimen-{n:02d}"
        write(os.path.join(blind, name + NUMBERED), numbered(data.decode("utf-8")))
        key[name] = path
    write(os.path.join(out, "key.json"), json.dumps(key, indent=2))
    print(f"Hashes match; wrote {len(specimens)} blind specimens and {len(sources)} numbered sources in {blind}")


if __name__ == "__main__":
    commands = {"number": number, "panel": panel}
    if len(sys.argv) != 4 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](sys.argv[2], sys.argv[3])
