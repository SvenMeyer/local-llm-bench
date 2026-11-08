# Qwen3.8-Flash-Next on Unsloth Studio (this machine)

How this combination is actually configured and run on the
**i7-13700H + RTX 4070 Laptop 8 GB, 125 GB RAM, no swap** box.
Measured 2026-09-17/18. Companion: [llama-run-guide.md](llama-run-guide.md)
(architecture and flags), [llama-todo.md](llama-todo.md) (open work),
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)
(results log),
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md)
(**how to run the scaled Group A/B/C bench** — start there in a fresh session).

This is **not** LM Studio. Unsloth Studio (`unsloth-desktop-bin` AUR,
`unsloth run`) talks to its own llama.cpp at `~/.unsloth/llama.cpp`.

---

## 1. What is loaded

Default since 2026-09-27: **GSQ-RCO Q2_0** (evaluation in
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md) §5
Groups E/F). `QUANT=iq4xs` on the launcher brings back UD-IQ4_XS.

| | Q2_0 (default) | UD-IQ4_XS (`QUANT=iq4xs`) |
|---|---|---|
| GGUF | `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` **Q2_0** (66.4 GB, 2 shards) | `unsloth/Qwen3.8-Flash-Next-GGUF` **UD-IQ4_XS** (93.7 GB, 3 shards) |
| path | `~/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/` | `~/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/` |
| `-m` | shard `…-00001-of-00002.gguf` | shard `…-00001-of-00003.gguf` (llama.cpp resolves the split) |
| MTP sidecar | symlink to Unsloth's `mtp-…-shared-Q4_K_M.gguf` (Studio only looks in the model's own dir) | `mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf` (1.91 GB) |
| 8k occupied TG + MTP | **21.2 t/s**, PP 180 | 9.8 t/s, PP 117 |
| VRAM / RSS @16384 | 4790 MiB / 61 GiB | 6696 MiB / ~87 GiB |
| wikitext-2 PPL (c512×40) | 3.359 | 2.744 |

| | |
|---|---|
| vision | **off** (`--no-mmproj`; per-model override `disable_vision: true`) |
| engine | Unsloth mix **b11027 + PR #220 pin** (`#144@ca1426903`) **+ x86 Q2_0 AVX-VNNI kernel** (ggml-org#26348 + `llama-q2_0-avxvnni-transposed.patch`), local native `sm_89` build `11170 (a2fa025fb)`. Build: `llama-unsloth-mix-pr220-q2_0-build.sh` |
| source tree | `~/.unsloth/llama.cpp-mix-pr220-q2_0/` (RPATH of live `llama-server`); the plain 11166 tree `~/.unsloth/llama.cpp-mix-pr220/` is its base |
| backups | `~/.unsloth/llama.cpp/build/bin-pre-b11160` = original 11166 binaries |
| live launcher | `unsloth studio --api-only` on `127.0.0.1:8888`, `--disable-tools` |

Use the recommended sampling (temp 1.0, min-p 0). Greedy Q2_0 looped once on
the house prompt.

Unsloth scans the LM Studio cache (`scan_folders` → `~/.cache/lm-studio/models`).
Do not re-download either quant.

---

## 2. Global Unsloth settings that fight this model

Model Memory toggles are **app-wide**, not per-model.

| UI | stored key | effect |
|---|---|---|
| Keep model in GPU memory | `model_memory_keep_resident` | no idle-unload; if RAM-reserve is off, forces `--load-mode mmap+mlock` |
| Don't reserve system RAM | `model_memory_no_ram_reserve` | **vetoes** a full host copy (`none` / `mlock` / `--no-mmap`) |

**Both ON** (the previous default here) = mmap + lazy n-gram paging. Fine for
everyday use. **Both OFF** is required for `--load-mode none`.

`--disable-tools` is **process-level only**. It is not in `studio.db`.
`unsloth run` defaults tools **on**; the Tauri app defaults them **off**.
Pi / coding agents need the flag on every `unsloth run`.

API: `PUT /api/settings/model-memory` and
`PUT /api/settings/openai-auto-switch/overrides` (owner bearer key).

---

## 3. Two RAM modes

### A. mmap / lazy PLE (Unsloth default, SSD paging)

Do **not** pass `--no-mmap`, `--mlock`, or `--lazy-mode off`.
`per_layer_token_embd` (28.8 GB) is `TENSOR_READ_LAZY`. Measured RSS ~52 GB
file-backed, not 93.7 GB anonymous. First generation is slow; judge run 2+.

### B. Full RAM (no streaming)

Needs the two Model Memory toggles **off**, then:

```
--load-mode none    # ordinary tensors malloc'd, not mmap'd
--lazy-mode off     # PLE/n-gram table fully resident (default auto still
                    # streams tensors > 4 GiB even with load-mode none)
```

Measured: RSS **~87.5 GB** (28.5 GB anon PLE + 58.8 GB expert shmem) + ~6 GB
VRAM. System used ~94 GiB / 125 GiB, ~30 GiB still available. **No swap** —
do not also compile CUDA or open a heavy browser during this load.

`--load-mode none` alone is **not** enough. That was the footgun.

Cold full-RAM load is ~1–2 min if the GGUF is already in page cache; a true
disk read of 90 GB is several minutes.

---

## 4. MTP on Unsloth's engine

Official fix: [unslothai/llama.cpp#220](https://github.com/unslothai/llama.cpp/pull/220)
(merged 2026-09-18) repins the Qwen3.8 MTP carry
([#144](https://github.com/unslothai/llama.cpp/pull/144)) from broken `f40f64a`
to `ca1426903`. That commit loads `layer.nextn.hc_head_norm` as `{ n_embd, hc }`
with `TENSOR_ALLOW_RESHAPE`, and lets `common/fit.cpp` price a borrowing
`shared-` draft head. The published prebuilt `b11027-mix-3e83366` still lists
the old pin; this box built the updated pin locally onto ggml-org `b11027`.

Stock `b11007-mix` / `b11027-mix-3e83366` **abort** creating the Qwen3.8 draft
context:

```
GGML_ASSERT(ggml_can_repeat(b, a)) failed
llama_model_qwen4exp::graph::build_hc_mix
llama_model_qwen4exp::graph_mtp
```

Studio then retries without flash-attn, crashes again, and returns HTTP 200
**without** MTP. The UI/API can still say `speculative_type: mtp`. Believe the
llama-server argv (`--model-draft` + `--spec-type draft-mtp`) and the
`draft acceptance` line in the llama log.

Cause: ggml-org #28896 reshaped trunk HC gammas to `{n_embd, hc}`.
`layer.nextn.hc_head_norm` was left `{hc_dim}`. Filed as
[unslothai/unsloth#11143](https://github.com/unslothai/unsloth/issues/11143)
(macOS); confirmed on this Linux CUDA box.

That one-line reshape is now in the official `#144` pin. This box previously
patched it locally (`build-hc-fix/`, `build/bin-pre-hc-fix/`). Live binaries
are the mix-pr220 install (`llama-unsloth-mix-pr220-build.sh` /
`llama-unsloth-mix-pr220-install.sh`). Mainline `llama.cpp/` still has **no**
qwen4exp MTP graph (`-md` silently ignored). `llama.cpp-mtp/` is PR #28243,
still open, **untested on this GGUF**.

MTP flags that matter on 8 GB:

```
--spec-type draft-mtp
--spec-draft-n-max 3          # Unsloth docs say 5; 3 is safer on prose
--spec-draft-cpu-moe          # draft has its own 1.8 GB expert bank
--cpu-moe -ngl 999
# do NOT push token_embd.weight=CPU while the shared head is attached
```

Vision stays off (`--no-mmproj`).

---

## 5. How to start it

Preferred:

```bash
cd /home/sum/Downloads/AI-Runtime
./llama-serve-qwen38-flash-next-unsloth.sh
```

Pi coding session (load this GGUF on :8888 if needed, then start Pi):
[`~/Scripts/aidev/pi-Qwen3.8-Flash-Next.sh`](/home/sum/Scripts/aidev/pi-Qwen3.8-Flash-Next.sh)
— notes in [`pi-Qwen3.8-Flash-Next.md`](/home/sum/Scripts/aidev/pi-Qwen3.8-Flash-Next.md).

That is `unsloth run` with `--disable-tools --api-only`, q8_0 KV, `--cpu-moe`,
`--load-mode none --lazy-mode off`, MTP **off** in the script (pass
`--speculative-type mtp --spec-draft-n-max 3 --spec-draft-cpu-moe` to turn it
on; leave `token_embd` on GPU).

Studio listens on **8888**. llama-server is on a **random** high port
(see `pgrep -af llama-server`). Chat Completions:

```
POST http://127.0.0.1:8888/v1/chat/completions
Authorization: Bearer sk-unsloth-…
```

Native `/completion` and `/props` are on the llama-server port, no key.
Do not start the Tauri `unsloth-studio` window on top of this process.

Sampling (thinking): temp **1.0**, top-p 0.95, top-k 20, min-p **0.0**.

---

## 6. What we measured (short)

Engine (2026-09-18 evening): official mix-pr220 (`11166 / 10921f3f1`), 8192
then 16384 ctx, `--cpu-moe`, q8_0 KV, 10 threads. MTP **loads** (`--spec-type
draft-mtp` on argv). VRAM 6546 MiB at 8192 MTP / 6696→7454 at 16384 occupied
— same footprint as the local `hc_head_norm` patch.

Occupied Group C on this engine (same CHARS as the morning patched-mix run):

| ctx used | PP t/s | TG t/s | draft |
|---:|---:|---:|---|
| 574 | 88.9 | 8.94 | 73% |
| 2029 | 110.5 | 10.58 | 69% |
| 3910 | 105.9 | 9.43 | 62% |
| 8389 | 114.9 | 9.25 | 67% |

PP matches the morning (~89–115 vs ~91–117). TG is flatter (8.9–10.6 vs
9.6–13.0); the 8k peak of 13.04 t/s / 86% accept did not repeat. Short
Group A on this engine (new prompts in `llama-qwen38-group-a-mtp.py`, not
a re-run of the morning digits/prose): digits **11.37 t/s** (81% accept),
prose **9.31 t/s** (68% accept). Log:
`llama-bench-qwen38-pr220-20260918-214747.log`.

Earlier the same day, **patched** `b11007-mix` (do not mix with the table
above):

| | PP t/s | TG t/s | notes |
|---|---:|---:|---|
| mmap, cold | 4.0 | 4.0 | n-gram page-ins |
| mmap, warm | 10.7 | 8.62 | 81 tok |
| full RAM, no MTP | 11.8 | **8.06** | 150 tok |
| full RAM, MTP n_max=3, digits | 12.1 | **12.93** | 98% accept |
| full RAM, MTP n_max=3, prose | 21.8 | **6.51** | 31% accept |

Generation is CPU-memory-bandwidth bound (~8 t/s). MTP is a **win on
low-entropy text** and can **lose on prose** at n_max=3. Do not quote 1.3–1.7×
as the number this laptop feels.

VRAM ~6.0 GB without MTP, ~6.5 GB with MTP, at 8192.
Occupied Group C (16384 alloc, MTP n_max=3, 2026-09-18):

| ctx used | PP t/s | TG t/s | draft |
|---:|---:|---:|---|
| 574 | 90.8 | 11.84 | 73% |
| 2029 | 114.1 | 9.60 | 69% |
| 3910 | 108.4 | 10.76 | 66% |
| 8389 | 117.3 | 13.04 | 86% |
| 15456 | 121.4 | 11.21 | 72% |
| 32702 | 116.7 | 7.62 | 40% |
| 64099 | 105.8 | 7.86 | 64% |
| 15456 @64k alloc | 119.8 | 9.70 | 67% |
| 32702 @64k alloc | 115.6 | 8.00 | 49% |

Occupied `/completion` prefill is ~100–121 t/s (105.8 at 64k); the ~12 t/s
figure is short-chat only. 15.5k is 11.21 t/s @16384 alloc and 9.70 @65536.
**32.7k unclipped is 8.00 t/s** (49% draft); **64.1k is 7.86 t/s**. Real-world
Solidity+TS @ 64k/15.5k fill: **10.52 / 11.35 t/s** (78–88% draft). Short
prompts at 64k+MTP CUDA-OOM. VRAM 6696 → 7454 on 16384; 32768 6998/7078;
65536 7602/7684 (154 MiB free).

---

## 7. Benchmarking this model

The procedure a **fresh session** should follow is
[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md). Short version:

Do **not** run `llama-bench-ctx-sweep.sh` as written: it **spawns a new
llama-server per context** and would reload 90 GB four times.

Occupied `/completion` prefill is ~90–117 t/s (~2× the 35B, not 15–20×).
Short chat prompts can still look like ~12 t/s. Cap first probes around
**0.5k / 2k / 4k / 8k** (done 2026-09-18). 65k/129k still unrun. Reload
**once** to 16384.

```bash
# see llama-qwen38-benchmark-run.md — do not poll, attach the watcher
UNSLOTH_API_KEY=sk-unsloth-… ./llama-bench-qwen38-unsloth-occupied.sh
```
