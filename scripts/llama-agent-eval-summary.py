#!/usr/bin/env python3
"""Summarise llama-agent-eval-<label>.jsonl files: pass rate, tool-call health, tokens, time, TG, MTP.

Usage: python3 llama-agent-eval-summary.py q2_0 coder gsq-iq3xxs
"""
import collections
import json
import sys

DIR = "/home/sum/Downloads/AI-Runtime"


def load(label):
    return [json.loads(l) for l in open(f"{DIR}/llama-agent-eval-{label}.jsonl")]


def summary(label):
    rows = load(label)
    n = len(rows)
    tok = sum(r["completion_tokens"] for r in rows)
    gen = sum(r["gen_s"] for r in rows)
    acc, drafted = sum(r["draft_acc"] for r in rows), sum(r["draft_n"] for r in rows)
    return {
        "label": label, "runs": n, "passed": sum(r["passed"] for r in rows),
        "bad_calls": sum(r["bad_calls"] for r in rows), "tool_calls": sum(r["tool_calls"] for r in rows),
        "errors": sum(1 for r in rows if r["error"]), "length_stops": sum(r["length_stops"] for r in rows),
        "avg_turns": sum(r["turns"] for r in rows) / n, "avg_tok": tok / n,
        "avg_wall_min": sum(r["wall_s"] for r in rows) / n / 60, "total_wall_h": sum(r["wall_s"] for r in rows) / 3600,
        "tg": tok / gen if gen else 0, "accept": acc / drafted if drafted else 0,
    }


def per_task(labels):
    t = collections.defaultdict(dict)
    for lab in labels:
        for r in load(lab):
            d = t[r["task"]].setdefault(lab, [0, 0, 0.0])
            d[0] += r["passed"]; d[1] += 1; d[2] += r["wall_s"]
    return t


if __name__ == "__main__":
    labels = sys.argv[1:]
    print("| model | pass | tool calls (bad) | errors | length stops | avg turns | avg tokens | avg min/task | total h | agent TG t/s | MTP accept |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for lab in labels:
        s = summary(lab)
        print(f"| {lab} | {s['passed']}/{s['runs']} | {s['tool_calls']} ({s['bad_calls']}) | {s['errors']} | {s['length_stops']} | "
              f"{s['avg_turns']:.1f} | {s['avg_tok']:.0f} | {s['avg_wall_min']:.1f} | {s['total_wall_h']:.1f} | {s['tg']:.2f} | {s['accept']:.0%} |")
    print()
    print("| task | " + " | ".join(f"{l} pass · min" for l in labels) + " |")
    print("|---|" + "---:|" * len(labels))
    for task, d in sorted(per_task(labels).items()):
        print(f"| {task} | " + " | ".join(f"{d[l][0]}/{d[l][1]} · {d[l][2] / d[l][1] / 60:.1f}" if l in d else "—" for l in labels) + " |")
