# Qwen3.8-Flash-Next — how to run the benchmark

**This is the file a fresh agent session should follow.** It is the scaled-down
copy of the 2026-09-17 Qwen3.6-35B-A3B Group A / B / C work, for this 90 GB
model on this laptop. Setup and flags live in
[llama-qwen38-flash-next-unsloth.md](llama-qwen38-flash-next-unsloth.md).
Results go in [llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)
§5 and the raw log `llama.cpp-test.sh`.

Paste into a new session:

```
Work in /home/sum/Downloads/AI-Runtime on this Manjaro box (i7-13700H, RTX 4070
Laptop 8 GB, 125 GB RAM, no swap).

Read, in order:
  llama-qwen38-benchmark-run.md
  llama-qwen38-flash-next-unsloth.md
  llama-todo.md
  llama-benchmark-and-tuning-guide.md §5 (Qwen3.8 Group A + Group C)

Do not re-derive Unsloth/MTP setup from chat history. Speak only for tested
paths — never claim MTP works in the Unsloth dashboard.

Already done (do NOT relaunch, do NOT dump the 90 GB load to re-measure):
  - First load + RAM modes + local hc_head_norm MTP patch (unslothai/unsloth#11143)
  - Official mix-pr220 install (unslothai/llama.cpp#220, #144@ca1426903 on b11027)
  - Group A morning (patched b11007): 8.06 t/s no-MTP; 12.93 t/s MTP digits (98%); 6.51 t/s MTP prose (31%)
  - Group C occupied morning: llama-bench-qwen38-occupied-20260918.log
    16384 ctx, MTP n_max=3. TG 11.84 / 9.60 / 10.76 / 13.04 t/s
  - Group C occupied evening mix-pr220: llama-bench-qwen38-pr220-20260918-214747.log
    TG 8.94 / 10.58 / 9.43 / 9.25 t/s at 574 / 2029 / 3910 / 8389; PP ~89–115.
    Live engine. Short-chat PP ~12 t/s is not the occupied number.

Hard rules:
  - Do not run llama-bench-ctx-sweep.sh (respawns 90 GB per size).
  - Do not poll long jobs. Background + watcher that prints only DONE/FAILED.
  - Do not pass --no-mmap or --mlock. Use /usr/bin/cp -af (cp is interactive).
  - Occupied probes talk native /completion on the llama-server port, not :8888.
  - Unsloth load API waits ~5 s for a 90 GB process; SIGTERM llama-server first
    or POST /api/inference/load returns HTTP 500.

Wait for me to say what to do next. Candidates, each a 90 GB reload unless
SKIP_RELOAD applies: one-at-a-time allocation (32k/65k), larger occupied
(16k/32k — not 65k/129k unless I ask), mainline b11011, llama.cpp-mtp PR
#28243. Do not start any of those unprompted.
```

---

## 0. Your job

1. **One snapshot** of whether a run is already in flight (section 2). Do not
   start a second 90 GB load.
2. If a log already ends with `# done `, record it and stop.
3. If a harness is running, **watch it**, do not relaunch.
4. If nothing is running, start **Group C only** (occupied-context, section 6).
5. When it finishes, write the numbers (section 8). Then stop. Do not start
   Group B, mainline, or `llama.cpp-mtp` unless the user asks.

Group A (engine / short MTP vs no-MTP at 8192) is **already measured**.
Re-running it dumps 90 GB of RAM for numbers we have.

---

## 1. Hard rules

- **Do not** run `llama-bench-ctx-sweep.sh`. It spawns a **new** llama-server
  per context size. That is a 90 GB reload × N.
- **Do not** copy the 35B occupied windows (16k / 65k / 129k) unless asked.
  Occupied PP is ~100 t/s (~2× the 35B, not 15–20×). Short chat can still look
  like ~12 t/s. 8k occupied is done; 65k/129k are still a long prefill.
- **Do not** poll. Launch the job in the background, attach
  `~/.grok/long-running-background-tasks/watch_qwen38_occupied.sh`, and wait
  to be woken on `DONE` / `FAILED`. An agent loop that `sleep`s and re-reads
  the log wastes tokens and does not make the job finish sooner.
- **Do not** claim MTP works in the Unsloth **dashboard / Tauri UI**. Only
  `unsloth run` + llama-server argv was tested.
- **Do not** pass `--no-mmap` or `--mlock`.
- **Do not** open a second Tauri `unsloth-studio` on top of a live `unsloth run`.
- **Do not** file a new GitHub issue for the MTP abort (already
  [unslothai/unsloth#11143](https://github.com/unslothai/unsloth/issues/11143)).
- Shell `cp` is an **interactive alias** on this box. Overwrite with
  `/usr/bin/cp -af`.
- Native `/completion` and `/props` are on the **llama-server** port (random
  high port). Studio Chat Completions are on **8888** and need a bearer key.
  Occupied probes talk to llama-server, not 8888.
- Believe llama-server argv (`--model-draft` + `--spec-type draft-mtp`) and
  `draft_n` / `draft_n_accepted` in `/completion` timings. Studio can report
  MTP on after a silent fallback.

---

## 2. First check — one snapshot, then decide

```bash
date -Iseconds
pgrep -a -f 'llama-bench-qwen38-unsloth-occupied.sh' || true
pgrep -a -f '/.unsloth/llama.cpp/llama-server -m' || true
ls -lt /home/sum/Downloads/AI-Runtime/llama-bench-qwen38-occupied-*.log 2>/dev/null | head
tail -n 20 /home/sum/Downloads/AI-Runtime/llama-bench-qwen38-occupied-20260918.log
free -h | awk 'NR<=2'
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
powerprofilesctl get 2>/dev/null || true
```

| What you see | What you do |
|---|---|
| Log ends with `# done ` | Section 8: record, then stop |
| Harness pid is alive | Section 7: attach the watcher, do **not** start another |
| Log has `LOAD_HTTP 500` / `FAILED: no llama-server` | Section 9: recover |
| llama-server already has `-c 16384` and `--spec-type draft-mtp`, no harness | Section 6 with `SKIP_RELOAD=1` |
| Nothing loaded / wrong ctx / no MTP | Section 5 then 6 |

Group C for 2026-09-18 is **done** (`llama-bench-qwen38-occupied-20260918.log`
ends `# done 2026-09-18T00:55:19+10:00`). Do not relaunch it. Numbers are in
the benchmark guide §5. A new session’s job is: confirm the log, confirm the
tables match, then stop unless the user asks for 32k alloc / 65k occupied /
mainline.

---

## 3. What this is (and what it is not)

| | Qwen3.6-35B-A3B (2026-09-17) | this model |
|---|---|---|
| Engine | Unsloth `b11007-mix` | live **mix-pr220** (`#144@ca1426903`); morning was patched `b11007-mix` |
| Active params | ~3 B | ~6 B |
| Prefill (occupied `/completion`) | ~230 t/s | **~90–117 t/s** (short chat ~12 t/s) |
| Generation | ~26 t/s | mix-pr220 occupied **8.9–10.6 t/s**; morning patched-mix **9.6–13.0 t/s** |
| Group A | 8192, 512 tok, no spec, Unsloth vs local | **done** at 8192 (see §4) |
| Group B | empty-KV 8k → 180k, **new server per size** | **do not** use that script. Optional later, one reload at a time |
| Group C | occupied ~0.5k / 16k / 65k / 129k, 128 gen, 200k alloc | **done** 2026-09-18: 0.5k / 2k / 4k / 8k, 128 gen, **16384** alloc, MTP on |

CHARS `2000,7000,14000,28000` are **character** counts of `llama.cpp/src`
C++ (~3.5 chars/token) → roughly 0.5k / 2k / 4k / 8k tokens.

Measured wall-clock for Group C (reload + four probes): **~6 min**
(00:49–00:55). Occupied PP is ~100 t/s, not the ~12 t/s short-prompt figure.

---

## 4. Already measured — do not redo

Patched Unsloth mix, 8192 ctx, `--cpu-moe`, q8_0 KV, 10 threads, `balanced`
(35 W GPU), 2026-09-18. Full RAM = `--load-mode none --lazy-mode off`.

| | PP t/s | TG t/s | notes |
|---|---:|---:|---|
| mmap, cold | 4.0 | 4.0 | n-gram page-ins |
| mmap, warm | 10.7 | 8.62 | |
| full RAM, no MTP | 11.8 | **8.06** | RSS ~87.5 GB |
| full RAM, MTP n_max=3, digits | 12.1 | **12.93** | 98% accept (112/114) |
| full RAM, MTP n_max=3, prose | 21.8 | **6.51** | 31% accept (85/277) |

VRAM ~5950 MiB no-MTP / ~6546 MiB MTP at 8192.

MTP on this box is a **win on low-entropy text** and can **lose on prose** at
`n_max=3`. Do not quote Unsloth’s 1.3–1.7× as what this laptop feels.

---

## 5. Preconditions (only if you must start or reload)

Stack:

| | |
|---|---|
| Host | i7-13700H, RTX 4070 Laptop 8 GB (often 35 W), 125 GB RAM, **no swap**, Manjaro |
| Engine | `~/.unsloth/llama.cpp` mix-pr220 `11166 (10921f3f1)` official `#144@ca1426903` |
| Model | `/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf` |
| MTP sidecar | `mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf` |
| Studio | `unsloth run` on `127.0.0.1:8888`, `--disable-tools --api-only` |
| Launcher | `./llama-serve-qwen38-flash-next-unsloth.sh` (MTP **off** by default) |

Model Memory toggles (Unsloth, **global**) must both be **OFF** for
`--load-mode none`. Confirm with `GET /api/settings/model-memory`.

If nothing is serving:

```bash
cd /home/sum/Downloads/AI-Runtime
./llama-serve-qwen38-flash-next-unsloth.sh
```

Wait until `curl -fsS http://127.0.0.1:8888/v1/models` works. RSS after a
full-RAM load is ~87.5 GB; if it sits near 52 GB file-backed, `--lazy-mode off`
did not take.

**Studio load API** needs the owner bearer key (`sk-unsloth-…`, prefix
`a947d60f` in `~/.unsloth/studio/auth/auth.db`). It is **not** in sqlite in
plaintext. Get it from Unsloth Studio → Settings → API, or from a previous
terminal’s `UNSLOTH_API_KEY`. **Do not write the secret into this markdown.**
Native `/completion` does not need it.

---

## 6. Start Group C (occupied context)

Harness: `llama-bench-qwen38-unsloth-occupied.sh`

What it does:

1. If llama-server is **already** `-c 16384` + `--spec-type draft-mtp`, skip
   the reload (`SKIP_RELOAD=1` is also accepted).
2. Otherwise SIGTERM the old llama-server and **wait until RAM is free**
   (Unsloth’s own kill wait is ~5 s — too short for 90 GB; a rushed reload
   returns HTTP 500).
3. POST `/api/inference/load` once: ctx **16384**, MTP `n_max=3`,
   `--cpu-moe --spec-draft-cpu-moe`, q8_0 KV, `--load-mode none --lazy-mode off`,
   `--no-mmproj`. **Do not** pass `token_embd.weight=CPU` with the shared head.
4. Probe native `/completion` with `CHARS=2000,7000,14000,28000`,
   `NPREDICT=128`, `cache_prompt: false`, temp 0, `ignore_eos`.

```bash
cd /home/sum/Downloads/AI-Runtime
export UNSLOTH_API_KEY='sk-unsloth-…'   # only needed if a reload will happen
export OUT=/home/sum/Downloads/AI-Runtime/llama-bench-qwen38-occupied-$(date +%Y%m%d-%H%M%S).log
: > "$OUT"
chmod +x ./llama-bench-qwen38-unsloth-occupied.sh
# If 16384+MTP is already up:
#   SKIP_RELOAD=1 ./llama-bench-qwen38-unsloth-occupied.sh
exec ./llama-bench-qwen38-unsloth-occupied.sh
```

Launch that as a **background** command (`timeout` 0). Capture the OS pid of
the harness (the `bash llama-bench-qwen38-unsloth-occupied.sh` line from
`pgrep`). Log path is `$OUT`.

Confirm after launch, **once**:

- llama-server argv contains `--model-draft` and `--spec-type draft-mtp`
- `/props` `n_ctx` is 16384 (not silently auto-reduced)
- log has `reloading to ctx 16384` **or** `skip reload`

If Studio says MTP on but argv has no `--model-draft`, the patch is not in
the live binary — stop, do not spend an hour probing a no-MTP server.

---

## 7. Wait without polling

Watcher (already on disk, prints **only** `DONE` / `FAILED`):

`~/.grok/long-running-background-tasks/watch_qwen38_occupied.sh`

```
monitor(
  command='bash /home/sum/.grok/long-running-background-tasks/watch_qwen38_occupied.sh <HARNESS_PID> <LOG>',
  description="Watch Qwen3.8 occupied-context bench"
)
```

Replace `<HARNESS_PID>` and `<LOG>`. Then leave it. Do not `sleep` in a loop.
Do not `get_command_or_subagent_output` on a timer.

On `DONE`: section 8.

On `FAILED`: section 9. Fix, relaunch, **replace** the monitor so it points
at the new pid.

---

## 8. Record results (definition of done)

The job is not done when the process starts. It is done when the numbers are
in the house files.

From the log, take each occupied row (`ctx_tok`, `PP t/s`, `TG t/s`,
`prefill`, `draft a/b`). Also record:

```bash
powerprofilesctl get
nvidia-smi --query-gpu=memory.used,temperature.gpu,power.draw --format=csv,noheader
# throttle bit: 0x1 means it was throttling
nvidia-smi -q -d PERFORMANCE 2>/dev/null | head
pgrep -a -f '/.unsloth/llama.cpp/llama-server -m'
```

Then:

1. Fill the **Qwen3.8 Group C** table in
   [llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)
   §5 (replace the pending row). Same columns as the 35B table.
2. Append the raw log block to `llama.cpp-test.sh` (newest at the bottom),
   including the full command, `n_ctx`, MTP accept rates, VRAM, profile.
3. One-line status in [README.md](lab-notebook.md) if the headline numbers changed.
4. Tell the user the four (ctx, PP, TG, accept) rows in the reply.

Do not start another sweep after that unless asked.

---

## 9. Failure recovery

**HTTP 500 on `/api/inference/load`.** Unsloth waited ~5 s, leftover
llama-server still holds ~90 GB. SIGTERM (then SIGKILL) **by the llama-server
pid**, wait until `free` shows ~100+ GiB available, retry the harness once.
Do not start a second `unsloth run`.

**MTP missing after HTTP 200.** Check argv. Stock mix aborts in
`build_hc_mix` / `ggml_can_repeat`. Live binary must be the patched
`~/.unsloth/llama.cpp/build/bin/llama-server` (RPATH may still point at
`build-hc-fix/bin` — that dir must exist). Pre-patch backup:
`build/bin-pre-hc-fix/`.

**`n_ctx` auto-reduced.** `--fit on` sizes for f16 KV. The harness passes
q8_0 explicitly; if `/props` is not 16384, the point is invalid.

**Harness died mid-probe.** A per-size `N | FAILED:` line is not fatal (the
python continues). A `LOAD_HTTP` or `FAILED: no llama-server` line is fatal.

**No swap / compile during the run.** Do not start a CUDA build or a heavy
browser. This load uses ~94 GiB of 125 GiB.

---

## 10. Not this session

Leave these until the user asks. Each is a 90 GB reload or a different binary.

- Group B allocation sweep (empty KV at 32k / 65k / 131k)
- Mainline `llama.cpp/` b11011 (no qwen4exp MTP; `-md` ignored)
- `llama.cpp-mtp/` PR #28243 (untested on this GGUF)
- Thread sweep `-t 8/12/14`, `-ncmoe N`, vision / mmproj
- `llama-perplexity` on q8_0 KV (local build only)
