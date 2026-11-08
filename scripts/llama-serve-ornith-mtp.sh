#!/usr/bin/env bash
# Launcher for Ornith-1.0-35B-Q6_K-MTP (wang-yang/Ornith-1.0-35B-MTP-GGUF).
# Community MTP graft onto deepreinforce-ai/Ornith-1.0-35B: same weights,
# same quant (Q6_K) as our plain Ornith, plus an MTP head grafted from
# Qwen/Qwen3.5-35B-A3B's official 1-layer MoE-MTP for --spec-type draft-mtp.
# Not deepreinforce-ai's own release -- verify quality vs plain Ornith
# before trusting it for real work, same as any third-party graft.

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/wang-yang/Ornith-1.0-35B-MTP-GGUF/Ornith-1.0-35B-Q6_K-MTP.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-ornith-1.0-35b-mtp}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

export LLAMA_ARG_CPU_MOE="${LLAMA_ARG_CPU_MOE:-1}"
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"

# Starting at 131072, not plain Ornith's 262144: the MTP head is an extra
# always-on-GPU layer (same pattern that OOM'd Qwen3.6-35B-A3B-MTP at full
# context). Untested at 262144 yet -- try it if you need the extra headroom,
# but don't be surprised if it needs dropping back down.
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-131072}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

export LLAMA_ARG_SPEC_TYPE="${LLAMA_ARG_SPEC_TYPE:-draft-mtp}"

exec llama-server \
  --jinja \
  --no-mmproj \
  --temp 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.05 \
  "$@"
