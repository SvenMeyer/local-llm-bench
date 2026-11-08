"""Agent-suite section for the report (imported by make_patcheval_report.py).

Reads llama-agent-eval-<label>.jsonl (one line per run; written by llama-agent-eval.py: 8 small coding tasks
through 5 OpenAI-style tools, graded by a pristine copy of the task's tests). Arms and their labels live in ARMS;
narrative lines in agent-eval-notes.json (edit that, then regenerate).
"""

from __future__ import annotations

import html
import json
import statistics as st
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTES = json.loads((Path(__file__).resolve().parent / "agent-eval-notes.json").read_text())

# label -> (model, engine / setup, memory footprint). Order = table order.
ARMS: list[tuple[str, str, str, str]] = [
    ("strata0211-iq3xxs-noskip-prior15", "Qwen3.8-Flash-Next GSQ IQ3_XXS", "Strata 0.2.11 (engine 0.1.57)", "76 GB file, RAM + 8 GB GPU"),
    ("strata0211-ud31-iq3xxs-noskip-prior15", "Qwen3.8-Flash-Next Unsloth v3.1 UD-IQ3_XXS", "Strata 0.2.11 (engine 0.1.57)", "84 GB file, RAM + 8 GB GPU"),
    ("strata0211-iq3s-noskip-prior15", "Qwen3.8-Flash-Next GSQ IQ3_S", "Strata 0.2.11 (engine 0.1.57)", "84 GB file, RAM + 8 GB GPU"),
    ("strata-iq3xxs-noskip", "Qwen3.8-Flash-Next GSQ IQ3_XXS", "Strata 0.2.7 (engine 0.1.52), 2026-10-29", "76 GB file, RAM + 8 GB GPU"),
    ("strata-iq3s-noskip", "Qwen3.8-Flash-Next GSQ IQ3_S", "Strata 0.2.7 (engine 0.1.52), 2026-10-29", "84 GB file, RAM + 8 GB GPU"),
    ("gsq-iq3xxs", "Qwen3.8-Flash-Next GSQ IQ3_XXS", "llama.cpp (Unsloth b11027 mix), 2026-10-27", "76 GB file, RAM + 8 GB GPU"),
    ("twil8b-i1q4km-nopreserve", "TwIL-8B i1-Q4_K_M (Granite dense 8.8B)", "llama.cpp b12169, --no-reasoning-preserve, seed 1 only", "5.4 GB, all on GPU (7.1 GB used)"),
    ("twil8b-i1q4km", "TwIL-8B i1-Q4_K_M (Granite dense 8.8B)", "llama.cpp b12169, reasoning kept in history, seed 1 only", "5.4 GB, all on GPU (7.1 GB used)"),
    ("bonsai2-ada", "Ternary-Bonsai-2 27B PTQ1_0", "llama.cpp Ada-surgery runtime, 2026-10-28", "~7 GB, all on GPU"),
]
SHORT = {
    "strata0211-iq3xxs-noskip-prior15": "GSQ IQ3_XXS · Strata 0.2.11",
    "strata0211-ud31-iq3xxs-noskip-prior15": "Unsloth v3.1 UD-IQ3_XXS · Strata 0.2.11",
    "strata0211-iq3s-noskip-prior15": "GSQ IQ3_S · Strata 0.2.11",
    "strata-iq3xxs-noskip": "GSQ IQ3_XXS · Strata 0.2.7",
    "strata-iq3s-noskip": "GSQ IQ3_S · Strata 0.2.7",
    "gsq-iq3xxs": "GSQ IQ3_XXS · llama.cpp",
    "twil8b-i1q4km-nopreserve": "TwIL-8B · no-preserve",
    "twil8b-i1q4km": "TwIL-8B · reasoning kept",
    "bonsai2-ada": "Bonsai 2 27B",
}
TASKS = [f"t{i}-{n}" for i, n in enumerate(
    ["bugfix-stats", "slugify", "refactor", "logparse", "config", "lru", "calc", "scheduler"], 1)]


def load(label: str) -> list[dict]:
    name = f"llama-agent-eval-{label}.jsonl"
    p = ROOT / "data" / "agent-eval" / name  # repo layout
    if not p.exists():
        p = ROOT / name  # flat working directory
    return [json.loads(x) for x in p.read_text().splitlines() if x.strip()] if p.exists() else []


def stats(rows: list[dict]) -> dict:
    n = len(rows)
    if not n:
        return {}
    tok = sum(r["completion_tokens"] for r in rows)
    gen = sum(r["gen_s"] for r in rows)
    s1 = [r for r in rows if r["seed"] == 1]
    return {
        "n": n, "passed": sum(r["passed"] for r in rows),
        "s1": f"{sum(r['passed'] for r in s1)}/{len(s1)}" if s1 else "—",
        "avg_tok": tok / n, "avg_min": sum(r["wall_s"] for r in rows) / n / 60,
        "med_min": st.median(r["wall_s"] for r in rows) / 60,
        "total_h": sum(r["wall_s"] for r in rows) / 3600, "tg": tok / gen if gen else 0.0,
        "timeouts": sum(1 for r in rows if r.get("error")),
    }


def arms() -> list[tuple[str, str, str, str, list[dict], dict]]:
    out = []
    for label, model, engine, mem in ARMS:
        rows = load(label)
        if rows:
            out.append((label, model, engine, mem, rows, stats(rows)))
    return out


COLS = ["Model", "Engine / setup", "Memory", "Pass (all runs)", "Seed 1", "Avg tokens/run", "Avg min/run",
        "Total h", "Decode t/s (agent)"]


def row(a) -> list[str]:
    _, model, engine, mem, _, s = a
    return [model, engine, mem, f"{s['passed']}/{s['n']}", s["s1"], f"{s['avg_tok']:,.0f}", f"{s['avg_min']:.1f}",
            f"{s['total_h']:.1f}", f"{s['tg']:.1f}"]


def task_cell(rows: list[dict], t: str) -> tuple[str, str]:
    rs = [r for r in rows if r["task"] == t]
    if not rs:
        return "—", "na"
    p = sum(r["passed"] for r in rs)
    m = st.mean(r["wall_s"] for r in rs) / 60
    cls = "pass" if p == len(rs) else "fail" if p == 0 else "timeout"
    return f"{p}/{len(rs)} · {m:.1f}", cls


def md(md_table) -> str:
    A = arms()
    p = [f"## {NOTES['title']}\n", f"*{NOTES['subtitle']}*\n"]
    p += [f"- {t}" for t in NOTES["takeaways"]]
    p.append("\n" + md_table(COLS, [row(a) for a in A]))
    p.append("\n" + NOTES["legend"] + "\n")
    p.append("### Per task (passed/runs · mean minutes)\n")
    p.append(md_table(["Task"] + [SHORT[a[0]] for a in A],
                      [[t] + [task_cell(a[4], t)[0] for a in A] for t in TASKS]))
    p.append("\n### Notes\n")
    p += [f"- {t}" for t in NOTES["notes"]]
    p.append("\n---\n")
    return "\n".join(p)


def htm(md_inline) -> str:
    h = lambda x: html.escape(str(x))  # noqa: E731
    A = arms()
    o = [f"<h2>{h(NOTES['title'])}</h2><p class='sub'>{h(NOTES['subtitle'])}</p><div class='cards'>"]
    o += [f"<div class='card'><b>{h(a)}</b><span>{h(b)}</span></div>" for a, b in NOTES["cards"]]
    o.append("</div><ul>" + "".join(f"<li>{md_inline(t)}</li>" for t in NOTES["takeaways"]) + "</ul>")
    o.append("<div class='scroll'><table><thead><tr>" + "".join(f"<th>{h(c)}</th>" for c in COLS) + "</tr></thead><tbody>")
    for a in A:
        r = row(a)
        cls = "win" if a[0] in NOTES.get("highlight", []) else ""
        tds = [f"<td>{h(c)}</td>" if i < 3 else f"<td class='num{' score' if i == 3 else ''}'>{h(c)}</td>"
               for i, c in enumerate(r)]
        o.append(f"<tr class='{cls}'>" + "".join(tds) + "</tr>")
    o.append(f"</tbody></table></div><p class='legend'>{md_inline(NOTES['legend'])}</p>")
    o.append("<h3>Per task</h3><p class='legend'>passed/runs · mean minutes per run</p>"
             "<div class='scroll'><table class='m'><thead><tr><th>Task</th>")
    o += [f"<th>{h(SHORT[a[0]])}</th>" for a in A]
    o.append("</tr></thead><tbody>")
    for t in TASKS:
        o.append(f"<tr><td>{h(t)}</td>")
        for a in A:
            txt, cls = task_cell(a[4], t)
            o.append(f"<td class='o-{cls}'>{h(txt)}</td>")
        o.append("</tr>")
    o.append("</tbody></table></div><h3>Notes</h3><ul>"
             + "".join(f"<li>{md_inline(t)}</li>" for t in NOTES["notes"]) + "</ul><hr>")
    return "".join(o)
