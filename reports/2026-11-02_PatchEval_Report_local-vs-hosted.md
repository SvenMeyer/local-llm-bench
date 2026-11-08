# Local vs hosted models: PatchEval and agent suite

*PatchEval 2026-11-08 · BenchKit PatchEval (20 real Python bug fixes) through the pi and mcode coding agents; agent-suite update below*

## Update 2026-11-07: tool-calling agent suite

*8 small Python coding tasks through 5 OpenAI-style tools (list/read/grep/write/run_tests), graded by the task's own tests; 3 seeds = 24 runs per setup unless noted. Laptop: RTX 4070 Laptop 8 GB (35 W cap), i7-13700H, 125 GB RAM.*

- **Daily pick stays Qwen3.8 GSQ IQ3_XXS on Strata.** On 0.2.11 it passed 24/24 in 1.2 h at 28.9 t/s, the fastest of all setups that pass everything.
- **Unsloth's v3.1 UD-IQ3_XXS ties but does not win.** 24/24 in 1.3 h; decode 24.6 t/s against 28.9 for GSQ IQ3_XXS on the same engine, with an 84 GB file against 76 GB. It wrote 5% fewer tokens per run (4,298 vs 4,526), far from the claimed 30%. This suite is too easy to show a quality difference (every Qwen3.8 setup scores 24/24); only a PatchEval run could test the accuracy claim.
- **TwIL-8B is fast on short work but not good enough for agent tasks.** It passed 5 of 8 (seed 1) where every Qwen3.8 setup passed 8 of 8, failing the LRU cache, calculator and scheduler tasks after 25-48 min each (Qwen3.8: 3-8 min). It fits fully in 7.1 GB of VRAM and needs no RAM, which is its one real advantage.
- **TwIL keeps its old reasoning in the prompt by default** (its chat template preserves reasoning traces), so agent contexts reach 30k+ tokens and decode drops to 9-13 t/s. `--no-reasoning-preserve` cut the 8-task time from 2.3 h to 1.7 h (13.5 -> 19.8 t/s) but passed the same 5 tasks.
- **Strata 0.2.11 is neither faster nor slower here.** Same-quant speeds match the October 0.1.52 runs (IQ3_XXS 28.9 vs 28.0 t/s, IQ3_S 23.3 vs 24.2). Its new default drafter (DFlash2) accepts 84-85% of guesses against MTP's 69-71%, but the net decode speed is the same. The prompt-speed changes in the release target larger cards.

| Model | Engine / setup | Memory | Pass (all runs) | Seed 1 | Avg tokens/run | Avg min/run | Total h | Decode t/s (agent) |
|---|---|---|---|---|---|---|---|---|
| Qwen3.8-Flash-Next GSQ IQ3_XXS | Strata 0.2.11 (engine 0.1.57) | 76 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 4,526 | 3.0 | 1.2 | 28.9 |
| Qwen3.8-Flash-Next Unsloth v3.1 UD-IQ3_XXS | Strata 0.2.11 (engine 0.1.57) | 84 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 4,298 | 3.2 | 1.3 | 24.6 |
| Qwen3.8-Flash-Next GSQ IQ3_S | Strata 0.2.11 (engine 0.1.57) | 84 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 3,958 | 3.2 | 1.3 | 23.3 |
| Qwen3.8-Flash-Next GSQ IQ3_XXS | Strata 0.2.7 (engine 0.1.52), 2026-10-29 | 76 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 3,767 | 2.7 | 1.1 | 28.0 |
| Qwen3.8-Flash-Next GSQ IQ3_S | Strata 0.2.7 (engine 0.1.52), 2026-10-29 | 84 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 3,992 | 3.2 | 1.3 | 24.2 |
| Qwen3.8-Flash-Next GSQ IQ3_XXS | llama.cpp (Unsloth b11027 mix), 2026-10-27 | 76 GB file, RAM + 8 GB GPU | 24/24 | 8/8 | 3,116 | 5.8 | 2.3 | 9.8 |
| TwIL-8B i1-Q4_K_M (Granite dense 8.8B) | llama.cpp b12169, --no-reasoning-preserve, seed 1 only | 5.4 GB, all on GPU (7.1 GB used) | 5/8 | 5/8 | 15,244 | 12.9 | 1.7 | 19.8 |
| TwIL-8B i1-Q4_K_M (Granite dense 8.8B) | llama.cpp b12169, reasoning kept in history, seed 1 only | 5.4 GB, all on GPU (7.1 GB used) | 5/8 | 5/8 | 13,444 | 17.0 | 2.3 | 13.5 |
| Ternary-Bonsai-2 27B PTQ1_0 | llama.cpp Ada-surgery runtime, 2026-10-28 | ~7 GB, all on GPU | 21/24 | 7/8 | 3,781 | 2.1 | 0.8 | 35.7 |

Decode t/s = completion tokens / generation seconds over the whole suite. TwIL ran seed 1 only (8 runs): compare it with the **Seed 1** column. All Strata runs: `--set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5`, 64k context, max 21,846 tokens per reply; Strata 0.2.11 used its default DFlash2 drafter, the October runs MTP.

### Per task (passed/runs · mean minutes)

| Task | GSQ IQ3_XXS · Strata 0.2.11 | Unsloth v3.1 UD-IQ3_XXS · Strata 0.2.11 | GSQ IQ3_S · Strata 0.2.11 | GSQ IQ3_XXS · Strata 0.2.7 | GSQ IQ3_S · Strata 0.2.7 | GSQ IQ3_XXS · llama.cpp | TwIL-8B · no-preserve | TwIL-8B · reasoning kept | Bonsai 2 27B |
|---|---|---|---|---|---|---|---|---|---|
| t1-bugfix-stats | 3/3 · 0.5 | 3/3 · 0.7 | 3/3 · 0.7 | 3/3 · 0.5 | 3/3 · 1.0 | 3/3 · 1.8 | 1/1 · 1.5 | 1/1 · 1.1 | 3/3 · 0.6 |
| t2-slugify | 3/3 · 2.1 | 3/3 · 3.8 | 3/3 · 2.2 | 3/3 · 2.1 | 3/3 · 2.4 | 3/3 · 5.5 | 1/1 · 5.5 | 1/1 · 9.1 | 3/3 · 1.8 |
| t3-refactor | 3/3 · 0.9 | 3/3 · 1.1 | 3/3 · 1.0 | 3/3 · 0.8 | 3/3 · 0.9 | 3/3 · 1.8 | 1/1 · 1.8 | 1/1 · 1.5 | 3/3 · 0.6 |
| t4-logparse | 3/3 · 1.8 | 3/3 · 1.4 | 3/3 · 2.6 | 3/3 · 2.9 | 3/3 · 4.2 | 3/3 · 4.9 | 1/1 · 1.6 | 1/1 · 1.7 | 2/3 · 1.8 |
| t5-config | 3/3 · 0.6 | 3/3 · 0.3 | 3/3 · 0.5 | 3/3 · 0.5 | 3/3 · 0.6 | 3/3 · 1.1 | 1/1 · 0.3 | 1/1 · 0.3 | 3/3 · 0.3 |
| t6-lru | 3/3 · 3.2 | 3/3 · 3.1 | 3/3 · 3.0 | 3/3 · 3.6 | 3/3 · 2.8 | 3/3 · 6.1 | 0/1 · 25.2 | 0/1 · 37.5 | 2/3 · 1.1 |
| t7-calc | 3/3 · 6.9 | 3/3 · 8.1 | 3/3 · 7.9 | 3/3 · 4.8 | 3/3 · 5.7 | 3/3 · 10.4 | 0/1 · 26.1 | 0/1 · 48.4 | 3/3 · 4.6 |
| t8-scheduler | 3/3 · 7.7 | 3/3 · 7.4 | 3/3 · 7.8 | 3/3 · 6.4 | 3/3 · 7.8 | 3/3 · 14.9 | 0/1 · 41.1 | 0/1 · 36.6 | 2/3 · 5.9 |

### Notes

- **Unsloth v3.1 download trick:** the 28.8 GB IQ4_NL engram table (shard 4 of UD-IQ3_XXS) is byte-identical to shard 2 of our GSQ files apart from its split header. A btrfs reflink copy plus Unsloth's `set_split.py` header patch reproduced Unsloth's sha256 exactly, so only 55 of 84 GB were downloaded and the table costs no extra disk.
- **TwIL-8B setup:** stock llama.cpp b12169 (no patches), mradermacher i1-Q4_K_M, KV q4_0 at 40k context, all 41 layers on the GPU. KV q8_0 only fits 24k; KV type does not change speed.
- **Bonsai 2 27B** is the earlier all-GPU comparison point: 21/24, 35.7 t/s, dropped on 2026-10-28.
- **Power:** GPU at its 35 W cap (~1.0-1.4 GHz) in every run; CPU 87-90 °C during Strata runs. The download was paused during the IQ3_S arm so it could not disturb RAM-resident experts.
- Logs: `overnight-strata0211-v31-20261107-0108.txt`, `llama-agent-eval-<label>.{log,jsonl,log.power}`, `llama-serve-<label>.engine.log`. Pipeline script: `overnight-strata0211-v31.sh`.

---

## PatchEval overview

- **DeepSeek V4.1 Flash through pi is the clear winner: 17/20 (85%)**, two more than the best local model, in **1.5 h instead of ~9 h**, for **about $1** for the whole suite. Median task: 2.5 min; local models typically run up to the 30-min limit.
- **Best local: Qwen3.8-Flash-Next on Strata, IQ3_XXS and IQ3_S both 15/20.** UD-IQ4_XS (14/20) buys nothing for its size. Ornith-1.5 122B and Bonsai 2 27B: 10/20.
- **Unsloth Dynamic v3.1 UD-IQ4_XS (2026-11-08): 12/20**, three below GSQ IQ3_XXS / IQ3_S, two below the old UD-IQ4_XS, so Unsloth's "+10-15% accuracy" claim does not show here. It decodes at only ~15 tok/s, so 13 of 20 tasks ran into the 30-min limit (7 timeouts, 6 passes at the deadline). It timed out on `json-repair-205` and `structlog-710`, which every other full run passed. It also used fewer output tokens per task (~21k vs ~31k for IQ3_XXS).
- **Scores include one re-graded task**: `pygments-2828`'s hidden test was flawed (BenchKit issue #89); every saved patch passes the fixed test, so each full run gains one pass (original scores shown as "orig."; re-graded cells marked *). A live re-run on the fixed test confirmed it for pi + DeepSeek.
- **MiniMax M3.1 Flash was dropped after 6 of 20 tasks** (3/6 with pi, 3/6 with mcode): it burned the $5 Vercel credit in ~15 task runs (≈ $0.33/task, ~7x DeepSeek per task) and needed the full 30 minutes on most tasks. On the same 6 tasks DeepSeek scored 5/6.
- **pi vs mcode on the same model** (MiniMax): equal score (3/6) and no clear token or speed difference. On the two tasks with complete counts mcode used 8-22% fewer output tokens; both agents ran into the 30-min limit on 4 of 6 tasks.

| # | Harness | Model | Think level | Output cap | Runs on | Score | Total wall | Median task | Avg stream tok/s | Cost |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | pi 0.84.2 | DeepSeek V4.1 Flash (1017) | max (OpenRouter reasoning.effort=max) | 64k | hosted: OpenRouter | 17/20 (85%, orig. 16) | 1.5 h | 2.5 min | 264 | $0.97 measured, OpenRouter (≈ $0.05/task) |
| 2 | pi 0.84.2 | Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS | server default: Strata high (template xhigh) | 16k | local: Strata 0.2.7, 64k ctx | 15/20 (75%, orig. 14) | 9.1 h | 30.0 min | 24 | no API cost; ~9-10 h of the laptop at full load |
| 3 | pi 0.84.2 | Qwen3.8-Flash-Next GSQ-RCO IQ3_S | server default: Strata high (template xhigh) | 16k | local: Strata 0.2.7, 64k ctx | 15/20 (75%, orig. 14) | 8.8 h | 30.0 min | 18 | no API cost; ~9-10 h of the laptop at full load |
| 4 | pi 0.84.2 | Qwen3.8-Flash-Next Unsloth UD-IQ4_XS | server default: Strata high (template xhigh) | 16k | local: Strata 0.2.7 (unsloth family), 64k ctx | 14/20 (70%, orig. 13) | 9.5 h | 30.0 min | 17 | no API cost; ~9-10 h of the laptop at full load |
| 5 | pi 0.84.2 | Qwen3.8-Flash-Next Unsloth Dynamic v3.1 UD-IQ4_XS | server default: Strata high (template xhigh) | 16k | local: Strata 0.2.11 (engine 0.1.57, DFlash2), 64k ctx | 12/20 (60%) | 9.0 h | 30.0 min | 15 | no API cost; ~9-10 h of the laptop at full load |
| 6 | pi 0.84.2 | Ornith-1.5-122B UD-Q4_K_XL | server default: thinking on (chat template) | 16k | local: llama.cpp b11170 (Unsloth), 32k ctx | 10/20 (50%, orig. 9) | 8.9 h | 30.0 min | 7 | no API cost; ~9-10 h of the laptop at full load |
| 7 | pi 0.84.2 | Bonsai 2 27B (Ada runtime) | medium, 20k thinking budget (runtime default) | 16k | local: Prism llama.cpp Ada build, 262k ctx | 10/20 (50%, orig. 9) | 9.7 h | 30.0 min | 25 | no API cost; ~9-10 h of the laptop at full load |
| – | pi 0.84.2 | MiniMax M3.1 Flash | max (thinkingLevelMap max) | 64k | hosted: Vercel AI Gateway | 3/6 (50%) * | 3.0 h (6 tasks) | 30.0 min | 182 | ≈ $0.33/task (measured $5.00 over ~15 MiniMax task runs) |
| – | mcode 0.7.2 (fork) | MiniMax M3.1 Flash | max (--effort max) | 64k | hosted: Vercel AI Gateway | 3/6 (50%) * | 2.9 h (6 tasks) | 30.0 min | 145 | ≈ $0.33/task (same $5.00 pool) |

\* stopped after 6 of 20 tasks; not ranked. Cost of local runs: electricity only.

### Same 6 tasks, all arms

| Harness | Model | Think level | Tasks 1-6 |
|---|---|---|---|
| pi 0.84.2 | DeepSeek V4.1 Flash (1017) | max (OpenRouter reasoning.effort=max) | 5/6 |
| pi 0.84.2 | Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS | server default: Strata high (template xhigh) | 3/6 |
| pi 0.84.2 | Qwen3.8-Flash-Next GSQ-RCO IQ3_S | server default: Strata high (template xhigh) | 2/6 |
| pi 0.84.2 | Qwen3.8-Flash-Next Unsloth UD-IQ4_XS | server default: Strata high (template xhigh) | 3/6 |
| pi 0.84.2 | Qwen3.8-Flash-Next Unsloth Dynamic v3.1 UD-IQ4_XS | server default: Strata high (template xhigh) | 3/6 |
| pi 0.84.2 | Ornith-1.5-122B UD-Q4_K_XL | server default: thinking on (chat template) | 2/6 |
| pi 0.84.2 | Bonsai 2 27B (Ada runtime) | medium, 20k thinking budget (runtime default) | 1/6 |
| pi 0.84.2 | MiniMax M3.1 Flash | max (thinkingLevelMap max) | 3/6 |
| mcode 0.7.2 (fork) | MiniMax M3.1 Flash | max (--effort max) | 3/6 |

### Read this before comparing

- The **output cap differs**: local runs used pi's default 16,384 tokens per reply, the hosted runs 64k. DeepSeek's replies average ~580 tokens (task maximum of the average: 928), so a 16k cap would almost certainly not have changed its score; strictly provable are 4 passes whose whole task stayed under 16k output (per-reply counts were added after this run).
- The **think level differs by design**: hosted runs at the highest level the provider offers (`max`); local runs at their runtime's default (thinking on). BenchKit's pi entry sends no reasoning setting, so the local servers chose.
- **Speed is not hardware-equal**: hosted tok/s depends on which upstream provider the gateway picked (OpenRouter served DeepSeek from Sail Research and InferenceNet at different times; Vercel served MiniMax from Fireworks or MiniMax). Local tok/s is one laptop (RTX 4070 Laptop 8 GB, i7-13700H, 125 GB RAM).
- **pi version**: BenchKit v0.2.0 pins pi **0.84.2** (2026-08-14) in the sandbox, for every run here; the pi on this machine is 1.4.0 (2026-10-21). Scores reflect the older agent.
- **The v3.1 run used a newer engine**: Strata 0.2.11 (engine 0.1.57) with DFlash2 drafting, where the other local Qwen3.8 runs used 0.2.7 with MTP. Same-quant speed on the agent suite is equal on both. It ran on the fixed dataset (`pilot-20-local1`), so its `pygments-2828` pass is live, not re-graded.
- **Passing at the deadline**: PatchEval grades the workspace even when the agent is stopped at 30 min, so many local and MiniMax passes are fixes that were already in place when time ran out.

## Details

### Setup (all runs)

|  |  |
|---|---|
| Benchmark | BenchKit v0.2.0 PatchEval, frozen release pilot-20: 20 real bug fixes from 12 Python projects, graded by hidden tests |
| Agent sandbox | fresh Docker container per task, /workspace only, no network except a restricted inference proxy |
| Limits | 30 min (1800 s) per task, one task at a time, no repair attempts |
| pi | stock pi coding agent 0.84.2, tools read / bash / edit / write |
| mcode | MiniMax Code 0.7.2 (our OpenRouter fork, as run by `mcode-or`), its own tools and prompt, `mcode exec --effort max`, run inside the same sandbox |

### Per task

✓ pass · ✗ fail · ⏱ timeout (30 min) · L reply hit the output cap · — not run. Number = minutes. * re-graded with the fixed `pygments-2828` test (see *Why some tasks fail*).

| Task | DeepSeek V4.1 Flash (pi) | Qwen3.8 IQ3_XXS (pi) | Qwen3.8 IQ3_S (pi) | Qwen3.8 UD-IQ4_XS (pi) | Qwen3.8 UD-IQ4_XS v3.1 (pi) | Ornith-1.5 122B (pi) | Bonsai 2 27B (pi) | MiniMax M3.1 Flash (pi) | MiniMax M3.1 Flash (mcode) |
|---|---|---|---|---|---|---|---|---|---|
| sqlit-246 | ✓ 2m | ✓ 30m | ✓ 17m | ✓ 30m | ✓ 21m | ✓ 17m | ✓ 16m | ✓ 30m | ✓ 30m |
| sqlit-260 | ✗ 3m | ✓ 30m | ✗ 24m | ✓ 30m | ⏱ 30m | ✗ 16m | ✗ 22m | ⏱ 30m | ✓ 30m |
| narwhals-3864 | ✓ 5m | ⏱ 30m | L 30m | ⏱ 30m | ⏱ 30m | L 30m | ⏱ 30m | ⏱ 30m | ⏱ 30m |
| city2graph-121 | ✓ 3m | ✗ 1m | ✓ 30m | ✓ 30m | ✓ 30m | ✓ 30m | ⏱ 30m | ✓ 30m | ✗ 17m |
| json-repair-207 | ✓ 5m | L 30m | L 30m | ⏱ 30m | ⏱ 30m | L 30m | ⏱ 30m | ✓ 30m | ✓ 30m |
| json-repair-191 | ✓ 4m | ✓ 30m | ⏱ 30m | ⏱ 30m | ✓ 30m | ⏱ 30m | ⏱ 30m | ✗ 7m | ✗ 8m |
| json-repair-205 | ✓ 2m | ✓ 30m | ✓ 30m | ✓ 30m | ⏱ 30m | ✓ 30m | ✓ 30m | — | — |
| click-3572 | ✓ 2m | ✓ 30m | ✓ 19m | ✓ 19m | ✓ 30m | ✓ 30m | ✓ 30m | — | — |
| click-3360 | ✓ 1m | ✓ 5m | ✓ 5m | ✓ 6m | ✓ 6m | ✓ 9m | ✓ 19m | — | — |
| click-2790 | ✓ 1m | ✓ 10m | ✓ 8m | ✓ 15m | ✓ 11m | ✓ 8m | ✓ 23m | — | — |
| pypdf-3982 | ✓ 6m | ✓ 30m | ✓ 30m | ✓ 30m | ✓ 30m | ⏱ 30m | ⏱ 30m | — | — |
| pypdf-3878 | ✓ 2m | ⏱ 30m | ✓ 30m | ⏱ 30m | ⏱ 30m | L 30m | ✓ 30m | — | — |
| pypdf-3587 | ✓ 2m | ✓ 24m | ✓ 23m | ✓ 30m | ✓ 30m | ✓ 30m | ✓ 30m | — | — |
| attrs-1575 | ✓ 2m | ✓ 30m | ✓ 23m | ✓ 23m | ✓ 23m | ✓ 30m | ⏱ 30m | — | — |
| typeguard-499 | ✗ 3m | ✓ 30m | ✓ 30m | ⏱ 30m | ✓ 30m | ⏱ 30m | ⏱ 30m | — | — |
| structlog-710 | ✓ 5m | ✓ 30m | ✓ 30m | ✓ 30m | ⏱ 30m | L 30m | ✓ 30m | — | — |
| pygments-2816 | ✗ 4m | L 30m | ⏱ 30m | ⏱ 30m | ⏱ 30m | L 30m | ⏱ 30m | — | — |
| pygments-2828 | ✓* 2m | ✓* 22m | ✓* 18m | ✓* 19m | ✓ 19m | ✓* 12m | ✓* 19m | — | — |
| tomlkit-440 | ✓ 3m | ✓ 30m | ✓ 30m | ✓ 30m | ✓ 27m | ⏱ 30m | ⏱ 30m | — | — |
| tomlkit-542 | ✓ 1m | ✓ 30m | ✓ 21m | ✓ 30m | ✗ 4m | ✓ 19m | ✓ 26m | — | — |
| **passed** | **17/20** | **15/20** | **15/20** | **14/20** | **12/20** | **10/20** | **10/20** | **3/6** | **3/6** |

### pi + DeepSeek V4.1 Flash (1017) · think max

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | DeepSeek V4.1 Flash (1017) |
| Think level | max (OpenRouter reasoning.effort=max) |
| Output cap per reply | 64k tokens |
| Runs on | hosted: OpenRouter |
| Score | 17/20 (85%, orig. 16) |
| Outcomes | 17 pass, 3 fail |
| Passes reached at the 30-min deadline | 0 |
| Total wall clock | 1.54 h for 20 tasks |
| Per task (median / mean) | 2.5 / 3.0 min |
| Avg stream tok/s | 264 |
| Output tokens | 0.48 M total, 23,963 per task |
| Input tokens (incl. cache) | 39.8 M total, 1.99 M per task |
| Assistant replies | 824 (largest per-task average 928 tokens/reply) |
| Replies cut by the output cap | 0 |
| Cost | $0.97 measured, OpenRouter (≈ $0.05/task) |
| Raw results | results/2026-11-01_16-54-55 |

### pi + Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS · think server

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS |
| Think level | server default: Strata high (template xhigh) |
| Output cap per reply | 16k tokens |
| Runs on | local: Strata 0.2.7, 64k ctx |
| Score | 15/20 (75%, orig. 14) |
| Outcomes | 15 pass, 2 timeout, 2 length limit, 1 fail |
| Passes reached at the 30-min deadline | 10 |
| Total wall clock | 9.14 h for 20 tasks |
| Per task (median / mean) | 30.0 / 25.6 min |
| Avg stream tok/s | 24 |
| Output tokens | 0.62 M total, 30,967 per task |
| Input tokens (incl. cache) | 29.7 M total, 1.48 M per task |
| Assistant replies | 951 (largest per-task average 1,181 tokens/reply) |
| Replies cut by the output cap | 2 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Raw results | results/2026-10-30_09-31-39 |

### pi + Qwen3.8-Flash-Next GSQ-RCO IQ3_S · think server

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Qwen3.8-Flash-Next GSQ-RCO IQ3_S |
| Think level | server default: Strata high (template xhigh) |
| Output cap per reply | 16k tokens |
| Runs on | local: Strata 0.2.7, 64k ctx |
| Score | 15/20 (75%, orig. 14) |
| Outcomes | 15 pass, 2 length limit, 2 timeout, 1 fail |
| Passes reached at the 30-min deadline | 7 |
| Total wall clock | 8.78 h for 20 tasks |
| Per task (median / mean) | 30.0 / 24.5 min |
| Avg stream tok/s | 18 |
| Output tokens | 0.46 M total, 23,162 per task |
| Input tokens (incl. cache) | 21.7 M total, 1.08 M per task |
| Assistant replies | 765 (largest per-task average 1,332 tokens/reply) |
| Replies cut by the output cap | 4 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Raw results | results/2026-10-30_18-19-26 |

### pi + Qwen3.8-Flash-Next Unsloth UD-IQ4_XS · think server

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Qwen3.8-Flash-Next Unsloth UD-IQ4_XS |
| Think level | server default: Strata high (template xhigh) |
| Output cap per reply | 16k tokens |
| Runs on | local: Strata 0.2.7 (unsloth family), 64k ctx |
| Score | 14/20 (70%, orig. 13) |
| Outcomes | 14 pass, 6 timeout |
| Passes reached at the 30-min deadline | 9 |
| Total wall clock | 9.50 h for 20 tasks |
| Per task (median / mean) | 30.0 / 26.6 min |
| Avg stream tok/s | 17 |
| Output tokens | 0.49 M total, 24,720 per task |
| Input tokens (incl. cache) | 22.8 M total, 1.14 M per task |
| Assistant replies | 822 (largest per-task average 1,211 tokens/reply) |
| Replies cut by the output cap | 2 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Raw results | results/2026-10-31_09-58-47 |

### pi + Qwen3.8-Flash-Next Unsloth Dynamic v3.1 UD-IQ4_XS · think server

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Qwen3.8-Flash-Next Unsloth Dynamic v3.1 UD-IQ4_XS |
| Think level | server default: Strata high (template xhigh) |
| Output cap per reply | 16k tokens |
| Runs on | local: Strata 0.2.11 (engine 0.1.57, DFlash2), 64k ctx |
| Score | 12/20 (60%) |
| Outcomes | 12 pass, 7 timeout, 1 fail |
| Passes reached at the 30-min deadline | 6 |
| Total wall clock | 8.95 h for 20 tasks |
| Per task (median / mean) | 30.0 / 25.1 min |
| Avg stream tok/s | 15 |
| Output tokens | 0.42 M total, 20,861 per task |
| Input tokens (incl. cache) | 18.6 M total, 0.93 M per task |
| Assistant replies | 706 (largest per-task average 1,671 tokens/reply) |
| Replies cut by the output cap | 0 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Largest single reply | 6,141 output tokens (0 replies over 16k; 20 tasks with per-reply data) |
| Score if capped at 16k per reply | 12/20 (a pass with any reply over 16,384 tokens counts as fail) |
| Upstream providers (requests) | ? 718 |
| Measured API cost (from the gateway) | $0.000 over 718 requests (20 tasks) |
| Median time to first token / decode speed | 2.8 s / 29 tok/s |
| Raw results | results/2026-11-08_09-49-31 |

### pi + Ornith-1.5-122B UD-Q4_K_XL · think server

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Ornith-1.5-122B UD-Q4_K_XL |
| Think level | server default: thinking on (chat template) |
| Output cap per reply | 16k tokens |
| Runs on | local: llama.cpp b11170 (Unsloth), 32k ctx |
| Score | 10/20 (50%, orig. 9) |
| Outcomes | 10 pass, 5 length limit, 4 timeout, 1 fail |
| Passes reached at the 30-min deadline | 5 |
| Total wall clock | 8.94 h for 20 tasks |
| Per task (median / mean) | 30.0 / 25.0 min |
| Avg stream tok/s | 7 |
| Output tokens | 0.20 M total, 10,058 per task |
| Input tokens (incl. cache) | 6.7 M total, 0.34 M per task |
| Assistant replies | 493 (largest per-task average 1,021 tokens/reply) |
| Replies cut by the output cap | 7 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Raw results | results/2026-11-01_10-55-28 |

### pi + Bonsai 2 27B (Ada runtime) · think medium

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | Bonsai 2 27B (Ada runtime) |
| Think level | medium, 20k thinking budget (runtime default) |
| Output cap per reply | 16k tokens |
| Runs on | local: Prism llama.cpp Ada build, 262k ctx |
| Score | 10/20 (50%, orig. 9) |
| Outcomes | 10 pass, 9 timeout, 1 fail |
| Passes reached at the 30-min deadline | 5 |
| Total wall clock | 9.66 h for 20 tasks |
| Per task (median / mean) | 30.0 / 27.3 min |
| Avg stream tok/s | 25 |
| Output tokens | 0.79 M total, 39,655 per task |
| Input tokens (incl. cache) | 35.0 M total, 1.75 M per task |
| Assistant replies | 965 (largest per-task average 1,853 tokens/reply) |
| Replies cut by the output cap | 0 |
| Cost | no API cost; ~9-10 h of the laptop at full load |
| Raw results | results/2026-10-28_13-27-34 |

### pi + MiniMax M3.1 Flash · think max

|  |  |
|---|---|
| Harness | pi 0.84.2 |
| Model | MiniMax M3.1 Flash |
| Think level | max (thinkingLevelMap max) |
| Output cap per reply | 64k tokens |
| Runs on | hosted: Vercel AI Gateway |
| Score | 3/6 (50%) — stopped after 6/20: Vercel credit ($5) used up |
| Outcomes | 3 pass, 2 timeout, 1 fail |
| Passes reached at the 30-min deadline | 3 |
| Total wall clock | 3.01 h for 6 tasks |
| Per task (median / mean) | 30.0 / 26.2 min |
| Avg stream tok/s | 182 |
| Output tokens | 1.37 M total, 228,234 per task |
| Input tokens (incl. cache) | 43.0 M total, 7.17 M per task |
| Assistant replies | 395 (largest per-task average 4,392 tokens/reply) |
| Replies cut by the output cap | 0 |
| Cost | ≈ $0.33/task (measured $5.00 over ~15 MiniMax task runs) |
| Largest single reply | 21,864 output tokens (1 replies over 16k; 1 tasks with per-reply data) |
| Raw results | results/2026-11-01_18-01-14, results/2026-11-01_18-11-11 |
| Note | task 6: 17 replies, the largest 21,864 output tokens (above a 16k cap). |

### mcode + MiniMax M3.1 Flash · think max

|  |  |
|---|---|
| Harness | mcode 0.7.2 (fork) |
| Model | MiniMax M3.1 Flash |
| Think level | max (--effort max) |
| Output cap per reply | 64k tokens |
| Runs on | hosted: Vercel AI Gateway |
| Score | 3/6 (50%) — stopped after 6/20: Vercel credit ($5) used up |
| Outcomes | 3 pass, 2 fail, 1 timeout |
| Passes reached at the 30-min deadline | 3 |
| Total wall clock | 2.87 h for 6 tasks |
| Per task (median / mean) | 30.0 / 24.2 min |
| Avg stream tok/s | 145 |
| Output tokens | 0.37 M total, 60,869 per task |
| Input tokens (incl. cache) | 9.6 M total, 1.59 M per task |
| Assistant replies | 350 (largest per-task average 6,418 tokens/reply) |
| Replies cut by the output cap | 0 |
| Cost | ≈ $0.33/task (same $5.00 pool) |
| Largest single reply | 16,238 output tokens (0 replies over 16k; 2 tasks with per-reply data) |
| Raw results | results/2026-11-01_17-59-48, results/2026-11-01_18-11-20, results/2026-11-01_18-11-44 |
| Note | mcode reports usage only at the end of a run, so the 3 tasks it was still working on at the 30-min limit have no token counts; totals here are a lower bound. Complete counts vs pi: json-repair-207 225k vs 245k output, json-repair-191 48k vs 61k. |

### Why some tasks fail

| Task | What happened |
|---|---|
| pygments-2828 (nobody passed): benchmark flaw | The hidden test is a golden file of exact token types and expects each slice `:` in `numbers[1::2]` as `Operator`. But the task's own `jsonnet.py` marks every `:` as `Punctuation` (lines 98, 155) and its operator rule has no `:`; the upstream fix added it. Four models followed the file's convention (`Punctuation`), two emitted `::` as one `Punctuation` token: all six failed on a choice nothing pointed to. Reported upstream: https://github.com/DogukanUrker/BenchKit/issues/89. Fixed locally in dataset `pilot-20-local1` (accepts `Operator` or `Punctuation`); the v3.1 UD-IQ4_XS run used the fixed test and passed it. All six saved patches pass the fixed test, so this report re-grades them as passes (`reports/patcheval-regrades.json`); the raw BenchKit results keep the original fails. |
| pygments-2816 (nobody passed) | DeepSeek's change broke two existing, visible tests (`general.jsx`, `test_aria_attribute.txt`) and its tokens for `I'm` differ from the golden file. A fair failure: running the existing tests would have caught it. |
| sqlit-260 (3 of 9 passed: IQ3_XXS, UD-IQ4_XS, mcode+MiniMax) | Not random. The issue asks to drop the trailing `;` that breaks `ALTER SESSION`. The hidden tests also require keeping `;` where PL/SQL needs it (`BEGIN … END;`, `DECLARE`, `CREATE … PROCEDURE`, comments). Every failing model, DeepSeek included, stripped `;` everywhere; the passes knew the Oracle rule without being told. |
| typeguard-499 (DeepSeek failed; Qwen3.8 IQ3_XXS, IQ3_S and UD-IQ4_XS v3.1 passed) | DeepSeek fixed exactly the reported repro in 3 min: it accepts a protocol member when the class *annotates* it (true in the issue, where the class inherits the protocol). The hidden test uses a class that only sets `self.foo` in `__init__`, with no annotation. IQ3_XXS spent 30 min and also detected attributes assigned on `self` (`__static_attributes__`, bytecode on older Pythons). |
| Pattern | DeepSeek's fails are fast (2-4 min) and narrow: it stops once the reported example works. The local models use the full 30 min and sometimes generalise further, which is how they win typeguard-499; more often the time runs out (timeouts). |

### Other runs (not in the tables)

- **pygments-2828 re-run on the fixed test** (`pilot-20-local1`, 2026-11-02, DeepSeek V4.1 Flash 1017, think max, 64k): **pi PASS** (2.0 min, $0.058, provider Cohere). **mcode FAIL** (1.9 min, $0.034, Cohere/Relace), but not for a mistake. Both agents found that the number pattern `(.[0-9])?` has an unescaped `.` (it lexes `1:8` in `[1:8:2]` as a number; still present in Pygments 2.21.0) and escaped it. mcode also let fractions have several digits (`2.25` as one token), said so in its answer, added slice tests, updated the one affected expected-output file and ran the full suite (5,307 passed). PatchEval discards agent edits to test files, so the changed output counted as a regression. The score cannot tell a disclosed, deliberate improvement from a regression; it rewards minimal fixes.
- Bonsai 2 27B with thinking **off**: stopped after 3 tasks (1/3), same per-task results as thinking on.
- MiniMax M3.1 Flash, pi, **16k cap, default thinking** (smoke test, 1 task): FAIL on `sqlit-246` (one reply hit the 16k limit). With 64k and `max` the same task passed.
- Two MiniMax runs were stopped and resumed at task boundaries (no task run twice); mcode's `city2graph-121` first hit a full disk (harness error, excluded) and was re-run (fail).

### Sources

- Per-task data: `reports/patcheval-data.json` (merged from the BenchKit `results.json` files listed per run); regenerate with `python3 reports/make_patcheval_report.py`.
- Costs: OpenRouter key usage on 2026-11-01 ($0.971, the DeepSeek run only); Vercel AI Gateway credits (total used $5.00).
- Earlier write-ups: `2026-10-30_18-20_Benchmark_Summary_Qwen3.8-flash-next-Strata.md`, `2026-11-01_11-00_Benchmark_Summary_Ornith-1.5-122B.md`, `handover-bonsai2-ada-evaluation.md`.
