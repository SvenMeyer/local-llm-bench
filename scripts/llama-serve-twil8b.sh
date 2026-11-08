#!/usr/bin/env bash
# llama-server launcher for webAI TwIL-8B (Granite 4.2 dense, balanced variant)
# on stock llama.cpp (/usr/local/bin/llama-server -> llama.cpp/build/bin).
# Every setting is an env var override, e.g.:
#   LLAMA_ARG_CACHE_TYPE_K=q4_0 LLAMA_ARG_CACHE_TYPE_V=q4_0 ./llama-serve-twil8b.sh
# --fit (on by default) only fills values left unset; check the log for
# "offloaded N/41 layers to GPU" to see whether everything stayed on the GPU.

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/mradermacher/TwIL-8B-i1-GGUF/TwIL-8B.i1-Q4_K_M.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-twil-8b}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

# Dense 8.8B. GPU layers are left to --fit (forcing -ngl 999 disables it, and
# 32k ctx at q8_0 KV then OOMs by ~200 MB). Set LLAMA_ARG_N_GPU_LAYERS to force.
# KV memory: 40 layers x 8 KV heads x 128 dim = ~85 KiB/token q8_0, ~45 KiB q4_0.
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
# Measured 2026-11-06 (b12169, 35 W): KV type does not change speed (q8_0, q4_0,
# mixed within 3% at 16k/24k depth). It only decides what fits with all layers on GPU:
#   q4_0/q4_0 -> 40k   (default; ~+0.4% PPL on Bonsai 2)
#   q8_0/q8_0 -> 24k   (near-lossless): LLAMA_ARG_CACHE_TYPE_K=q8_0 LLAMA_ARG_CACHE_TYPE_V=q8_0 LLAMA_ARG_CTX_SIZE=24576
# Reasoning model: the card asks for a large budget (-c 40960; ~19.5k tokens per AIME problem).
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q4_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q4_0}"
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-40960}"
# --fit keeps 1024 MiB spare by default; this GPU drives no display, so 512 is enough
# and is what lets 40k stay fully on the GPU.
export LLAMA_ARG_FIT_TARGET="${LLAMA_ARG_FIT_TARGET:-512}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

# Sampling from the model's generation_config.json (temperature 1.0, top_p 0.95).
exec llama-server \
  --jinja \
  --temp 1.0 \
  --top-p 0.95 \
  "$@"
