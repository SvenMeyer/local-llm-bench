# TODO — Qwen3.8-Flash-Next bring-up

Open work, ordered. Context for all of it:
[llama-run-guide.md](llama-run-guide.md),
[llama-compile-guide.md](llama-compile-guide.md), and
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)
— log every measurement into that last one's results table as you go.

Last updated 2026-09-19, after Ternary-Bonsai-2 PTQ1_0/PQ2_0 on Prism
`llama.cpp-prism` `b10706 / 1a07bfa5f`. Flash-Next setup:
[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md).
**Next Flash-Next bench:** [llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md)
(paste that file into a fresh session; do not re-derive from this TODO).
Bonsai 2 numbers: [llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md) §5.

---

## ~~Ternary-Bonsai-2-27B Prism fork~~ — DONE 2026-09-19 00:20

`llama.cpp-prism` `b10706 / 1a07bfa5f`. Both GGUFs load. PTQ1_0 max **32k q8_0**
or **64k q4_0**; PQ2_0 max **16k q8_0** or **32k q4_0**. llama-bench tg128
**19.89 / 18.71** t/s (PTQ1_0 / PQ2_0); occupied full-window **13.52 / 12.74**.
Log `llama-bench-ternary-bonsai2.log`. Do not install Prism over `/usr/local/bin`.

## ~~Blocked on the download~~ — DONE 2026-09-17 18:03

Verified complete: 00001 (10.9 MB), 00002 (49.84 GB), 00003 (43.84 GB) = 90 GiB,
**no `.part` files**, plus `mtp-…-shared-Q4_K_M.gguf` (1.9 GB) and
`mmproj-F16.gguf` (904 MB).

**Reboot before the first load.** 93.7 GB of model against 125 GB RAM means free
RAM is the binding constraint, and the mmap reasoning in §1 only gets a fair test
on a clean page cache.

---

## 0. Carry-over from the Qwen3.6-35B-A3B session (2026-09-17)

Measured on this box, full tables in the benchmark guide §5. Apply these before
re-deriving anything:

- **`-ctk q8_0 -ctv q8_0` is a context lever, not a speed lever.** It does not
  speed up generation; it shrinks KV so more fits. `--fit on` sizes for **f16** KV
  and will silently auto-reduce your context (it cut 262144 → 8192 on the 35B).
  Always read back the real `n_ctx` from `/props`.
- **`--cpu-moe` (all experts in CPU RAM) is the practical default on 8 GB** — 200192
  context in 5.2 GB VRAM, nothing migrating between devices. Likely even more
  clearly right here, where the expert weights are far larger.
- **Allocated ≠ occupied.** Reserving 180k cost 12% TG; *filling* 65k cost 23% and
  129k cost 83%. On **this** 90 GB model, do **not** drive that with
  `llama-bench-ctx-sweep.sh` (it respawns the server per size). Occupied
  procedure: [llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md).
- **Prefill dominates long-prompt wall-clock** (284 s at 65k, 1120 s at 129k on the
  35B). Occupied PP here is ~100 t/s (~2× slower, not 15–20×). Those runs used
  `cache_prompt: false`; normal use reuses the cached prefix.
- **Do not benchmark against Unsloth's engine and call it ours.** `~/.unsloth/llama.cpp`
  is `b11007-mix-3e83366`, a genuine fork that beat our native b11011 by 9%. It is the
  faster *server*, but it ships no `llama-bench`/`llama-perplexity` — use our build for
  those, and never mix engines within one comparison.
- **Record the power profile.** A 129k point taken after ~19 min of sustained prefill
  on `balanced` dropped superlinearly (20.2 → 4.56 t/s); thermal throttling is
  unresolved and that row is explicitly flagged as untrusted.

---

## 1. First load — DONE 2026-09-18 (Unsloth Studio, not mainline launcher)

Loaded via `unsloth run` on patched mix, 8192 ctx, `--cpu-moe`, q8_0 KV,
`--no-mmproj`.

- mmap + default lazy: RSS ~52 GB **file-backed** (PLE not resident). Warm TG **8.62 t/s**.
- `--load-mode none --lazy-mode off`: RSS **~87.5 GB** (28.5 GB anon PLE). TG **8.06 t/s**.
- VRAM **~5950 MiB** no-MTP / **~6546 MiB** MTP at 8192 — weights estimate was ~3.2 GB;
  the rest is CUDA context + compute + KV.
- `--load-mode none` **without** `--lazy-mode off` still streams the 28.8 GB PLE.
- Stock Unsloth mix **crashes MTP**; one-line `hc_head_norm` patch fixes it
  ([#11143](https://github.com/unslothai/unsloth/issues/11143)).
- Do **not** run `llama-bench-ctx-sweep.sh` as written (respawns 90 GB per size).

## 2. Occupied-context probe — DONE 2026-09-18 00:55 +10

[llama-qwen38-benchmark-run.md](llama-qwen38-benchmark-run.md),
`llama-bench-qwen38-unsloth-occupied.sh`, 16384 alloc, MTP n_max=3.
Log: `llama-bench-qwen38-occupied-20260918.log`.

| ctx used | PP t/s | TG t/s | draft |
|---:|---:|---:|---|
| 574 | 90.8 | 11.84 | 73% |
| 2029 | 114.1 | 9.60 | 69% |
| 3910 | 108.4 | 10.76 | 66% |
| 8389 | 117.3 | **13.04** | 86% |
| 15456 | 121.4 | 11.21 | 72% |
| 32702 | 116.7 | **7.62** | 40% |
| 64099 | 105.8 | **7.86** | 64% |
| 15456 @64k alloc | 119.8 | 9.70 | 67% |
| 32702 @64k alloc | 115.6 | **8.00** | 49% |

Occupied PP is ~100–121 t/s (105.8 at 64k). 8k occupied did not hurt TG; 15.5k
@16384 is 11.21, @65536 is 9.70 (−13% from the bigger reservation). **32.7k
unclipped is 8.00 t/s** (49% draft); the earlier 7.62/40% was n_predict-clipped.
**64.1k is 7.86 t/s**. Real-world Solidity+TS at 64k alloc / 15.5k fill:
**10.52 then 11.35 t/s** (78–88% draft). Short prompts at 64k+MTP OOM.
Rows in the benchmark guide §5.

## 2b. Context allocation (later; each size is a 90 GB reload)

Default estimate: 65536 comfortable, 131072 plausible, 262144 will not fit.
**Do not** run `llama-bench-ctx-sweep.sh` as written.

- [ ] try one reload at a time, q8 KV explicit (`--fit` sizes for f16)
- [ ] if it fits, confirm it survives a **long generation**, not just load —
      the Qwen3.6-35B-A3B-MTP model loaded fine at 262144 and then OOM'd
      mid-generation (2026-07-15)
- [ ] record the KV cost per token actually observed vs the ~25 KB estimate
- [ ] confirm `-ot token_embd.weight=CPU` is a win on the **no-MTP** path
      (do not set it while the shared MTP head is attached)

## 3. Baseline benchmark (mainline, no MTP)

- [ ] prompt + generation t/s at 65536 via `llama-bench` and via a real prompt
- [ ] compare against expectation of 8–15 t/s (run-guide §10)
- [ ] record the **power profile** (balanced / performance) with each number —
      house convention in `llama.cpp-test.sh`
- [ ] try `-t 8 / 10 / 12 / 14` — this should be memory-bandwidth bound, so more
      threads may not help; the E-cores may actively hurt
- [ ] try `-ub 512` vs larger, and `-ncmoe N` to put a few expert layers back on
      the GPU if any VRAM is spare

## 4. MTP evaluation

```bash
./llama-serve-qwen38-flash-next-mtp.sh
```

- [ ] confirm you are on the **MTP build** — `llama.cpp-mtp/build/bin/llama-server`,
      version `10802 (d1a92352c)`. A mainline binary silently ignores `-md` and
      yields exactly 1.00×.
- [ ] read `draft_n` / `draft_n_accepted` from the server response; compute the
      acceptance rate. Reference: 78–82 % on Qwen3.6-35B-A3B-MTP.
- [ ] tune `--spec-draft-n-max` — script default 3, Unsloth docs say 5, their
      MTP README says 2
- [ ] **resolve the open `token_embd` question** (run-guide §7): the MTP script
      keeps it on GPU because the shared head borrows it. Test whether
      `LLAMA_ARG_OVERRIDE_TENSOR=token_embd.weight=CPU` actually hurts. If not,
      set it and raise the MTP context from 32768.
- [ ] verify `--spec-draft-cpu-moe` really keeps the draft's 1.8 GB of experts
      off the GPU — check the memory breakdown, do not assume
- [ ] **decide**: is MTP's VRAM cost worth it at the context size you want?
      Compare t/s at *equal context* against §3, not MTP-at-32k vs mainline-at-64k.

## 4b. Evaluate GSQ-RCO quants (and possibly the Strata engine)

Full analysis in [strata-engine-evaluation.md](strata-engine-evaluation.md). Order is
deliberate — the quant and the engine are separable, and the quant is the cheap half.

- [x] ~~verify the GSQ GGUFs are loadable by our build~~ **DONE 2026-09-26** — all 19 quant
      types in all 3 tiers resolve against our `ggml.h` with CPU traits + CUDA kernels; headers
      read remotely with `./gguf_head.py`. No blocker on the quant side.
- [x] ~~clear disk~~ **DONE 2026-09-27** — Q2_0 fit; `/home` now ~20 G free
      (`eval-data/kld-base-udiq4xs-c512x40.bin`, 5 GB, can go if space is needed)
- [x] ~~**download ISTA-DASLab `Q2_0` first**~~ **DONE 2026-09-27** (2 h 56 min, sha256 OK). (66.42 GB). §5b of the evaluation shows it is the
      right tier here: expert path is uniform `Q2_0 x144` with **no lookup-table i-quants**,
      which matters because we run every expert on an **AVX2-only** CPU. Tied with IQ2_XS on
      quality (89.07 vs 89.16) and 1.6 GB smaller.
- [ ] on first load, confirm the split loader accepts a **symlinked shard 2** — it is
      byte-identical across all three tiers (sha256 `316b46f3a2dbd68c`), so extra tiers cost
      only their shard 1 (+47.04 GB for IQ3_XXS instead of +75.84)
- [x] ~~benchmark it against our UD-IQ4_XS numbers at **equal context**~~ **DONE
      2026-09-27** — same engine, 16384 + MTP: Q2_0 **21.2 vs 9.8 t/s** TG at 8k, PP 180
      vs 117; PPL 3.36 vs 2.74. Q2_0 is now the launcher default. Tuning guide §5
      Groups E/F. Needed the x86 Q2_0 kernel (engine 11170 / a2fa025fb) and an MTP
      sidecar symlink in the GSQ dir.
- [ ] only if the −3.8% reasoning gap bites, add `IQ3_XXS` (+47.04 GB) and compare.
      Measured gap vs UD-IQ4_XS: PPL +22%, top-1 agreement 78%; house prompt fine at
      temp 1.0. Needs disk first (~20 G free).
- [ ] only then consider building Strata (manual CUDA build, their 13.0 vs our 13.3, and
      *"RTX 30/40 untested"* — we would be the first Ada)

## 5. Quality sanity check

- [ ] verify the sampling defaults produce sane output — this model wants
      temp **1.0** / min-p **0.0**, unlike the 0.6/0.05 used for Qwen3.5/3.6
- [ ] check `<think>` tags render correctly through `--jinja`
- [ ] try `--chat-template-kwargs '{"reasoning_effort":"medium"}'` and confirm
      it changes behaviour (default is `xhigh`)
- [x] ~~run the house test prompt used throughout `llama.cpp-test.sh`~~ **DONE
      2026-09-27** on Q2_0 and UD-IQ4_XS, `llama-qwen38-quality-probe.py`: correct
      contracts at temp 1.0; the default `xhigh` reasoning needs ~4–8k tokens

## 6. Vision (optional)

- [ ] drop `--no-mmproj`, add `--mmproj .../mmproj-F16.gguf` (0.90 GB)
- [ ] find what context is still reachable with it loaded
- [ ] test with `llama-mtmd-cli` on a sample image
- [ ] decide whether to keep a separate vision launcher or not bother on 8 GB

## 7. Housekeeping

- [ ] delete `llama.cpp-bin-backup-b10016/` once the new build is trusted
- [ ] fold the measured numbers back into `llama-run-guide.md` and **remove the
      [UNVERIFIED] markers** from the sections that have been confirmed
- [ ] append results to `llama.cpp-test.sh` in the existing running-log style
- [ ] watch `ggml-org/llama.cpp#28243` — **when it merges**, delete the
      `llama.cpp-mtp` worktree (`git worktree remove ../llama.cpp-mtp`), drop
      `llama-serve-qwen38-flash-next-mtp.sh`, and move the MTP flags into the
      main launcher
- [ ] `git pull` mainline periodically — `qwen4exp` is new and was still getting
      fixes weekly through September (see compile-guide §8)

---

## Known unknowns

Things genuinely not established yet, so nobody re-derives them from scratch:

1. ~~**Does resident RAM really stay near 62 GB?**~~ **Measured 2026-09-18.**
   mmap + lazy PLE: RSS ~52 GB **file-backed**. Full RAM (`--load-mode none
   --lazy-mode off`): RSS **~87.5 GB** (28.5 GB anon PLE + 58.8 GB expert
   shmem) + ~6 GB VRAM.
2. ~~**How badly does the n-gram LUT page-in hurt?**~~ **Measured.** Cold mmap
   ~4 t/s; warm mmap 8.62 t/s gen / 10.7 PP. Full RAM did **not** speed decode
   (8.06 t/s) — it only removed SSD faults on the n-gram table.
3. **Is the indexer cache quantizable?** It is assumed to follow `-ctk`, but the
   estimate in run-guide §4 conservatively treats it as f16. Worth checking —
   it is roughly half the KV budget.
4. **Does vision fit at all on 8 GB?** Untested. Kept `--no-mmproj`.
5. ~~**Real t/s.**~~ **Measured.** Live engine mix-pr220 occupied 16384:
   **8.94 / 10.58 / 9.43 / 9.25 t/s** at 0.5k–8k (PP 89–115). Morning
   patched-mix 8192: **8.06 t/s** no-MTP, **12.93 t/s** MTP digits (98%),
   **6.51 t/s** MTP prose (31%); occupied **11.84 / 9.60 / 10.76 / 13.04 /
   11.21 t/s** at 0.5k–15.5k.
6. **Is q8_0 KV actually near-lossless here?** Assumed from the general literature,
   never measured. Needs `llama-perplexity`, which exists only in the local build —
   so it must be measured on `llama.cpp/`, not on Unsloth's engine.
7. **Was the 129263-token collapse thermal?** 20.2 → 4.56 t/s is superlinear and the
   run followed ~19 min of sustained prefill on `balanced`. Re-run cold on
   `performance` before believing it. Until then that row stays flagged.
8. **`-ncmoe N` has never been swept** on either model — only the two endpoints
   (`--cpu-moe`, i.e. all experts on CPU, and full GPU offload) are known.
9. **Does a CPU-resident `token_embd` hurt shared MTP?** The Unsloth MTP load
   currently leaves it on GPU. Untested the other way.
