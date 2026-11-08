#!/usr/bin/env bash
# Measure Ternary-Bonsai-2-27B PTQ1_0 (1-bit) and PQ2_0 (2-bit) on this box.
# Prism llama.cpp only. llama-bench first, then llama-server ctx + occupied.
#
# Usage:
#   ./llama-bench-ternary-bonsai2.sh
#   QUANT=PTQ1_0 ./llama-bench-ternary-bonsai2.sh   # one pack only
set -euo pipefail

ROOT="${ROOT:-/home/sum/Downloads/AI-Runtime}"
BIN_DIR="${BIN_DIR:-$ROOT/llama.cpp-prism/build/bin}"
BENCH="$BIN_DIR/llama-bench"
SERVER="$BIN_DIR/llama-server"
CLI="$BIN_DIR/llama-cli"
MODEL_DIR="${MODEL_DIR:-/home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf}"
PORT="${PORT:-8099}"
OUT="${OUT:-$ROOT/llama-bench-ternary-bonsai2-$(date +%Y%m%d-%H%M%S).log}"
QUANT="${QUANT:-BOTH}"
THREADS="${THREADS:-10}"
NPREDICT="${NPREDICT:-128}"
SRC="${SRC:-$ROOT/llama.cpp-prism/src}"
SKIP_BENCH="${SKIP_BENCH:-}"
SKIP_SMOKE="${SKIP_SMOKE:-1}"

PTQ="$MODEL_DIR/Ternary-Bonsai-2-27B-PTQ1_0.gguf"
PQ2="$MODEL_DIR/Ternary-Bonsai-2-27B-PQ2_0.gguf"

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds) profile=$(powerprofilesctl get 2>/dev/null || echo unknown)"
echo "# bin $BIN_DIR"
"$SERVER" --version || true
"$BENCH" --version || true
echo "# gpu $(nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,power.limit --format=csv,noheader)"
free -h | awk 'NR<=2'
echo

fail() { echo "FAILED: $*"; exit 1; }
[[ -x "$BENCH" && -x "$SERVER" ]] || fail "prism binaries missing in $BIN_DIR"

models=()
case "$QUANT" in
  BOTH|both) models+=("PTQ1_0:$PTQ" "PQ2_0:$PQ2") ;;
  PTQ1_0|ptq1_0|1) models+=("PTQ1_0:$PTQ") ;;
  PQ2_0|pq2_0|2) models+=("PQ2_0:$PQ2") ;;
  *) fail "QUANT=$QUANT" ;;
esac

kill_port() {
  local p pid
  p=$(ss -ltnp "sport = :$PORT" 2>/dev/null | awk -Fpid= '/pid=/{print $2}' | cut -d, -f1 | head -1 || true)
  if [[ -n "${p:-}" ]]; then
    echo "# kill leftover pid $p on :$PORT"
    kill "$p" 2>/dev/null || true
    sleep 2
    kill -9 "$p" 2>/dev/null || true
    sleep 1
  fi
  pid=$(pgrep -f "$BIN_DIR/llama-server" | head -1 || true)
  if [[ -n "${pid:-}" ]]; then
    echo "# kill leftover llama-server $pid"
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
    sleep 1
  fi
}

wait_health() {
  local pid="$1" log="$2" i
  for i in $(seq 1 90); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q ok; then
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 2
  done
  return 1
}

server_props() {
  curl -fsS --max-time 5 "http://127.0.0.1:$PORT/props" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); g=d.get('default_generation_settings',{}); print(g.get('n_ctx','?'), g.get('n_gpu_layers', g.get('n_gpu_layer','?')))"
}

run_bench() {
  local label="$1" model="$2"
  echo "===== llama-bench $label ====="
  echo "# $(date -Iseconds)"
  echo "# gpu before: $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)"
  if ! "$BENCH" -m "$model" -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -t "$THREADS" -p 512 -n 128 -r 3; then
    echo "# llama-bench ngl99 failed for $label; retrying -ngl 80"
    "$BENCH" -m "$model" -ngl 80 -fa on -ctk q8_0 -ctv q8_0 -t "$THREADS" -p 512 -n 128 -r 3 || echo "# llama-bench failed for $label"
  fi
  echo "# gpu after: $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)"
  echo
}

smoke_cli() {
  local label="$1" model="$2"
  echo "===== smoke llama-cli $label ====="
  # New llama-cli is a chat REPL. Without --single-turn it waits on stdin
  # and looks like a loaded-but-idle GPU. Force one shot, no stdin.
  "$CLI" -m "$model" -ngl 99 -fa on -c 2048 -n 64 -t "$THREADS" --no-warmup \
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --no-display-prompt \
    --reasoning-budget 0 --single-turn --no-jinja \
    -p "Explain what a merkle tree is in two sentences." \
    </dev/null \
    || echo "# smoke cli failed for $label"
  echo
}

start_server() {
  local label="$1" model="$2" ctx="$3" kv="$4"
  local log="$ROOT/llama-serve-bonsai2-$label-c${ctx}-${kv}.log"
  kill_port
  echo "===== server $label -c $ctx kv=$kv ====="
  echo "# log $log"
  "$SERVER" -m "$model" --host 127.0.0.1 --port "$PORT" \
    -ngl 99 -fa on -c "$ctx" -ctk "$kv" -ctv "$kv" \
    --jinja --no-mmproj --fit off --parallel 1 --metrics \
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
    --threads "$THREADS" \
    >"$log" 2>&1 &
  local pid=$!
  echo "# pid $pid"
  if ! wait_health "$pid" "$log"; then
    echo "# SERVER_FAILED $label c=$ctx kv=$kv"
    grep -iE 'error|failed|out of memory|oom|GGML|unknown type' "$log" | tail -n 8 || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    sleep 2
    return 1
  fi
  local props vram
  props=$(server_props)
  vram=$(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)
  echo "# ready n_ctx/ngl: $props  vram: $vram"
  return 0
}

group_a() {
  echo "===== group A short /completion ====="
  PORT="$PORT" NPREDICT="$NPREDICT" python3 "$ROOT/llama-qwen38-group-a-mtp.py" || echo "# group A failed"
}

occupied() {
  local chars="$1"
  echo "===== occupied CHARS=$chars ====="
  PORT="$PORT" NPREDICT="$NPREDICT" CHARS="$chars" SRC="$SRC" \
    python3 "$ROOT/llama-bench-occupied-ctx.py" || echo "# occupied failed"
}

# Context sizes to try. Stop a KV series when a size fails to load.
try_ctxs() {
  local label="$1" model="$2" kv="$3"
  shift 3
  local ctx last_ok=""
  for ctx in "$@"; do
    if start_server "$label" "$model" "$ctx" "$kv"; then
      last_ok="$ctx"
      group_a
      # Occupied only at 8192 (compare vs Flash-Next Group C) and the largest
      # size that actually loaded. Auto-fit in the python probe on overflow.
      if [[ "$ctx" == "8192" || "$ctx" == "${*: -1}" ]]; then
        local half full
        half=$(( ctx * 7 / 4 ))
        full=$(( ctx * 7 / 2 ))
        occupied "2000,${half},${full}"
      fi
      kill_port
      sleep 3
    else
      echo "# stop $label kv=$kv at -c $ctx (last_ok=${last_ok:-none})"
      if [[ -n "$last_ok" && "$last_ok" != "8192" ]]; then
        if start_server "$label" "$model" "$last_ok" "$kv"; then
          local half full
          half=$(( last_ok * 7 / 4 ))
          full=$(( last_ok * 7 / 2 ))
          occupied "2000,${half},${full}"
          kill_port
          sleep 3
        fi
      fi
      break
    fi
  done
}

# Fit probe: let llama-server pick n_ctx for this VRAM, then occupied once.
fit_probe() {
  local label="$1" model="$2" kv="$3"
  local log="$ROOT/llama-serve-bonsai2-$label-fit-${kv}.log"
  kill_port
  echo "===== server $label --fit on kv=$kv (no -c) ====="
  "$SERVER" -m "$model" --host 127.0.0.1 --port "$PORT" \
    -ngl 99 -fa on -ctk "$kv" -ctv "$kv" \
    --jinja --no-mmproj --fit on --parallel 1 --metrics \
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
    --threads "$THREADS" \
    >"$log" 2>&1 &
  local pid=$!
  if ! wait_health "$pid" "$log"; then
    echo "# FIT_FAILED $label kv=$kv"
    grep -iE 'error|failed|out of memory|oom|auto-reduced' "$log" | tail -n 8 || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  echo "# fit n_ctx/ngl: $(server_props)  vram: $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)"
  group_a
  occupied "2000,7000,14000"
  kill_port
  sleep 3
}

for entry in "${models[@]}"; do
  label="${entry%%:*}"
  model="${entry#*:}"
  [[ -f "$model" ]] || fail "missing $model"
  echo
  echo "########## $label $(ls -lh "$model" | awk '{print $5}') ##########"
  if [[ "$SKIP_BENCH" == "1" || "$SKIP_BENCH" == "$label" ]]; then
    echo "# skip llama-bench for $label (SKIP_BENCH=$SKIP_BENCH)"
  else
    run_bench "$label" "$model"
  fi
  if [[ "$SKIP_SMOKE" == "1" ]]; then
    echo "# skip llama-cli smoke (interactive REPL; server Group A covers this)"
  else
    smoke_cli "$label" "$model"
  fi
  if [[ "$label" == "PTQ1_0" ]]; then
    try_ctxs "$label" "$model" q8_0 4096 8192 16384 32768 65536
    try_ctxs "$label" "$model" q4_0 32768 65536 131072
  else
    try_ctxs "$label" "$model" q8_0 2048 4096 8192 16384
    try_ctxs "$label" "$model" q4_0 8192 16384 32768
  fi
  fit_probe "$label" "$model" q8_0 || true
done

kill_port
echo "# gpu final: $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)"
echo "# done $(date -Iseconds)"
