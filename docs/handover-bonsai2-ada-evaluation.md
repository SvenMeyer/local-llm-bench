# Handover: Bonsai 2 27B on the "Ada surgery" runtime (2026-10-27 / 28)

Self-contained. A fresh session should read this file first, then `README.md` only if it needs the wider box context.
Everything below was measured on this box on 2026-10-27 evening to 2026-10-28 afternoon.

## 1. What this is about

A tweet (2026-10, @DogukanUrker) claimed: **Bonsai 2 27B** (PrismML, 1.58-bit ternary, `PTQ1_0`, 5.9 GB) on
**Cary Palmer's runtime** ([professorpalmer/bonsai-ada-surgery](https://github.com/professorpalmer/bonsai-ada-surgery),
a PrismML llama.cpp fork + 71 patches) runs 2-4x faster than stock Prism and scores **15/20 on PatchEval** (Pi agent),
one task behind the official Qwen3.8-27B API (16/20). The user asked to replicate it on this laptop and run the same
benchmarks we used for Qwen3.8-Flash-Next (PPL, occupied-context speed probe, `llama-agent-eval.py`), then also
the tweet's own benchmark (BenchKit PatchEval with Pi).

## 2. Status at handover (2026-10-28 ~15:00)

| stage | status |
|---|---|
| build runtime, launcher, MTP head | done |
| perplexity / KLD | done |
| speed: new vs stock Prism, depth sweep | done |
| CUDA busy-wait fix (`blocking` sync) + upstream comment | done |
| `llama-agent-eval.py`, KV q3 / q4 / q8 | done |
| PatchEval, thinking ON (runtime default) | **done: 9/20** |
| power profile balanced vs performance | done |
| **PatchEval, thinking OFF** | **stopped after task 3 of 20 by the user's choice. RESUME tasks 4-20 (section 7)** |
| docs: speed table / guide / README | not yet updated (section 8) |

## 3. Setup (where things are)

| what | path |
|---|---|
| runtime repo (clone, d6c977f 2026-10-26) | `bonsai-ada-surgery/` |
| built engine (Linux, sm_89, gcc15 host) | `bonsai-ada-surgery/vendor/prism-llama/build-linux/bin/` (`vendor/prism-llama` -> `vendor/linux-1d9a45e4...`) |
| build log | `llama-bonsai-ada-build.log` |
| **launcher** (Linux port of the runtime's Windows 8 GB preset) | `llama-serve-bonsai2-ada.sh` (`DRY=1` prints the full command + env) |
| model, official | `~/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf` |
| model + MTP head (Q8_0, sha256 verified vs HF) | `~/.cache/lm-studio/models/CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF/...-mtp-procreations.gguf` |
| model + **Q4_0 head (launcher default, 8 GB)** | same dir, `...-mtp-procreations-q4head.gguf` (made with `build/requant_mtp.py`; trunk byte-identical to the official file, checked) |
| python venv for the runtime's tools (numpy) | `bonsai-ada-surgery/.venv` |
| BenchKit (v0.2.0, 12f79c6) | `benchkit-src/BenchKit/` (`uv sync` done; PatchEval data in `~/.cache/benchkit/datasets/patcheval/pilot-20`) |
| BenchKit reports | `benchkit-src/BenchKit/results/<timestamp>/` (results.html/json/md) |
| old stock Prism engine (b10706) | `llama.cpp-prism/build/bin/`, launcher `llama-serve-ternary-bonsai2.sh` |

Launcher defaults: 262144 window, **q3_0** K/V, tiered KV (VRAM line sized at start, ~82.7k cells), MTP draft 1 with
lookup drafting (`ngram-mod,draft-mtp`, up to 32), shared CUDA pool, packed KQ mask, f16/chunked prefill, sparse
auto, medium reasoning with a 20k budget, `-t 6`. Switches: `KV=q4_0|q8_0`, `CTX=`, `THINK=0`, `LOOKUP=0`,
`SPEC=0`, `REPLAY=1` (do not, see 6.1), `SCHED=blocking`, `HOST=` (default 127.0.0.1), `PORT=` (8099), `HEAD=q8`.

Scripts written this session (all in the repo root, each has a header comment):

| script | does |
|---|---|
| `llama-gpu-power-log.sh OUT [PID]` | every 5 s: GPU draw, SM clock, GPU temp, CPU package temp |
| `llama-bonsai2-eval-pipeline.sh` | deep probe (new runtime) -> stock Prism probe -> agent eval (q3) |
| `llama-bonsai2-kv-arms.sh` | 16k KLD q4/q3 vs q8, then agent eval with q4 and q8 |
| `llama-bonsai2-patcheval.sh` | PatchEval with Pi. Env: `THINK=0|1`, `LABEL=`, `BENCHKIT_PI_TIMEOUT` (default 1800 here) |
| `llama-bonsai2-sched-ab.sh` / `llama-bonsai2-poll-ab.sh` | CUDA wait mode A/B / `--poll` A/B |
| `llama-bonsai2-powerprofile-ab.sh` | balanced vs performance (switches over D-Bus, restores on exit) |
| `llama-cuda-schedule-env.patch` | local engine patch, 36 lines (section 6.2) |

Changed existing files: `llama-wait-ready.sh` now honours `WAIT_HOST=` (default 127.0.0.1).

## 4. Results

### 4.1 Quality (wikitext-2)

c512 x 40 (same as the Qwen3.8 runs; Bonsai and Qwen3.8 share the 248,320-token qwen35 tokenizer):
PPL q8_0 KV **7.983** (stock engine 7.983, same), q3_0 KV 8.039. KLD vs the stored Qwen3.8 UD-IQ4_XS logits:
1.34 (top-1 60%). That is a different, much smaller model, so it is not a quant-quality number.

K/V cache at 16k context (c16384 x 8, q8_0 cache = base): q4_0 PPL +0.3 %, KLD 0.0026, top-1 97.9 %;
**q3_0 PPL +0.8 %, KLD 0.0093, top-1 95.8 %**, 99th-pct KLD 0.074. These match the runtime author's published
numbers.

### 4.2 Speed: occupied probe

Probe: `llama-bench-occupied-ctx.py`, greedy, 128 gen. Balanced profile, 35 W unless marked.

New runtime, 262k q3_0, MTP only (`LOOKUP=0`), `blocking`:

| ctx tokens | 574 | 2,029 | 3,910 | 8,389 | 33,178 | 61,308 | 129,263 |
|---|---:|---:|---:|---:|---:|---:|---:|
| PP t/s | 399 | 477 | 481 | 471 | 386 | 341 | 139 (20 W) |
| TG t/s | 29.8 | 29.9 | 29.7 | 30.9 | 26.8 | 25.0 | 6.6 (20 W, past VRAM line) |

Stock Prism b10706, PTQ1_0, 64k q4_0 all-VRAM, no draft: PP 255 / 267 / 263 / 258 / 231 / 197;
TG 20.3 / 19.7 / 18.9 / 17.8 / 13.3 / (2.7, throttled to 20 W).
**New vs stock: TG 1.5x at 0.5k, 1.7x at 8k, 2.0x at 33k; PP 1.6-1.8x.** For comparison, Qwen3.8 GSQ Q2_0 at 8k is
20-21 TG and ~300 PP.

With lookup drafting on (runtime default), TG rises on text that repeats context (up to 197 t/s on a copy-heavy
answer). Lookup also learns across requests, so repeated rounds get faster: use round 1, or `LOOKUP=0`, for fair numbers.

`llama-bench` pp512 / tg128 (no draft, q8_0 KV): **518 / 22.9** balanced, 570 / 24.1 performance. Stock in Sept:
268 / 19.9.

### 4.3 `llama-agent-eval.py` (8 tasks x 3 seeds, thinking OFF, 262k, MTP + lookup)

| cache | pass | min/task | agent TG | notes |
|---|---:|---:|---:|---|
| q3_0 | **21/24** | 2.1 | 35.7 | 3 fails = 16-turn limit |
| q4_0 | 18/24 | 2.5 | 35.3 | 2x t7 runaway `write_file` hit the 8192-token cap -> HTTP 500; 4 turn limit |
| q8_0 | 17/24 | 2.6 | — | all turn-limit fails |
| Qwen3.8 Q2_0 / IQ3_XXS (2026-10-27) | 24/24 | 5.1 / 5.8 | 10.8 / 9.8 | |

Read it as noise between the KV types: 24 runs at temp 1.0. Bonsai fails by running out of turns on t7 and t8, and
needs ~1.8x more turns than Qwen. It is ~2.5x faster per task. The eval is still too easy to rank strong models.

### 4.4 PatchEval (BenchKit, Pi agent, 20 tasks, `BENCHKIT_PI_TIMEOUT=1800`)

1800 s rather than the default 900, because this laptop decodes ~1.8x slower than the tweet's RTX 3060. Task 1 passed
at 974 s, so 900 s would have measured the hardware.

**Thinking ON (runtime default, medium, 20k budget): 9/20 (45 %)**, 0 harness errors, 0 loop kills, 9 h 39 min.
Report: `benchkit-src/BenchKit/results/2026-10-28_13-27-34/`, log `benchkit-patcheval-bonsai2-ada.log`.

| # | task | result | # | task | result |
|---|---|---|---|---|---|
| 1 | sqlit-246 | PASS 974 s | 11 | pypdf-3982 | timeout |
| 2 | sqlit-260 | FAIL | 12 | pypdf-3878 | PASS (at limit) |
| 3 | narwhals-3864 | timeout | 13 | pypdf-3587 | PASS (at limit) |
| 4 | city2graph-121 | timeout | 14 | attrs-1575 | timeout |
| 5 | json-repair-207 | timeout | 15 | typeguard-499 | timeout |
| 6 | json-repair-191 | timeout | 16 | structlog-710 | PASS (at limit) |
| 7 | json-repair-205 | PASS (at limit) | 17 | pygments-2816 | timeout |
| 8 | click-3572 | PASS (at limit) | 18 | pygments-2828 | FAIL |
| 9 | click-3360 | PASS 1119 s | 19 | tomlkit-440 | timeout |
| 10 | click-2790 | PASS 1410 s | 20 | tomlkit-542 | PASS 1554 s |

9 of the 11 losses are timeouts. Time goes into long thinking turns: in tasks 1-4, 8 requests ran past 4k tokens
(max 16,849), and those were more than half of all generated tokens. "PASS (at limit)" means the agent was still
working at 1800 s and the workspace was already correct when graded. The tweet's 15/20 most plausibly differs by speed.

**Thinking OFF (`THINK=0`), partial 1/3:** task 1 PASS 713 s, task 2 FAIL 1479 s, task 3 (narwhals-3864) TIMEOUT
1801 s. The first three tasks give the same results as thinking ON. Log `benchkit-patcheval-bonsai2-ada-think0.log`,
partial report `benchkit-src/BenchKit/results/2026-10-28_15-02-59/`. Thinking off did not shorten tasks much: in task 2 the GPU was idle ~48 %
of the time while Pi ran tools and tests in the sandbox, which BenchKit limits to 2 CPUs by default
(`BENCHKIT_SANDBOX_CPUS`).

### 4.5 CUDA wait mode (local patch, section 6.2), 4k / 8k, MTP only, fresh server per arm

| | spin (driver default) | blocking |
|---|---:|---:|
| llama-server CPU in decode | 97 % of a core | ~0 % |
| CPU package mean | 93 °C | 80 °C |
| TG 4k / 8k | 30.3 / 32.2 | 29.2 / 31.2 (-3.5 %) |
| PP | 478 / 468 | 475 / 468 |

`--poll 0` does not stop the spin; the driver does it, not llama.cpp's thread pool. Long runs with `blocking` held
35 W ~95 % of the time. Posted as a comment from the user's GitHub account (with an AI-assist disclosure) on
upstream PR ggml-org/llama.cpp#26487, which proposes `GGML_CUDA_BLOCKING_SYNC=1`:
https://github.com/ggml-org/llama.cpp/pull/26487#issuecomment-6443411923 . Check for replies.

### 4.6 Power profile (sustained 6 rounds ~4.5 min + llama-bench)

performance vs balanced: GPU ceiling **40 W** vs 35 W (hardware max 50), fans ~6 % faster, **TG +9 %, PP +9-10 %**,
GPU W +14 %, CPU mean 89 vs 76 °C. Did not throttle in 5 min; untested for hours. Switch:
`busctl set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles
org.freedesktop.UPower.PowerProfiles ActiveProfile s performance` (`powerprofilesctl` is broken: python `gi` missing).
The box is on **balanced** now.

## 5. Box facts learned (also in memory)

- **Thermal throttle:** after minutes of sustained full-GPU load the Dell XPS 15 heat-soaks (fans at max, internal
  sensors 52-78 °C) and Dynamic Boost (`nvidia-powerd`) cuts the GPU ceiling **35 -> 20 W**, ~4x slower decode. It
  recovers after a few minutes idle. Log power with every benchmark and wait for 35 W before an arm:
  `nvidia-smi -q -d POWER | grep 'Current Power Limit'`. The user may clean the fans later; re-run then.
- The GUI is on the Intel iGPU (`KWIN_DRM_DEVICES=/dev/dri/card0`); the NVIDIA card is inference-only. Full VRAM is the
  server's own sizing (the runtime fills the card on purpose). The user switched off 3 external displays at ~00:50 on
  10-28 (q3 agent arm ran with them on, everything later with them off).
- Linux has no WDDM spill: VRAM over-commit means an OOM crash, not a slowdown.
- Docker 29.7.2 + `docker-buildx` were installed and started by the user for BenchKit (user is in the `docker` group).

## 6. Gotchas found (do not rediscover)

1. **Replay rollback crashes on Linux:** `LLAMA_RS_REPLAY=1` (runtime 8 GB default) gives "illegal memory access" in
   `launch_gated_delta_net<...>` (replay path) on a ~4k code prompt with lookup drafting. The launcher defaults
   `REPLAY=0`, so draft 1 / tail 1, a 142 MiB plane, and an 82.7k instead of 92.7k VRAM line. Not reported upstream yet.
2. **Local engine edit:** `ggml/src/ggml-cuda/ggml-cuda.cu` has `GGML_CUDA_SCHEDULE=blocking|yield|spin|auto` and
   `GGML_CUDA_BLOCKING_SYNC=1` (the upstream PR name). Saved as `llama-cuda-schedule-env.patch`. The runtime's
   `build/build_linux.sh` refuses to rebuild a tree with local edits; rebuild with
   `cmake --build build-linux --target llama-server llama-bench llama-perplexity -j 8` in `vendor/prism-llama`, with
   `/opt/cuda/bin` on PATH. Host compiler g++-15 is already in the CMake cache.
3. **BenchKit's Pi proxy runs in Docker** and reaches the host via `host.docker.internal` = docker0 `172.17.0.1`. A
   server on 127.0.0.1 gets **zero requests** and every task "fails" in ~18 s with 0 tok/s. The PatchEval script
   starts the server with `HOST=172.17.0.1` (not LAN-exposed) and `BENCHKIT_HOST=http://172.17.0.1:8099/v1`.
4. A killed BenchKit leaves `buildx_buildkit_benchkit-build-*` behind. Clean with
   `docker buildx ls | awk '/^benchkit-build-/{print $1}' | xargs -r -n1 docker buildx rm --force`, plus
   `docker ps -aq --filter label=benchkit.run | xargs -r docker rm -f`. Stop BenchKit with ONE SIGINT to its python
   process (not `uv`) so it writes a partial report and cleans up.
5. zsh does not word-split `set -- $var`; run multi-arm loops under `bash -c`.
6. The probe's raw `/completion` makes the model continue the source text; lookup drafting copies it. That flatters TG.
7. llama-server returns HTTP 500 (not a truncated call) when a tool call hits `max_tokens` mid-JSON.
8. `llama-wait-ready.sh` needs `WAIT_HOST=172.17.0.1` when the server is bound there.

## 7. NEXT: resume the thinking-off PatchEval (tasks 4-20)

Stopped on purpose at 14:57 on 2026-10-28, right after task 3 had reported, with one SIGINT. BenchKit saved the
partial report `results/2026-10-28_15-02-59` (1/3) and cleaned up Docker, and llama-server was stopped. The box is idle,
on balanced.

BenchKit slices are 0-indexed, end-exclusive, so `patcheval:3-20` = tasks 4..20. Expect ~7 h (about 25 min per task).
Run in `balanced`. Start cool: CPU < 65 °C and `Current Power Limit` 35 W.

```bash
cd /home/sum/Downloads/AI-Runtime
docker info >/dev/null && docker buildx version      # daemon up? if not: ! sudo systemctl start docker
pgrep -x llama-server                                 # must be empty
THINK=0 HOST=172.17.0.1 SCHED=blocking setsid nohup ./llama-serve-bonsai2-ada.sh \
  > llama-serve-bonsai2-ada-patcheval-think0-resume.log 2>&1 < /dev/null &
WAIT_HOST=172.17.0.1 ./llama-wait-ready.sh 8099 120
cd benchkit-src/BenchKit
BENCHKIT_PI_TIMEOUT=1800 BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:8099/v1 \
BENCHKIT_HARDWARE="RTX 4070 Laptop 8GB (35 W)" \
  uv run benchkit --headless --models bonsai-2-27b --benchmarks patcheval:3-20 --harness pi \
  > ../../benchkit-patcheval-bonsai2-ada-think0-resume.log 2>&1 &
# power log: ../../llama-gpu-power-log.sh ../../benchkit-patcheval-bonsai2-ada-think0-resume.log.power <benchkit PID>
```

Run it in the background and watch the `^\[hh:mm:ss\]` result lines in the log. Do not poll; use a monitor. Final
score = tasks 1-3 (from the first think0 log) + tasks 4-20 (resume report). Compare per task with the thinking-ON
table in 4.4.

## 8. After that: write it up

- Append rows to `llama-speed-table.md` (small / dense section) for the new runtime: probe, llama-bench, performance
  mode. Add a Bonsai block for agent eval, PatchEval and the KV arms.
- Add a "Bonsai 2 on the Ada runtime" section to `llama-benchmark-and-tuning-guide.md` §5, and the raw commands +
  numbers to `llama.cpp-test.sh`.
- README: add `llama-serve-bonsai2-ada.sh` to Builds / Launchers, and update the status footer.
- Optional "GPU-only mode" test: `performance` profile plus CPU turbo off (`/sys/devices/system/cpu/intel_pstate/no_turbo`,
  root, so the user runs it). Dynamic Boost may then give the GPU 45-50 W instead of 40. Also try once
  `sudo nvidia-smi -pl 50`, which is probably locked on this laptop ("Requested Power Limit N/A"). Log the ceiling and
  power and compare with 4.6.
- Optional, user's call: report the replay crash (6.1) on the runtime's issue tracker; add energy numbers (RAPL needs
  root) to the upstream PR comment; PatchEval in performance mode; a harder in-house agent task set.

## 9. The user

Wants results printed as they land, and the work kept moving without pausing for confirmation. Compare only at equal
context, MTP and power state. Box: i7-13700H, RTX 4070 Laptop 8 GB (35 W), 125 GB RAM, Manjaro, driver 610.57.04,
CUDA 13.3.
