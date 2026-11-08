#!/usr/bin/env python3
"""Merge BenchKit PatchEval results into reports/patcheval-data.json, one entry per arm.

Arms (setups) and their result folders are listed in reports/patcheval-arms.json.
Run:  python3 reports/build_patcheval_data.py && python3 reports/make_patcheval_report.py
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
RESULTS = HERE.parent / "data" / "benchkit-results"  # repo layout
if not RESULTS.exists():
    RESULTS = HERE.parent / "benchkit-src" / "BenchKit" / "results"  # working directory with a BenchKit clone
KEEP = (
    "task_id", "outcome", "passed", "response_time_s", "output_tokens", "input_tokens",
    "tok_s", "model_turns", "tool_calls", "length_exceeded", "timed_out",
    "call_usage", "upstream_calls",
)  # fmt: skip


def load(run: str) -> dict:
    path = RESULTS / run / "results.json"
    jobs = [j for j in json.loads(path.read_text()) if j.get("benchmark") == "patcheval"]
    if not jobs:
        raise SystemExit(f"{path}: no patcheval job")
    return jobs[0]


def main() -> None:
    config = json.loads((HERE / "patcheval-arms.json").read_text())
    regrade_path = HERE / "patcheval-regrades.json"
    regrades = json.loads(regrade_path.read_text())["regrades"] if regrade_path.exists() else []
    out: dict = {}
    order: list[str] | None = None
    for arm in config["arms"]:
        tasks: dict[str, dict] = {}
        total_time = 0.0
        for run in arm["dirs"]:
            job = load(run)
            total_time += float(job.get("total_time") or 0)
            for task in job["tasks"]:
                tid = task["task_id"]
                old = tasks.get(tid)
                if old and not (old["outcome"] == "harness_error" != task.get("outcome")):
                    continue  # keep the first real result; a later one only replaces a harness error
                tasks[tid] = {k: task.get(k) for k in KEEP} | {"run": run}
            if order is None and len(job["tasks"]) == 20:
                order = [t["task_id"] for t in job["tasks"]]
        for rg in regrades:
            if arm["key"] in rg["arms"] and rg["task"] in tasks:
                task = tasks[rg["task"]]
                if task["outcome"] != rg["outcome"]:
                    task["outcome_original"] = task["outcome"]
                    task["outcome"] = rg["outcome"]
                    task["passed"] = rg["outcome"] == "pass"
                    task["regraded"] = rg["reason"]
        meta = {k: v for k, v in arm.items() if k not in ("key", "dirs")}
        out[arm["key"]] = meta | {"dirs": arm["dirs"], "tasks": tasks, "total_time": total_time}
        orig = sum(t.get("outcome_original", t["outcome"]) == "pass" for t in tasks.values())
        print(f"{arm['key']:12} {sum(t['outcome'] == 'pass' for t in tasks.values())}/{len(tasks)} (original {orig})")
    out["_order"] = order or sorted({t for a in out.values() for t in a["tasks"]})
    out["_arms"] = [a["key"] for a in config["arms"]]
    out["_regrades"] = regrades
    (HERE / "patcheval-data.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print(HERE / "patcheval-data.json")


if __name__ == "__main__":
    main()
