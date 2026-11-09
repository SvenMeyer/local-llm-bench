# AI-Runtime

Local LLM inference on this machine: **i7-13700H + RTX 4070 Laptop 8 GB**,
125 GB RAM, Manjaro KDE. llama.cpp built from source against CUDA 13.3.

Current focus: running **Qwen3.8-Flash-Next** (`unsloth/Qwen3.8-Flash-Next-GGUF`,
UD-IQ4_XS, 93.7 GB) — a 125 B / 6 B-active hybrid MoE, llama.cpp arch `qwen4exp`.

## Start here

| file | what it covers |
|---|---|
| **[llama-compile-guide.md](llama-compile-guide.md)** | machine spec, cmake flags and why, toolchain gotchas, how to rebuild or build a PR worktree |
| **[llama-run-guide.md](llama-run-guide.md)** | the model's architecture, memory budget, every runtime flag, MTP, sampling |
| **[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)** | how to measure, what to vary, **running log of configs tried and their tok/s** |
| **[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md)** | **this combo:** Unsloth Studio + UD-IQ4_XS + MTP patch, RAM modes, how to start |
| **[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md)** | **fresh session:** how to run the scaled Group A/B/C bench (start here) |
| **[llama-todo.md](llama-todo.md)** | open work and known unknowns |
| **[strata-engine-evaluation.md](strata-engine-evaluation.md)** | the Strata engine + ISTA-DASLab GSQ-RCO quants for *this* model — 8 GB VRAM arithmetic, quality evidence, and the test order |
| **[PATCHEVAL-RUNBOOK.md](PATCHEVAL-RUNBOOK.md)** | **benchmark a model or agent on PatchEval** (local or hosted, pi or mcode) and update the comparison report in [reports/](../reports/) |
| **[handover-strata-evaluation.md](handover-strata-evaluation.md)** | **next session starts here (2026-10-29)**: Qwen3.8 on Strata: setup, probe results, overnight eval, next decisions |
| **[handover-bonsai2-ada-evaluation.md](handover-bonsai2-ada-evaluation.md)** | **next session starts here (2026-10-28)**: Bonsai 2 27B on the Ada-surgery runtime: setup, all results, gotchas, and how to resume the thinking-off PatchEval |
| **[handover-gsq-q2_0-evaluation.md](handover-gsq-q2_0-evaluation.md)** | (done 2026-10-27) — self-contained: download Q2_0, launch it, benchmark against the UD-IQ4_XS baseline |
| `llama.cpp-test.sh` | append-only raw log: commands actually run, numbers actually measured, going back to 2026-04 |
| `llama-bench-ctx-sweep.sh` | context **allocation** sweep — what context fits and what reserving it costs. **Do not** use on this 90 GB model (respawns a server per size) |
| `llama-bench-occupied-ctx.py` | context **occupancy** probe — speed once the window holds real tokens |
| `gguf_head.py` | read a **remote** GGUF's header + per-tensor quant types via HTTP range request — validate a 70 GB download for ~24 MB |
| `llama-bench-qwen38-unsloth-occupied.sh` | one-shot Qwen3.8 occupied probe: one reload to 16384 + MTP, then ~0.5k/2k/4k/8k |
| `llama-bench-ternary-bonsai2.sh` | Ternary-Bonsai-2 PTQ1_0 / PQ2_0 llama-bench + ctx + occupied (Prism fork) |

Guides are the distilled knowledge; `llama.cpp-test.sh` is the raw history.
When a measurement changes what we believe, update the guide *and* log the raw
output.

## Builds

| path | version | purpose |
|---|---|---|
| `llama.cpp/` | `11011 (aa39d7a3e)` | canonical mainline. `/usr/local/bin/llama-server` symlinks here |
| `llama.cpp-mtp/` | `10802 (d1a92352c)` | git worktree of PR #28243 — **only** build that supports MTP for this model |
| `llama.cpp-prism/` | `10706 (1a07bfa5f)` | git worktree of `prism/prism` (PrismML-Eng/llama.cpp). **Required** for Ternary-Bonsai-2 `PTQ1_0` / `PQ2_0`. Do not install over `/usr/local/bin` |
| `llama.cpp-bin-backup-b10016/` | — | previous build's binaries, delete once the new one is trusted |
| `~/.unsloth/llama.cpp/` | `b11027-mix-pr220` `11166 (10921f3f1)` | Unsloth Studio engine. Official MTP pin `#144@ca1426903` (PR #220). Source `~/.unsloth/llama.cpp-mix-pr220/`. Published `b11027-mix-3e83366` still has the broken pin. See [setup](llama-qwen38-flash-next-unsloth.md) |

One canonical clone plus worktrees — do not add fresh clones.

## Launchers

All take env-var overrides, e.g. `LLAMA_ARG_CTX_SIZE=131072 ./llama-serve-…sh`.

| script | model |
|---|---|
| `llama-serve-qwen38-flash-next.sh` | Qwen3.8-Flash-Next (mainline build, **no MTP**) |
| `llama-serve-qwen38-flash-next-mtp.sh` | Qwen3.8-Flash-Next + MTP (`llama.cpp-mtp` / PR #28243) |
| `llama-serve-qwen38-flash-next-unsloth.sh` | Qwen3.8-Flash-Next via **Unsloth Studio** (tools off, full-RAM flags) |
| `llama-serve.sh` | Ornith 1.0 35B |
| `llama-serve-mtp.sh` | Qwen3.6-35B-A3B-MTP |
| `llama-serve-ornith-mtp.sh` | Ornith 35B + community MTP graft |
| `llama-serve-bonsai.sh` | Bonsai 27B Q1_0 (mainline) |
| `llama-serve-ternary-bonsai2.sh` | Ternary-Bonsai-2-27B PTQ1_0 / PQ2_0 (Prism fork) |

## Three things that will bite you

1. **Never pass `--no-mmap` or `--mlock`** to Qwen3.8-Flash-Next. 28.8 GB of it
   is an n-gram table loaded lazily row-by-row; either flag turns that into a
   real allocation. [Details](llama-run-guide.md#3-the-single-most-important-fact)
2. **MTP is not one binary.** Mainline **silently ignores** `-md`. Published
   Unsloth `*-mix-3e83366` **crashes** then pretends it loaded. Live engine is
   the PR #220 mix (`#144@ca1426903`) in `~/.unsloth/llama.cpp`.
   [Details](llama-qwen38-flash-next-unsloth.md#4-mtp-on-unsloths-engine)
3. **This model's sampling differs** from the other Qwen models here: temp
   **1.0**, min-p **0.0** (not 0.6 / 0.05).
   [Details](llama-run-guide.md#6-sampling--different-from-the-other-qwen-models-here)
4. **Allocated context ≠ usable context.** Reserving 180k costs ~12% TG, but
   *filling* 65k cost 23% and 129k cost 83% (Qwen3.6-35B-A3B, 2026-09-17). Always
   run both benchmark scripts; quoting only the allocation number overstates what
   you can actually use. Also: don't swap Unsloth Studio onto a local build — its
   `b11007-mix` fork measured **9% faster** than our `-march=native` b11011, because
   it already targets `sm_89` natively *and* carries modified quant/flash-attention
   kernels. Keep the local build for `llama-bench`/`llama-perplexity`, which Unsloth
   does not ship. [Details](llama-benchmark-and-tuning-guide.md#5-results-log)

---

*Status 2026-09-27: Qwen3.8-Flash-Next now runs the **GSQ-RCO Q2_0** quant by
default. Same engine, 16384 + MTP: **21.2 t/s TG at 8k occupied vs 9.8 t/s**
for UD-IQ4_XS (PP 180 vs 117), with 4.8 GB VRAM and 61 GiB RAM. Quality cost:
wikitext PPL 3.36 vs 2.74. The house Solidity prompt is correct at temp 1.0;
do not run it greedy. The engine is mix-pr220 plus an x86 Q2_0 AVX-VNNI kernel
(`11170 / a2fa025fb`, `llama-unsloth-mix-pr220-q2_0-build.sh`). The newer
b11160 mix was tested and rejected: no faster, and its CUDA fusion corrupts
greedy output. `QUANT=iq4xs` on the launcher restores UD-IQ4_XS. How to start:

**2026-10-27 quant shoot-out** (speed table, group H): GSQ IQ3_XXS (`QUANT=gsq-iq3xxs`) is the
quality pick at 11.3 t/s (KLD 0.29 vs IQ4_XS), Q2_0 stays the speed pick at ~21 t/s (KLD 0.50), and the
GSQ Coder (`QUANT=coder`) loses on both (5.4 t/s, KLD 0.94). All three passed 24/24 of the tool-calling
agent eval (`llama-agent-eval.py`).

**2026-10-26:** an `unsloth` update (2026.10.5) silently replaced the engine
with stock `b11541`, which has no x86 Q2_0 kernel (**3.5 t/s**). 11170 was
restored into `~/.unsloth/llama.cpp/build/bin` (stock kept in
`bin-b11541-stock`): 20–21 t/s TG and, from Studio's new `--ubatch-size 2048`,
PP ~300 t/s at 8k. **After every `unsloth` update, check
`~/.unsloth/llama.cpp/BUILD_INFO.txt`** and re-copy if it is not
`+q2_0-avxvnni`. UD-IQ4_XS needs ub 1024 with MTP (the launcher sets it). Group G.

[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md).

Results: [llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md) §5 Groups E/F/G. One-row-per-config summary: [llama-speed-table.md](llama-speed-table.md).
How to bench: [llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md).
Do **not** use `llama-bench-ctx-sweep.sh` on this model.*

***Next step (optional):** only if Q2_0's quality cost shows in real work, try
GSQ `IQ3_XXS` (shard 1 only, +47.04 GB; shard 2 is byte-identical, so symlink it).
Free disk first: `/home` has ~20 G. Strata stays out of scope until then; see
[strata-engine-evaluation.md](strata-engine-evaluation.md).*

*Status 2026-10-28: Bonsai 2 27B on the Ada-surgery runtime (`llama-serve-bonsai2-ada.sh`): 1.5-2x stock Prism decode,
~30 t/s at 8k, PatchEval 9/20 with thinking on. Next step: resume the thinking-off PatchEval, see
[handover-bonsai2-ada-evaluation.md](handover-bonsai2-ada-evaluation.md) §7.*

*Status 2026-10-28 evening: **Bonsai 2 dropped** (not capable enough). Qwen3.8-Flash-Next on the **Strata engine** runs IQ3_XXS at ~38 t/s decode (llama.cpp ~9-10). Overnight result (2026-10-29): **Strata + ISTA IQ3_XXS + `--set STRATA_ROUTE_TAIL_SKIP=0` = 24/24 in 64.5 min vs llama.cpp 24/24 in 140 min**; pi agent 24/24 on it. Details and next steps: [handover-strata-evaluation.md](handover-strata-evaluation.md).*

*Status 2026-10-30: **PatchEval through pi (20 real bug fixes, 30 min each) on Strata: IQ3_XXS 14/20 and IQ3_S 14/20** (Bonsai 2: 9/20). IQ3_XXS decodes 24 t/s vs 17, IQ3_S needs 25% fewer tokens, so time per task is equal. UD-IQ4_XS 13/20 at 16 t/s (2026-10-31): no gain. **Daily pick: IQ3_XXS.** Details: [handover-strata-evaluation.md](handover-strata-evaluation.md).*

*Status 2026-11-01: **Ornith-1.5-122B UD-Q4_K_XL: PatchEval 9/20** (llama.cpp, 32k, 7 t/s: Strata refuses its IQ4_XS/Q6_K experts). 2.5x fewer tokens than Qwen3.8 but 3x slower decode, so 9 tasks hit the 30-min limit. **Strata updated to 0.2.9 (engine 0.1.55): it turns residency-biased routing OFF by default** (IQ3_S suite 24/24 but 16.3 t/s vs 24.2); add `--set STRATA_ROUTE_PRIOR=1.5` to keep the old setup. **Daily pick stays IQ3_XXS.** Details: [2026-11-01_11-00_Benchmark_Summary_Ornith-1.5-122B.md](2026-11-01_11-00_Benchmark_Summary_Ornith-1.5-122B.md).*

*Status 2026-11-02: **hosted DeepSeek V4.1 Flash (pi, think max) PatchEval 16/20 in 1.5 h for ~$0.81-0.97**, ahead of the best local model (Qwen3.8 IQ3_XXS/IQ3_S, 14/20, ~9 h). MiniMax M3.1 Flash dropped (3/6, ~$0.33/task). Report: [reports/2026-11-02_PatchEval_Report_local-vs-hosted.md](../reports/2026-11-02_PatchEval_Report_local-vs-hosted.md). Next runs: follow [PATCHEVAL-RUNBOOK.md](PATCHEVAL-RUNBOOK.md).*

*Status 2026-11-03: **Strata 0.2.9 speed restored**: `STRATA_ROUTE_PRIOR=1.5` is now in the saved launch configs and `patcheval-strata-quants.sh`. PatchEval IQ3_S tasks 1-6 (60 min/task, 64k cap) on engine 0.1.55: 3/6, 20.7 t/s decode, the same as 0.1.52 (19.8 t/s). Upstream issue: [Niko1221/Strata#5000](https://github.com/Niko1221/Strata/issues/5000). Log: `benchkit-patcheval-strata-iq3s-noskip-prior15-64k-t3600-first6.log`, results `benchkit-src/BenchKit/results/2026-11-03_06-21-42`.*

*Status 2026-11-06: **TwIL-8B (webAI, Granite 4.2 dense 8.8B reasoning model) runs on stock llama.cpp, no patches.** The canonical clone was updated b11011 -> **b12169** (old binaries in `llama.cpp-bin-backup-b11011`; the Unsloth engine for Qwen3.8 is untouched, since our Q2_0 kernel PR ggml-org#26348 is still open). Quant: `mradermacher/TwIL-8B-i1-GGUF` **i1-Q4_K_M** (balanced variant, 5.35 GB). Launcher `llama-serve-twil8b.sh`: all layers on the GPU, **KV q4_0 at 40k** (q8_0 fits only 24k; KV type does not change speed). Speed at the 35 W GPU cap: TG ~30 t/s on an empty context, 19 at 16k, 15 at 24k; real answers 26-27 t/s. Math and code smoke tests correct. Rows: [llama-speed-table.md](llama-speed-table.md) "TwIL-8B". Next step (optional): PatchEval or the agent eval on it.*

*Status 2026-11-07 (overnight, agent suite 24 runs each): **Strata updated 0.2.10 -> 0.2.11 (engine 0.1.57); no speed change on this card** (same-quant decode matches October). On 0.2.11, all with `STRATA_ROUTE_TAIL_SKIP=0 STRATA_ROUTE_PRIOR=1.5`: **GSQ IQ3_XXS 24/24, 1.2 h, 28.9 t/s (daily pick stays)**; Unsloth **v3.1 UD-IQ3_XXS** 24/24, 1.3 h, 24.6 t/s (84 GB, ties but slower; its 28.8 GB engram shard is a reflink of our GSQ shard 2); GSQ IQ3_S 24/24, 1.3 h, 23.3 t/s. **TwIL-8B: 5/8** (seed 1; fails t6-t8 at 25-48 min each; `--no-reasoning-preserve` is faster, same score) - not an agent model for us. Deleted to free disk: old Unsloth UD-IQ4_XS and Ornith-1.5. Report: [reports/2026-11-02_PatchEval_Report_local-vs-hosted.md](../reports/2026-11-02_PatchEval_Report_local-vs-hosted.md) (new top section). Next (optional): PatchEval UD-IQ3_XXS vs GSQ IQ3_XXS to test Unsloth's accuracy claim (~9 h each).*

*Status 2026-11-07 (afternoon): Unsloth v3.1 **UD-IQ4_XS** (94 GB, Strata name `ud-iq4_xs-v31`) downloaded for a later PatchEval run (shard 4 reflinked from UD-IQ3_XXS). Plan and commands: [handover-unsloth-v31-patcheval.md](handover-unsloth-v31-patcheval.md); arms `ud31iq3xxs` / `ud31iq4xs` added to `patcheval-strata-quants.sh`.*

*Status 2026-11-08: **PatchEval on Unsloth Dynamic v3.1 UD-IQ4_XS: 12/20** (Strata 0.2.11, DFlash2, 15 t/s, 9.0 h; 7 timeouts). That's below GSQ IQ3_XXS / IQ3_S (15/20 re-graded) and the old UD-IQ4_XS (14/20), so Unsloth's accuracy claim does not hold here. Slow decode puts 13 of 20 tasks at the 30-min limit. **Daily pick stays GSQ IQ3_XXS.** The v3.1 UD-IQ3_XXS PatchEval was not run (stopped at task 1 on request). VRAM peaked at 7.78 of 8.19 GB, so Strata's fit margin may be too conservative (see [llama-speed-table.md](llama-speed-table.md)). Report: [reports/2026-11-02_PatchEval_Report_local-vs-hosted.md](../reports/2026-11-02_PatchEval_Report_local-vs-hosted.md); charts: [reports/patcheval-charts.html](../reports/patcheval-charts.html).*

*Status 2026-11-08 (later): **GitHub repo [SvenMeyer/local-llm-bench](https://github.com/SvenMeyer/local-llm-bench)** (private until reviewed) holds the shareable part of this folder in a structured layout (docs/, scripts/, reports/, patches/, data/). This folder stays the working area; after new results run `./export-to-repo.sh`, then commit in `~/Downloads/local-llm-bench`. Charts recolored: Unsloth quants in Unsloth's logo green (#14b789), GSQ blue.*

*Status 2026-11-09: **Routing A/B on one engine** (Strata 0.2.11 / 0.1.57, GSQ IQ3_S, DFlash2, GPU unlock on, PatchEval tasks 1-6, 50 min/task, 64k cap): `STRATA_ROUTE_PRIOR` **0: 4/6, 18.7 t/s; 0.5: 4/6, 19.7 t/s; 1.5: 6/6, 19.3 t/s**. No quality cost from 1.5 on these tasks (the +2 is within noise: both extra passes were decided near the time limit). Expert-cache hit rate 21.5% / 32.6% / 53.2%, but with DFlash2 decode barely moves (MTP on 0.1.55 was 16.3 vs 24.2). Keep 1.5. GPU unlock: no Strata speed change (warm prefill 450 vs 446 t/s). VRAM: 114 MiB free at peak (used+free = 7,892 MiB, so the Nov 8 "400 MB spare" was wrong). Memory check (`strata-mem-check.sh`): `--kv k8v4` and `--set kv-resident=20480` add 44-103 expert slots, short-prompt decode +1-4% (noise level), lowest free VRAM -46..-66 MiB: not adopted. Qwen keeps polishing 7-30 min after its own tests pass (DeepSeek stops in 1-2 min): `patcheval-after-fix.py`, table `patcheval-after-fix-20261109.tsv`. Logs: `patcheval-strata-prior-ab-20261109-0153.{txt,vram}`, results `benchkit-src/BenchKit/results/2026-11-09_{05-50-23,10-01-36,14-28-23}`. Next (optional): replay the fix at the first green test run through the hidden grader, to see whether the polishing helps.*

*Status 2026-11-09 (evening): **Replay test** (`patcheval-replay.py`, BenchKit's own grader, all 18 A/B tasks, every replay reproduced the original patch and grade): the version at the agent's **first green test run** already passed in 12 of the 14 final passes. In the other 2 (both prior 1.5) the deciding source edit came 0.2-2 min after that run, from a quick check against the issue's own example. The long polishing tail never changed a result, yet it takes 12.5 of 38.4 min per task and 29% of output tokens. **Prompt cache misses** are pi compacting the conversation at our 64k limit (~2 min per compaction, 1-2 per long task); next GPU test: `--context 128k`. Next prompt test: a Qwen system-prompt variant ("verify against the issue's example, then stop"). Table: `patcheval-replay-20261109.tsv`. Community post draft: `reports/2026-11-09_strata-8gb-post-draft.md` (not posted).*
