# Strata engine + GSQ-RCO quants — evaluation for this box

Assessment of [Niko1221/Strata](https://github.com/Niko1221/Strata) (v0.1.2, 2026-09-25) and
the [ISTA-DASLab GSQ-RCO](https://huggingface.co/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF)
quantizations, both of which target **our exact model**, Qwen3.8-Flash-Next.

Written 2026-09-26. Nothing here is measured on this machine — everything below is either
quoted from the sources, or **derived** from their source code and marked as such. Our own
measured baseline for comparison is in
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md#5-results-log):
**8.94 / 10.58 / 9.43 / 9.25 t/s** at 0.5k / 2k / 4k / 8k occupied, 16384 allocated, MTP
n_max=3, `--cpu-moe`, Unsloth mix-pr220 build.

---

## 1. Verdict

Worth testing, in this order: **the quant first, the engine second.** They are separable and
the quant is the cheaper, lower-risk half.

- Strata's numbers are **real measurements**, not marketing: `bench/results/2026-09-24-final/matrix.json`
  carries raw rows (wall time, TTFT, spec-accept rate, VRAM slots). But only on **one card**,
  an RTX 5070 12 GB. Every other card in `estimates.md` is extrapolation.
- The headline gap over us is roughly **7–9x on decode** and **~5x on prefill**. It does not
  come from one trick, and **the single largest factor is one we already have** (MTP).
- On 8 GB we would get roughly **a quarter to a third of the expert cache** the design wants
  (§4). The author's own requirements table says *"12 GB VRAM or more (8 GB runs, slowly)"*
  and *"Measured on RTX 5070; RTX 30/40 untested"* — our Ada card would be the first of its
  generation tried.
- The quant quality claim is **better supported than expected** and is the more interesting
  finding of the two (§5).

## 2. What Strata is

A from-scratch CUDA inference engine for this one architecture, ~200 source files, borrowing
only `third_party/ggml` headers. It has hand-written kernels for the things that make this
model unusual — `native_qsa*` (the sparse-indexer attention), `native_gdn*` (Gated DeltaNet),
`ple*` (per-layer embeddings), `ngram*` (the 28.8 GB table), `router_top10` — plus parity
tests against reference vectors for nearly every kernel, and a memory planner
(`include/strata/plan/plan.hpp`) that is documented to **refuse rather than silently
overcommit**. This is not a wrapper.

Its tiering, from `docs/DETAILS.md`:

- **GPU:** attention, DeltaNet mixers, gated-residual weights, routers, shared experts,
  output head, MTP draft layer, KV cache, and an **expert cache** that fills whatever VRAM
  remains with the most-used experts, adapting during the conversation.
- **RAM:** all 24,576 experts, pinned. The **CPU computes the experts that are not on the
  GPU, concurrently with the GPU working on the cached ones.**
- **SSD:** the 28.8 GB n-gram table, a few rows per token through the OS cache.
- **Speculation:** the model's own MTP layer drafts up to 3 tokens; 2.4–3.2 accepted per pass.

## 3. Where the speed actually comes from

| Mechanism | Their gain | Available to us? |
|---|---|---|
| MTP speculative decode | 2.4–3.2 tok/pass, accept 0.74–0.87 | **Already banked** — our 8.94–10.58 t/s figures already include MTP |
| 2-bit-class quant (66–76 GB vs our 93.7 GB) | ~1.4–1.5x fewer expert bytes per token | **Yes, and cheaply** — see §5/§7 |
| Hot-expert VRAM cache + CPU computing misses *concurrently* with GPU | large | **Only via Strata.** llama.cpp has no equivalent: `--cpu-moe` is static all-or-nothing, `-ncmoe N` is static per-layer. Neither adapts to routing frequency, neither overlaps CPU and GPU expert work |
| Fused architecture-specific kernels | large, especially prefill | Only via Strata |

Their measured prefill is **539 t/s** against our **~89–115 t/s**. They process 128k of prompt
in 237 s. For the workflow of feeding source files and asking questions, that ~5x prefill gap
is probably worth more day to day than the decode gap — our own logs show prefill dominating
long-prompt wall-clock (1120 s at 129k on the 35B).

## 4. The 8 GB arithmetic — DERIVED from `plan.hpp`

`plan.hpp` makes this computable rather than guesswork. Constants, all read from the source:

| quantity | value | where |
|---|---|---|
| one expert slot | 1,382,400 B | `Costs::expert_blob` |
| KV + indexer keys | **13,056 B/token** | `kv_bytes_per_token()`: 12 QSA layers x (1056 INT8 KV+scales + 32 pooled indexer key) |
| GDN recurrent state | 117.7 MB, **not evictable** | `state_bytes()`: 36 GDN layers x 3,268,608 B |
| VRAM pool | `free_vram - dense - embd` | `plan_main.cpp:61` |

Note their KV is **13 KB/token, half** the ~25 KB our run-guide §4 estimated — INT8 KV plus
one pooled 128-wide indexer key per 4-token block, not per token.

Back out the pool from their **measured** `vram_slots`, since the hardcoded
`vram_pool_bytes() = 5.943e9` disagrees with the benchmark rows:

| ctx | measured slots | slots x 1.3824 MB | + KV | + state | ⇒ pool |
|---|---:|---:|---:|---:|---:|
| 1k | 4517 | 6.244 GB | 0.013 | 0.118 | **6.38 GB** |
| 32k | 4174 | 5.770 GB | 0.428 | 0.118 | **6.32 GB** |
| 64k | 3809 | 5.266 GB | 0.856 | 0.118 | **6.24 GB** |

So pool ≈ **6.3 GB** on their 12 GB card, which puts **dense + embeddings at ~5.7–5.9 GB —
a fixed cost that cannot be shrunk.** That single number is what governs whether 8 GB works.

Our card: 8188 MiB total, 44 MiB in use (display is on the iGPU, so we keep nearly all of
it). Allowing ~300–400 MB for the CUDA context, `free_vram` ≈ 8.0 GB, so **pool ≈ 2.2 GB**:

| ctx | KV | expert cache left | slots (ours) | theirs | ratio |
|---|---:|---:|---:|---:|---:|
| 4k | 0.053 | 2.03 GB | ~1,470 | 4464 | 33% |
| 32k | 0.428 | 1.65 GB | ~1,200 | 4174 | 29% |
| 64k | 0.856 | 1.23 GB | ~890 | 3809 | 23% |
| 128k | 1.711 | 0.37 GB | ~270 | ~3190 | 8% |
| 262k | 3.422 | — | **`DoesNotClose`** | ~1950 | — |

These are **upper bounds**: `workspace_bytes` is unknown and subtracts further. At 262k the KV
alone (3.42 GB) exceeds the whole pool, so the planner throws at startup by design — 262k is
arithmetically impossible on this card, and ~64k is the realistic ceiling.

Decode overlaps GPU work on cached experts with CPU work on the misses, so throughput is
bounded by the slower side. At ~29% of the intended cache our miss rate rises and the CPU side
dominates. **Rough estimate: 25–45 t/s at short context**, still 3–4x our measured 9–10 t/s,
but with wide error bars on an untested GPU generation.

## 5. The quant quality claim — the more interesting half

**Claim examined:** that GSQ-RCO IQ2 matches Unsloth at ~2 bits more.

**Directionally right, but shift it one notch, and the evidence is split across two sources.**

The HF model card for the 125B quants compares **only against BF16 — it contains no Unsloth
comparison at all**:

| variant | bpw | GB | zero-shot avg | reasoning task avg |
|---|---:|---:|---:|---:|
| BF16 | 16.00 | 354 | 76.94 | **93.12** |
| Q2_0 | 2.40 | 66.4 | 78.00 | 89.07 (−4.4%) |
| IQ2_XS | 2.50 | 68.0 | 77.16 | 89.16 (−4.3%) |
| IQ3_XXS | 3.00 | 75.8 | 77.23 | **92.57 (−0.6%)** |

Read the **task average** (AIME25, GPQA-Diamond, LiveCodeBench v6), not the zero-shot column.
The zero-shot set (arc, hellaswag, winogrande, piqa) is saturated and noisy — quantized models
scoring *above* BF16 there, as all three do here, is noise, not a free lunch, and a "101.4%
recovery" headline built on it should be discounted.

On that reading: **IQ3_XXS at 3.00 bpw is near-lossless (−0.6%)**, while IQ2_XS and Q2_0 give
up a real ~4.3% on reasoning.

**The actual head-to-head with Unsloth is in the method repo**, not the model card.
[IST-DASLab/GSQ](https://github.com/IST-DASLab/GSQ) (73★, active 2026-07) §"Qwen3-8B GGUF
K-Quant" states that starting from **public Unsloth GGUF checkpoints**, GSQ refines the
discrete assignments and projects back into the *same* K-Quant format, and:

> The gains are largest in the aggressive Q2_K setting (avg score 50.03 → **56.28**).

That is **+6.25 points at identical bits and identical format** over Unsloth. So GSQ really
does beat Unsloth at equal bpw — measured, and on a Qwen3 model. Two caveats that bound how
far to carry it:

1. *"Gains are largest in the aggressive Q2_K setting"* — the advantage **compresses as bits
   increase**, so a +6 point gap at 2 bits does not imply the same at 4. Our UD-IQ4_XS
   (~4.25 bpw) sits where GSQ's edge is smallest.
2. On Llama-3.1 at 2-bit, GSQ scores **68.55** vs QTIP (vector-quantized) 69.88 and FP16
   73.71 — i.e. GSQ closes *most* of the scalar-to-VQ gap while staying in a scalar format
   that existing INT kernels can run. It is a strong scalar method, not a new tier.

**Practical conclusion:** the fair comparison for us is **GSQ IQ3_XXS (3.00 bpw, 75.8 GB)
against our UD-IQ4_XS (~4.25 bpw, 93.7 GB)** — about 1.25 bpw and 18 GB less, at a claimed
−0.6% from BF16. That is a credible quality-neutral-or-better swap, which is a stronger
statement than the speed argument. "IQ2 ≈ Unsloth+2bits" overstates it for reasoning work.

Two further caveats from the model card, both relevant to us:

- The quants are *"primarily optimized for **xhigh** reasoning effort"* and at lower effort
  *"degradation can be larger."* If we run `reasoning_effort: medium` for speed
  (run-guide §6), the published quality numbers do not apply.
- `ffn_down_exps` is **pinned to Q2_0** and excluded from the search, because its 640 rows are
  not divisible by 256; the n-gram table is pinned at IQ4_NL (~4.5 bpw).

**`Q2_0` is a real ggml type and our build supports it — CHECKED 2026-09-26.** This was the
gating worry (if `Q2_0` were Strata-local, the pinned `ffn_down_exps` would make even the
IQ3_XXS file unloadable outside Strata). It is not:

```
ggml/include/ggml.h:432          GGML_TYPE_Q2_0 = 42
ggml/src/ggml.c:685              type_traits entry, blck_size QK2_0, block_q2_0
ggml/src/ggml.c:8083             quantize_q2_0(...)
ggml/src/ggml-cuda/mmvq.cu:43    vec_dot_q2_0_q8_1     (CUDA matvec)
ggml/src/ggml-cuda/convert.cu    dequant paths at 462/519/579/638
```

So it has CPU traits, a quantizer, a CUDA dot-product kernel and dequant — not just an enum
slot. **The ISTA-DASLab GGUFs should load and run in our existing Unsloth Studio build**, which
means the quant can be evaluated with no new engine at all. Still worth confirming against the
real file header before committing 76 GB (§7 step 1), since a type existing is not proof that
*this* file's particular tensor/shape combinations are all handled.

GSQ can refine GGUF in-format, so in principle our existing quant could be improved in place —
but that needs GPTQ Hessians plus Gumbel-Softmax optimization over a 125B model. Not
happening on this laptop.

## 5b. Header verification — all three quants, VERIFIED 2026-09-26

Parsed the **real GGUF headers** off HuggingFace via HTTP range requests (~24 MB fetched per
file; the header is 11.02 MB), not just the published allocation files — script kept at
`scratchpad/gguf_head.py`. Both sources agree exactly.

```
general.architecture = qwen4exp        <- matches our build's arch
qwen4exp.expert_count = 512  x 48 blocks = 24,576 experts
general.size_label   = 512x56B         GGUF v3, 1223 tensors, kv=73/73/67
```

**All 19 distinct quant types across all three files resolve against our `ggml.h`, and every
one has CPU type traits plus CUDA kernels in our build.** Nothing exotic, nothing Strata-only.
Shard 2 is one IQ4_NL tensor (the n-gram table) in every tier.

Routed-expert tensors (144 = 48 blocks x gate/up/down) — **this is the decisive table**:

| tier | expert-path types | i-quants in expert path? |
|---|---|---|
| **Q2_0** | `Q2_0 x144` — **uniform** | **none** |
| IQ2_XS | `IQ2_S x68, Q2_0 x48, IQ2_XXS x22, IQ1_M x6` | yes, incl. 6x **IQ1_M** |
| IQ3_XXS | `Q2_0 x30, IQ3_S x26, IQ2_XS x20, IQ2_S x20, IQ4_NL x18, IQ2_XXS x18, IQ3_XXS x12` | yes, 6 kinds |

Two consequences:

1. **`ffn_down_exps` is `Q2_0` in all three tiers** (48/48 in Q2_0 and IQ2_XS; 30/48 in
   IQ3_XXS, rest IQ4_NL) — it is pinned because its 640 rows are not divisible by 256. So
   `GGML_TYPE_Q2_0` support is **mandatory for every tier**, not just the Q2_0 one. Good thing
   it is present (§5).
2. **Q2_0's expert path is entirely free of lookup-table i-quants.** We run *all* experts on
   CPU (`--cpu-moe`) with **AVX2 only**, and i-quant CPU kernels are materially slower than
   plain Q-quant ones. So the tier that is best for our specific configuration is the uniform
   one — matching Strata's own note that Q2_0 *"avoids lookup-table formats"* and is *"fastest"*.

### Q2_0 dominates IQ2_XS on this box — on all three axes

| | Q2_0 | IQ2_XS |
|---|---|---|
| reasoning task avg | 89.07 | 89.16 (+0.1 = noise) |
| total size | **66.42 GB** | 68.03 GB |
| expert path on an AVX2 CPU | **uniform, no LUT** | IQ2_S / IQ2_XXS / IQ1_M |

So picking Q2_0 is **not** trading quality for speed — it is the same quality (0.1 point apart,
well inside benchmark noise), smaller, and better suited to CPU-resident experts. The genuine
quality decision is **Q2_0 (89.07) vs IQ3_XXS (92.57)**: −3.8% on reasoning for 9.4 GB less
and a LUT-free expert path.

### Shard 2 is shared — saves 28.8 GB per extra tier

Exact sizes and LFS hashes:

| tier | shard 1 | shard 2 | total |
|---|---:|---:|---:|
| Q2_0 | 37.62 GB `69820c02ec7d0b45` | 28.80 GB `316b46f3a2dbd68c` | **66.42 GB** |
| IQ2_XS | 39.23 GB `92cee27ae5bbadcd` | 28.80 GB `316b46f3a2dbd68c` | 68.03 GB |
| IQ3_XXS | 47.04 GB `219ea929900dfa9e` | 28.80 GB `316b46f3a2dbd68c` | 75.84 GB |

**Shard 2 is byte-identical across all three tiers** (same sha256) — it is the n-gram table,
pinned at IQ4_NL regardless of budget. So a *second* tier costs only its shard 1:
Q2_0 + IQ3_XXS = 37.62 + 47.04 + 28.80 = **113.46 GB**, not 142.26 GB.

To exploit that, symlink the one physical shard 2 under each tier's expected filename. Safe in
principle — identical sha256 means shard 2 carries no tier-specific identifier for the split
loader to reject — but **confirm on first load** rather than assuming.

## 6. Practical gates on this machine

| gate | status |
|---|---|
| **Disk** | `/home` has 57 G free of 1.9 T (97% full). IQ3_XXS needs 75.8 GB, Q2_0 66.4 GB. **Solvable — user will add a disk or clear files manually.** Not a blocker, but must be done before any download. |
| **No Linux binary** | The only v0.1.2 asset is `strata-windows-x64.zip` (80 MB). `setup.sh` exists but apt-gets Ubuntu packages; on **Manjaro we compile manually**, and they pin **CUDA 13.0** against our **13.3**. |
| **No AVX-512** | `/proc/cpuinfo` shows `avx2 avx_vnni` only — the 13700H is Raptor Lake, AVX-512 fused off. Strata's fast CPU expert kernel **requires AVX512-VNNI + VBMI + VL and explicitly refuses** without them (`cpu/expert.hpp:80-89`); we take the AVX2 fallback. Their reference CPU is a **Zen 4 (Ryzen 5 7600), which has AVX-512.** This hits exactly the CPU-side expert compute their design leans on. Their docs downplay it as *"a bit faster"*, but it is unmeasured on Intel. |
| **VRAM** | 8188 MiB vs 12 GB intended ⇒ ~29% of the expert cache (§4). 262k impossible, ~64k realistic. |
| **RAM** | **Our advantage:** 125 GB vs their 64 GB baseline. Normal operation loads 35–43 GB; we never touch their documented slow path (disk thrashing when RAM is short). |
| **GPU generation** | sm_89 prebuilds exist, but *"RTX 30/40 untested"* — only Blackwell has been run. |

## 7. Recommended order — cheapest decisive test first

1. ~~**Free.** Is `Q2_0` real, and are the files loadable?~~ **DONE 2026-09-26 — yes to both.
   All 19 types in all 3 tiers verified against our build from the real GGUF headers (§5, §5b).
   No blocker remains on the quant side.**
2. **~45–48 GB, uses the stack that already works.** Unsloth publishes `UD-IQ3_XXS` and
   `UD-Q2_K_XL` for this model. Downloading one and re-running
   [llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md) answers *"how much of the
   gap is just smaller experts?"* with one variable changed, no new engine, nothing deleted.
   This also gives the Unsloth-side baseline that the GSQ-vs-Unsloth comparison is missing at
   this model size.
3. **66.42 GB — now the most attractive step, run it before or instead of step 2.**
   **ISTA-DASLab `Q2_0` in our existing Unsloth Studio.** §5b shows it is the right tier for
   this box: uniform LUT-free expert path for our AVX2 CPU, smallest of the three, and
   statistically tied with IQ2_XS on quality. Add IQ3_XXS later for **+47.04 GB only** (shared
   shard 2) if the −3.8% reasoning gap turns out to matter.
4. **Build Strata.** Only worth the CUDA-13.0-on-13.3 build and the untested-Ada risk if
   steps 2–3 show the remaining gap really is the expert cache and the fused kernels.

Order matters because steps 2 and 3 are reversible and reuse a working setup, while step 4 is
a manual out-of-tree CUDA build of an engine whose own author has not run our GPU generation.

## 8. Open questions

1. ~~Does the GSQ-RCO GGUF load in llama.cpp?~~ **Answered 2026-09-26: `Q2_0` is
   `GGML_TYPE_Q2_0 = 42` with CPU traits + CUDA kernels in our build (§5). The quant is
   testable without Strata.** Still to confirm on the actual file header.
2. **What is `workspace_bytes`?** Unknown, so every slot count in §4 is an upper bound.
3. **How does decode t/s degrade with slot count?** Their data varies slots only as a
   *side effect* of context, so cache size and context length are confounded in every published
   row. Our 8 GB point is a large extrapolation off that confound.
4. **What does losing AVX-512 cost on the CPU expert kernel?** Unmeasured by them; hits the
   half of the design we would lean on hardest.
5. **Quality at non-xhigh reasoning effort.** The published numbers explicitly do not cover it.
6. **Is `expert-profile.bin` model-specific and does it fit our quant?** They ship a
   precomputed expert-frequency profile; unclear whether it is keyed to their pack.
