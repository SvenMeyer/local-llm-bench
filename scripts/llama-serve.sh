#!/usr/bin/env bash
# Minimal-config launcher for llama-server.
# Every setting below is an env var override — e.g.:
#   LLAMA_ARG_MODEL=/path/to/other.gguf ./llama-serve.sh
# Anything not set here falls back to llama-server's own defaults,
# including --fit (auto GPU-layers/context sizing, on by default) —
# it only fills in values you leave unset below.

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/deepreinforce-ai/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-ornith-1.0-35b}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

# Memory profile below is copied from LM Studio's saved load config for this
# model (.internal/user-concrete-model-default-config/deepreinforce-ai/...),
# tested working at ~6GB VRAM with the full 262144-token (256k) native context.
export LLAMA_ARG_CPU_MOE="${LLAMA_ARG_CPU_MOE:-1}"          # all MoE expert tensors -> CPU RAM
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"  # everything else -> GPU
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-262144}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

# Sampling: kept close to your previous values, plus --top-k as an unverified
# suggestion for this Qwen-family MoE model. Adjust freely.
exec llama-server \
  --jinja \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  "$@"
