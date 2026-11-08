# Benchmarking and tuning guide

How to measure, what to vary, and the running log of every configuration tried.

Context: [llama-run-guide.md](llama-run-guide.md) (what the flags mean),
[llama-todo.md](llama-todo.md) (open work).
To **run** the Qwen3.8 copy of Group A/B/C:
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md).

---

## 1. Measurement hygiene on this machine

Get these wrong and the numbers are not comparable.

- **Power profile matters.** The GPU is capped at **35 W** and the CPU is hybrid
  (6 P + 8 E). `balanced` vs `performance` has shifted prompt throughput by
  >2× in past runs. **Always record which profile was active.**
- **Warm the page cache.** Qwen3.8-Flash-Next streams its 28.8 GB n-gram table
  from SSD on demand (run-guide §3). The first run is pessimistic. **Discard
  run 1, report run 2+.**
- **Nothing else running.** A background compile costs ~20 % (Bonsai measured
  26 t/s idle vs 21.2 t/s during a build).
- **Same prompt every time.** See §3.
- **Report both numbers.** Prefill (prompt processing) and generation are bound
  by different things here — prefill is GPU/compute bound, generation is CPU
  memory-bandwidth bound. A change can improve one and wreck the other.

## 2. Two ways to measure

**`llama-bench`** — clean, repeatable, no chat template. Best for sweeps:

```bash
cd /home/sum/Downloads/AI-Runtime/llama.cpp
./build/bin/llama-bench \
  -m /home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf \
  -ngl 999 --cpu-moe -fa 1 -ctk q8_0 -ctv q8_0 -t 10 -p 512 -n 128
```

**`llama-server` / `llama-cli`** — the real path, includes the chat template and
MTP. This is the only way to measure MTP, since `llama-bench` has no draft
model. `llama-cli` prints `[ Prompt: X t/s | Generation: Y t/s ]` on exit,
which is the format used throughout `llama.cpp-test.sh`.

Always also capture:

```bash
… 2>&1 | grep -A4 memory_breakdown     # VRAM/RAM actually used
nvidia-smi --query-gpu=memory.used,power.draw --format=csv   # during generation
```

For MTP, the server returns `draft_n` and `draft_n_accepted` per response —
acceptance rate is `draft_n_accepted / draft_n`. Below ~60 % MTP is probably
not paying for its VRAM.

## 3. Standard test prompt

Reuse the house prompt so numbers compare against the 35 B models already in
`llama.cpp-test.sh`:

> create a whitelist in solidity with some basic functions to add accounts with
> a name of type `bytes32` (which we use to represent a short string), and a
> delete function

For prefill-specific measurement use `llama-bench -p 512` / `-p 4096` instead —
a short chat prompt barely exercises prefill.

## 4. What to vary, in priority order

Change **one thing at a time** and log it.

| # | knob | values to try | expected effect |
|---|---|---|---|
| 1 | `-c` context | 32768 / 65536 / 131072 | the binding VRAM constraint; find the ceiling that survives a *long* generation, not just load |
| 2 | `-t` threads | 8 / 10 / 12 / 14 | generation is bandwidth-bound, so more threads may not help and E-cores may hurt |
| 3 | `-ctk`/`-ctv` | q8_0/q8_0, q8_0/q4_0, f16/f16 | trades KV size against quality; all 49 FA combos are compiled in |
| 4 | `-ncmoe N` | 0 (= `--cpu-moe`) then 2, 4, 8 | puts N expert layers back on GPU if VRAM is spare — usually the single biggest generation win when it fits |
| 5 | `-ot token_embd.weight=CPU` | on / off | ~0.68 GB of VRAM vs a CPU-side lookup |
| 6 | `-ub` ubatch | 512 (default) / 1024 / 2048 | mostly prefill; larger costs compute buffer VRAM |
| 7 | MTP `--spec-draft-n-max` | 2 / 3 / 5 | only on the MTP build; watch acceptance rate |
| 8 | power profile | balanced / performance | record, don't tune |

**Compare MTP against mainline at equal context**, not MTP-at-32k against
mainline-at-64k — otherwise you are measuring the context difference.

## 5. Results log

Append a row per configuration. Newest at the bottom. `PP` = prompt/prefill
t/s, `TG` = token generation t/s.

Columns: date · build · ctx · threads · KV quant · offload · other · PP t/s ·
TG t/s · VRAM · profile · notes

All rows below: Qwen3.6-35B-A3B UD-Q4_K_XL, `--flash-attn on`, `--kv-unified`,
default threads, `balanced` power profile.

**Group A — engine A/B.** Same flags, spec-decode off, exactly 512 tokens at
temp 0 with `ignore_eos` so neither engine wins on generation length.

| date | build | ctx | -t | KV | offload | other | PP t/s | TG t/s | VRAM | profile | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | unsloth b11007-mix-3e83366 | 8192 | def | f16 | `--fit on` | no spec, 512 tok | — | **30.20** | 6584 MiB | balanced | bundled engine |
| 2026-09-17 | local b11011 (native) | 8192 | def | f16 | `--fit on` | no spec, 512 tok | — | **27.62** | 6598 MiB | balanced | local `-march=native` + `sm_89-real` is **9% SLOWER** |

**Group B — context allocation sweep**, q8_0 KV, unsloth engine, near-empty KV
(10-token prompt). Measures the cost of *reserving* context, not using it.
No run was silently auto-reduced; `actual n_ctx` verified via `/props`.

| date | build | ctx | -t | KV | offload | other | PP t/s | TG t/s | VRAM | profile | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | unsloth b11007-mix | 8192 | def | q8_0/q8_0 | `--fit on` | empty KV | — | 29.96 | 6640 MiB | balanced | baseline |
| 2026-09-17 | unsloth b11007-mix | 32768 | def | q8_0/q8_0 | `--fit on` | empty KV | — | 29.74 | 6772 MiB | balanced | −0.7% |
| 2026-09-17 | unsloth b11007-mix | 65536 | def | q8_0/q8_0 | `--fit on` | empty KV | — | 29.47 | 6680 MiB | balanced | **−1.6%, effectively free** |
| 2026-09-17 | unsloth b11007-mix | 131072 | def | q8_0/q8_0 | `--fit on` | empty KV | — | 27.37 | 6662 MiB | balanced | −8.6% |
| 2026-09-17 | unsloth b11007-mix | 180224 | def | q8_0/q8_0 | `--fit on` | empty KV | — | 26.47 | 6706 MiB | balanced | −11.6% |

**Group C — occupied context**, `--cpu-moe` (all MoE in CPU RAM), `-c 200192`,
q8_0 KV, prompt = real `llama.cpp/src` files, `cache_prompt: false`, 128 tokens
generated. This is the number you actually feel.

| date | build | ctx used | -t | KV | offload | other | PP t/s | TG t/s | VRAM | profile | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | unsloth b11007-mix | 574 | def | q8_0/q8_0 | `--cpu-moe` | 200k alloc | 193.6 | 26.37 | 5196 MiB | balanced | 200192 ctx in 5.2 GB — MoE fully on CPU |
| 2026-09-17 | unsloth b11007-mix | 16049 | def | q8_0/q8_0 | `--cpu-moe` | 56 s prefill | 286.1 | 24.53 | 5196 MiB | balanced | −7% |
| 2026-09-17 | unsloth b11007-mix | 65219 | def | q8_0/q8_0 | `--cpu-moe` | 284 s prefill | 229.9 | 20.20 | 5196 MiB | balanced | −23% |
| 2026-09-17 | unsloth b11007-mix | 129263 | def | q8_0/q8_0 | `--cpu-moe` | **1120 s prefill** | 115.4 | **4.56** | 5196 MiB | balanced | −83%; see caveat below |

### What these say

1. **Do not replace the bundled engine with a local build.** `unsloth-desktop-bin`
   ships `b11007-mix-3e83366`: upstream b11007 plus a real fork. `BUILD_INFO.txt`
   shows `supported sms: 75,80,86,89` (sm_89 native, no JIT) and
   `ggml_cpu_all_variants: ON` (runtime AVX2/VNNI dispatch), so a local
   `-march=native` build has no codegen edge to trade — while their tree carries 26
   changed/new `src/` files and modified `ggml-cuda/{mmq,mmvq,mmvf,fattn}.cu`,
   new `fattn-banded.cu`, `ggml.c` and `ggml-quants.c`. Keep the local build anyway:
   Unsloth ships only `llama-server` + `llama-quantize`, so `llama-bench`,
   `llama-perplexity`, `llama-cli` and friends exist *only* locally.

2. **q8_0 KV is a context lever, not a speed lever.** Studio's `--fit on` sized for
   f16 KV and auto-reduced 262144 → 8192. With q8_0 the same card holds 22× more.
   Allocation is nearly free up to ~65k (−1.6%).

3. **Allocating context is cheap; filling it is not.** Group B says 180k costs 12%.
   Group C says 65k of *real* tokens costs 23%, and 129k costs 83%. Reserve
   generously, but treat occupied context as the real budget.

4. **Prefill dominates wall-clock on long prompts** — 284 s at 65k, 1120 s at 129k.
   These ran with `cache_prompt: false` to measure honestly; in normal use
   llama-server reuses the cached prefix, so follow-up turns on an already-loaded
   context skip prefill entirely. Starting small and growing (the LM Studio habit)
   is the right instinct.

5. **`--cpu-moe` is the practical default here.** All experts in CPU RAM, nothing
   migrating, 200192 context in 5.2 GB VRAM with ~3 GB spare.

**Caveat on the 129263 row:** single sample, taken after ~19 min of sustained
prefill on a laptop at `balanced`. The drop from 20.2 → 4.56 is superlinear where
context merely doubled, so thermal/power throttling is a live suspect and this
point should be re-run cold (and on `performance`) before being trusted. GPU read
63 °C with throttle bitmask `0x1` right after the run.

### Reference numbers from other models on this box

Same GPU, for scale. Full detail in `llama.cpp-test.sh`.

| model | config | PP t/s | TG t/s |
|---|---|---:|---:|
| Qwen3.5-35B-A3B UD-Q4_K_XL | `-ot exps=CPU`, 131072, q8_0 KV | 274 | 23.9 |
| Qwen3.6-35B-A3B UD-Q6_K_XL | `--cpu-moe`, 131072, q8_0 KV, balanced | 175 | 18.6 |
| Qwen3.6-35B-A3B-MTP | `--spec-type draft-mtp`, 131072 | — | 25.1 |
| Qwen3.5-9B Q4_K_S | all GPU, 16384, q4_0 KV | 290 | 37.5 |
| Bonsai 27B Q1_0 | dense, all GPU, 32768 | 46.5 | ~26 |
| Ternary-Bonsai-2 PTQ1_0 | Prism fork, all GPU, llama-bench | **268.3** | **19.89** |
| Ternary-Bonsai-2 PQ2_0 | Prism fork, all GPU, llama-bench | **421.7** | **18.71** |

### Ternary-Bonsai-2-27B — Prism llama.cpp `b10706 / 1a07bfa5f`

Needs `llama.cpp-prism` (worktree of `prism/prism`). Stock llama.cpp rejects
`PTQ1_0` / `PQ2_0`. Log: `llama-bench-ternary-bonsai2.log`. Launcher:
`llama-serve-ternary-bonsai2.sh`. `--no-mmproj`, 10 threads, profile unknown
(`powerprofilesctl` empty). `--fit on` under-sizes vs what actually loads
(PTQ1_0 q8_0 fit 21760 vs measured 32768; PQ2_0 q8_0 fit 4096 vs 16384).

**llama-bench** `-ngl 99 -fa on -ctk q8_0 -ctv q8_0 -p 512 -n 128 -r 3`:

| pack | size | pp512 | tg128 |
|---|---:|---:|---:|
| PTQ1_0 | 5.53 GiB | **268.30 ± 0.97** | **19.89 ± 0.09** |
| PQ2_0 | 6.70 GiB | **421.71 ± 1.72** | **18.71 ± 0.08** |

**Max context that loads** (explicit `-c`, `--fit off`, idle VRAM):

| pack | KV | max `-c` | idle VRAM | next size |
|---|---|---:|---:|---|
| PTQ1_0 | q8_0 | **32768** | 7112 MiB | 65536 OOM (rs cache 150 MiB) |
| PTQ1_0 | q4_0 | **65536** | 7336 MiB | 131072 OOM (KV 2304 MiB) |
| PQ2_0 | q8_0 | **16384** | 7632 MiB | 32k not tried (206 MiB free) |
| PQ2_0 | q4_0 | **32768** | 7744 MiB (94 MiB free) | — |

Short-chat TG (empty window) is ~20 t/s PTQ1_0 / ~18.5 t/s PQ2_0 across those
sizes. Occupied decode drops as the window fills:

| pack | alloc | KV | filled | PP t/s | TG t/s |
|---|---:|---|---:|---:|---:|
| PTQ1_0 | 8192 | q8_0 | 8064 | 260.9 | **18.14** |
| PTQ1_0 | 32768 | q8_0 | 32640 | 231.3 | **13.52** |
| PTQ1_0 | 65536 | q4_0 | 65408 | 201.2 | **10.02** |
| PQ2_0 | 8192 | q8_0 | 8064 | 396.2 | **16.65** |
| PQ2_0 | 16384 | q8_0 | 15682 | 368.1 | **14.92** |
| PQ2_0 | 32768 | q4_0 | 32640 | 328.0 | **12.74** |

PQ2_0 is the faster prefill; PTQ1_0 is the faster decode and the one that
still has KV headroom on this 8 GB card. Practical keep-set: PTQ1_0 `-c 32768`
q8_0, or PQ2_0 `-c 8192` q8_0 / `-c 16384` q8_0 if 206 MiB free is acceptable.

Qwen3.8-Flash-Next has 6 B active params against those models' ~3 B, but a far
larger total footprint. Run procedure:
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md).

**Group A — Qwen3.8-Flash-Next**, Unsloth patched mix, 8192 ctx, `--cpu-moe`,
q8_0 KV, 10 threads, full RAM, `balanced`, 2026-09-18 morning. Keep as the
patched-`b11007` snapshot. Evening mix-pr220 Group A used different prompts
(`llama-qwen38-group-a-mtp.py`); do not overwrite these rows.

| date | build | ctx | -t | KV | offload | other | PP t/s | TG t/s | VRAM | profile | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` | mmap warm, no MTP | 10.7 | 8.62 | ~6.0 GB | balanced | |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` | full RAM, no MTP | 11.8 | **8.06** | 5950 MiB | balanced | RSS ~87.5 GB |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` + `--spec-draft-cpu-moe` | MTP n_max=3, digits | 12.1 | **12.93** | 6546 MiB | balanced | 98% accept |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` + `--spec-draft-cpu-moe` | MTP n_max=3, prose | 21.8 | **6.51** | 6546 MiB | balanced | 31% accept |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` + `--spec-draft-cpu-moe` | MTP n_max=3, digits (new prompt) | 18.9 | **11.37** | 6546 MiB | unknown | 81% accept (90/111). Official #144@ca1426903 |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 8192 | 10 | q8_0/q8_0 | `--cpu-moe` + `--spec-draft-cpu-moe` | MTP n_max=3, prose (new prompt) | 15.3 | **9.31** | 6546 MiB | unknown | 68% accept (171/250). 256 gen |

**Group C — Qwen3.8 occupied context**, 16384 alloc, MTP n_max=3, `--cpu-moe`
+ `--spec-draft-cpu-moe`, q8_0 KV, 10 threads, `cache_prompt: false`, 128 gen,
prompt = `llama.cpp/src`. Log: `llama-bench-qwen38-occupied-20260918.log`.
`n_ctx` verified 16384. Procedure:
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md).

| date | build | ctx used | -t | KV | offload | other | PP t/s | TG t/s | VRAM | profile | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 574 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | 16384 alloc, MTP n_max=3 | 90.8 | 11.84 | 6696 MiB | unknown | draft 87/119 (73%) |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 2029 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | | 114.1 | 9.60 | | unknown | draft 85/124 (69%) |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 3910 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | | 108.4 | 10.76 | | unknown | draft 84/127 (66%) |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 8389 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | 71.5 s prefill | **117.3** | **13.04** | 7454 MiB after | unknown | draft 91/106 (86%) |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 15456 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | 16384 alloc, SKIP_RELOAD, CHARS=54000 | 121.4 | 11.21 | 7454 MiB | unknown | draft 86/120 (72%); 127.3 s prefill. Log: `llama-bench-qwen38-occupied-16k.log` |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 32702 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | **32768 alloc**, CHARS=110000 | 116.7 | **7.62** | 7078 MiB after | unknown | draft 35/88 (40%); n_predict clipped (~66 gen). CHARS=112000 was HTTP 400 (33178>32768). Log: `llama-bench-qwen38-occupied-32k-retry.log` |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 64099 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | **65536 alloc**, CHARS=220000 | 105.8 | **7.86** | 7682 MiB after | unknown | draft 83/130 (64%); 606 s prefill; 128 gen unclipped. Log: `llama-bench-qwen38-occupied-64k.log` |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 15456 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | **65536 alloc**, SKIP_RELOAD, 128 gen | 119.8 | 9.70 | 7684 MiB | unknown | draft 85/126 (67%). Same 15.5k fill as 16384-alloc 11.21 t/s. Log: `llama-bench-qwen38-occupied-64k-alloc-clean.log` |
| 2026-09-18 | unsloth b11007-mix + hc_head_norm | 32702 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | **65536 alloc**, SKIP_RELOAD, 128 gen | 115.6 | **8.00** | 7684 MiB | unknown | draft 75/153 (49%). Unclipped vs 32768-alloc 7.62 t/s (~66 gen). |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 574 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | 16384 alloc, official MTP pin | 88.9 | 8.94 | 6696 MiB | unknown | draft 87/119 (73%). Same CHARS as morning |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 2029 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | | 110.5 | 10.58 | | unknown | draft 85/124 (69%) |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 3910 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | | 105.9 | 9.43 | | unknown | draft 82/132 (62%) |
| 2026-09-18 | unsloth mix-pr220 `10921f3f1` | 8389 | 10 | q8_0/q8_0 | `--cpu-moe` + draft CPU-MoE | 73.0 s prefill | **114.9** | **9.25** | 7454 MiB after | unknown | draft 84/126 (67%). Log: `llama-bench-qwen38-pr220-20260918-214747.log` |

Occupied `/completion` prefill is **~90–121 t/s** (105.8 at 64k), not the ~12 t/s
seen on short chat. That is ~2× slower than the 35B’s ~230 t/s, not 15–20×.
Generation with MTP stayed in the **9.6–13.0 t/s** band out to 15.5k occupied
(11.21 t/s at 15.5k, −14% vs the 8k peak). At **32.7k / 64.1k occupied** TG is
**7.62 / 7.86 t/s** (−40% vs 8k). The 32.7k row is n_predict-clipped (~66 gen,
40% accept); 64.1k had a full 128 gen and 64% accept. The 8k point is still
the *fastest* TG (86% accept). First 32k CHARS=112000 overshot
(`request 33178 > 32768`); the probe now tokenizes and trims. VRAM: 6696 → 7454
on the 16384 load; 32768 load 6998/7078; 65536 load 7602 empty / 7682 after 64k
(156 MiB free).

**Real-world @ 65536 (same load, 2026-09-18).** Short prompts CUDA-OOM the
decode graph (~1.7 GiB) and kill llama-server. A ~15k-token filled
`/completion` works. Chat-wrapped *write a Solidity staking contract and a
test suite in typescript*: **10.52 t/s** (1024 gen, 78% draft) then
**11.35 t/s** continuation with `cache_prompt` (2048 gen, 88% draft).
Artifact `llama-qwen38-realworld-staking-output.md` (full contract; tests
cut at Unstaking by n_predict). Do not use `/v1/chat/completions` with
`max_tokens=6144` on this 8 GB / 64k+MTP load.

**Group E — engine A/B for Qwen3.8**, UD-IQ4_XS, 2026-09-27. 16384 alloc, MTP
n_max=3, `--cpu-moe` + draft CPU-MoE, q8_0 KV, 10 threads, full RAM, `balanced`,
same CHARS as Group C. TG t/s by occupied context. The newer engine is an
Unsloth-recipe mix on ggml-org b11160 (`llama-unsloth-mix-b11160-build.sh`), not
installed. Logs: `llama-bench-qwen38-udiq4xs-b11{166-ab,305}-*.log`.

| engine | 574 | 2029 | 3910 | 8389 | notes |
|---|---:|---:|---:|---:|---|
| mix-pr220 `11166 / 10921f3f1` r1 | 11.29 | 11.12 | 11.10 | 9.82 | baseline |
| mix-pr220 `11166 / 10921f3f1` r2 | 10.59 | 9.95 | 9.74 | 10.64 | |
| b11160-mix `11305 / e1204080a`, fusion on | 10.38 | **3.91** | 9.51 | 11.66 | blank-line loop at 2k, draft 19/318 |
| same, 2nd run | 10.67 | **5.84** | 9.52 | 9.66 | |
| same, `GGML_CUDA_DISABLE_FUSION=1` | 11.67 | 10.99 | 10.49 | 9.10 | output restored, no faster |

The newer engine's CUDA fusion changes greedy output on qwen4exp (suspect
`1a679828f` top-k MoE fusion; not sparse FA #28770). With fusion off it is no
faster. **Kept the 11166 base**; only the x86 Q2_0 kernel was added (Group F).

**Group F — Qwen3.8 GSQ-RCO Q2_0 vs UD-IQ4_XS**, engine mix-pr220-q2_0
`11170 / a2fa025fb` (= 11166 + ggml-org#26348 + `llama-q2_0-avxvnni-transposed.patch`)
for **both** quants, 2026-09-27. Flags as Group E. PP / TG t/s.
Logs: `llama-bench-qwen38-{udiq4xs,q2_0}-b11170-occupied-*.log`.

| quant | size | ctx used | PP t/s | TG t/s | draft | VRAM | RSS |
|---|---|---:|---:|---:|---|---|---|
| UD-IQ4_XS | 93.7 GB | 574 | 93.4 | 11.62 | 87/119 | 6696 MiB | ~87 GiB |
| UD-IQ4_XS | | 2029 | 113.6 | 10.87 | 85/124 | | |
| UD-IQ4_XS | | 3910 | 108.3 | 10.20 | 83/130 | | |
| UD-IQ4_XS | | 8389 | 116.7 | **9.83** | 82/134 | | |
| Q2_0 r1 | 66.4 GB | 574 | 144.3 | 20.22 | 80/138 | 4790 MiB | 61 GiB |
| Q2_0 r1 | | 2029 | 177.1 | 22.15 | 83/128 | | |
| Q2_0 r1 | | 3910 | 168.5 | 18.01 | 75/155 | | |
| Q2_0 r1 | | 8389 | 180.2 | **21.23** | 84/124 | | |
| Q2_0 r2 | | 574 | 158.7 | 20.05 | 81/135 | | |
| Q2_0 r2 | | 2029 | 176.8 | 20.93 | 83/128 | | |
| Q2_0 r2 | | 3910 | 168.5 | 19.01 | 78/146 | | |
| Q2_0 r2 | | 8389 | 180.1 | **21.19** | 85/126 | | |

Quality, same engine: wikitext-2 PPL (c512 × 40 chunks) **3.359 vs 2.744**
(+22%). KLD of Q2_0 against UD-IQ4_XS logits: mean 0.498, same top token 78%.
House Solidity prompt at temp 1.0 (3 seeds): Q2_0 **15.2–15.8 t/s**, 3/3
correct and finished. UD-IQ4_XS 7.2–7.7 t/s, 2/3 hit the 8192 cap. Greedy Q2_0
looped once, so do not run it at temp 0.

**Verdict:** Q2_0 is ~2× TG and ~1.55× PP at 8k, with 2 GB less VRAM and 26 GiB
less RAM. The quality loss shows in the statistics, not in the house prompt.
Handover §9 threshold (≥13 t/s at 8k) is passed, so Q2_0 is now the launcher
default. The Q2_0 CPU kernel is required: without #26348 + the local patch, x86
runs the scalar path (5.66 vs 7.60 cycles/32 values at MEM size, 2.90 vs 5.86
in cache).

**Group G — Unsloth's Oct engine update**, 2026-10-26. `unsloth` 2026.10.5
(installed 2026-10-14) replaced `~/.unsloth/llama.cpp` with stock
`b11541-mix-2500203`, overwriting the 11170 build. Studio now also passes
`--ubatch-size 2048` (September argv had none, so 512). 16384 alloc, MTP
n_max=3, same probe as Group F. TG t/s at 574 / 2029 / 3910 / 8389:

| engine | quant | ub | TG | PP @8k | VRAM |
|---|---|---|---|---:|---:|
| 11170 (Sept, Group F) | Q2_0 | 512 | 20.1 / 20.9 / 19.0 / 21.2 | 180 | 4.8 GB |
| stock b11541 | Q2_0 | 2048 | 3.3–3.6 / 3.8–4.1 / 3.1–3.3 / 3.3–3.5 | 309–314 | 6.4 GB |
| 11170 restored | Q2_0 | 2048 | 19.9–20.9 / 19.0–20.7 / 18.0–20.4 / **20.0–21.4** | **285–319** | 5.8 GB |
| stock b11541 | UD-IQ4_XS | 2048 | — CUDA OOM (1.36 GB alloc), Studio retried without MTP | | |
| 11170 restored | UD-IQ4_XS | 1024 | 10.0 / 10.5 / 8.5 / 9.7 (CPU 99 °C) | 97 | 7.1 GB |

Stock b11541 has only the scalar `ggml_vec_dot_q2_0_q8_0_generic` on x86, so
Q2_0 decode collapses ~6×. MTP acceptance was unchanged (75–86%). The PP gain
is Studio's ubatch 2048, **not** the engine: the old binary gets it too.
UD-IQ4_XS needs ub ≤1024 with MTP (launcher sets it). Sustained runs on
`balanced` throttle (fans max, 84–99 °C); the r2 rows are the hot ones.
**Verdict:** restored 11170 into Studio; stock bundle kept at
`~/.unsloth/llama.cpp/build/bin-b11541-stock`. Logs:
`llama-bench-qwen38-{q2_0,udiq4xs}-b11*-{occupied,restored}*-2026102*.log`.

## 6. Recording results

Keep the table in §5 as the structured summary, and put raw output —
full commands, memory breakdown tables, anything surprising — in
`llama.cpp-test.sh`, which is the append-only running log.

Rule of thumb: **if a run changes what you believe, update
[llama-run-guide.md](llama-run-guide.md) too** and strike the relevant
`[UNVERIFIED]` marker.
