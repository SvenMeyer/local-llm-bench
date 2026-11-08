# PatchEval runbook: run a model or agent, then update the report

Everything needed to benchmark another model or harness (agent) on BenchKit PatchEval and add it to the
comparison report. Written 2026-11-02 after the local and hosted runs; current results are in
[`reports/2026-11-02_PatchEval_Report_local-vs-hosted.md`](../reports/2026-11-02_PatchEval_Report_local-vs-hosted.md)
(and `.html`).

## 1. What PatchEval is

- 20 real bug fixes from 12 Python projects (BenchKit PatchEval release `pilot-20`). The agent gets the
  issue text and the repo in a Docker sandbox; hidden tests grade the workspace afterwards (fail-to-pass
  tests plus the project's own regression suite).
- Limits used for every run so far: **1800 s (30 min) per task, 1 task at a time, no repair attempts.**
  A task still running at 30 min is graded as it stands (so "pass at the deadline" is possible).
- Score = passes / 20. Harness errors (sandbox/disk/daemon faults) are excluded from the score.

## 2. Files

| File | What it is |
|---|---|
| `patcheval-hosted.sh` | **pi + any hosted model** in `~/.pi/agent/models.json` |
| `patcheval-mcode.sh` | **mcode (MiniMax Code fork) + any model** in `~/.minimax/config.yaml` |
| `patcheval-handoff.sh` | stop a running run after its current task (saves results) and resume the rest |
| `patcheval-strata-quants.sh`, `patcheval-llamacpp-ornith.sh` | templates for **local** models (Strata / llama.cpp) |
| `patcheval-dataset/pilot-20-local1/` | our dataset copy with the fixed `pygments-2828` test (section 7) |
| `mcode-sandbox-dist/` | mcode build + Node 24 native deps, copied into the sandbox (`README.md` there: rebuild) |
| `benchkit-src/BenchKit/` | BenchKit v0.2.0 (`12f79c6`) **with uncommitted local patches** (section 8) |
| `benchkit-local-patches.diff` | those patches as one file, to re-apply after a BenchKit update |
| `reports/patcheval-arms.json` | list of every tested setup and its result folders: **edit this to add a run** |
| `reports/patcheval-regrades.json` | post-hoc re-grades (flawed hidden tests), applied on top of the raw results |
| `reports/build_patcheval_data.py` | merges the result folders into `reports/patcheval-data.json` |
| `reports/make_patcheval_report.py` | writes the report `.md` and `.html` from that data |

## 3. Before a run (checklist)

```bash
cd ~/Downloads/AI-Runtime
docker info >/dev/null && echo docker ok          # sudo systemctl start docker
df -h / | tail -1                                 # need >= 20 GB free: each run's build cache is ~9 GB
cd benchkit-src/BenchKit && git status --short    # local patches present? (section 8)
export BENCHKIT_PATCHEVAL_DATASET=~/Downloads/AI-Runtime/patcheval-dataset/pilot-20-local1
```

Credits: check the balance before a long hosted run (a run stops with HTTP 402 when it runs out):

```bash
curl -s -H "Authorization: Bearer $OPENROUTER_API_KEY" https://openrouter.ai/api/v1/key      # usage, usage_daily, limit_remaining
curl -s -H "Authorization: Bearer <vercel key>" https://ai-gateway.vercel.sh/v1/credits      # balance, total_used
```

Expected time and cost per 20 tasks (measured):

| Setup | Wall clock | API cost |
|---|---|---|
| pi + DeepSeek V4.1 Flash 1017 (OpenRouter, think max) | 1.5 h | ~$0.81-0.97 |
| pi or mcode + MiniMax M3.1 Flash (Vercel, think max) | ~10 h (most tasks hit 30 min) | ~$7 (est., stopped at 6/20) |
| local Qwen3.8 / Ornith / Bonsai on this laptop | 9-10 h | none |

## 4. Run a hosted model with pi

1. The model must be in `~/.pi/agent/models.json` (pi's own config: the run copies that entry, so pi
   behaves as it does for you). The API key there may be literal, `$NAME`, `${NAME}` or `!command`.
2. **Thinking `max` only works if the entry's `thinkingLevelMap` names it.** pi silently lowers a level the
   map does not list (MiniMax had no map: `max` became `high`). The script adds `xhigh`/`max` for
   `minimax/minimax-m3.1-flash`; for another model add it in the entry (or extend the script).
3. Smoke test (1 task, ~5-10 min), then the full run:

```bash
PROVIDER=openrouter MODEL=deepseek/deepseek-v4.1-flash-1017 SLICE=patcheval:1 LABEL=smoke-x ./patcheval-hosted.sh
PROVIDER=openrouter MODEL=deepseek/deepseek-v4.1-flash-1017 \
  setsid nohup ./patcheval-hosted.sh > patcheval-hosted-<label>-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
```

| Variable | Default | Meaning |
|---|---|---|
| `PROVIDER`, `MODEL` | `vercel-gateway-free`, `minimax/minimax-m3.1-flash` | provider id and model id in pi's config |
| `THINKING` | `max` | pi `--thinking` level (off ... max) |
| `MAX_TOKENS` | `65536` | output cap per reply (pi's default would be 16,384; local runs used 16k) |
| `SLICE` | `patcheval` | `patcheval:1` (first task), `patcheval:17-18` (task index 17 only, 0-based, end exclusive) |
| `LABEL` | derived | log name `benchkit-patcheval-<LABEL>.log` |

The script makes a real 1-token test call first and stops if it is not HTTP 200 (bad key, no credit).

## 5. Run a model with mcode (or another harness)

```bash
PROVIDER=openrouter MODEL=deepseek/deepseek-v4.1-flash-1017 BASE_MODEL=deepseek/deepseek-v4.1-flash \
  MAX_TOKENS=65536 setsid nohup ./patcheval-mcode.sh > patcheval-mcode-<label>-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
```

- Reads `~/.minimax/config.yaml`, keeps only that provider, points it at BenchKit's proxy and removes the key
  (written to `mcode-sandbox-<label>.yaml`; your config is not changed).
- `BASE_MODEL`: copy settings from this entry when `MODEL` is not in the config (mcode only had the
  unversioned DeepSeek id). `MAX_TOKENS`: override `limit.output`. `EFFORT` (default `max`): `--effort`.
- mcode refuses `--effort max` unless the model entry has `thinking.effortOptions`; the script adds
  `default..max` when missing.
- After updating the mcode fork, rebuild `mcode-sandbox-dist/` (see its `README.md`): `dist/` needs
  `better-sqlite3` built for the sandbox's Node 24.
- **Another harness**: BenchKit selects the agent with `BENCHKIT_AGENT` (`pi` default, `mcode`);
  `src/benchkit/mcode_agent.py` is the template: subclass `PiAgentRunner`, install the agent into the
  sandbox container, run it non-interactively, translate its event stream, record `call_usage`.
- Known mcode limit: token usage of a task cut at the 30-min limit comes only from its session log
  (`call_usage`); before 2026-11-01 18:00 such tasks show 0 tokens.

## 6. Run a local model

Use `patcheval-strata-quants.sh` (Strata) or `patcheval-llamacpp-ornith.sh` (llama.cpp) as a template:
start the server on `127.0.0.1:8099`, wait on `/health`, expose it to Docker with
`socat TCP-LISTEN:8099,bind=172.17.0.1,...`, then run BenchKit with
`BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:8099/v1`. Local runs so far used pi's default
16k output cap and the server's default thinking; set `BENCHKIT_PI_MODEL='{"maxTokens":65536,"reasoning":true}'`
and `BENCHKIT_PI_THINKING=...` to change that. Export `BENCHKIT_PATCHEVAL_DATASET` first.

## 7. Dataset: `pilot-20-local1` (use it for all new runs)

Our copy of `pilot-20` with one change: `pygments-2828`'s hidden golden-file test is replaced by
`tests/test_patcheval_jsonnet_array_slice.py`, which keeps upstream's exact token stream but accepts the
slice colons in `numbers[1::2]` as `Operator` or `Punctuation` (two tokens or one `::`). The original
expected `Operator` only, which nothing in the issue or the lexer points to
([BenchKit issue #89](https://github.com/DogukanUrker/BenchKit/issues/89)). Validated: unfixed lexer
fails, upstream fix passes, a wrong token type fails, and all six earlier model patches pass.
First runs on it (2026-11-02, DeepSeek V4.1 Flash, think max, 64k): pi PASS; mcode FAIL: it also made fractions multi-digit (a real, disclosed fix) and updated the expected output, but agent edits to test files are discarded, so PatchEval rewards minimal fixes.

- Runs before 2026-11-02 were graded with the original test (all six models failed `pygments-2828`).
  The report re-grades them as passes through `reports/patcheval-regrades.json` (task, arms, new outcome,
  evidence); raw BenchKit results stay unchanged, and the report shows the original score next to the
  corrected one and marks re-graded cells with `*`. New runs on `pilot-20-local1` need no re-grade.
- To re-grade another flawed task later: build the fixed hidden test, check it in Docker `--network none`
  against the unfixed code (must fail), the upstream fix (must pass) and each saved patch
  (`workspace.patch` in `results.json`, applied without test files), then add an entry to `patcheval-regrades.json`.
- If BenchKit publishes a fixed release, switch to it and drop the copy.

## 8. Local BenchKit patches (uncommitted in `benchkit-src/BenchKit`)

| Setting / file | What it does |
|---|---|
| `BENCHKIT_PI_MODEL` (JSON) | merged into pi's model entry in the sandbox: `maxTokens`, `reasoning`, `thinkingLevelMap`, `compat` |
| `BENCHKIT_PI_THINKING` | passes `--thinking <level>` to pi |
| `BENCHKIT_AGENT=mcode` + `BENCHKIT_MCODE_*` | runs mcode instead of pi (`mcode_agent.py`) |
| `call_usage` per task | tokens and stop reason of every assistant reply (enables the 16k-cap score) |
| `upstream_calls` per task | the proxy records provider, exact cost, tokens, time to first token, decode tok/s per request |

All in `results.json` per task. Restore after a BenchKit update:
`cd benchkit-src/BenchKit && git apply ../../benchkit-local-patches.diff` (re-export it after changing the code:
`{ git diff; git diff --no-index /dev/null src/benchkit/mcode_agent.py; } > ../../benchkit-local-patches.diff`).
BenchKit pins **pi 0.84.2** in the sandbox (not your 1.4.0); changing `PI_PACKAGE`/`PI_VERSION` and the
lockfile in `src/benchkit/pi_package/` changes the agent for every later run, so re-run the baselines too.

## 9. Watch, stop, resume

- Run in the background (`setsid nohup ... &`), and arm a watchdog that reports each task line, a STALL when
  the log has not changed for 40 min (30 min task + build), and the end (`Saved:`). Re-arm it when it expires.
- Two runs can share the machine (each has its own builder and network); MiniMax-style runs that always
  use the full 30 min make the laptop the bottleneck only for local models.
- **Stop with exactly one SIGINT** to the `benchkit` python process: it finishes cleanly and saves every
  completed task. A second SIGINT aborts and saves nothing. `patcheval-handoff.sh <run>` does this at a task
  boundary and starts the remaining slice (`patcheval:N-20`) under the label `...-fromN`.
- Re-run a single task (for example after a harness error): `SLICE=patcheval:<index>-<index+1>`.

## 10. After a run: update the report

1. Find the result folder(s): `grep '^Saved:' benchkit-patcheval-<label>*.log`
   (folders are in `benchkit-src/BenchKit/results/`).
2. Add one entry to `reports/patcheval-arms.json`, in ranking position: `key`, `short`, `harness`
   (with version), `model`, `think`, `cap`, `runtime`, `cost` (hosted: from the balance endpoints above),
   optional `status` (unfinished run, shown but not ranked), and `dirs` (all folders of a resumed run;
   later folders replace only harness errors).
3. Rebuild and render:

```bash
python3 reports/build_patcheval_data.py && python3 reports/make_patcheval_report.py \
  && python3 reports/make_patcheval_charts.py   # charts: reports/patcheval-charts.html + reports/charts/*.svg
```

A new arm also needs a `FAMILY` and `LABEL` entry (and label placement in `OFFSETS`) in
`reports/make_patcheval_charts.py`; the script stops and names any arm that is missing.

4. Edit the prose in `reports/make_patcheval_report.py` when the ranking or story changes: `DATE`,
   `TAKEAWAYS`, `FAIRNESS`, `FAILURES`, `OTHER_RUNS`, and the four overview `cards` in `build_html`.
   Rename the output if you want a new dated report (`stem` at the bottom).
5. Check the HTML (light/dark, phone width), e.g. `chromium --headless=new --screenshot=... file://...html`.
6. Update `README.md`'s status line and this runbook's numbers if they moved.

## 11. Gotchas (all hit at least once)

- `cp` and `mv` are aliased to prompt in this shell: use `command cp -f` in scripts, `< /dev/null` for stdin.
- A full disk shows up as a harness error ("Docker buildx failed"); free space and re-run that task.
- `pgrep -f <pattern>` also matches the shell running it: use `pgrep -f "[b]enchkit ..."`.
- Gateway routing changes per request: OpenRouter served DeepSeek from Sail Research and InferenceNet,
  Vercel served MiniMax from Fireworks or MiniMax. Speed numbers mix providers (see `upstream_calls`).
- OpenRouter bills the 1017 snapshot as `deepseek/deepseek-v4.1-flash-20261017`; its dashboard day is UTC.
- Code from task archives is untrusted: inspect or test it only inside Docker with `--network none`.
