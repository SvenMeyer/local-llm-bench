# Running Qwen3.8-Flash-Next on 8 GB VRAM + 125 GB RAM

Everything known about running `unsloth/Qwen3.8-Flash-Next-GGUF` on this
machine. Architecture and flag math were written 2026-09-17 from the GGUF
**before** first load; **measured** Unsloth numbers from 2026-09-18 are in
[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md)
(start there to actually run it). To **bench** it, follow
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md) in a fresh session.

Companion docs: [llama-compile-guide.md](llama-compile-guide.md),
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md),
[llama-todo.md](llama-todo.md). Raw log: `llama.cpp-test.sh`.

---

## 1. Status as of 2026-09-18

| | |
|---|---|
| mainline build | `11011 (aa39d7a3e)` at `llama.cpp/` — runs the model, **no MTP** (`-md` ignored) |
| MTP worktree | `10802 (d1a92352c)` at `llama.cpp-mtp/` — PR #28243, **not yet smoke-tested** on this GGUF |
| Unsloth engine | `b11027-mix-pr220` `11166 (10921f3f1)` — official `#144@ca1426903` MTP pin (PR #220). This is what is serving |
| model | UD-IQ4_XS **complete** (90 GiB + 1.91 GB MTP sidecar + 0.90 GB mmproj, unused) |
| measured TG | mix-pr220 occupied 16384: **8.94 / 10.58 / 9.43 / 9.25 t/s** at 0.5k–8k. Morning patched-mix 8192: 8.06 no-MTP / 12.93 MTP digits / 6.51 MTP prose |

Files live in `/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/`:

```
Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf     0.01 GB  metadata only, 0 tensors
Qwen3.8-Flash-Next-UD-IQ4_XS-00002-of-00003.gguf    49.84 GB
Qwen3.8-Flash-Next-UD-IQ4_XS-00003-of-00003.gguf    43.84 GB
mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf            1.91 GB
mmproj-F16.gguf                                      0.90 GB
```

Pass **shard 00001** as `-m`; llama.cpp resolves the split itself. While
downloading, LM Studio names in-flight shards `downloading_*.gguf.part`, so a
load attempt fails with `failed to load GGUF split from …-00002-of-00003.gguf`.
That is the expected pre-completion error, not a bug.

## 2. What this model actually is

Architecture id is **`qwen4exp`** — `general.description` is literally
"A Preview of the Qwen4 Architecture". It is **not** a Qwen3-Next variant and
shares almost nothing operationally with the Qwen3.5/3.6 MoEs already on this
box. Read from the GGUF, since the model card omits most of it:

```
block_count               48          context_length      262144
embedding_length          2560        size_label          512x56B
expert_count              512         expert_used_count   10
expert_ff_length          640         shared expert ff    640
attention.head_count      24          head_count_kv       2
attention.key_length      256         value_length        256
full_attention_interval   4
ssm.conv_kernel           4           ssm.state_size      128
ssm.group_count           16          ssm.inner_size      6144
indexer.head_count        4           indexer.key_length  128
indexer.top_k             2048
hyper_connection.count    4           hyper_connection.low_rank  320
ple.ngram_size            3           ple.heads_per_ngram 8   (-> 16 heads)
embedding_length_per_layer_input      160
rope.freq_base            1e7         rope.dimension_count 64
tokenizer: gpt2 / pre=qwen35, bos=pad=248044, eos=248046, add_bos=false
```

Layer layout: **12 × (3 × Gated-DeltaNet → MoE, then 1 × Qwen-Sparse-Attention → MoE)**.
`full_attention_interval=4` means every 4th layer is a real attention layer;
the other 36 are recurrent (linear attention). Officially 125 B total / 6 B
active, plus 51 B of n-gram embeddings and 4 B of MTP → the "177 B params"
figure on the model card.

### Where the 93.7 GB goes

| component | size | quant |
|---|---:|---|
| `*_exps` — 512 experts × 48 layers | **~57 GB** | IQ3_S gate/up, IQ4_NL down |
| `per_layer_token_embd` — the n-gram LUT | **~28.8 GB** | IQ4_NL `[160, 320001536]` |
| `output.weight` | 521 MB | Q6_K `[2560, 248320]` |
| `token_embd.weight` | 676 MB | Q8_0 `[2560, 248320]` |
| everything else (attn / ssm / hc / shexp / norms) | ~3.4 GB | ~71 MB per layer |

Per-layer non-expert tensors, for budgeting: `attn_qkv` 28 MB + `attn_gate`
17 MB + `hc_*` 14 MB + shared-expert 5 MB + `ffn_gate_inp` 5 MB + ssm ~2 MB.

## 3. The single most important fact

**`per_layer_token_embd` is 28.8 GB but is never fully loaded.** llama.cpp
creates it with `TENSOR_READ_LAZY`, documented in `src/llama-model-loader.h` as:

> read rows on demand instead of loading whole tensor; requires mmap

It is paged in from SSD per lookup, so only hot rows become resident. Real
resident RAM is therefore roughly **57 GB of experts + ~5 GB ≈ 62 GB**, not
93.7 GB. That is what makes a 93.7 GB model comfortable in 125 GB.

Two hard consequences:

- **Never pass `--no-mmap`.** It turns the lazy LUT into a genuine 28.8 GB read.
- **Never pass `--mlock`.** Same, but it also pins it.

Unsloth's docs say the same thing in passing: *"you can also offload the PLE /
Ngram layer to SSD and use mmap."*

Corollary: **first-token latency on a cold page cache will be poor**, and the
model will feel faster after it warms up. Judge throughput on a second run.

## 4. Why 8 GB VRAM is viable at all

Only **12 of 48 layers** hold a KV cache. Per token:

- attention KV: 12 layers × 2 kv-heads × 256 × (K+V) @ q8_0 ≈ **13 KB**
- sparse-attention indexer cache: 12 × 4 heads × 128, **K only** — upstream
  dropped the V allocation in #28330 ≈ **12 KB**

≈ **25 KB/token**, i.e. ~1.6 GB at 64 k, ~3.2 GB at 128 k. A dense 48-layer
model of this width would be ~4× worse. The Gated-DeltaNet layers instead carry
a fixed-size recurrent state (context-independent).

### VRAM budget (7661 MiB free)

Calculated:

```
non-expert weights on GPU            ~3.4 GB
output.weight                         0.52 GB
token_embd -> pushed to CPU          -0.68 GB
                                     ---------
                                     ~3.2 GB weights
leaves ~3.0-3.2 GB for KV + compute buffers
=> 65536 comfortable, 131072 plausible, 262144 native will NOT fit
```

**Measured 2026-09-18** on Unsloth patched mix, `--cpu-moe`, q8_0 KV, 8192 ctx:
**~5950 MiB** no-MTP, **~6546 MiB** MTP (`n_max=3`, shared Q4_K_M draft).
Weights-only ~3.2 GB was optimistic — CUDA context + compute + KV ate the rest.
131072 allocation is still untried on this GGUF.

`-ot token_embd.weight=CPU` is safe here **because `output.weight` exists as a
separate tensor** and is not tied to the embedding. If a future quant ties
them, drop that override or generation will crawl.

## 5. Launchers

```
llama-serve-qwen38-flash-next.sh          # mainline, no MTP, default -c 65536
llama-serve-qwen38-flash-next-mtp.sh      # MTP worktree build, default -c 32768
llama-serve-qwen38-flash-next-unsloth.sh  # Unsloth Studio (what is serving)
```

Same env-var-override style as the existing `llama-serve*.sh` scripts:

```bash
LLAMA_ARG_CTX_SIZE=131072 ./llama-serve-qwen38-flash-next.sh
```

The **Unsloth** launcher is the measured path (full GGUF, full RAM, patched MTP).
The two mainline scripts were dry-run validated against the incomplete download
and have **not** yet been smoke-tested on the finished 90 GiB.

### Core flags and why

| flag | value | why |
|---|---|---|
| `-m` | shard `00001` | llama.cpp resolves the rest of the split |
| `--cpu-moe` | on | all 512 routed experts → CPU RAM; they are 57 GB |
| `-ngl` | 999 | everything else on GPU |
| `-ot` | `token_embd.weight=CPU` | 676 MB of VRAM for a GET_ROWS lookup — bad trade |
| `-fa` | on | flash attention |
| `-ctk`/`-ctv` | `q8_0` | halves KV vs f16; built with all 49 FA combos so any mix is available |
| `-c` | 65536 | see §4; push upward once measured |
| `-t` | 10 | 6 P-cores + hyperthreads; matches what the other scripts use |

`--fit` is **on by default** (target margin 1024 MiB/device, min ctx 4096) and
will auto-size anything left unset. Let it do the work before hand-tuning.

## 6. Sampling — different from the other Qwen models here

The Qwen3.5/3.6 scripts on this box use temp 0.6 / min-p 0.05. **This model
wants different values.** From the model card:

| mode | temp | top-p | top-k | min-p | presence | repetition |
|---|---|---|---|---|---|---|
| thinking (default) | **1.0** | 0.95 | 20 | **0.0** | 0.0 | 1.0 |
| instruct / non-thinking | 0.7 | 0.80 | 20 | 0.0 | 1.5 | 1.0 |

Thinking is on by default and wrapped in `<think>` tags. Reasoning depth is a
**chat-template kwarg, not a CLI flag**:

```bash
--chat-template-kwargs '{"reasoning_effort":"medium"}'   # xhigh|medium|low|none
```

`xhigh` is the default. Other template kwargs: `enable_thinking`,
`preserve_thinking`. Suggested output budgets within a 1 M context are 262144
tokens for reasoning and 131072 for the final response.

`--jinja` is required for the chat template to be used at all.

## 7. MTP (multi-token prediction) speculative decoding

Claimed **1.3–1.7×** with no quality loss — verification is exact, only speed
changes.

### Three binaries, three behaviours

| binary | Qwen3.8 MTP |
|---|---|
| mainline `llama.cpp/` b11011 | **`-md` silently ignored** |
| published Unsloth `*-mix-3e83366` | **aborts** in `build_hc_mix` (`ggml_can_repeat`), then HTTP 200 without MTP |
| mix-pr220 (`#144@ca1426903`, this box) | **works** — official pin from unslothai/llama.cpp#220 |
| `llama.cpp-mtp/` PR #28243 | expected to work (older graph); **not measured here** |

Issue: [unslothai/unsloth#11143](https://github.com/unslothai/unsloth/issues/11143).
How to run the patched Unsloth server:
[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md).

> If you ever benchmark MTP and measure exactly 1.00×, check which binary you
> ran *and* whether `--model-draft` is actually on the llama-server argv.

### Which head file

We have `shared-Q4_K_M` (1.91 GB). Unsloth recommends `shared-Q8_0` (2.79 GB)
as fastest, but on 8 GB VRAM the extra ~0.9 GB is worth more as KV — they cost
the difference at only "~2 points less acceptance". Available variants:
`shared-Q4_K_M` 1.91 / `shared-Q8_0` 2.79 / `shared-BF16` 5.23 GB, plus
self-contained `Q4_K_M` 2.79 / `Q8_0` 4.14 / `BF16` 7.77 GB.

`shared-` means it **borrows `token_embd` and `output.weight` from the target
model** (`qwen4exp.nextn_shared_target_tensors = True`) instead of carrying its
own — saving ~1.3 GB. BF16 is both bigger *and* slower than Q8_0 because the
draft step is dominated by the output projection.

### Structure of the head, and why it is cheap

One extra block, **`blk.48`** (`block_count` 49, `nextn_predict_layers` 1). It
has its **own full 512-expert MoE** — `blk.48.ffn_gate_exps` Q4_K
`[2560, 640, 512]`, `ffn_up_exps` Q4_K, `ffn_down_exps` Q8_0 — which is ~1.8 GB
of its 1.9 GB.

So with expert offload it costs only **~100 MB of VRAM**, and drafting is one
layer's worth of expert compute against the target's 48. Cheap even CPU-side.

### **`--cpu-moe` does NOT reach the draft model**

`common_params_speculative` carries its **own** `tensor_buft_overrides` vector,
separate from `common_params`. Without a second flag, that 1.8 GB of draft
experts goes straight onto the 8 GB card.

```bash
--spec-draft-cpu-moe   # -cmoed, env LLAMA_ARG_SPEC_DRAFT_CPU_MOE
```

Draft-side equivalents of the main offload flags:

| main | draft |
|---|---|
| `-ot` / `--override-tensor` | `-otd` / `--spec-draft-override-tensor` |
| `-cmoe` / `--cpu-moe` | `-cmoed` / `--spec-draft-cpu-moe` |
| `-ncmoe` / `--n-cpu-moe` | `-ncmoed` / `--spec-draft-n-cpu-moe` |

### Open question for the MTP script **[UNVERIFIED]**

The MTP launcher currently leaves `token_embd` **on the GPU**, because the
shared head borrows that exact tensor and pushing it to CPU would drag the
draft's embedding lookup onto the CPU every draft step. That costs 0.68 GB of
KV budget, which is why its default context is 32768 rather than 65536.

**This may be unnecessary.** Test both. If borrowing tolerates a CPU-resident
`token_embd`, re-add `LLAMA_ARG_OVERRIDE_TENSOR=token_embd.weight=CPU` and
raise the context.

### Tuning

`--spec-draft-n-max` — Unsloth's docs use 5, their MTP README uses 2. Script
defaults to 3. It has **no env var**; pass it on the command line. Tune off the
`draft_n` / `draft_n_accepted` fields the server returns per response.

For reference, the 2026-07-15 MTP work on Qwen3.6-35B-A3B measured 78–82 %
acceptance and +17–26 % real speedup on this same GPU.

## 8. Vision / mmproj **[UNVERIFIED]**

The model is tagged image-text-to-text, `ple.image_token_id = 248056`, and
`mmproj-F16.gguf` (0.90 GB) is downloaded. Both launchers currently pass
`--no-mmproj` because that 0.9 GB does not obviously fit alongside everything
else on 8 GB.

To try it: drop `--no-mmproj`, add `--mmproj <path>`, and expect to cut context
substantially. `llama-mtmd-cli` is built. Unsloth mention setting `longest_edge`
to 469762048 for long video, via vLLM/SGLang overrides — no llama.cpp equivalent
documented.

## 9. Env var names are not guessable

Several cost real debugging time. Verified against `common/arg.cpp`:

| flag | env var |
|---|---|
| `-ot` | `LLAMA_ARG_OVERRIDE_TENSOR` (**not** `..._TENSOR_OVERRIDES`) |
| `-md` | `LLAMA_ARG_SPEC_DRAFT_MODEL` (**not** `LLAMA_ARG_MODEL_DRAFT`) |
| `-cmoed` | `LLAMA_ARG_SPEC_DRAFT_CPU_MOE` |
| `-cmoe` | `LLAMA_ARG_CPU_MOE` |
| `--spec-type` | `LLAMA_ARG_SPEC_TYPE` |
| `--spec-draft-n-max` | *(none — command line only)* |

Check with:
`grep -n -A8 '"--flag-name"' common/arg.cpp | grep set_env`

Also: **`-no-cnv` was removed** from `llama-cli`; single-turn is now `-st`.

## 10. Measuring

> Method, the knobs worth sweeping, and the running results log now live in
> **[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)**.
> Kept here: the commands and the expectations.

```bash
# memory breakdown is printed at load; this is the number to trust
llama-server … 2>&1 | grep -A4 memory_breakdown

# throughput
./build/bin/llama-bench -m <shard 00001> -ngl 999 --cpu-moe -fa 1 \
  -ctk q8_0 -ctv q8_0 -t 10
```

Watch for `CUDA compute buffer size … does not match expectation` in the log —
seen before on this box, and it means the reserved compute buffer was too
small, eating headroom you thought you had.

Benchmark hygiene on this machine: the GPU is capped at 35 W and the CPU is
hybrid, so results shift with the power profile (balanced vs performance) and
with anything else compiling. `llama.cpp-test.sh` records the profile alongside
each number — keep doing that.

### Expectations — measured at 8192

Generation **is** CPU-memory-bandwidth bound. Arithmetic said 8–15 t/s; Unsloth
patched mix at 8192, `--cpu-moe`, q8_0 KV, 10 threads, `balanced`:

| | PP t/s | TG t/s |
|---|---:|---:|
| mmap cold | 4.0 | 4.0 |
| mmap warm | 10.7 | 8.62 |
| full RAM, no MTP | 11.8 | **8.06** |
| full RAM, MTP n_max=3, digits (98% accept) | 12.1 | **12.93** |
| full RAM, MTP n_max=3, prose (31% accept) | 21.8 | **6.51** |

Full RAM did not speed decode vs warm mmap. MTP is a win only on low-entropy
text at `n_max=3`. Occupied-context (16384 alloc, MTP n_max=3, 2026-09-18): TG **11.84 / 9.60 /
10.76 / 13.04 t/s** at 574 / 2029 / 3910 / 8389 tokens; PP **90–117 t/s**.
The ~12 t/s PP figure is short-chat only. 8k occupied did not drop TG.

## 11. Other models on this machine

Older launchers still use `/usr/local/bin/llama-server`. Ternary-Bonsai-2
needs the Prism binary in `llama.cpp-prism/build/bin`.

| script | model | notes |
|---|---|---|
| `llama-serve.sh` | Ornith 1.0 35B Q6_K | full 262144 ctx in ~6 GB |
| `llama-serve-mtp.sh` | Qwen3.6-35B-A3B-MTP | `--spec-type draft-mtp`, 131072 (262144 OOMs) |
| `llama-serve-ornith-mtp.sh` | Ornith 35B + community MTP graft | 131072 |
| `llama-serve-bonsai.sh` | Bonsai 27B Q1_0 | dense, 32768, ~26 t/s (mainline) |
| `llama-serve-ternary-bonsai2.sh` | Ternary-Bonsai-2-27B | Prism fork. PTQ1_0: 32k q8_0 ~20 t/s empty / 13.5 t/s full. PQ2_0: faster PP (~420), 16k q8_0 |

`--cpu-moe` is a no-op on dense models. Only GGUFs with a baked MTP head
support `draft-mtp` — it is a property of the specific export, not of the arch.

## 12. Things that do not work / were rejected

- **LM Studio cannot use these builds.** It ships self-contained backend
  bundles with proprietary `.node` bindings; no config points it at an external
  backend. Its version numbering is decoupled from upstream llama.cpp.
- **Unsloth Studio** uses its own checkout at `~/.unsloth/llama.cpp`. Override
  with `UNSLOTH_LLAMA_CPP_PATH=/home/sum/Downloads/AI-Runtime/llama.cpp`.
- **DSpark** was evaluated and rejected 2026-07-15 — needs a separate fork,
  and the best independent non-datacenter benchmark was *slower* than vanilla.
  Full writeup in `llama.cpp-test.sh`.
