#!/usr/bin/env bash
# Launcher for Bonsai 27B (dense qwen35 arch, NOT MoE -- no --cpu-moe needed).
# Q1_0 quant, ~4.7GB total incl. mmproj, fits fully on GPU with room to spare.
# Memory profile: LM Studio's saved default config for this model only sets
# kCache/vCache to q8_0 -- no GPU-layer override, meaning full GPU offload.

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/prism-ml/Bonsai-27B-gguf/Bonsai-27B-Q1_0.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-bonsai-27b}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"
# 262144 (the model's native max) OOM'd here: dense 27B model, so unlike the
# MoE models the KV cache scales with the FULL param count's attention shape,
# not just the ~3B active experts. 32768 confirmed working with ~2.3GB headroom.
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-32768}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

# No speculative decoding for Bonsai: prism-ml's "DSpark" drafter needs a
# separate incompatible fork (PrismML-Eng/llama.cpp) that mainline can't load
# ("unknown model architecture: 'dspark'"). Evaluated 2026-07-15 and decided
# against building it -- independent benchmarks on the real (mainline-track)
# DSpark PR show it net-slower than vanilla on non-datacenter GPUs, plus an
# active silent correctness bug in the shared draft path. See llama.cpp-test.sh
# for the full writeup. Drafter file removed; ~2.3GB VRAM headroom is spare.

exec llama-server \
  --jinja \
  --no-mmproj \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  "$@"
