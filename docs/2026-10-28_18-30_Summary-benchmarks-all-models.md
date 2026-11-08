# Local AI Model Benchmarks - summary 26 Oct 2026 18:30

Summary done by : Minimax-m3.1-flash (vercel AI-Gateway)

## Machine

i7-13700H + RTX 4070 Laptop 8 GB (35 W ceiling, `balanced` unless noted), 125 GB RAM, llama.cpp built from source w/ CUDA 13.3 — `README.md:3-5`, `llama-speed-table.md:10-13`.

All numbers are **PP = prefill t/s, TG = generation t/s**. "occ 8k" = occupied-window probe (real tokens in the window, `cache_prompt:false`, 128 gen) — that's the honest number; "empty" = short prompt, much faster.

## Models tested, with speeds

### 1. Qwen3.8-Flash-Next (MoE, 125 B total / 6 B active, `qwen4exp`) — main focus
Engine `b11027-mix-pr220` + `+q2_0-avxvnni` (build `11170/a2fa025fb`), MTP n_max=3, `--cpu-moe`, q8_0 KV. Occupied 8k (`llama-speed-table.md:22-40, 50-60`):

| quant | PP t/s | TG t/s | notes |
|---|---:|---:|---|
| GSQ-RCO **Q2_0** (66 GB) | 285–319 (up to 435 on stock b11876) | **20–21.4** | speed pick, 4.8–5.8 GB VRAM |
| GSQ-RCO **IQ3_XXS** (76 GB) | 259–261 | **11.3** | quality pick (KLD 0.29) |
| **UD-IQ4_XS** (94 GB) | 97–117 | **9.7–9.8** | quality baseline, PPL 2.74 |
| GSQ **Coder** (IQ1_M, 58 GB) | 131–142 | **5.3–5.5** | slowest, KLD 0.94 |

Variants: no-MTP empty prompt 11.8 PP / **8.06 TG**; MTP digits **12.93 TG** (98% accept) vs prose 6.51 (31% accept) — `llama-benchmark-and-tuning-guide.md:196-203`. Full 131k fill: **PP 34.9, TG 2.01** (62 min prefill) — `llama-speed-table.md:69`. Stock b11541 engine (no x86 Q2_0 kernel): TG drops to **3.4** — `llama.cpp-test.sh:958-968`.

Latest power-profile A/B (2026-10-28, IQ4_XS, `llama-qwen38-powerprofile-ab-cleanfans-20261028-161405.txt`): balanced PP 116–178 / TG 8.7–9.5; performance PP 122–180 / TG **9.8–12.7** (GPU ceiling 35 → 40 W).

### 2. Ternary-Bonsai-2-27B (1.58-bit ternary, PrismML)
- **Stock Prism b10706**, llama-bench pp512/tg128: PTQ1_0 **268.3 / 19.89**; PQ2_0 **421.7 / 18.71** (`llama-benchmark-and-tuning-guide.md:196-201`). Occupied: PTQ1_0 260.9/18.14 @8k, 231/13.52 @32k, 201/10.02 @64k; PQ2_0 396/16.65, 368/14.92, 328/12.74 (`…:220-232`).
- **"Ada surgery" runtime** (bonsai-ada-surgery fork, 262k ctx, q3_0 KV, MTP+lookup, `blocking`): PP 399/477/481/**471**/386/341/139 and TG 29.8/29.9/29.7/**30.9**/26.8/25.0/6.6 at 574/2k/3.9k/**8.4k**/33k/61k/129k (`handover-bonsai2-ada-evaluation.md` §4.2). vs stock: **TG 1.5–2.0×, PP 1.6–1.8×**.
- Newest A/B (`llama-bonsai2-powerprofile-ab-cleanfans-20261028-155630.txt`): llama-bench pp512 **613** / tg128 **28.4** (balanced), **644 / 29.8** (performance); occupied probe PP 546–591 / TG 34–37 with lookup drafting on.

### 3. Qwen3.6-35B-A3B (MoE)
- UD-Q4_K_XL, `--cpu-moe`, 200k alloc, occupied: 574→**193.6 PP / 26.37 TG**, 16k→286/24.53, 65k→230/20.20, 129k→115/**4.56** (`llama-benchmark-and-tuning-guide.md:139-146`). Empty-window TG **30.20** (Unsloth b11007) / 27.62 (local build, 9% slower).
- UD-Q6_K_XL: PP 175, TG 18.6 (measured 14.3–18.6 across runs, `llama.cpp-test.sh:251-270`).
- MTP variant: TG **25.1** (`llama-benchmark-and-tuning-guide.md:170`).
- Qwen3.5-35B-A3B UD-Q4_K_XL (`-ot exps=CPU`): PP **274**, TG **23.9** (`llama.cpp-test.sh:14-36`).

### 4. Dense / small models
| model | PP t/s | TG t/s | source |
|---|---:|---:|---|
| Qwen3.5-4B UD-Q4_K_XL (+mmproj, vision) | **889.7** | **53.6** | `llama.cpp-test.sh:169-190` |
| Qwen3.5-9B Q4_K_S, all GPU, 16k | **290.2** | **37.5** | `llama.cpp-test.sh:73-100` |
| Qwen3.5-9B Q4_K_S, 64k ctx | 265.1 | 37.4 | `llama.cpp-test.sh:107-118` |
| Qwen3.5-9B Q4_K_M | 186.1 | 28.2 | `llama.cpp-test.sh:136-141` |
| Qwen3.5-9B UD-Q5_K_XL | 163–168 | 29.6–30.4 | `llama.cpp-test.sh:145-166` |
| Bonsai 27B Q1_0 (dense) | **46.5** | **~26** | `llama-speed-table.md:124` |
| Qwen3.6-27B UD-Q4_K_XL (partial offload) | 9.5 | 2.3 (aborted) | `llama.cpp-test.sh:280-300` |
| gemma-4-31b-i1 (LM Studio) | — | 2.44 | `llama.cpp-test.sh:273-278` |
| Ornith 1.0 35B | launcher exists (`llama-serve.sh`) but **no PP/TG measured in the repo** | | `llama.cpp-test.sh:318-343` |

## Caveats
- TG is only comparable at equal context, equal MTP/drafting setting and equal power state — `llama-speed-table.md:13-16`.
- The occupied probe's raw `/completion` continues source text, so lookup drafting flatters Bonsai TG (up to 197 t/s on copy-heavy answers) — `handover-bonsai2-ada-evaluation.md` §6.6.
- Thermal throttling is live: sustained load drops the GPU ceiling 35 → 20 W and ~4× decode; wait for a cool box before comparing arms — `handover-bonsai2-ada-evaluation.md` §5.
- The speed table has **not** yet been updated with the Bonsai-2 Ada runtime rows or the 2026-10-28 power-profile A/Bs (handover §8 lists that as pending) — the numbers above come from `handover-bonsai2-ada-evaluation.md` and the two `*-powerprofile-ab-*20261028*.txt` files.

If you want this consolidated into `llama-speed-table.md`, that needs write mode (`/mode build`).
