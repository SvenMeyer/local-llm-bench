# Handover: PatchEval on Unsloth Dynamic v3.1 Qwen3.8 quants

*Written 2026-11-07. **Done 2026-11-08: only the `ud31iq4xs` arm ran (user choice): 12/20**, results `2026-11-08_09-49-31`; see the README status line. `ud31iq3xxs` not run. Procedure: [PATCHEVAL-RUNBOOK.md](PATCHEVAL-RUNBOOK.md). This file only says what is
different for this run.*

## Goal

Unsloth re-uploaded its Qwen3.8-Flash-Next GGUFs as "Dynamic v3.1" on 2026-11-04. It claims "10-15% increased accuracy
and 30% less token usage vs other quants of the same size". Our agent suite can't test that: every Qwen3.8 setup
scores 24/24 on it (2026-11-07 overnight: v3.1 UD-IQ3_XXS 24/24 at 24.6 t/s, GSQ IQ3_XXS 24/24 at 28.9 t/s; see
`reports/2026-11-02_PatchEval_Report_local-vs-hosted.md`, top section). PatchEval (20 real bug fixes) can.

## Arms

| Order | Arm (`ARMS=`) | Files | Size | Compare with |
|---|---|---|---|---|
| 1 | `ud31iq3xxs` | `~/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ3_XXS/` | 84 GB | GSQ IQ3_XXS **14/20** |
| 2 | `ud31iq4xs` | `~/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/` | 94 GB | GSQ IQ3_S **14/20**; old 09-30 UD-IQ4_XS **13/20** |
| opt. | `iq3xxs` + `SUFFIX=-0211` | GSQ IQ3_XXS | 76 GB | same-engine baseline (see Fairness) |

Shard 4 (the 28.8 GB IQ4_NL engram table) of both v3.1 sets is a btrfs reflink of GSQ IQ3_XXS/Q2_0 shard 2. The
sha256 matches Unsloth's (`5de8b5db…`), and it costs no extra disk. Don't "clean up" either copy without checking that.

## Run

Do the checklist in runbook §3 first (Docker up, ≥20 GB free, `BENCHKIT_PATCHEVAL_DATASET` exported, BenchKit
patches present). Then:

```bash
cd ~/Downloads/AI-Runtime
~/.local/bin/strata launch --stop </dev/null               # nothing else may hold the GPU or port 8099
export BENCHKIT_PATCHEVAL_DATASET=~/Downloads/AI-Runtime/patcheval-dataset/pilot-20-local1
ARMS="ud31iq3xxs ud31iq4xs" SUFFIX=-0211 \
  setsid nohup ./patcheval-strata-quants.sh > patcheval-strata-v31-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
```

- **Time:** ~9-10 h per arm (30 min cap per task). Run both on one long night, or one arm per night: `ARMS=ud31iq3xxs` first.
- **Watch:** a cron wake-up every ≤45 min (user rule) plus a Monitor on the progress file and
  `benchkit-patcheval-strata-ud31-*-0211.log`, as on the 2026-11-07 overnight run. Resume or stop: runbook §9.
- **Script defaults** (`patcheval-strata-quants.sh`, arms added 2026-11-07):
  - `PI_TIMEOUT=1800`, pi output cap 16384, full 20 tasks.
  - `--set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5`, 64k context, Strata Auto drafting (DFlash2).
  - These match the 14/20 runs except for the engine and drafter (see below).

## Fairness

- The 14/20 GSQ baselines ran on Strata 0.2.7 (engine 0.1.52) with MTP. Now it's 0.2.11 / 0.1.57 with DFlash2.
  The agent suite showed equal speed on both, but PatchEval quality wasn't re-measured. For a clean same-engine
  comparison, add `ARMS="iq3xxs ..." SUFFIX=-0211`, at +9 h.
- One run per arm: ±1-2 tasks is noise (IQ3_XXS and IQ3_S both scored 14/20 with different failures).
  Treat "v3.1 better" as real only at ≥16/20.
- Expect UD-IQ4_XS-v31 to be the slowest arm: more expert bytes per token, and 33 layers of the new Q5_0 expert
  format. Slower decode means more 30-min timeouts, which costs score. Report timeouts separately.

## Gotchas

- **Launch:** UD-IQ3_XXS by `--model-path <shard 1> --model ud-iq3_xxs` worked (model id
  `qwen3.8-flash-next-unsloth-ud-iq3_xxs`, first start ~2 min incl. preparation).
  - UD-IQ4_XS-v31 hasn't been started yet. Check it first with
    `strata launch --plan --model-path <UD-IQ4_XS shard 1> --model ud-iq4_xs-v31 --context 64k --yes --no-tui`.
  - The plan must show **no download**: without `--model-path` Strata would fetch 93.7 GB again.
- **Skipped arms:** an arm whose log already has `Saved:` is skipped, so always give a new `SUFFIX`.
- **MTP heads:** the GSQ folders' MTP-head symlinks point into `unsloth/Qwen3.8-Flash-Next-GGUF/`.
  Keep `mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf` there.
- **Download stalls:** an unauthenticated `hf download` stalled at 1.2 GB once. Use `curl -C -` with a sha256 check.

## After the run

Runbook §10:
1. Add the arms to `reports/patcheval-arms.json` (with the `Saved:` folders).
2. Run `python3 reports/build_patcheval_data.py && python3 reports/make_patcheval_report.py`.
3. Rewrite `TAKEAWAYS` and the cards.
4. Update the README status line, `llama-speed-table.md` and memory (`strata-0211-unsloth-v31-no-gain.md`).

## Optional before PatchEval

- **Speed check, ~1.3 h:** the 24-run agent suite on UD-IQ4_XS, label `strata0211-ud31-iq4xs-noskip-prior15`.
  Copy `run_arm` from `overnight-strata0211-v31.sh`.
  - Add the row to `reports/agent_eval_section.py` `ARMS`/`SHORT`, then regenerate the report.
  - If decode is far below 24 t/s, PatchEval timeouts will dominate. Weigh that before spending 10 h.
