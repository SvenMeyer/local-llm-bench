# Inference speed table (this box)

One row per model × quant × engine × key parameters. Headline numbers only;
the full runs, per-context breakdowns and caveats live in
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md) §5
(the "src" column names the group) and the raw log `llama.cpp-test.sh`.
**Append a row for every new measurement**, newest at the bottom of its model block.

Box: i7-13700H, RTX 4070 Laptop 8 GB (`10de:2820`, AD106M), 125 GB RAM, `balanced` unless noted.
PP = prefill t/s, TG = generation t/s. "occ" = real tokens in the window
(occupied probe, `cache_prompt: false`, 128 gen); "empty" = short prompt.
Compare TG only at equal context and equal MTP setting.

## Qwen3.8-Flash-Next (MoE, 6 B active)

Common flags unless noted: `--cpu-moe`, q8_0/q8_0 KV, FA on, 10 threads, full RAM
(`--load-mode none --lazy-mode off`), alloc 16384.

| date | quant | engine | key params | ctx | PP | TG | VRAM | src |
|---|---|---|---|---|---:|---:|---:|---|
| 2026-09-18 | UD-IQ4_XS | b11007-mix + hc_head_norm patch | alloc 8192, no MTP | empty | 11.8 | 8.06 | 5.9 GB | A |
| 2026-09-18 | UD-IQ4_XS | b11007-mix + hc_head_norm patch | MTP n3, digits / prose | empty | 12–22 | 12.93 / 6.51 | 6.5 GB | A |
| 2026-09-18 | UD-IQ4_XS | b11007-mix + hc_head_norm patch | MTP n3 | occ 8k | 117 | 13.04 | 7.5 GB | C |
| 2026-09-18 | UD-IQ4_XS | b11007-mix + hc_head_norm patch | MTP n3, alloc 65536 | occ 64k | 106 | 7.86 | 7.7 GB | C |
| 2026-09-18 | UD-IQ4_XS | mix-pr220 `11166/10921f3f1` | MTP n3 | occ 8k | 115 | 9.25 | 7.5 GB | C |
| 2026-09-27 | UD-IQ4_XS | b11160-mix `11305`, CUDA fusion on | MTP n3 | occ 2k / 8k | — | 3.91 / 11.66 | — | E (broken output) |
| 2026-09-27 | UD-IQ4_XS | b11160-mix `11305`, fusion off | MTP n3 | occ 8k | — | 9.10 | — | E |
| 2026-09-27 | UD-IQ4_XS | mix-pr220-q2_0 `11170/a2fa025fb` | MTP n3, ub 512 | occ 8k | 117 | 9.83 | 6.7 GB | F |
| 2026-09-27 | GSQ-RCO Q2_0 | mix-pr220-q2_0 `11170/a2fa025fb` | MTP n3, ub 512 | occ 8k | 180 | **21.2** | 4.8 GB | F |
| 2026-10-26 | GSQ-RCO Q2_0 | stock Unsloth `b11541-mix-2500203` | MTP n3, ub 2048 | occ 8k | 311 | 3.4 | 6.4 GB | G (no x86 Q2_0 kernel) |
| 2026-10-26 | UD-IQ4_XS | stock Unsloth `b11541-mix-2500203` | MTP n3, ub 2048 | — | — | — | OOM | G |
| 2026-10-26 | GSQ-RCO Q2_0 | mix-pr220-q2_0 `11170` (restored) | MTP n3, ub 2048 | occ 8k | 285–319 | **20.0–21.4** | 5.8 GB | G |
| 2026-10-26 | UD-IQ4_XS | mix-pr220-q2_0 `11170` (restored) | MTP n3, ub 1024 | occ 8k | 97 | 9.7 | 7.1 GB | G (CPU 99 °C) |
| 2026-10-26 | GSQ-RCO Q2_0 | stock Unsloth `b11876-mix-ec42614` (direct) | MTP n3, ub 2048 | occ 2k–8k | 392–435 | 14.0–18.7 | 6.4 GB | upstream AVX2 Q2_0 (#30447) |
| 2026-10-26 | GSQ-RCO Q2_0 | mix-pr220-q2_0 `11170` (direct) | MTP n3, ub 2048 | occ 2k–8k | 264–309 | 15.5–19.7 | 5.8 GB | same flags as row above; box hot |

| 2026-10-27 | GSQ-RCO IQ3_XXS | mix-pr220-q2_0 `11170` (direct) | MTP n3, ub 2048 | occ 8k | 259–261 | **11.3** | 6.6 GB | H |
| 2026-10-27 | GSQ-RCO Coder (256 exp, "IQ1_M") | mix-pr220-q2_0 `11170` (direct) | MTP n3, ub 2048 | occ 8k | 131–142 | 5.3–5.5 | 6.6 GB | H |

### Quant shoot-out, 2026-10-27 (engine 11170, group H)

Quality on wikitext-2 (c512 × 40) vs UD-IQ4_XS logits (no BF16 base on this box). Agent eval is
`llama-agent-eval.py`: 8 tasks (t1–t8, incl. multi-file refactor, LRU bugs, parser, scheduler)
× 3 seeds, OpenAI tool calls through llama-server, 64k ctx, MTP n3, xhigh reasoning (template default),
temp 1.0. Scored against pristine tests.

| quant | disk | PPL | KLD vs IQ4_XS | top-1 agree | 99% KLD | TG occ 8k | PP occ 8k | agent pass | min/task | agent TG |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| UD-IQ4_XS | 93.7 GB | 2.744 | (base) | (base) | — | 9.7–9.8 | 97–117 | not run | — | — |
| **GSQ IQ3_XXS** | 75.8 GB | **2.849** | **0.293** | **84.2%** | 3.35 | **11.3** | **260** | 24/24 | 5.8 | 9.8 |
| GSQ Q2_0 | 66.4 GB | 3.359 | 0.498 | 78.0% | 4.76 | **20–21** | 285–319 | 24/24 | **5.1** | **10.8** |
| GSQ Coder | 58.4 GB | 5.110 | 0.938 | 68.8% | 7.65 | 5.3–5.5 | 131–142 | 24/24 | 7.6 | 8.4 |

All 72 agent runs passed with 0 malformed tool calls, 0 errors, 0 length stops. **The task set does not
separate these quants**, so quality ranking comes from KLD/PPL only. Wikitext is general text, which the
Coder pruned away by design. Its KLD overstates its coding loss, but its speed (the slowest of all) is real.
Agent TG is below the probe TG because of longer outputs, tool turns and prompt growth.

### Max context, UD-IQ4_XS on `11170` (2026-10-26)

Loaded with `llama-serve-qwen38-direct.sh`; "ok" = loads, `n_ctx` verified, short prompt
generates. VRAM free is about 7547 MiB; at 131072 the model takes 4459 MiB, KV + indexer + RS 1948, compute 1200 (ub 512).

| MTP | KV | ub | extra | max ok | next size | idle VRAM | short TG |
|---|---|---:|---|---:|---|---:|---:|
| on | q8_0 | 512 | — | **65536** | 81920 OOM (185 MiB) | 7602 MiB | 7.02 |
| on | q8_0 | 256 | — | 65536 | 98304 OOM (192 MiB) | — | — |
| off | q8_0 | 256 | `-ot token_embd.weight=CPU` | **131072** | 196608 OOM | 7774 MiB | 7.45 |
| off | q4_0 | 256 | `-ot token_embd.weight=CPU` | **196608** | 262144 OOM (1124 MiB) | 7444 MiB | 7.34 |
| on | q4_0 | 512 | — | <131072 | 131072 OOM (233 MiB) | — | — |

**Full-window check** (MTP off, q8_0, ub 256, 131072): 129,263 tokens filled with no OOM
(VRAM 7798 MiB). Prefill took **3700 s (~62 min, 34.9 t/s)**, then TG **2.01 t/s**. It works, but it isn't usable;
the box was hot after an hour of load, so treat it as a lower bound. **Chosen default: MTP on, q8_0, 65536**
(Sept: 64k filled at 7.86 t/s).

### Which kernels the Qwen3.8 quants actually use (routed experts, from GGUF headers)

Unsloth's names are labels for mixes. With `--cpu-moe` these experts run on the CPU,
so their x86 vec_dot kernel sets decode speed.

| GGUF | GB | top-1 vs BF16 (Unsloth) | gate/up experts | down experts |
|---|---:|---:|---|---|
| UD-IQ4_XS | 93.7 | 89.55 | IQ3_S | IQ4_NL |
| UD-Q3_K_XL | 90.0 | 88.32 | IQ3_XXS | IQ4_NL |
| UD-IQ3_XXS | 82.0 | 85.41 | IQ2_S | IQ4_NL |
| UD-Q2_K_XL | 78.9 | 82.72 | IQ2_XS | IQ4_NL |
| GSQ-RCO Q2_0 | 66.4 | not published | Q2_0 ×144 (uniform) | |
| GSQ-RCO IQ2_XS | 68.0 | not published | IQ2_S 68 · Q2_0 48 · IQ2_XXS 22 · IQ1_M 6 | |
| GSQ-RCO IQ3_XXS | 75.8 | not published | Q2_0 30 · IQ3_S 26 · IQ2_XS 20 · IQ2_S 20 · IQ4_NL 18 · IQ2_XXS 18 · IQ3_XXS 12 | |
| GSQ-RCO IQ3_S | 83.6 | not published | IQ2_S 40 · IQ4_NL 39 · IQ3_XXS 34 · IQ3_S 20 · Q2_0 9 · IQ4_XS 2 | |
| GSQ-RCO Coder (256 experts) | 58.4 | not published | same mix as GSQ IQ3_S | |

GSQ shard 2 (28.8 GB n-gram table, sha `316b46f3a2dbd68c`) is byte-identical in every GSQ
tier **and** the Coder, so each extra tier costs only its shard 1 (IQ3_XXS 47.0, IQ3_S 54.8,
Coder 29.6 GB). Symlink the existing Q2_0 shard 2.

ISTA reasoning task avg (AIME25 / GPQA-D / LCB v6, xhigh effort): BF16 93.12 · IQ3_S 93.26 ·
IQ3_XXS 92.57 · IQ2_XS 89.16 · Q2_0 89.07. LCB v6: 87.43 / 86.86 / 86.29 / 83.43 / 81.14.
Coder: LCB 87.43, SWE-bench Verified 79.2 vs BF16 82.8.

Single-thread vec_dot throughput, 11170 build, 512 MB working set (from RAM), i7-13700H
(`scratchpad vecdot_bench.c`, 2026-10-26), in Gweights/s: q2_0 **22.3** · q2_K 31.4 · q4_K 24.3 ·
q3_K 20.1 · iq4_xs 18.4 · iq4_nl 16.3 · q8_0 14.4 · iq2_xxs 12.0 · iq2_s 11.4 · iq3_xxs 9.8 ·
iq3_s **6.7**. The IQ grid kernels are 2–3× slower per weight than k-quants. UD-IQ4_XS
spends most of its decode time in the slowest kernel (iq3_s).

**Estimated** occ-8k TG with MTP. This is a two-point fit (T = 14.4 ms + 0.731 × expert-kernel cost) on
the measured IQ4_XS 9.8 and Q2_0 21.2; not measured:
UD-Q3_K_XL ~12.6 · UD-IQ3_XXS ~13.9 · UD-Q2_K_XL ~14 (iq2_xs assumed like iq2_xxs) ·
GSQ IQ3_XXS ~12.9 (measured 11.3) · GSQ IQ3_S ~12.5 · GSQ Coder ~12.5 (**measured 5.4, the estimate was wrong**:
the model only counted expert kernels; the Coder's dense path is far heavier, with Q6_K/Q5_K/BF16 on GPU and
perplexity pass time 26.8 s vs Q2_0 12.7 s) · GSQ IQ2_XS ~14.8 (iq1_m assumed 12 Gw/s).

## Qwen3.6 / 3.5 35B-A3B (MoE, 3 B active)

| date | quant | engine | key params | ctx | PP | TG | VRAM | src |
|---|---|---|---|---|---:|---:|---:|---|
| 2026-09-17 | UD-Q4_K_XL | Unsloth `b11007-mix-3e83366` | `--fit on`, f16 KV, alloc 8192 | empty | — | 30.20 | 6.6 GB | A |
| 2026-09-17 | UD-Q4_K_XL | local b11011 (`-march=native`, sm_89) | same | empty | — | 27.62 | 6.6 GB | A |
| 2026-09-17 | UD-Q4_K_XL | Unsloth `b11007-mix` | `--fit on`, q8_0 KV, alloc 180224 | empty | — | 26.47 | 6.7 GB | B |
| 2026-09-17 | UD-Q4_K_XL | Unsloth `b11007-mix` | `--cpu-moe`, q8_0 KV, alloc 200192 | occ 16k / 65k | 286 / 230 | 24.53 / 20.20 | 5.2 GB | C |
| — | Qwen3.6 UD-Q6_K_XL | — | `--cpu-moe`, alloc 131072, q8_0 KV | — | 175 | 18.6 | — | ref |
| — | Qwen3.6-MTP | — | `--spec-type draft-mtp`, alloc 131072 | — | — | 25.1 | — | ref |
| — | Qwen3.5 UD-Q4_K_XL | — | `-ot exps=CPU`, alloc 131072, q8_0 KV | — | 274 | 23.9 | — | ref |

## Small / dense models

| date | model / quant | engine | key params | ctx | PP | TG | VRAM | src |
|---|---|---|---|---|---:|---:|---:|---|
| — | Qwen3.5-9B Q4_K_S | — | all GPU, q4_0 KV, alloc 16384 | — | 290 | 37.5 | — | ref |
| — | Bonsai 27B Q1_0 | — | dense, all GPU, alloc 32768 | — | 46.5 | ~26 | — | ref |
| 2026-09-19 | Ternary-Bonsai-2 PTQ1_0 | Prism `b10706/1a07bfa5f` | llama-bench, all GPU, q8_0 KV | pp512/tg128 | 268 | 19.89 | — | Bonsai |
| 2026-09-19 | Ternary-Bonsai-2 PQ2_0 | Prism `b10706/1a07bfa5f` | llama-bench, all GPU, q8_0 KV | pp512/tg128 | 422 | 18.71 | — | Bonsai |
| 2026-09-19 | Ternary-Bonsai-2 PQ2_0 | Prism `b10706/1a07bfa5f` | server, q8_0 KV, alloc 16384 | occ 15.7k | 368 | 14.92 | — | Bonsai |

## TwIL-8B (webAI, Granite 4.2 dense 8.8B, balanced) — stock llama.cpp

Launcher `llama-serve-twil8b.sh`; scripts `llama-twil8b-fit-bench.sh`, `llama-twil8b-kv-ab.sh`. GPU held at its 35 W cap (~1.0 GHz SM);
a cold first run boosts briefly (tg128 37.4 at d0, 19.0 at d24576), so use the steady rows. All-GPU fit: q4_0 KV 40k, q8_0 KV 24k.

| date | quant | engine | key params | ctx | PP | TG | VRAM | src |
|---|---|---|---|---|---:|---:|---:|---|
| 2026-11-06 | TwIL-8B i1-Q4_K_M (Granite dense) | stock `b12169/3ed7284f2` | llama-bench, all GPU, q8_0 KV, 35 W steady | d0 pp512/tg128 | 1408 | 29.92 | — | TwIL |
| 2026-11-06 | TwIL-8B i1-Q4_K_M | stock `b12169` | llama-bench, all GPU, q8_0 KV (q4_0 / mixed within 3%) | d16384 | 621 | 18.98 | — | TwIL |
| 2026-11-06 | TwIL-8B i1-Q4_K_M | stock `b12169` | llama-bench, all GPU, q8_0 KV (q4_0 / mixed within 3%) | d24576 | 435 | 15.09 | — | TwIL |
| 2026-11-06 | TwIL-8B i1-Q4_K_M | stock `b12169` | server, q4_0 KV, alloc 40960, real reasoning answers | occ ~2-3.5k | — | 26-27 | — | TwIL |
| 2026-11-07 | TwIL-8B i1-Q4_K_M | stock `b12169` | agent suite seed 1, reasoning kept (template default) | agent, up to 36k | — | 13.52 | 7.1 GB | TwIL |
| 2026-11-07 | TwIL-8B i1-Q4_K_M | stock `b12169` | agent suite seed 1, `--no-reasoning-preserve` | agent, <10k typical | — | 19.84 | 7.1 GB | TwIL |

## Qwen3.8-Flash-Next on Strata 0.2.11 — agent suite (2026-11-07)

24-run tool-calling suite (`llama-agent-eval.py`), 64k, `STRATA_ROUTE_TAIL_SKIP=0 STRATA_ROUTE_PRIOR=1.5`, default DFlash2 drafter, 35 W.
TG = suite completion tokens / generation seconds. October 0.1.52 (MTP): IQ3_XXS 28.02, IQ3_S 24.24.

| date | quant | engine | key params | ctx | PP | TG | VRAM | src |
|---|---|---|---|---|---:|---:|---:|---|
| 2026-11-07 | GSQ IQ3_XXS | Strata 0.2.11 / 0.1.57 | agent suite, DFlash2 85% accept | agent | — | 28.87 | 8 GB + RAM | overnight |
| 2026-11-07 | Unsloth v3.1 UD-IQ3_XXS | Strata 0.2.11 / 0.1.57 | agent suite, DFlash2 84% accept | agent | — | 24.63 | 8 GB + RAM | overnight |
| 2026-11-07 | GSQ IQ3_S | Strata 0.2.11 / 0.1.57 | agent suite, DFlash2 84% accept | agent | — | 23.26 | 8 GB + RAM | overnight |
| 2026-11-08 | Unsloth v3.1 UD-IQ4_XS | Strata 0.2.11 / 0.1.57 | PatchEval via pi (20 tasks, 30 min cap), DFlash2 | agent, 64k | — | 15.1 | 7.32 p50 / 7.58 p99 / 7.78 peak of 8.19 GB | PatchEval 12/20 |

TG for the PatchEval row = BenchKit average stream tok/s (not comparable 1:1 with the suite TG). VRAM from a 5 s
`nvidia-smi` log (`benchkit-patcheval-strata-ud31-iq4xs-noskip-0211.log.vram`).
**Correction 2026-11-09:** the "~400 MB unused at peak" read here was total minus used. On this card used + free is
always 7,892 MiB, so 296 MiB of the 8,188 are never usable. The 2026-11-09 A/B log (`patcheval-strata-prior-ab-20261109-0153.vram`,
free MiB per sample) shows **114 MiB free at peak** (used 7,778, same peak as Nov 8), 556 MiB most of the time, below 400 MiB in
5% of samples. Real spare at peak is ~110 MiB (~55 experts at ~2 MiB each), not ~400.
