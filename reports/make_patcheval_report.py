#!/usr/bin/env python3
"""Build the PatchEval comparison report (Markdown + HTML) from patcheval-data.json.

Run: python3 reports/make_patcheval_report.py   (writes next to this file)
Data: patcheval-data.json, merged from BenchKit results.json files (see its "dirs" per arm).
"""

from __future__ import annotations

import html
import json
import statistics as st
from pathlib import Path

import agent_eval_section as AE

HERE = Path(__file__).resolve().parent
D = json.loads((HERE / "patcheval-data.json").read_text())
ORDER: list[str] = D["_order"]
DATE = "2026-11-08"  # last PatchEval update; the file name keeps its first date (STEM)
STEM = "2026-11-02_PatchEval_Report_local-vs-hosted"

# Arms, their order (= ranking), labels, cost and status come from patcheval-arms.json
# via build_patcheval_data.py.
ARMS: list[str] = D["_arms"]
SHORT = {k: D[k]["short"] for k in ARMS}
COST = {k: D[k]["cost"] for k in ARMS if D[k].get("cost")}
LOCAL_COST = "no API cost; ~9-10 h of the laptop at full load"
STATUS = {k: D[k]["status"] for k in ARMS if D[k].get("status")}
CAP16 = 16384
SYM = {"pass": "✓", "fail": "✗", "timeout": "⏱", "length_exceeded": "L", "harness_error": "E"}
WORD = {
    "pass": "pass",
    "fail": "fail",
    "timeout": "timeout",
    "length_exceeded": "length limit",
    "harness_error": "harness error",
}


def stats(key: str) -> dict:
    a = D[key]
    ts = list(a["tasks"].values())
    walls = [t["response_time_s"] for t in ts]
    tps = [t["tok_s"] for t in ts if t["tok_s"]]
    outcomes: dict[str, int] = {}
    for t in ts:
        outcomes[t["outcome"]] = outcomes.get(t["outcome"], 0) + 1
    passes = [t for t in ts if t["outcome"] == "pass"]
    return {
        "n": len(ts),
        "passed": len(passes),
        "passed_original": sum(t.get("outcome_original", t["outcome"]) == "pass" for t in ts),
        "pct": 100 * len(passes) / len(ts),
        "outcomes": outcomes,
        "total_h": a["total_time"] / 3600,
        "median_task_min": st.median(walls) / 60,
        "mean_task_min": st.mean(walls) / 60,
        "tok_s": st.mean(tps) if tps else 0.0,
        "out_per_task": st.mean([t["output_tokens"] or 0 for t in ts]),
        "in_per_task_m": st.mean([t["input_tokens"] or 0 for t in ts]) / 1e6,
        "out_total_m": sum(t["output_tokens"] or 0 for t in ts) / 1e6,
        "in_total_m": sum(t["input_tokens"] or 0 for t in ts) / 1e6,
        "turns": sum(t["model_turns"] or 0 for t in ts),
        "len_hits": sum(1 for t in ts if t["length_exceeded"]),
        "deadline_passes": sum(1 for t in passes if t["response_time_s"] >= 1790),
        "avg_reply_max": max(
            (t["output_tokens"] or 0) / max(1, t["model_turns"] or 1) for t in ts
        ),
        **telemetry(ts, passes),
    }


def telemetry(ts: list[dict], passes: list[dict]) -> dict:
    """Per-reply and per-request numbers; only runs since 2026-11-01 18:00 record them."""
    out: dict = {}
    with_calls = [t for t in ts if t.get("call_usage")]
    if with_calls:
        replies = [c for t in with_calls for c in t["call_usage"]]
        out["reply_max"] = max(c["output"] for c in replies)
        out["replies_over_16k"] = sum(c["output"] > CAP16 for c in replies)
        covered = [t for t in passes if t.get("call_usage")]
        if len(covered) == len(passes) and len(with_calls) == len(ts):
            out["score_16k"] = sum(
                all(c["output"] <= CAP16 for c in t["call_usage"]) for t in passes
            )
        out["reply_tasks"] = len(with_calls)
    calls = [c for t in ts for c in t.get("upstream_calls") or []]
    if calls:
        providers: dict[str, int] = {}
        for c in calls:
            name = c.get("provider") or "?"
            providers[name] = providers.get(name, 0) + 1
        ttft = [c["ttft_s"] for c in calls if c.get("ttft_s") is not None]
        decode = [c["decode_tok_s"] for c in calls if c.get("decode_tok_s")]
        out["providers"] = ", ".join(f"{k} {v}" for k, v in sorted(providers.items(), key=lambda x: -x[1]))
        out["requests"] = len(calls)
        out["measured_cost"] = sum(c.get("cost") or 0 for c in calls)
        out["ttft_median"] = st.median(ttft) if ttft else None
        out["decode_median"] = st.median(decode) if decode else None
        out["call_tasks"] = sum(1 for t in ts if t.get("upstream_calls"))
    return out


S = {k: stats(k) for k in ARMS}


def score(k: str) -> str:
    s = S[k]
    orig = f", orig. {s['passed_original']}" if s["passed_original"] != s["passed"] else ""
    return f"{s['passed']}/{s['n']} ({s['pct']:.0f}%{orig})"


def cost(k: str) -> str:
    return COST.get(k, LOCAL_COST)


def cell(k: str, tid: str) -> tuple[str, str]:
    t = D[k]["tasks"].get(tid)
    if not t:
        return "—", "not run"
    mins = t["response_time_s"] / 60
    if t.get("regraded"):
        return (f"{SYM[t['outcome']]}* {mins:.0f}m",
                f"{WORD[t['outcome']]} (re-graded: {t['regraded']}; originally {WORD[t['outcome_original']]}), {mins:.1f} min")
    return f"{SYM[t['outcome']]} {mins:.0f}m", f"{WORD[t['outcome']]}, {mins:.1f} min"


OVERVIEW_COLS = [
    "#", "Harness", "Model", "Think level", "Output cap", "Runs on", "Score",
    "Total wall", "Median task", "Avg stream tok/s", "Cost",
]  # fmt: skip


def overview_rows() -> list[list[str]]:
    rows = []
    for i, k in enumerate(ARMS, 1):
        a, s = D[k], S[k]
        rows.append(
            [
                str(i) if k not in STATUS else "–",
                a["harness"],
                a["model"],
                a["think"],
                a["cap"],
                a["runtime"],
                score(k) + (" *" if k in STATUS else ""),
                f"{s['total_h']:.1f} h" + (f" ({s['n']} tasks)" if s["n"] < 20 else ""),
                f"{s['median_task_min']:.1f} min",
                f"{s['tok_s']:.0f}",
                cost(k),
            ]
        )
    return rows


TAKEAWAYS = [
    "**DeepSeek V4.1 Flash through pi is the clear winner: 17/20 (85%)**, two more than the best "
    "local model, in **1.5 h instead of ~9 h**, for **about $1** for the whole suite. Median task: "
    "2.5 min; local models typically run up to the 30-min limit.",
    "**Best local: Qwen3.8-Flash-Next on Strata, IQ3_XXS and IQ3_S both 15/20.** UD-IQ4_XS (14/20) "
    "buys nothing for its size. Ornith-1.5 122B and Bonsai 2 27B: 10/20.",
    "**Unsloth Dynamic v3.1 UD-IQ4_XS (2026-11-08): 12/20**, three below GSQ IQ3_XXS / IQ3_S, two below the "
    "old UD-IQ4_XS, so Unsloth's \"+10-15% accuracy\" claim does not show here. It decodes at only ~15 tok/s, "
    "so 13 of 20 tasks ran into the 30-min limit (7 timeouts, 6 passes at the deadline). It timed out on "
    "`json-repair-205` and `structlog-710`, which every other full run passed. It also used fewer output "
    "tokens per task (~21k vs ~31k for IQ3_XXS).",
    "**Scores include one re-graded task**: `pygments-2828`'s hidden test was flawed (BenchKit issue #89); "
    "every saved patch passes the fixed test, so each full run gains one pass (original scores shown as "
    "\"orig.\"; re-graded cells marked *). A live re-run on the fixed test confirmed it for pi + DeepSeek.",
    "**MiniMax M3.1 Flash was dropped after 6 of 20 tasks** (3/6 with pi, 3/6 with mcode): it burned "
    "the $5 Vercel credit in ~15 task runs (≈ $0.33/task, ~7x DeepSeek per task) and needed the full "
    "30 minutes on most tasks. On the same 6 tasks DeepSeek scored 5/6.",
    "**pi vs mcode on the same model** (MiniMax): equal score (3/6) and no clear token or speed "
    "difference. On the two tasks with complete counts mcode used 8-22% fewer output tokens; both "
    "agents ran into the 30-min limit on 4 of 6 tasks.",
]

FAIRNESS = [
    "The **output cap differs**: local runs used pi's default 16,384 tokens per reply, the hosted runs "
    "64k. DeepSeek's replies average ~580 tokens (task maximum of the average: 928), so a 16k cap would "
    "almost certainly not have changed its score; strictly provable are 4 passes whose whole task "
    "stayed under 16k output (per-reply counts were added after this run).",
    "The **think level differs by design**: hosted runs at the highest level the provider offers "
    "(`max`); local runs at their runtime's default (thinking on). BenchKit's pi entry sends no "
    "reasoning setting, so the local servers chose.",
    "**Speed is not hardware-equal**: hosted tok/s depends on which upstream provider the gateway "
    "picked (OpenRouter served DeepSeek from Sail Research and InferenceNet at different times; Vercel "
    "served MiniMax from Fireworks or MiniMax). Local tok/s is one laptop (RTX 4070 Laptop 8 GB, "
    "i7-13700H, 125 GB RAM).",
    "**pi version**: BenchKit v0.2.0 pins pi **0.84.2** (2026-08-14) in the sandbox, for every "
    "run here; the pi on this machine is 1.4.0 (2026-10-21). Scores reflect the older agent.",
    "**The v3.1 run used a newer engine**: Strata 0.2.11 (engine 0.1.57) with DFlash2 drafting, where the "
    "other local Qwen3.8 runs used 0.2.7 with MTP. Same-quant speed on the agent suite is equal on both. It ran on "
    "the fixed dataset (`pilot-20-local1`), so its `pygments-2828` pass is live, not re-graded.",
    "**Passing at the deadline**: PatchEval grades the workspace even when the agent is stopped at "
    "30 min, so many local and MiniMax passes are fixes that were already in place when time ran out.",
]

FAILURES = [
    ("pygments-2828 (nobody passed): benchmark flaw",
     "The hidden test is a golden file of exact token types and expects each slice `:` in "
     "`numbers[1::2]` as `Operator`. But the task's own `jsonnet.py` marks every `:` as `Punctuation` "
     "(lines 98, 155) and its operator rule has no `:`; the upstream fix added it. Four models followed "
     "the file's convention (`Punctuation`), two emitted `::` as one `Punctuation` token: all six failed "
     "on a choice nothing pointed to. Reported upstream: https://github.com/DogukanUrker/BenchKit/issues/89. "
     "Fixed locally in dataset `pilot-20-local1` (accepts `Operator` or `Punctuation`); the v3.1 UD-IQ4_XS run used "
     "the fixed test and passed it. All six saved patches "
     "pass the fixed test, so this report re-grades them as passes (`reports/patcheval-regrades.json`); the "
     "raw BenchKit results keep the original fails."),
    ("pygments-2816 (nobody passed)",
     "DeepSeek's change broke two existing, visible tests (`general.jsx`, `test_aria_attribute.txt`) and "
     "its tokens for `I'm` differ from the golden file. A fair failure: running the existing tests "
     "would have caught it."),
    ("sqlit-260 (3 of 9 passed: IQ3_XXS, UD-IQ4_XS, mcode+MiniMax)",
     "Not random. The issue asks to drop the trailing `;` that breaks `ALTER SESSION`. The hidden tests "
     "also require keeping `;` where PL/SQL needs it (`BEGIN … END;`, `DECLARE`, `CREATE … PROCEDURE`, "
     "comments). Every failing model, DeepSeek included, stripped `;` everywhere; the passes knew the "
     "Oracle rule without being told."),
    ("typeguard-499 (DeepSeek failed; Qwen3.8 IQ3_XXS, IQ3_S and UD-IQ4_XS v3.1 passed)",
     "DeepSeek fixed exactly the reported repro in 3 min: it accepts a protocol member when the class "
     "*annotates* it (true in the issue, where the class inherits the protocol). The hidden test uses a "
     "class that only sets `self.foo` in `__init__`, with no annotation. IQ3_XXS spent 30 min and also "
     "detected attributes assigned on `self` (`__static_attributes__`, bytecode on older Pythons)."),
    ("Pattern",
     "DeepSeek's fails are fast (2-4 min) and narrow: it stops once the reported example works. The "
     "local models use the full 30 min and sometimes generalise further, which is how they win "
     "typeguard-499; more often the time runs out (timeouts)."),
]

OTHER_RUNS = [
    "**pygments-2828 re-run on the fixed test** (`pilot-20-local1`, 2026-11-02, DeepSeek V4.1 Flash 1017, think "
    "max, 64k): **pi PASS** (2.0 min, $0.058, provider Cohere). **mcode FAIL** (1.9 min, $0.034, Cohere/Relace), "
    "but not for a mistake. Both agents found that the number pattern `(.[0-9])?` has an unescaped `.` "
    "(it lexes `1:8` in `[1:8:2]` as a number; still present in Pygments 2.21.0) and escaped it. mcode also let "
    "fractions have several digits (`2.25` as one token), said so in its answer, added slice tests, updated the one "
    "affected expected-output file and ran the full suite (5,307 passed). PatchEval discards agent edits to test "
    "files, so the changed output counted as a regression. The score cannot tell a disclosed, deliberate "
    "improvement from a regression; it rewards minimal fixes.",
    "Bonsai 2 27B with thinking **off**: stopped after 3 tasks (1/3), same per-task results as thinking on.",
    "MiniMax M3.1 Flash, pi, **16k cap, default thinking** (smoke test, 1 task): FAIL on `sqlit-246` "
    "(one reply hit the 16k limit). With 64k and `max` the same task passed.",
    "Two MiniMax runs were stopped and resumed at task boundaries (no task run twice); mcode's "
    "`city2graph-121` first hit a full disk (harness error, excluded) and was re-run (fail).",
]


def detail(k: str) -> list[tuple[str, str]]:
    a, s = D[k], S[k]
    oc = ", ".join(f"{v} {WORD[o]}" for o, v in sorted(s["outcomes"].items(), key=lambda x: -x[1]))
    rows = [
        ("Harness", a["harness"]),
        ("Model", a["model"]),
        ("Think level", a["think"]),
        ("Output cap per reply", a["cap"] + " tokens"),
        ("Runs on", a["runtime"]),
        ("Score", score(k) + (f" — {STATUS[k]}" if k in STATUS else "")),
        ("Outcomes", oc),
        ("Passes reached at the 30-min deadline", str(s["deadline_passes"])),
        ("Total wall clock", f"{s['total_h']:.2f} h for {s['n']} tasks"),
        ("Per task (median / mean)", f"{s['median_task_min']:.1f} / {s['mean_task_min']:.1f} min"),
        ("Avg stream tok/s", f"{s['tok_s']:.0f}"),
        ("Output tokens", f"{s['out_total_m']:.2f} M total, {s['out_per_task']:,.0f} per task"),
        ("Input tokens (incl. cache)", f"{s['in_total_m']:.1f} M total, {s['in_per_task_m']:.2f} M per task"),
        ("Assistant replies", f"{s['turns']:,} (largest per-task average {s['avg_reply_max']:,.0f} tokens/reply)"),
        ("Replies cut by the output cap", str(s["len_hits"])),
        ("Cost", cost(k)),
    ]
    if "reply_max" in s:
        rows.append(("Largest single reply", f"{s['reply_max']:,} output tokens "
                     f"({s['replies_over_16k']} replies over 16k; {s['reply_tasks']} tasks with per-reply data)"))
    if "score_16k" in s:
        rows.append(("Score if capped at 16k per reply", f"{s['score_16k']}/{s['n']} "
                     "(a pass with any reply over 16,384 tokens counts as fail)"))
    if "requests" in s:
        rows += [
            ("Upstream providers (requests)", s["providers"]),
            ("Measured API cost (from the gateway)", f"${s['measured_cost']:.3f} over {s['requests']} requests "
             f"({s['call_tasks']} tasks)"),
            ("Median time to first token / decode speed",
             f"{s['ttft_median']:.1f} s / " + (f"{s['decode_median']:.0f} tok/s" if s["decode_median"] else "n/a")),
        ]
    rows += [
        ("Raw results", ", ".join(f"results/{d}" for d in a["dirs"])),
    ]
    if k == "mm_mcode":
        rows.append(("Note", "mcode reports usage only at the end of a run, so the 3 tasks it was still working on at "
                     "the 30-min limit have no token counts; totals here are a lower bound. Complete counts vs pi: "
                     "json-repair-207 225k vs 245k output, json-repair-191 48k vs 61k."))
    if k == "mm_pi":
        rows.append(("Note", "task 6: 17 replies, the largest 21,864 output tokens (above a 16k cap)."))
    return rows


SETUP = [
    ("Benchmark", "BenchKit v0.2.0 PatchEval, frozen release pilot-20: 20 real bug fixes from 12 Python "
     "projects, graded by hidden tests"),
    ("Agent sandbox", "fresh Docker container per task, /workspace only, no network except a restricted "
     "inference proxy"),
    ("Limits", "30 min (1800 s) per task, one task at a time, no repair attempts"),
    ("pi", "stock pi coding agent 0.84.2, tools read / bash / edit / write"),
    ("mcode", "MiniMax Code 0.7.2 (our OpenRouter fork, as run by `mcode-or`), its own tools and prompt, "
     "`mcode exec --effort max`, run inside the same sandbox"),
]


# ---------------------------------------------------------------- Markdown
def md_table(header: list[str], rows: list[list[str]]) -> str:
    esc = lambda x: str(x).replace("|", "\\|")  # noqa: E731
    out = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    out += ["| " + " | ".join(esc(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


def build_md() -> str:
    p = [f"# Local vs hosted models: PatchEval and agent suite\n\n*PatchEval {DATE} · BenchKit PatchEval (20 real Python bug fixes) "
         "through the pi and mcode coding agents; agent-suite update below*\n", AE.md(md_table), "## PatchEval overview\n"]
    p += [f"- {t}" for t in TAKEAWAYS]
    p.append("\n" + md_table(OVERVIEW_COLS, overview_rows()))
    p.append("\n\\* stopped after 6 of 20 tasks; not ranked. Cost of local runs: electricity only.\n")
    p.append("### Same 6 tasks, all arms\n")
    first6 = ORDER[:6]
    rows = []
    for k in ARMS:
        n = sum(1 for t in first6 if D[k]["tasks"].get(t, {}).get("outcome") == "pass")
        rows.append([D[k]["harness"], D[k]["model"], D[k]["think"], f"{n}/6"])
    p.append(md_table(["Harness", "Model", "Think level", "Tasks 1-6"], rows))
    p.append("\n### Read this before comparing\n")
    p += [f"- {t}" for t in FAIRNESS]
    p.append("\n## Details\n\n### Setup (all runs)\n")
    p.append(md_table(["", ""], [[a, b] for a, b in SETUP]))
    p.append("\n### Per task\n\n✓ pass · ✗ fail · ⏱ timeout (30 min) · L reply hit the output cap · — not run. "
             "Number = minutes. * re-graded with the fixed `pygments-2828` test (see *Why some tasks fail*).\n")
    head = ["Task"] + [f"{SHORT[k]} ({D[k]['harness'].split()[0]})" for k in ARMS]
    rows = [[t] + [cell(k, t)[0] for k in ARMS] for t in ORDER]
    rows.append(["**passed**"] + [f"**{S[k]['passed']}/{S[k]['n']}**" for k in ARMS])
    p.append(md_table(head, rows))
    for k in ARMS:
        a = D[k]
        p.append(f"\n### {a['harness'].split()[0]} + {a['model']} · think {a['think'].split(' ')[0].rstrip(':,')}\n")
        p.append(md_table(["", ""], [[x, y] for x, y in detail(k)]))
    p.append("\n### Why some tasks fail\n")
    p.append(md_table(["Task", "What happened"], [[a, b] for a, b in FAILURES]))
    p.append("\n### Other runs (not in the tables)\n")
    p += [f"- {t}" for t in OTHER_RUNS]
    p.append("\n### Sources\n\n- Per-task data: `reports/patcheval-data.json` (merged from the BenchKit "
             "`results.json` files listed per run); regenerate with `python3 reports/make_patcheval_report.py`.\n"
             "- Costs: OpenRouter key usage on 2026-11-01 ($0.971, the DeepSeek run only); "
             "Vercel AI Gateway credits (total used $5.00).\n"
             "- Earlier write-ups: `2026-10-30_18-20_Benchmark_Summary_Qwen3.8-flash-next-Strata.md`, "
             "`2026-11-01_11-00_Benchmark_Summary_Ornith-1.5-122B.md`, `handover-bonsai2-ada-evaluation.md`.\n")
    return "\n".join(p)


# ---------------------------------------------------------------- HTML
CSS = """
:root{--bg:#fbfaf8;--fg:#1d1d1f;--muted:#6b6b70;--line:#e3e1dc;--card:#ffffff;--accent:#2f6fde;
--pass:#1f8a4c;--pass-bg:#e5f4ea;--fail:#c2362b;--fail-bg:#fbe7e5;--to:#9a6500;--to-bg:#fbf1dc;
--na:#9a9aa0;--na-bg:#f1f0ed;--hl:#eef3fd}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#141416;--fg:#ececee;--muted:#a0a0a8;
--line:#2c2c31;--card:#1c1c20;--accent:#7aa5f5;--pass:#6fd396;--pass-bg:#173523;--fail:#f08c82;--fail-bg:#3a1a17;
--to:#e6b65c;--to-bg:#382b12;--na:#77777f;--na-bg:#232327;--hl:#1d2638}}
:root[data-theme="dark"]{--bg:#141416;--fg:#ececee;--muted:#a0a0a8;--line:#2c2c31;--card:#1c1c20;--accent:#7aa5f5;
--pass:#6fd396;--pass-bg:#173523;--fail:#f08c82;--fail-bg:#3a1a17;--to:#e6b65c;--to-bg:#382b12;--na:#77777f;
--na-bg:#232327;--hl:#1d2638}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1180px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:28px;margin:0 0 4px;letter-spacing:-.01em}h2{font-size:21px;margin:40px 0 12px}
h3{font-size:16px;margin:28px 0 8px}.sub{color:var(--muted);margin:0 0 24px}
ul{padding-left:20px}li{margin:6px 0}code{font-size:13px;background:var(--na-bg);padding:1px 5px;border-radius:4px}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--card)}
table{border-collapse:collapse;width:100%;font-size:13.5px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{font-weight:600;color:var(--muted);white-space:nowrap;background:var(--card);position:sticky;top:0}
tr:last-child td{border-bottom:none}td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
tr.win td{background:var(--hl)}tr.stopped td{color:var(--muted)}
.score{font-weight:700;white-space:nowrap}.bar{display:block;height:4px;border-radius:2px;background:var(--line);margin-top:4px}
.bar>i{display:block;height:100%;border-radius:2px;background:var(--accent)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin:16px 0 8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.card b{display:block;font-size:24px;letter-spacing:-.01em}.card span{color:var(--muted);font-size:13px}
.m td{text-align:center;white-space:nowrap;font-variant-numeric:tabular-nums;padding:6px 8px}
.m td:first-child{text-align:left;font-family:ui-monospace,monospace;font-size:12.5px}
.m th{white-space:normal;min-width:84px;font-size:12px}
.o-pass{background:var(--pass-bg);color:var(--pass)}.o-fail{background:var(--fail-bg);color:var(--fail)}
.o-timeout,.o-length_exceeded{background:var(--to-bg);color:var(--to)}.o-na,.o-harness_error{background:var(--na-bg);color:var(--na)}
.kv td:first-child{color:var(--muted);width:290px}.legend{color:var(--muted);font-size:13px;margin:6px 0 10px}
.tag{display:inline-block;font-size:12px;padding:1px 7px;border-radius:999px;background:var(--na-bg);color:var(--muted);margin-left:6px}
details{margin:10px 0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:4px 14px}
summary{cursor:pointer;padding:8px 0;font-weight:600}
"""


def h(x: object) -> str:
    return html.escape(str(x))


def md_inline(text: str) -> str:
    out, bold = [], False
    for i, part in enumerate(h(text).split("**")):
        if i:
            bold = not bold
            out.append("<b>" if bold else "</b>")
        out.append(part)
    s = "".join(out)
    parts = s.split("`")
    return "".join(f"<code>{p}</code>" if i % 2 else p for i, p in enumerate(parts))


def build_html() -> str:
    o = ["<!doctype html><html lang='en'><head><meta charset='utf-8'>",
         "<meta name='viewport' content='width=device-width,initial-scale=1'>",
         "<title>Local Model Comparison</title><style>", CSS, "</style></head><body><main>",
         "<h1>Local vs hosted models: PatchEval and agent suite</h1>",
         f"<p class='sub'>PatchEval {DATE} · BenchKit PatchEval (20 real Python bug fixes, hidden-test grading) through "
         "the pi and mcode coding agents; agent-suite update first</p>",
         AE.htm(md_inline), "<h2>PatchEval overview</h2><div class='cards'>"]
    best_local = S["iq3xxs"]
    cards = [
        (f"{S['deepseek']['passed']}/20", "DeepSeek V4.1 Flash · pi · think max (incl. 1 re-graded)"),
        (f"{best_local['passed']}/20", "best local: Qwen3.8 IQ3_XXS / IQ3_S on Strata (incl. 1 re-graded)"),
        (f"{S['deepseek']['total_h']:.1f} h vs ~9 h", "hosted vs local wall clock, 20 tasks"),
        ("≈ $1 vs ≈ $7", "DeepSeek vs MiniMax per 20 tasks (API)"),
    ]
    o += [f"<div class='card'><b>{h(a)}</b><span>{h(b)}</span></div>" for a, b in cards]
    o.append("</div><ul>" + "".join(f"<li>{md_inline(t)}</li>" for t in TAKEAWAYS) + "</ul>")
    o.append("<div class='scroll'><table><thead><tr>" + "".join(f"<th>{h(c)}</th>" for c in OVERVIEW_COLS)
             + "</tr></thead><tbody>")
    for k, row in zip(ARMS, overview_rows(), strict=True):
        cls = "win" if k == "deepseek" else "stopped" if k in STATUS else ""
        tds = []
        for i, c in enumerate(row):
            if OVERVIEW_COLS[i] == "Score":
                tds.append(f"<td class='score'>{h(c)}<span class='bar'><i style='width:{S[k]['pct']:.0f}%'></i></span></td>")
            elif OVERVIEW_COLS[i] in ("Total wall", "Median task", "Avg stream tok/s", "#"):
                tds.append(f"<td class='num'>{h(c)}</td>")
            else:
                tds.append(f"<td>{h(c)}</td>")
        o.append(f"<tr class='{cls}'>" + "".join(tds) + "</tr>")
    o.append("</tbody></table></div><p class='legend'>* stopped after 6 of 20 tasks (Vercel credit used up); "
             "not ranked. Local runs: no API cost.</p>")
    o.append("<h3>Same 6 tasks, all arms</h3><div class='scroll'><table><thead><tr><th>Harness</th><th>Model</th>"
             "<th>Think level</th><th>Tasks 1-6</th></tr></thead><tbody>")
    for k in ARMS:
        n = sum(1 for t in ORDER[:6] if D[k]["tasks"].get(t, {}).get("outcome") == "pass")
        o.append(f"<tr><td>{h(D[k]['harness'])}</td><td>{h(D[k]['model'])}</td><td>{h(D[k]['think'])}</td>"
                 f"<td class='num score'>{n}/6</td></tr>")
    o.append("</tbody></table></div>")
    o.append("<h3>Read this before comparing</h3><ul>" + "".join(f"<li>{md_inline(t)}</li>" for t in FAIRNESS) + "</ul>")
    o.append("<h2>Details</h2><h3>Setup (all runs)</h3><div class='scroll'><table class='kv'><tbody>"
             + "".join(f"<tr><td>{h(a)}</td><td>{md_inline(b)}</td></tr>" for a, b in SETUP) + "</tbody></table></div>")
    o.append("<h3>Per task</h3><p class='legend'>✓ pass · ✗ fail · ⏱ timeout (30 min) · L reply hit the output "
             "cap · — not run. Number = minutes. * re-graded with the fixed <code>pygments-2828</code> test.</p><div class='scroll'><table class='m'><thead><tr><th>Task</th>")
    o += [f"<th>{h(SHORT[k])}<br><span style='font-weight:400'>{h(D[k]['harness'].split()[0])} · "
          f"{h(D[k]['think'].split(' ')[0].rstrip(':,'))}</span></th>" for k in ARMS]
    o.append("</tr></thead><tbody>")
    for t in ORDER:
        o.append(f"<tr><td>{h(t)}</td>")
        for k in ARMS:
            txt, title = cell(k, t)
            oc = D[k]["tasks"].get(t, {}).get("outcome", "na")
            o.append(f"<td class='o-{oc}' title='{h(title)}'>{h(txt)}</td>")
        o.append("</tr>")
    o.append("<tr><td><b>passed</b></td>" + "".join(f"<td class='score'>{S[k]['passed']}/{S[k]['n']}</td>" for k in ARMS)
             + "</tr></tbody></table></div>")
    o.append("<h3>Per run</h3>")
    for k in ARMS:
        a = D[k]
        tag = f"<span class='tag'>{h(STATUS[k])}</span>" if k in STATUS else ""
        o.append(f"<details{' open' if k == 'deepseek' else ''}><summary>{h(a['harness'])} + {h(a['model'])} · think "
                 f"{h(a['think'].split(' ')[0].rstrip(':,'))} — {h(score(k))}{tag}</summary><table class='kv'><tbody>"
                 + "".join(f"<tr><td>{h(x)}</td><td>{h(y)}</td></tr>" for x, y in detail(k)) + "</tbody></table></details>")
    o.append("<h3>Why some tasks fail</h3><div class='scroll'><table class='kv'><tbody>"
             + "".join(f"<tr><td>{h(a)}</td><td>{md_inline(b)}</td></tr>" for a, b in FAILURES)
             + "</tbody></table></div>")
    o.append("<h3>Other runs (not in the tables)</h3><ul>" + "".join(f"<li>{md_inline(t)}</li>" for t in OTHER_RUNS) + "</ul>")
    o.append("<h3>Sources</h3><ul><li>Per-task data: <code>reports/patcheval-data.json</code>, merged from the BenchKit "
             "<code>results.json</code> files listed per run; regenerate with <code>python3 reports/make_patcheval_report.py</code>.</li>"
             "<li>Costs: OpenRouter key usage on 2026-11-01 ($0.971, the DeepSeek run only); Vercel AI Gateway "
             "credits (total used $5.00).</li></ul></main></body></html>")
    return "".join(o)


if __name__ == "__main__":
    stem = STEM
    (HERE / f"{stem}.md").write_text(build_md())
    (HERE / f"{stem}.html").write_text(build_html())
    print(HERE / f"{stem}.md")
    print(HERE / f"{stem}.html")
