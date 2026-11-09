#!/usr/bin/env python3
"""Where does PatchEval time go after the fix? Reads BenchKit results.json files (pi harness).

Per task: minute of the first source edit, minute the agent's own pytest run first came back all green after an
edit, end minute, and what the agent did after that first green run (tool calls by kind, edits, output tokens).
Tool call i follows upstream call i (pi: one tool call per model turn), so its time is that call's start + duration.
Usage: python3 -I patcheval-after-fix.py results/DIR [results/DIR ...]  [--tsv OUT]
"""
import json, re, sys, collections

PASS_RE = re.compile(r"\b(\d+) passed\b")
BAD_RE = re.compile(r"\b(\d+) (failed|error|errors)\b|Error|Traceback|FAILED|ERROR")


def kind(t):
    n = t["name"]
    if n in ("edit", "write"):
        return "edit"
    if n == "read":
        return "read"
    c = t["arguments"].get("command", "")
    if "pytest" in c:
        return "test"
    if re.search(r"\b(ruff|mypy|flake8|pylint|black|isort|pre-commit)\b", c):
        return "lint"
    if re.search(r"\bgit (diff|status|log|show|stash)\b", c):
        return "git"
    if re.search(r"python3? -c|python3? - <<|python3? \S+\.py|cat > |<<'?EOF", c):
        return "script"
    if re.search(r"^\s*(cd [^&]+&&\s*)?(grep|rg|sed -n|cat|head|tail|ls|find|wc|awk)\b", c):
        return "read"
    if re.search(r"\b(sed -i|perl -pi|patch|apply)\b", c):
        return "edit"
    return "other"


def green(t):
    out = t.get("output") or ""
    return kind(t) == "test" and PASS_RE.search(out) and not re.search(r"\b\d+ (failed|errors?)\b", out)


def analyse(task):
    tt, up = task.get("tool_trace") or [], task.get("upstream_calls") or []
    if not tt:
        return None
    end_s = task["response_time_s"]
    if up:
        t0 = up[0]["started"]
        times = [(up[i]["started"] + (up[i].get("total_s") or 0) - t0) / 60 if i < len(up) else end_s / 60 for i in range(len(tt))]
    else:  # older runs: no per-turn times, so estimate by the share of tool calls done (marked est)
        times = [(i + 1) / len(tt) * end_s / 60 for i in range(len(tt))]
    first_edit = next((i for i, t in enumerate(tt) if kind(t) == "edit"), None)
    first_green = next((i for i, t in enumerate(tt) if first_edit is not None and i > first_edit and green(t)), None)
    end = task["response_time_s"] / 60
    after = collections.Counter(kind(t) for t in tt[first_green + 1:]) if first_green is not None else collections.Counter()
    tok_after = sum((u.get("completion_tokens") or 0) for u in up[first_green + 1:]) if first_green is not None else 0
    tok_all = sum((u.get("completion_tokens") or 0) for u in up)
    src_after = 0
    if first_green is not None:
        for t in tt[first_green + 1:]:
            if kind(t) == "edit":
                p = t["arguments"].get("path") or t["arguments"].get("command", "")
                if not re.search(r"(^|/)tests?/|test_|_test\.py|\.md\b|CHANGELOG|docs/|/tmp/", p):
                    src_after += 1
    return dict(task=task["task_id"], outcome=task["outcome"], done=task["done_reason"] + ("" if up else " est"), end=end,
                edit=times[first_edit] if first_edit is not None else None,
                green=times[first_green] if first_green is not None else None,
                calls=len(tt), after=after, src_after=src_after, tok_after=tok_after, tok_all=tok_all)


def main(argv):
    out = None
    if "--tsv" in argv:
        i = argv.index("--tsv"); out = argv[i + 1]; argv = argv[:i] + argv[i + 2:]
    rows = []
    for d in argv:
        for job in json.load(open(f"{d}/results.json")):
            label = job.get("variant") or d
            for task in job["tasks"]:
                a = analyse(task)
                if a:
                    a["run"] = d.rstrip("/").split("/")[-1]; rows.append(a)
    f = lambda v: "-" if v is None else f"{v:5.1f}"
    kinds = ("test", "edit", "read", "script", "lint", "git", "other")
    hdr = "run\ttask\toutcome\tdone\tfirst_edit_min\tfirst_green_min\tend_min\tmin_after_green\tcalls\t" + "\t".join(f"after_{k}" for k in kinds) + "\tsrc_edits_after\ttok_after\ttok_all"
    lines = [hdr]
    for a in rows:
        ag = (a["end"] - a["green"]) if a["green"] is not None else None
        lines.append("\t".join([a["run"], a["task"], a["outcome"], a["done"], f(a["edit"]), f(a["green"]), f(a["end"]), f(ag), str(a["calls"])]
                               + [str(a["after"].get(k, 0)) for k in kinds] + [str(a["src_after"]), str(a["tok_after"]), str(a["tok_all"])]))
    print("\n".join(lines))
    if out:
        open(out, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
