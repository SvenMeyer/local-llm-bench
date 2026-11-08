# local-llm-bench

Can a laptop with an 8 GB GPU run a 125B open-weight model well enough to fix real bugs? This repo has
our measurements: big MoE models (mostly **Qwen3.8-Flash-Next**, 125B total / 6B active) run locally from
system RAM plus an 8 GB laptop GPU, compared with hosted models, on real coding-agent work.

Everything is open source: the models, the engines (llama.cpp, Unsloth's llama.cpp fork, Strata), the
agent ([pi](https://github.com/earendil-works/pi)) and the benchmark ([BenchKit](https://github.com/DogukanUrker/BenchKit)
PatchEval). The data, scripts and patches are here so you can check the numbers or run the same tests
on your own hardware, models or agent.

**Results page with interactive charts:** [`reports/patcheval-charts.html`](reports/patcheval-charts.html)
· full report: [`reports/2026-11-02_PatchEval_Report_local-vs-hosted.md`](reports/2026-11-02_PatchEval_Report_local-vs-hosted.md)

![PatchEval pass rate vs mean time per task](reports/charts/score-vs-time.svg)

## PatchEval results

20 real bug fixes from 12 Python projects, graded by hidden tests; one task at a time, 30 min limit per
task, pi coding agent (mcode for one MiniMax run).

| Setup | Runs on | Score | Total time | Decode tok/s |
|---|---|---:|---:|---:|
| DeepSeek V4.1 Flash (think max) | hosted, OpenRouter (~$1 for all 20) | **17/20** | 1.5 h | 264 |
| Qwen3.8-Flash-Next GSQ-RCO IQ3_XXS | laptop, Strata 0.2.7 | **15/20** | 9.1 h | 24 |
| Qwen3.8-Flash-Next GSQ-RCO IQ3_S | laptop, Strata 0.2.7 | 15/20 | 8.8 h | 18 |
| Qwen3.8-Flash-Next Unsloth UD-IQ4_XS (Oct) | laptop, Strata 0.2.7 | 14/20 | 9.5 h | 17 |
| Qwen3.8-Flash-Next Unsloth Dynamic v3.1 UD-IQ4_XS | laptop, Strata 0.2.11 | 12/20 | 9.0 h | 15 |
| Ornith-1.5 122B Unsloth UD-Q4_K_XL | laptop, llama.cpp | 10/20 | 8.9 h | 7 |
| Bonsai 2 27B (ternary) | laptop, Prism llama.cpp | 10/20 | 9.7 h | 25 |
| MiniMax M3.1 Flash (pi / mcode) | hosted, Vercel AI Gateway | 3/6 each, stopped | — | 145-182 |

Scores count one re-graded task (`pygments-2828`, flawed hidden test,
[BenchKit #89](https://github.com/DogukanUrker/BenchKit/issues/89)) as a pass for runs before the fix.

## What we learned

- **A hosted model is still far ahead**: DeepSeek V4.1 Flash solves 2 more tasks than the best local setup, 6x faster, for about $1.
- **Locally, speed is score.** Local runs decode at 7-25 tok/s, so most tasks run into the 30-minute limit, and the
  faster quants score higher. On this box the expert-kernel speed of a quant type matters more than its bits
  ([details](docs/llama-speed-table.md)).
- **GSQ-RCO quants beat Unsloth's at equal size** for Qwen3.8 here, and Unsloth's Dynamic v3.1 re-upload did not
  improve on the October version (12 vs 14/20; within noise, but slower).
- **The 24-run tool-calling agent suite is saturated**: every Qwen3.8 setup scores 24/24, so only PatchEval separates them.
- One run per setup: treat differences of 1-2 tasks as noise.

## Hardware

Laptop: Intel i7-13700H, NVIDIA RTX 4070 Laptop **8 GB** (35 W cap in most runs), **125 GB RAM**, Manjaro Linux,
CUDA 13.3. The GPU only runs inference (the desktop is on the Intel iGPU). Models of 76-94 GB live in RAM; the
GPU holds attention, KV cache and the hottest experts.

## Layout

| Path | What |
|---|---|
| [`reports/`](reports/) | charts page, PatchEval report (Markdown + HTML), report and chart generators, merged data (`patcheval-data.json`) |
| [`docs/`](docs/) | lab notebook (chronological status log), runbook, engine and quant guides, per-model summaries, handovers |
| [`docs/PATCHEVAL-RUNBOOK.md`](docs/PATCHEVAL-RUNBOOK.md) | how to run PatchEval with pi or mcode on local or hosted models |
| [`docs/llama-speed-table.md`](docs/llama-speed-table.md) | every speed measurement: engine, quant, context, VRAM |
| [`scripts/`](scripts/) | server launchers, benchmark and eval drivers, overnight chains, build scripts |
| [`patches/`](patches/) | BenchKit v0.2.0 changes (pi/mcode harness, telemetry), llama.cpp patches, the `pygments-2828` test fix |
| [`data/benchkit-results/`](data/benchkit-results/) | raw BenchKit output per run, including full agent transcripts (`results.json`) |
| [`data/agent-eval/`](data/agent-eval/) | 24-run tool-calling agent suite results (JSONL) |
| [`data/runs/`](data/runs/), [`data/logs/`](data/logs/) | run summaries, thermal/power/VRAM traces, benchmark logs |

## Reproduce

1. BenchKit v0.2.0 plus [`patches/benchkit-v0.2.0-local.diff`](patches/benchkit-v0.2.0-local.diff) (and
   `patches/benchkit-mcode_agent.py` as `src/benchkit/mcode_agent.py` for the mcode harness).
2. The `pilot-20` PatchEval dataset from BenchKit, with
   [`patches/patcheval-pygments-2828-hidden-test.patch`](patches/patcheval-pygments-2828-hidden-test.patch) as the
   hidden test of `pygments-2828` (our `pilot-20-local1`; see runbook section 7).
3. Follow [`docs/PATCHEVAL-RUNBOOK.md`](docs/PATCHEVAL-RUNBOOK.md). The local runs use
   [`scripts/patcheval-strata-quants.sh`](scripts/patcheval-strata-quants.sh); hosted runs `scripts/patcheval-hosted.sh`.
4. Add your run to `reports/patcheval-arms.json`, then
   `python3 reports/build_patcheval_data.py && python3 reports/make_patcheval_report.py && python3 reports/make_patcheval_charts.py`.

The scripts are lab tools, not a package: they were run from one flat working folder and contain absolute paths
from our machine (`/home/sum/...`, `~/Downloads/AI-Runtime`). Adjust paths before running them.

## License

Our scripts, reports and data: MIT ([LICENSE](LICENSE)). `patches/benchkit-*` modify BenchKit (Apache-2.0); the
llama.cpp patches modify llama.cpp (MIT). Models, engines and benchmark tasks belong to their authors.
