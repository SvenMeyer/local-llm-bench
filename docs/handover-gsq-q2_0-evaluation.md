# HANDOVER — download and evaluate ISTA-DASLab GSQ-RCO **Q2_0**

Self-contained. Written 2026-09-26. A fresh session should be able to work from this file
plus [README.md](lab-notebook.md) alone.

Background analysis: [strata-engine-evaluation.md](strata-engine-evaluation.md) (why Q2_0 and
not the other two tiers). Open work: [llama-todo.md](llama-todo.md) §4b.

---

## 1. Mission

Download `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` **Q2_0** (66.42 GB) and benchmark it
against our existing UD-IQ4_XS numbers **at equal context, with MTP on both sides**, in the
Unsloth Studio stack that already works.

**The question:** is a 2.40 bpw GSQ quant faster than our 4.25 bpw Unsloth quant on this box
without losing usable quality? Nobody has published this comparison at this model size — the
GSQ-vs-Unsloth head-to-head exists only for Qwen3-**8B** at Q2_K (avg 50.03 → 56.28).

**Do not install or build the Strata engine in this session.** It is a separate, later decision
(see the evaluation doc §6–§7). This session tests **only the quant**, using our current engine.

## 2. Machine

`i7-13700H` (6P+8E, **AVX2 + AVX-VNNI, no AVX-512**) · `RTX 4070 Laptop 8 GB` (sm_89, 8188 MiB,
display on the iGPU so ~8.0 GB usable) · **125 GB RAM, no swap** · Manjaro KDE · CUDA 13.3.

Disk: `/home` had **84 G free / 89,168,650,240 bytes** at handover (user deleted an older model
to make room). Q2_0 needs 66.42 GB ⇒ **~22 GB spare.** Re-check `df -h /home` before starting;
do not start the download with less than ~70 GB free.

## 3. Baseline to beat — MEASURED 2026-09-18

Engine: Unsloth mix **PR #220** pin, local native sm_89 build **`11166 (10921f3f1)`**, source
`~/.unsloth/llama.cpp-mix-pr220/`. Model `unsloth/Qwen3.8-Flash-Next-GGUF` **UD-IQ4_XS**
(93.7 GB, 3 shards). Config: **16384 allocated**, `--cpu-moe`, **q8_0 KV**, 10 threads,
**MTP `--spec-draft-n-max 3`**, vision off.

| occupied ctx | PP t/s | **TG t/s** | draft accept |
|---:|---:|---:|---:|
| 574 | 88.9 | **8.94** | 73% |
| 2029 | 110.5 | **10.58** | 69% |
| 3910 | 105.9 | **9.43** | 62% |
| 8389 | 114.9 | **9.25** | 67% |

Longer contexts, measured on the **earlier patched `b11007-mix`** engine — *different engine, do
not put these in the same table as the four rows above*: 32702 → **8.00 t/s** (49% accept),
64099 → **7.86 t/s** (64%). Real-world Solidity+TS at 64k/15.5k fill: 10.52 / 11.35 t/s.

VRAM for reference: 6546 MiB at 8192+MTP; 6696 → 7454 MiB at 16384 occupied.

**Quality reference point:** ISTA-DASLab publishes Q2_0 at reasoning-task avg **89.07** vs BF16
**93.12** (−4.4%). Our UD-IQ4_XS has **never been benchmarked for quality by anyone**, so the
quality comparison will be qualitative unless `llama-perplexity` is run (local build only — the
Unsloth engine does not ship it).

## 4. Step 1 — download

`hf` CLI is present (huggingface_hub 1.5.0). **`huggingface-cli` is broken on this box — use
`hf`.** `aria2c` is not installed.

Target layout keeps LM Studio's `<publisher>/<model>/` convention, because Unsloth Studio
discovers models by scanning `~/.cache/lm-studio/models` (`scan_folders`):

```bash
DEST=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF
mkdir -p "$DEST"
hf download ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF \
    --include 'Q2_0/*' \
    --local-dir "$DEST"
# files land in $DEST/Q2_0/ ; flatten so llama.cpp split resolution and the
# LM Studio scanner both see them at the model-dir level:
mv "$DEST"/Q2_0/*.gguf "$DEST"/ && rmdir "$DEST"/Q2_0
```

Expected result — **verify before launching**:

| file | GB | sha256 (first 16) |
|---|---:|---|
| `Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf` | 37.62 | `69820c02ec7d0b45` |
| `Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00002-of-00002.gguf` | 28.80 | `316b46f3a2dbd68c` |

Run it in the **background** and poll the directory size, not the tool's progress bar — this is
a multi-hour download. `hf download` resumes; re-running the same command after an interruption
continues where it stopped.

**Already verified remotely, do not re-check:** GGUF v3, `general.architecture = qwen4exp`,
1223 tensors, `expert_count = 512 × 48 blocks`, and **all 19 quant types present resolve
against our `ggml.h` with CPU traits + CUDA kernels**. Routed experts are a uniform `Q2_0 ×144`
with no lookup-table i-quants — that uniformity is the whole reason this tier was chosen for an
AVX2-only CPU running every expert on CPU. `./gguf_head.py <url> <label>` re-reads any remote
GGUF header for ~24 MB if needed.

**Later, if adding IQ3_XXS (+47.04 GB only):** shard 2 is **byte-identical across all three
tiers** (`316b46f3a2dbd68c`), so symlink the one physical copy under the second tier's expected
filename instead of downloading it twice. Confirm the split loader accepts the symlink on first
load.

## 5. Step 2 — launch

Adapt the existing launcher; do **not** write a new one from scratch:

```bash
cd /home/sum/Downloads/AI-Runtime
LLAMA_ARG_MODEL=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf \
  ./llama-serve-qwen38-flash-next-unsloth.sh
```

`llama-serve-qwen38-flash-next-unsloth.sh:23` reads `LLAMA_ARG_MODEL`, so the path is
overridable. **But line 30 hardcodes `--gguf-variant UD-IQ4_XS`** — check `unsloth run --help`
for the accepted values and set it to `Q2_0`, or drop the flag if it is only a label. This is
the one edit the script needs.

Flags that must stay (they are in the script already, lines 39–53):

```
--cpu-moe                 all experts in CPU RAM — the validated config on 8 GB
-ctk q8_0 -ctv q8_0       KV quant; a context lever, not a speed lever
--threads 10
--no-mmproj               vision off
--load-mode none          ordinary tensors malloc'd, not mmap'd
--lazy-mode off           PLE/n-gram table fully resident, NOT streamed from SSD
```

**Footgun, already paid for once:** `--load-mode none` **alone is not enough** — `--lazy-mode`
defaults to `auto`, which still streams tensors > 4 GiB. Both are required. And **never pass
`--no-mmap` or `--mlock`**: 28.8 GB of this model is the lazily-read n-gram table and either
flag turns it into a real allocation. With both flags correct, expect RSS **~87.5 GB** of 125 GB
— do not compile CUDA or open a heavy browser during the load; there is **no swap**.

**MTP is off in the script by default.** The baseline in §3 used it, so turn it on or the
comparison is invalid:

```
--speculative-type mtp --spec-draft-n-max 3 --spec-draft-cpu-moe
```

The draft sidecar is `mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf` (1.91 GB) in the **existing
unsloth model dir** — `/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/`.

> **OPEN RISK, resolve early:** that sidecar was built against the Unsloth UD-IQ4_XS
> checkpoint. It is the same architecture and the draft head *borrows* `token_embd` from the
> main model, so it should attach — **but this is unverified against a GSQ-quantized main
> model.** Check it on the first load, before running any benchmark. Do **not** trust the
> Studio UI/API field `speculative_type: mtp`; it reports `mtp` even when MTP silently failed.
> Believe only the **llama-server argv** (`--model-draft` + `--spec-type draft-mtp`) and the
> `draft acceptance` line in the llama log. If MTP will not attach, benchmark **both models
> with MTP off** and say so explicitly in the results table.

Do not push `token_embd.weight=CPU` while the shared draft head is attached.

Studio listens on **127.0.0.1:8888** (`Authorization: Bearer sk-unsloth-…`). llama-server is on
a **random high port** — find it with `pgrep -af llama-server`; `/props` and `/completion` there
need no key.

Sampling for this model: **temp 1.0, top-p 0.95, top-k 20, min-p 0.0** (differs from the other
Qwen models here). Keep reasoning effort at the default **xhigh** — the GSQ quants are
explicitly *"primarily optimized for xhigh"* and the published quality numbers do not hold below
it.

## 6. Step 3 — benchmark

Procedure lives in [llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md). Short form:

```bash
UNSLOTH_API_KEY=sk-unsloth-… ./llama-bench-qwen38-unsloth-occupied.sh
```

- **Allocate 16384 and cap the first probes at 0.5k / 2k / 4k / 8k** — the same four points as
  §3, so the rows are directly comparable. Extend only after those land.
- **Do NOT run `llama-bench-ctx-sweep.sh`.** It spawns a fresh llama-server per context and
  would reload 66 GB four times. It is written for the 35B.
- **Reload once** to 16384; do not restart per data point.
- Record the **power profile** (balanced / performance) with every number — house convention.
- Attach the watcher rather than polling in a loop.

## 7. Step 4 — record

1. Append raw output to `llama.cpp-test.sh` (append-only log, house style).
2. Add rows to [llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md) §5,
   in a **new group** labelled with the engine build **and** the quant. Never mix engines or
   quants inside one table — that mistake is already flagged twice in these docs.
3. Update the README status footer and tick the boxes in `llama-todo.md` §4b.
4. If it wins, update `llama-qwen38-flash-next-unsloth.md` §1 to say which GGUF is canonical.

## 8. Traps specific to this box

- **Never `pkill -f llama`** here. The pattern matches the agent wrapper's own command line and
  kills the session (exit 144, happened once). Track server PIDs explicitly and kill by PID.
- **Stale result files lie.** A `curl` printed "Failed to connect" while the parser happily
  reported `30.14` from a pre-existing JSON. Delete the output file first and use
  `--fail-with-body`.
- **`--fit on` sizes for f16 KV** and silently auto-reduces context (it cut 262144 → 8192 on the
  35B). Always read back the real `n_ctx` from `/props`.
- **Allocated ≠ occupied context.** Reserving 180k cost 12% TG; *filling* 65k cost 23%. Quote
  occupied numbers.
- Tool results here are compressed by the **headroom** proxy. When exact strings matter (editing
  a file, quoting a number), call `headroom_retrieve` with the printed hash — retrieval can
  nest, so a retrieved payload may itself carry another hash.

## 9. Decision criteria

| outcome at equal context + equal MTP | read |
|---|---|
| **TG ≥ ~13 t/s** (+40% over 9.25 @ 8k) | Q2_0 wins outright. Make it canonical; the LUT-free expert path on an AVX2 CPU is the likely cause. Then weigh IQ3_XXS (+47 GB) for the −3.8% reasoning gap. |
| **TG ~10–12 t/s** | Real but modest. Keep it for long-context work (18 GB smaller ⇒ more page cache), but the bulk of Strata's 7–9x claim is **not** the quant, it is the expert cache + fused kernels. That strengthens the case for eventually building Strata. |
| **TG ≈ 9–10 t/s, unchanged** | Decode is not bound by expert bytes on this box. Conclude the gap is engine-side, and stop spending disk on quant variants. |
| **Output quality visibly degrades** | Abort the tier; try IQ3_XXS (+47.04 GB, shared shard 2) before concluding anything about GSQ as a method. |

Use the house test prompt (the Solidity whitelist / `bytes32` one from `llama.cpp-test.sh`) for
cross-model comparability, plus the real-world Solidity+TS 64k case that has 10.52 / 11.35 t/s
on record.

## 10. What is already settled — do not re-derive

- Unsloth's bundled engine beat our `-march=native` build by **9%**; keep our local build only
  for `llama-bench` / `llama-perplexity`, which Unsloth does not ship.
- q8_0 KV is a **context** lever, not a speed lever.
- `--cpu-moe` is the validated placement on 8 GB.
- `GGML_TYPE_Q2_0 = 42` is real and fully supported here; all three GSQ tiers are loadable.
- Q2_0 is the right tier for this box (uniform LUT-free experts, smallest, statistically tied
  with IQ2_XS at 89.07 vs 89.16).
- Strata itself needs a manual CUDA build (Windows-only binaries, their 13.0 vs our 13.3), would
  get **~29% of the intended expert cache** on 8 GB, and its author has never run an RTX 40.
