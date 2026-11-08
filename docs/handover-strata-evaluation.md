# Handover: Qwen3.8-Flash-Next on the Strata engine (started 2026-10-28)

Goal (user, 2026-10-28): Qwen3.8-Flash-Next quality at clearly more than the ~10 t/s we get on llama.cpp.
A setup is only worth keeping if it scores at least **23/24** on the in-house agent eval (`llama-agent-eval.py`).

Dropped: **Bonsai 2** (21/24, PatchEval 9/20), **Laguna S 2.1** (6.5-7.6 t/s decode on the Unsloth engine,
files deleted), **DeepSeek V4.1** (239+ GB download, 12 GB card minimum).

## Setup (done)

- Strata Terminal 0.2.7 (build/engine 0.1.52, `linux-x86_64-cuda-cuda13`), installed with the release `install.sh`
  (checksummed + signed feed, no sudo): `~/.local/bin/strata`, components in `~/.local/share/strata/`.
- It uses our GGUFs where they are (`--model-path`). One-time prep wrote:
  `~/.cache/lm-studio/mtp/` (Strata's MTP draft layer, 5.2 GB download, packed to `mtp-q2_0.gguf` + `rt/`),
  `~/.cache/lm-studio/packs/unsloth-ud-iq4_xs/`, and `*.done` marker files next to the model shards.
- Engine logs: `~/.local/state/strata/launch/<model>-64k.engine.log` (expert-cache hit rate, per-request speed).

Launch (64k context to match the llama.cpp eval runs; port 8099 is what the eval script uses):

```sh
strata launch --model-path ~/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF \
  --model iq3_xxs --context 64k --vision off --access local --port 8099 --no-api-key --yes --no-tui --restart
strata launch --stop
```

**UD-IQ4_XS needs a smaller draft vocabulary on 8 GB** (3.6 GiB of Q8_0 dense weights; otherwise
`mtp: the draft head does not fit`, ~130 MiB short). The draft vocab only limits what MTP proposes; output is unchanged:

```sh
strata launch --model-path ~/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF --model ud-iq4_xs --family unsloth \
  --context 64k --vision off --access local --port 8099 --no-api-key --yes --no-tui --restart \
  --set mtp-draft-vocab=/home/sum/.local/share/strata/terminal/0.1.52/data/draft_vocab_en.bin
```

`llama-agent-eval.py` now also records `model_s` / `eff_tps` (client-side request time, engine-neutral).
Strata returns llama.cpp-style `timings`, so `tg_tps` works too.

## Probe results: `t8-scheduler`, seed 1 (longest task), balanced profile

| setup | result | wall | decode t/s | GPU expert-cache hit | notes |
|---|---|---:|---:|---:|---|
| llama.cpp (Unsloth engine) IQ3_XXS, 2026-10-27 | PASS | 842 s | 9.3 | n/a | old baseline |
| llama.cpp (Unsloth engine) Q2_0, 2026-10-27 | PASS | 922 s | 10.2 | n/a | |
| **Strata IQ3_XXS** | PASS | **246 s** | **38.2** | 63-77% | 753 slots; route tail skip on (default) |
| **Strata UD-IQ4_XS** | PASS | 658 s | 18.1 | 38-50% | 384 slots; tail skip off (Strata default for Unsloth) |
| Laguna S 2.1 UD-Q4_K_XL, Unsloth engine | stopped | >28 min | 6.5-7.6 | n/a | one turn ran into the 8192-token cap |

Quality yardstick from Strata's docs (`docs/QUANTS.md`: same top token as Q8_0 / mean KL):
IQ3_XXS 84.5% / 0.202, IQ3_S 87.7% / 0.144, UD-IQ4_XS 88.9% / 0.101, UD-Q4_K_XL 93.1% / 0.056.
Route tail skip costs KL ~0.006 (top-1 97.7%), small next to the quant itself.

Heat: Strata loads CPU and GPU together. IQ3_XXS probe: CPU package 97 C, fans at max. UD-IQ4_XS on balanced: ~86-88 C.

## First full run: IQ3_XXS 21/24, but the harness was not equal (v1)

2026-10-28 21:34-22:52, arm A only (stopped there on the user's request): **21/24** in 77 min (llama.cpp IQ3_XXS:
24/24 in 140 min), agent TG 27.7 t/s vs 9.8, but 41% more tokens per task. Fails: `t7-calc` s1 + s3 (both: `%` not
tokenized, model stopped; not an engine bug, `%` round-trips fine), `t8-scheduler` s3. Kept as
`llama-agent-eval-strata-iq3xxs-v1.*`, server log `llama-serve-strata-iq3xxs-v1-20261028.server.log`.

Two Strata server behaviours made the run unequal to llama.cpp (both fixed for the next run):
1. **`answer_room`** (default on): with `max_tokens` 8192, Strata caps thinking at 6144 and forces a wrap-up;
   5 requests hit it (llama.cpp's longest turn was 6291, 0 length stops). The config key `"answer_room": false`
   is dropped by `strata launch` on every start, and a request `reasoning_budget_tokens` is capped the same way.
   Fix: the suite sends `MAX_TOKENS=10923`, so the cap is 8193 (= llama.cpp's limit).
2. **Undeclared tool calls** (`edit_file` x4, `write_path_note` x1): Strata returns them as text plus
   `strata_rejected_tool_calls`; the eval took the text as "done" and ended the task. llama.cpp passes them through and
   the eval reports "unknown tool". Fix: `llama-agent-eval.py` now reports them back (counted in `rejected_calls`
   and `bad_calls`) and continues. It also records `max_req_tokens` per run.

Reasoning effort is equal: Strata's default "high" maps to the template's `xhigh` (`serve/frontend.py`).

## Full suite

**The user starts it later**:

```sh
cd ~/Downloads/AI-Runtime && nohup ./llama-strata-overnight.sh > llama-strata-overnight-$(date +%Y%m%d-%H%M).txt 2>&1 &
```

`llama-strata-overnight.sh` arms (24 runs each): A `strata-iq3xxs` (rerun with the fixed harness; skipped once its jsonl has 24 rows),
B `strata-iq3xxs-noskip` (`STRATA_ROUTE_TAIL_SKIP=0`), D `strata-ud-iq4xs`, E `strata-iq3s`.
On start it downloads ISTA IQ3_S shard 1 (54.8 GB, sha256-checked, `llama-gsq-download.sh iq3s`, log
`llama-gsq-iq3s-download.log`) in the background; shard 2 + MTP are symlinked. E waits for the download and runs last.
Results in `llama-agent-eval-<label>.jsonl`; summary at the end of the output file; thermal log `llama-strata-overnight-thermal-*.tsv`.

## Next decisions

1. If A (and B) reach 23/24: IQ3_XXS on Strata is the new default (~4x faster than llama.cpp).
2. UD-IQ4_XS is the "more quality" option at ~18 t/s if D reaches 23/24.
3. **ISTA IQ3_S as a middle ground** (user is open to it): 55 GB download (shard 1 only; shard 2 is the shared
   n-gram table, symlink it like IQ3_XXS). Its expert format (IQ3_S) is the same as UD-IQ4_XS's gate/up, but ISTA's
   dense side is smaller, so more GPU cache slots: expect between 18 and 38 t/s (estimate, not measured).
   The user's reading of the ISTA chart: IQ3_S beats IQ3_XXS clearly only on GPQA-Diamond.
4. UD-Q4_K_XL (111 GB) parked by the user's choice ("no download for now").
5. Then update README status, `llama-speed-table.md`, and the benchmark guide.

## pi (the user's target agent) and wrong tool calls (2026-10-28 night)

Read from pi 1.4.0's bundle (`@earendil-works/pi-coding-agent`) and the engines' source:

| | llama.cpp (Unsloth engine) | Strata 0.2.7 |
|---|---|---|
| Call to an undeclared tool name | **cannot happen**: after `<tool_call>` a lazy grammar allows only declared names (`p.literal(name)`) and schema-shaped args (`common/chat-auto-parser-generator.cpp`) | model may write it; server returns it as **text** + `strata_rejected_tool_calls` (by design, #3796; no grammar, "schema prompting + validation") |
| What pi does | n/a (if it got a structured unknown call: `Tool X not found` error back to the model, loop continues) | pi ignores the extra field, sees a text-only reply, and its loop **ends the run** (`toolCalls.length > 0` is the only continue condition) |

So with Strata, a hallucinated tool name silently ends a pi task. pi's own system prompt invites it ("you may have access
to other custom tools depending on the project"). Options if this shows up in the pi runs: a pi extension that re-prompts
when the last reply holds a `<tool_call>` text block, or ask Strata upstream for grammar-constrained tool names.

Measured, not just read: `pi-agent-eval.py` runs the 8 in-house tasks through `pi --mode json` (read/bash/edit/write)
in bubblewrap (read-only system, writable sandbox, own `PI_CODING_AGENT_DIR` in `pi-eval/agent-dir`, so `~/.pi` is
untouched), scores with the pristine tests, and flags `ended_on_text_call`. Events per run in `pi-eval/events/<label>/`.
`pi-strata-followup.sh` (started 23:16, log `pi-strata-followup-*.txt`) waits for the suite, then runs each line of
`pi-eval/plan.txt` (IQ3_XXS 3 samples, UD-IQ4_XS 1 sample). The plan is read only when the suite ends; **do not edit
`llama-strata-overnight.sh` while it runs** (bash reads scripts as it goes).

**Sandbox for daily pi use: NVIDIA OpenShell** (user suggestion, github.com/NVIDIA/OpenShell, v0.1.6, Apache-2.0).
Needs a local gateway plus Docker / Podman / MicroVM (`vm` driver; `/dev/kvm` exists, user is in the `docker` group,
Docker daemon currently stopped: `sudo systemctl start docker`). Default sandbox image has no agent: pi must be
installed in it, and a network policy must allow the model server (`host.openshell.internal`). Anonymous telemetry is
on by default (opt-out not checked yet). Not used for the overnight runs (bubblewrap there); evaluate it as the
sandbox for pi on real repos.

## Strata changes which experts run on 8 GB cards (found 2026-10-29 00:15)

0.2.7 turns on **residency-biased routing** (`STRATA_ROUTE_PRIOR=1.5`) by itself on discrete NVIDIA cards <= 13 GiB:
the router prefers experts already in VRAM. Strata's own numbers (RTX 3060, IQ3_XXS): +15% story / +37% code decode,
but agent loops **4.5/10 vs 5.6/10** without it ("within run-to-run spread"; `docs/DETAILS.md`, release notes 0.2.7).
Fits what we see: `t8-scheduler` needs 16 turns on Strata vs 7-9 on llama.cpp. Arm B (`noskip`) only disables the
route tail skip, so `llama-strata-queue2.sh` adds **`strata-iq3xxs-faithful`** (`STRATA_ROUTE_TAIL_SKIP=0` +
`STRATA_ROUTE_PRIOR=0`, 24 runs) after the pi runs, then pi on UD-IQ4_XS (moved out of `pi-eval/plan.txt`).
Order tonight: suite (A, B, D, E) -> pi IQ3_XXS x3 -> faithful IQ3_XXS -> pi UD-IQ4_XS.
Sampling is not a difference: Strata honours top_k/top_p/min_p/seed per request; no reasoning-loop recoveries fired.

## Result: turn the route tail skip OFF (2026-10-29 01:50)

| setup (IQ3_XXS, 64k, 16k thinking cap) | pass | total | tokens/task | avg turns | turn-limit hits | agent TG |
|---|---:|---:|---:|---:|---:|---:|
| llama.cpp (Unsloth engine), 2026-10-27 | 24/24 | 140 min | 3116 | 6.0 | 0 | 9.8 |
| Strata defaults (`strata-iq3xxs`) | 23/24 | 93 min | 5654 | 7.0 | 2 | 29.5 |
| **Strata `STRATA_ROUTE_TAIL_SKIP=0`** (`strata-iq3xxs-noskip`) | **24/24** | **64.5 min** | **3767** | 6.2 | 0 | 28.0 |

The skip barely changes decode speed but makes the model think and loop much more (t8-scheduler 13.7 -> 6.4 min).
**Recommended Strata launch: add `--set STRATA_ROUTE_TAIL_SKIP=0`.** (Unsloth packs already get it by default.)
The pi runs now use it (`pi-eval/plan.txt`: `pi-strata-iq3xxs-noskip`). `llama-strata-queue3.sh` adds
`strata-iq3s-noskip` after queue 2 (the suite's arm E is IQ3_S on defaults) and prints a summary of all setups.
2026-10-29 02:50: `stop-suite-after-ud.sh` ends the suite after arm D, so **arm E (IQ3_S on Strata defaults) does not
run** (time: the night would otherwise end ~11:30). IQ3_S is measured in queue 3 with the tail skip off. To run the
defaults arm later: `ARMS=E ./llama-strata-overnight.sh` (A/B/D are skipped since their jsonl files are complete).

**pi has no default timeout on its `bash` tool** (2026-10-29 04:45). In `pi-strata-iq3xxs-noskip` t7-calc s2 the model
ran a random fuzz test of its calculator that included `**` chains (e.g. `10 ** 10 ** 10`); python sat at 100% CPU,
pi waited (the tool has an optional `timeout` the model did not set) and Strata was idle. After 8 min I killed that one
python process by hand, as a user would press Ctrl-C; pi got the error and continued. That run is marked "intervened".
For daily pi use: give bash a default timeout (pi setting/extension) or expect to interrupt such hangs.

## Result: keep residency-biased routing ON, turn only the tail skip OFF (2026-10-29 06:35)

| IQ3_XXS on Strata | pass | total | tokens/task | agent TG |
|---|---:|---:|---:|---:|
| defaults (skip + route prior) | 23/24 | 93 min | 5654 | 29.5 |
| `ROUTE_TAIL_SKIP=0` (prior on) | **24/24** | **64.5 min** | 3767 | 28.0 |
| faithful: `ROUTE_TAIL_SKIP=0` + `ROUTE_PRIOR=0` | 24/24 | 79 min | 3941 | 22.6 |

The route prior adds ~24% decode at no visible cost in tokens or passes; the tail skip is what inflates thinking.
**Recommended daily setup: `--set STRATA_ROUTE_TAIL_SKIP=0` only.**

pi (the real agent) on that setup: **24/24** in 91.7 min (8 min of it a hang I stopped, see above), 4490 tokens/task,
8.2 turns, **0 unknown-tool calls, 0 runs ended by a text tool call**, 9 ordinary tool errors (pi-agent-eval-pi-strata-iq3xxs-noskip.jsonl).

## Final results, night of 2026-10-28/29 (all done 08:37; box idle, Strata stopped)

In-house agent eval, 8 tasks x 3 seeds, 64k ctx, 16k thinking cap, fixed harness:

| setup | pass | total | tokens/task | agent TG | turn-limit hits |
|---|---:|---:|---:|---:|---:|
| llama.cpp IQ3_XXS (2026-10-27 baseline) | 24/24 | 140 min | 3116 | 9.8 | 0 |
| Strata IQ3_XXS, defaults | 23/24 | 93 min | 5654 | 29.5 | 2 |
| **Strata IQ3_XXS, `ROUTE_TAIL_SKIP=0`** | **24/24** | **64.5 min** | 3767 | 28.0 | 0 |
| Strata IQ3_XXS, faithful (skip 0 + prior 0) | 24/24 | 79 min | 3941 | 22.6 | 0 |
| Strata IQ3_S, `ROUTE_TAIL_SKIP=0` | 24/24 | 76 min | 3992 | 24.2 | 1 |
| Strata UD-IQ4_XS (skip off by default) | 24/24 | 110 min | 4847 | 20.2 | 1 |

pi (real agent, bubblewrap): IQ3_XXS no-skip **24/24** (92 min incl. an 8-min hang I killed), UD-IQ4_XS **8/8** (44 min).
**0 unknown-tool calls and 0 runs ended by a text tool call in 32 pi runs.** The risk is real (our own harness saw 5 per
24 runs with `write_file`/`edit_file`-style names) but pi's tool names did not trigger it.

**Recommendation:** Strata + ISTA IQ3_XXS + `--set STRATA_ROUTE_TAIL_SKIP=0` = 2.2x faster end-to-end than llama.cpp at the
same pass rate. IQ3_S no-skip is the quality step-up at -15% speed (76 vs 64.5 min); UD-IQ4_XS is slowest and shows no
gain on this suite. The suite is too easy to separate quality (every setup without the skip is 24/24): next is a harder
test, e.g. BenchKit PatchEval with the pi harness on IQ3_XXS vs IQ3_S (needs the Docker daemon).

Open items: pi `bash` has no default timeout; OpenShell as the daily pi sandbox; README / speed table / guide update.

## PatchEval through pi: IQ3_XXS vs IQ3_S (2026-10-29/30)
BenchKit v0.2.0 PatchEval pilot-20 (20 real Python bug fixes, stock pi 0.84.2 in BenchKit's Docker sandbox, hidden-test
grading), Strata 0.2.7, 64k context, `STRATA_ROUTE_TAIL_SKIP=0`, 1800 s per task (same as the Bonsai run).
Runner `patcheval-strata-quants.sh` (Strata on 127.0.0.1, socat bridge on docker0 172.17.0.1 only); logs
`benchkit-patcheval-strata-<label>.log`, reports `benchkit-src/BenchKit/results/2026-10-30_09-31-39` (IQ3_XXS),
`.../2026-10-30_18-19-26` (IQ3_S). A timed-out task is still graded on its workspace.
| setup | pass | passed inside 30 min | broke existing tests | avg task | output tok/task | stream t/s | wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| Bonsai 2 27B (Ada runtime, 262k) | 9/20 | 4 | - | 27 min | - | 25 | 9h40 |
| **Qwen3.8 IQ3_XXS** | **14/20** | 4 | 1 | 25.6 min | 31.0k | 24.0 | 9h08 |
| **Qwen3.8 IQ3_S** | **14/20** | 7 | 2 | 24.5 min | 23.2k | 17.4 | 8h47 |
| Qwen3.8 UD-IQ4_XS (2026-10-31) | 13/20 | 4 | 2 | 26.6 min | 24.7k | 16.4 | 9h30 |
- Tie. 12 tasks passed by both; XXS only: sqlit-260, json-repair-191; S only: city2graph-121, pypdf-3878 (one sample
  each, so +-2 tasks is noise). Union 16/20; never solved: narwhals-3864, json-repair-207, pygments-2816, pygments-2828.
- IQ3_S decodes 27% slower but writes 25% fewer tokens per task, so time per task comes out equal, and it finishes
  inside the limit more often (7 vs 4). IQ3_XXS feels faster interactively.
- 64k is enough: pi compacts (seen 57k -> 28k) and carries on. No rejected/unknown tool calls in 40 runs.
- One incident (IQ3_XXS, city2graph-121): after 6 read-only steps the model returned an empty reply (no text, no tool
  call), pi ended the run at 75 s. Not seen on IQ3_S.
- UD-IQ4_XS (run 2026-10-31 00:28-09:58, report `.../2026-10-31_09-58-47`): **13/20**, slowest (16.4 t/s), no gain.
  11 tasks passed by all three quants; the same 4 failed on all three. Differences sit on 5 tasks, each one sample.
  0 rejected tool calls, 0 empty-reply stops. **Verdict: IQ3_XXS stays the daily quant** (same score, fastest decode).

## Strata 0.2.9 / engine 0.1.55 and Ornith-1.5 (2026-11-01)

- Updated 2026-10-31 23:59 (`strata update`; rollback: `strata components rollback`). **Engine 0.1.55 turns residency-biased routing OFF by default on <=12 GB cards** (release 0.2.8: tied to repeated text in long sessions). Our 2026-10-29 setup kept it ON. IQ3_S suite replay: 24/24, 3,536 tok/task, **16.3 t/s vs 24.2**, decode expert-cache hit rate 21% vs 46%. To restore: `strata launch ... --set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5`.
- Ornith-1.5-122B UD-Q4_K_XL (qwen35moe): Strata's q36 path refuses IQ4_XS/Q6_K experts and has no KV format option. Ran on llama.cpp (Unsloth b11170, 32k, q8_0 KV, --cpu-moe, no MTP): **PatchEval 9/20**, 10k tok/task, 7.2 t/s, 9 timeouts. Summary: `2026-11-01_11-00_Benchmark_Summary_Ornith-1.5-122B.md`.
