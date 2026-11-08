#!/usr/bin/env bash
# Context ALLOCATION sweep: how much context can be reserved, and what it costs.
#
# Measures TG with a near-empty KV, so it answers "can I allocate this context"
# — NOT "how fast is it once full". For the latter use llama-bench-occupied-ctx.py.
# Both numbers are needed; conflating them is the trap section 4 warns about.
#
# Records the context the server ACTUALLY settled on (via /props): llama-server's
# `--fit on` silently auto-reduces (it cut 262144 -> 8192 for Qwen3.6-35B-A3B),
# and a reduced run must not masquerade as a passing one.
#
# Servers are tracked by PID and killed by PID. Never use `pkill -f` here: the
# pattern also matches the harness/agent wrapper's own command line and kills it.
#
# Usage:
#   MODEL=/path/model.gguf ./llama-bench-ctx-sweep.sh
#   MODEL=... CONTEXTS="8192 32768" EXTRA="--cpu-moe" ./llama-bench-ctx-sweep.sh
set -uo pipefail

MODEL="${MODEL:?set MODEL=/path/to/model.gguf}"
BIN="${BIN:-/home/sum/.unsloth/llama.cpp/llama-server}"
CONTEXTS="${CONTEXTS:-8192 32768 65536 131072}"
KV="${KV:-q8_0}"
EXTRA="${EXTRA:-}"
PORT="${PORT:-8099}"
OUT="${OUT:-/tmp/ctx-sweep-$$}"
mkdir -p "$OUT"

probe() {
  local ctx="$1" pid ready=0 i actual vram tg
  # shellcheck disable=SC2086 # EXTRA is intentionally word-split
  "$BIN" -m "$MODEL" --port "$PORT" --parallel 1 \
      --flash-attn on --no-context-shift -c "$ctx" \
      -ctk "$KV" -ctv "$KV" --fit on --metrics --kv-unified --jinja $EXTRA \
      > "$OUT/sweep-$ctx.log" 2>&1 &
  pid=$!

  # Big models mmap slowly on first touch; allow 10 min.
  for i in $(seq 1 120); do
    curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q ok && { ready=1; break; }
    kill -0 "$pid" 2>/dev/null || break
    sleep 5
  done

  if [ "$ready" -ne 1 ]; then
    echo "$ctx|SERVER_FAILED|-|-"
    grep -iE 'error|failed|out of memory|auto-reduced' "$OUT/sweep-$ctx.log" | tail -2 >&2
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; sleep 3
    return 1
  fi

  actual=$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/props" 2>/dev/null \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('default_generation_settings',{}).get('n_ctx','?'))" 2>/dev/null)
  vram=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null)

  curl -sS --max-time 600 "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' \
    -d '{"prompt":"hi","n_predict":16,"temperature":0}' -o /dev/null

  curl -sS --max-time 900 "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' \
    -d '{"prompt":"write a minimal staking contract in Solidity","n_predict":256,"temperature":0,"ignore_eos":true}' \
    -o "$OUT/sweep-$ctx.json"

  tg=$(python3 -c "
import json
try:
    t=json.load(open('$OUT/sweep-$ctx.json'))['timings']
    print(f\"{t['predicted_per_second']:.2f}\")
except Exception:
    print('ERR')
")
  echo "$ctx|$actual|$tg|$vram"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; sleep 4
}

echo "# model: $MODEL"
echo "# bin:   $BIN"
echo "# KV:    $KV   extra: ${EXTRA:-none}"
echo "requested|actual_n_ctx|TG t/s|VRAM"
for c in $CONTEXTS; do probe "$c"; done
