#!/usr/bin/env bash
# Ternary-Bonsai-2-27B on the PrismML llama.cpp fork.
# Default: PTQ1_0 (5.95 GB, faster Ada decode). Override:
#   QUANT=PQ2_0 ./llama-serve-ternary-bonsai2.sh
#   CTX=8192 KV=q4_0 ./llama-serve-ternary-bonsai2.sh
#
# Requires llama.cpp-prism (not mainline, not /usr/local/bin/llama-server).
# Vision projector is off: 8 GB VRAM is already tight on the 2-bit pack.
set -euo pipefail

ROOT="${ROOT:-/home/sum/Downloads/AI-Runtime}"
BIN="${BIN:-$ROOT/llama.cpp-prism/build/bin/llama-server}"
MODEL_DIR="${MODEL_DIR:-/home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf}"
QUANT="${QUANT:-PTQ1_0}"
case "$QUANT" in
  PTQ1_0|ptq1_0|1|1bit) MODEL="$MODEL_DIR/Ternary-Bonsai-2-27B-PTQ1_0.gguf"; ALIAS="${ALIAS:-bonsai2-27b-ptq1}" ;;
  PQ2_0|pq2_0|2|2bit)   MODEL="$MODEL_DIR/Ternary-Bonsai-2-27B-PQ2_0.gguf";  ALIAS="${ALIAS:-bonsai2-27b-pq2}" ;;
  *) echo "QUANT must be PTQ1_0 or PQ2_0, got $QUANT" >&2; exit 2 ;;
esac

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-$MODEL}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-$ALIAS}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-${PORT:-8099}}"
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-${NGL:-999}}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-${KV:-q8_0}}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-${KV:-q8_0}}"
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-${CTX:-8192}}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

if [[ ! -x "$BIN" ]]; then
  echo "missing $BIN — run llama-prism-build.sh first" >&2
  exit 1
fi
if [[ ! -f "$LLAMA_ARG_MODEL" ]]; then
  echo "missing model $LLAMA_ARG_MODEL" >&2
  exit 1
fi

exec "$BIN" \
  --jinja \
  --no-mmproj \
  --temp 1.0 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --fit off \
  --parallel 1 \
  "$@"
