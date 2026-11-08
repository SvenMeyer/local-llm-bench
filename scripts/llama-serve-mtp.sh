#!/usr/bin/env bash
# Launcher for Qwen3.6-35B-A3B-MTP with MTP speculative decoding enabled.
# This GGUF has a real MTP head baked in (nextnPredictLayers=1, confirmed via
# LM Studio's gguf-metadata-cache.json) — Ornith's GGUF does not, so it uses
# llama-serve.sh instead.
#
# Same env-var override pattern as llama-serve.sh, e.g.:
#   LLAMA_ARG_MODEL=/path/to/other-mtp-model.gguf ./llama-serve-mtp.sh

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-Q6_K.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-qwen3.6-35b-a3b-mtp}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

# Same memory profile as the Ornith launcher (same qwen35moe family, same
# 8GB-VRAM laptop GPU) — MoE experts on CPU, everything else on GPU, q8 KV cache.
export LLAMA_ARG_CPU_MOE="${LLAMA_ARG_CPU_MOE:-1}"
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"

# Ornith's full 262144 (256k) native context does NOT fit here even though it's
# the same architecture: this quant is an "UD" (unsloth dynamic) build that
# keeps attention/output layers at higher precision, and has one extra layer
# for the MTP head — both stay on GPU, so the always-resident footprint is
# bigger. At 262144 this OOM'd mid-generation with zero headroom for the
# compute buffer (verified: crashed here on 2026-07-15). 131072 (128k) leaves
# ~2GB free and confirmed working, MTP draft acceptance included.
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-131072}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

# MTP speculative decoding: uses the model's own MTP head, no separate draft model.
export LLAMA_ARG_SPEC_TYPE="${LLAMA_ARG_SPEC_TYPE:-draft-mtp}"

# --no-mmproj: harmless here (mmproj auto-load only triggers in -hf/remote
# mode per the server README, not for a local -m path like this one) but kept
# as a safety net in case that changes.
exec llama-server \
  --jinja \
  --no-mmproj \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  "$@"
