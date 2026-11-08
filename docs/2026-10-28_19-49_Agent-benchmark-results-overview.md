# Agent benchmark results — overview at 2026-10-28 19:49 AEDT

Written by pi (MiniMax-M3.1) from the raw logs in this repo. Source files cited inline.

## Two different agent suites exist — don't conflate them

| suite | harness | tasks | models run |
|---|---|---|---|
| **BenchKit PatchEval** (pilot-20) | **Pi agent** 0.84.2 (read/bash/edit/write) | 20 repo bugfix tasks | **bonsai-2-27b only** |
| `llama-agent-eval.py` (in-house) | custom OpenAI-tool loop, 5 tools | 8 tasks × 3 seeds = 24 runs | 6 model configs |

The **Pi-agent** suite has only ever been run on Bonsai 2. The cross-model capability/time picture comes from the in-house suite.

---

## 1. BenchKit PatchEval (Pi agent) — Bonsai 2 27B, thinking ON (full 20 tasks)

Source: `benchkit-patcheval-bonsai2-ada.log`, `benchkit-src/BenchKit/results/2026-10-28_13-27-34/results.{csv,md}`. Timeout 1800 s/task, 1 concurrent, `BENCHKIT_PI_TIMEOUT=1800`.

| # | task | result | time | stream t/s | gen tok | input tok | turns | tool calls |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 1 | sqlit-246 | ✅ PASS | 974 s | 27.4 | 25 999 | 897 948 | 33 | 33 |
| 2 | sqlit-260 | ❌ FAIL | 1 330 s | 23.3 | 30 238 | 2 116 507 | 56 | 55 |
| 3 | narwhals-3864 | ⏱ TIMEOUT | 1 802 s | 26.0 | 45 864 | 2 675 166 | 69 | 75 |
| 4 | city2graph-121 | ⏱ TIMEOUT | 1 802 s | 25.7 | 42 620 | 675 509 | 23 | 27 |
| 5 | json-repair-207 | ⏱ TIMEOUT | 1 802 s | 23.9 | 42 413 | 752 687 | 25 | 27 |
| 6 | json-repair-191 | ⏱ TIMEOUT | 1 802 s | 23.7 | 37 511 | 962 955 | 29 | 37 |
| 7 | json-repair-205 | ✅ PASS *(at limit)* | 1 802 s | 26.3 | 46 486 | 2 141 551 | 55 | 57 |
| 8 | click-3572 | ✅ PASS *(at limit)* | 1 802 s | 24.3 | 42 864 | 3 531 175 | 71 | 71 |
| 9 | click-3360 | ✅ PASS | 1 119 s | 28.0 | 30 138 | 1 410 583 | 61 | 60 |
| 10 | click-2790 | ✅ PASS | 1 410 s | 26.9 | 37 048 | 1 832 825 | 64 | 63 |
| 11 | pypdf-3982 | ⏱ TIMEOUT | 1 802 s | 25.7 | 43 026 | 2 313 312 | 60 | 60 |
| 12 | pypdf-3878 | ✅ PASS *(at limit)* | 1 802 s | 25.3 | 44 654 | 2 587 944 | 74 | 79 |
| 13 | pypdf-3587 | ✅ PASS *(at limit)* | 1 802 s | 26.3 | 45 854 | 1 330 012 | 41 | 46 |
| 14 | attrs-1575 | ⏱ TIMEOUT | 1 802 s | 25.6 | 44 416 | 1 161 581 | 48 | 48 |
| 15 | typeguard-499 | ⏱ TIMEOUT | 1 802 s | 25.9 | 45 328 | 1 243 050 | 38 | 38 |
| 16 | structlog-710 | ✅ PASS *(at limit)* | 1 802 s | 25.5 | 44 899 | 3 090 831 | 55 | 67 |
| 17 | pygments-2816 | ⏱ TIMEOUT | 1 802 s | 23.3 | 37 289 | 1 565 725 | 37 | 38 |
| 18 | pygments-2828 | ❌ FAIL | 1 161 s | 26.0 | 28 975 | 1 077 558 | 37 | 36 |
| 19 | tomlkit-440 | ⏱ TIMEOUT | 1 802 s | 22.5 | 36 748 | 1 208 869 | 23 | 23 |
| 20 | tomlkit-542 | ✅ PASS | 1 554 s | 26.5 | 40 734 | 2 379 221 | 66 | 65 |

*"(at limit)" = the agent was still working when the 1800 s cap hit, but the workspace was already correct when graded. BenchKit's markdown labels these TIMEOUT; the console/scoring counts them as passes.*

**Totals (from `results.csv`):** score **45.0 % (9/20)** · 2 FAIL · 14 TIMEOUT-flagged (5 of which are the at-limit passes) · **0 harness errors, 0 loop kills, 0 malformed tool calls** (1005/1005 valid) · stream **25.3 t/s** · aggregate 22.8 t/s · avg response **1 638 s** · wall **9 h 39 m** · 793 104 output tokens, 34.9 M input tokens · 965 model turns, 1 005 tool calls · avg turns-to-solve 57.8 · median time-to-answer 401.6 s · median thinking time 401.6 s.

**Reading of the result:** 4 of 9 passes finished inside the limit (avg 1 265 s); the other 5 only passed because the workspace happened to be right at the cut-off (avg 1 802 s). 9 of 11 losses are timeouts, and time goes into long thinking turns — in tasks 1-4 eight requests ran past 4 k tokens (max 16 849), which was more than half of all generated tokens. So the model *is* capable on these repos (it found the PostgreSQL dollar-quote root cause correctly in task 1), but at ~25 t/s it cannot finish a 20-minute task in 30 minutes.

## 2. BenchKit PatchEval — thinking OFF, partial (1 of 20 done, 3 attempted)

Source: `benchkit-patcheval-bonsai2-ada-think0.log`, `results/2026-10-28_15-02-59/`.

| # | task | result | time | stream t/s | gen tok | input tok | turns | tool calls |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 1 | sqlit-246 | ✅ PASS | 713 s | 27.1 | 18 065 | 2 276 890 | 75 | 74 |
| 2 | sqlit-260 | ❌ FAIL | 1 479 s | 19.4 | 15 733 | 7 351 971 | 150 | 149 |
| 3 | narwhals-3864 | ⏱ TIMEOUT | 1 802 s | 23.3 | 36 080 | 12 964 374 | 253 | 253 |

Partial totals: score 33.3 % (1/3) · 23.1 t/s · avg response 1 331 s · wall 1 h 23 m · 69 878 output tokens, 22.6 M input tokens · 478 turns, 476 tool calls. **Tasks 4-20 not run** (stopped on purpose; resume recipe in `handover-bonsai2-ada-evaluation.md` §7). Thinking-off did not shorten tasks much: in task 2 the GPU was idle ~48 % of the time while Pi ran tools/tests in the sandbox (BenchKit limits it to 2 CPUs).

Two earlier aborted attempts, for the record: `attempt1` (server on 127.0.0.1 → Docker proxy saw 0 requests, task "failed" in 18.5 s at 0 t/s) and `attempt2` (900 s timeout → task 1 TIMEOUT at 901.5 s). Both are harness-config failures, not model results.

## 3. Cross-model capability + time — in-house agent eval (8 tasks × 3 seeds = 24 runs each)

Sources: `llama-agent-eval-{q2_0,gsq-iq3xxs,coder,bonsai2-ada,bonsai2-ada-kvq4_0,bonsai2-ada-kvq8_0}.log`.

| model | pass | min/task | total wall | TG t/s | notes |
|---|---:|---:|---:|---:|---|
| **Bonsai 2 27B** (Ada runtime, q3_0 KV) | **21/24** | **2.1** | 50 min | 35.7 | ~2.4× faster than Q2_0, but 3 fails (turn-limit) |
| Bonsai 2 27B, q4_0 KV | 18/24 | 2.5 | 60 min | 35.3 | 2× t7 runaway → HTTP 500 (8192-token cap) |
| Bonsai 2 27B, q8_0 KV | 17/24 | 2.8 | 68 min | — | all fails = turn limit |
| **Qwen3.8 Q2_0** (GSQ) | **24/24** | 5.1 | 122 min | 10.8 | cleanest tool use |
| **Qwen3.8 IQ3_XXS** (GSQ) | **24/24** | 5.8 | 140 min | 9.8 | quality pick |
| Qwen3.8 Coder (GSQ IQ1_M) | 24/24 | 7.6 | 183 min | 8.4 | slowest |

**Per-task pass count and average minutes (pass·min per task):**

| task | Q2_0 | IQ3_XXS | Coder | Bonsai q3_0 | Bonsai q4_0 | Bonsai q8_0 |
|---|---|---|---|---|---|---|
| t1 bugfix-stats | 3/3 · 1.4 | 3/3 · 1.8 | 3/3 · 2.0 | 3/3 · 0.6 | 3/3 · 0.5 | 3/3 · 0.5 |
| t2 slugify | 3/3 · 3.0 | 3/3 · 5.5 | 3/3 · 5.4 | 3/3 · 1.8 | 2/3 · 1.0 | 1/3 · 1.1 |
| t3 refactor | 3/3 · 1.6 | 3/3 · 1.8 | 3/3 · 2.6 | 3/3 · 0.6 | 3/3 · 0.6 | 3/3 · 0.6 |
| t4 logparse | 3/3 · 7.6 | 3/3 · 4.9 | 3/3 · 8.0 | 2/3 · 1.8 | 3/3 · 1.5 | 3/3 · 1.8 |
| t5 config | 3/3 · 0.7 | 3/3 · 1.1 | 3/3 · 0.9 | 3/3 · 0.3 | 3/3 · 0.3 | 3/3 · 0.3 |
| t6 lru | 3/3 · 5.2 | 3/3 · 6.1 | 3/3 · 9.1 | 2/3 · 1.1 | 3/3 · 1.1 | 2/3 · 1.2 |
| t7 calc | 3/3 · 8.4 | 3/3 · 10.4 | 3/3 · 14.3 | 3/3 · 4.6 | **0/3** · 6.4 | 1/3 · 8.9 |
| t8 scheduler | 3/3 · 12.7 | 3/3 · 14.9 | 3/3 · 18.7 | 2/3 · 5.9 | 1/3 · 8.8 | 1/3 · 8.3 |
| **total** | **24/24** | **24/24** | **24/24** | **21/24** | **18/24** | **17/24** |

Bonsai's 3 fails are on t4 (s1), t8 (s2), t6 (s3) — all **hit the 16-turn limit**, not wrong answers. It needs ~1.8× more turns than Qwen for the same tasks, but is ~2.4× faster per task, so wall-clock still wins.

## Caveats for reading these tables

- **Not a like-for-like ranking across the two suites.** PatchEval (real repos, 20 tasks, Pi harness) and the in-house eval (8 synthetic tasks, custom harness) measure different things. Only one model has a PatchEval score.
- **Reasoning settings differ:** Qwen3.8 ran with xhigh reasoning (template default), Bonsai with `THINK=0` — so the Bonsai 21/24 was achieved *without* thinking.
- **Context/drafting differ:** Qwen3.8 at 64 k ctx with MTP n3; Bonsai at 262 k with MTP + lookup drafting (lookup flatters its TG).
- **The in-house eval is too easy to separate strong models** (all Qwen quants 24/24) — the quality ranking there comes from KLD/perplexity, not pass rate.
- **The PatchEval timeout is the binding constraint, not capability.** 9/11 losses are timeouts, and the tweet's 15/20 was measured on an RTX 3060-class box that decodes ~1.8× faster than this laptop.

## What is still outstanding

1. **Thinking-off PatchEval tasks 4-20** — the run was stopped at task 3 on purpose; resume command is in `handover-bonsai2-ada-evaluation.md` §7. Needs ~7 h.
2. **PatchEval for any other model** — Qwen3.8 Q2_0 / IQ3_XXS have never been through the Pi harness, so there is no cross-model PatchEval comparison at all yet.
3. **Reasoning-on PatchEval resume** is complete (9/20), but a like-for-like thinking-on vs thinking-off pair only exists for tasks 1-3.

Writing these into `llama-speed-table.md` / the guide (handover §8) needs write mode — say the word and I'll draft the rows in `/mode build`.
