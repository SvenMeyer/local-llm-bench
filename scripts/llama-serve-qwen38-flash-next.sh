#!/usr/bin/env bash
# Launcher for Qwen3.8-Flash-Next (unsloth UD-IQ4_XS) -- "A Preview of the Qwen4
# Architecture", llama.cpp arch `qwen4exp`.
#
# Full reasoning behind every flag here: llama-run-guide.md
# Open questions / what still needs measuring: llama-todo.md Supported in mainline since
# ggml-org/llama.cpp#27742 (Aug 2026) plus a run of follow-up fixes; our old
# b10016 build predates it and cannot load this model at all.
#
# Shape (from the GGUF metadata, not the model card):
#   48 blocks, n_embd 2560, native ctx 262144
#   12 x (3 x Gated-DeltaNet -> MoE) + 1 x (Qwen Sparse Attention -> MoE)
#     -> only every 4th layer (full_attention_interval=4) has a real KV cache;
#        the other 36 are recurrent, so KV cost is ~1/4 of a dense 48L model.
#   MoE: 512 experts, 10 routed + 1 shared, expert FFN 640
#   QSA: 24 Q heads / 2 KV heads, head_dim 256, indexer 4 heads x 128, top_k 2048
#   PLE: 3-gram, 16 heads x ~20M rows x 160 dims = 51B params of lookup table
#
# Disk 93.7GB, but resident RAM is much lower than that -- see the mmap note.

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-qwen3.8-flash-next}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

# Offload split. Measured from the GGUF tensor table:
#   per layer, non-expert tensors ~71MB (attn_qkv 28 + attn_gate 17 + hc_* 14 +
#   shexp 5 + ffn_gate_inp 5 + ssm ~2) -> ~3.4GB over 48 layers
#   + output.weight (Q6_K) 521MB  = ~3.9GB resident on the 8GB card
#   the *_exps tensors are 57GB (IQ3_S gate/up + IQ4_NL down) -> must be CPU
export LLAMA_ARG_CPU_MOE="${LLAMA_ARG_CPU_MOE:-1}"      # all 512 routed experts -> CPU RAM
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"

# token_embd is a GET_ROWS lookup -- 676MB of VRAM for a table we touch a
# handful of rows of per batch. Pushing it to CPU buys ~0.7GB of KV headroom
# for free. output.weight stays on GPU (it is a real matmul every token).
export LLAMA_ARG_OVERRIDE_TENSOR="${LLAMA_ARG_OVERRIDE_TENSOR:-token_embd.weight=CPU}"

# per_layer_token_embd (the 28.8GB n-gram table) needs NO override: llama.cpp
# creates it with TENSOR_READ_LAZY -- "read rows on demand instead of loading
# whole tensor; requires mmap". It is paged in from the SSD per lookup, so only
# the hot rows ever become resident. Consequence: do NOT pass --no-mmap and do
# NOT pass --mlock, either one turns 93.7GB into a real allocation.

# Context. KV is ~13KB/token (12 QSA layers x 2 kv heads x 256 x K+V @ q8_0)
# plus ~12KB/token for the sparse-attention indexer cache. ~2.5-3GB of KV
# headroom after weights => ~64-128k. Starting conservative; 262144 native
# almost certainly will not fit on 8GB (cf. the Qwen3.6-MTP OOM, 2026-07-15).
export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-65536}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

# MTP is NOT enabled here. mtp-Qwen3.8-Flash-Next-shared-*.gguf only works on
# ggml-org/llama.cpp#28243, still OPEN as of 2026-09-17 -- on a stock mainline
# build passing -md does nothing at all (upstream has no MTP graph for
# qwen4exp). See llama.cpp-test.sh for the separate MTP worktree.

# Sampling: Qwen3.8 thinking-mode defaults from the model card. Note temp 1.0,
# min-p 0.0 -- NOT the temp 0.6 / min-p 0.05 we use for the Qwen3.5/3.6 models.
exec llama-server \
    --jinja \
    --no-mmproj \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 0.0 \
    "$@"
