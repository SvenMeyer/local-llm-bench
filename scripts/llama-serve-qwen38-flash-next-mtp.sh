#!/usr/bin/env bash
# Qwen3.8-Flash-Next WITH MTP speculative decoding.
#
# Full reasoning behind every flag here: llama-run-guide.md (section 7)
# Open questions / what still needs measuring: llama-todo.md
#
# This deliberately does NOT use /usr/local/bin/llama-server. MTP for qwen4exp
# is ggml-org/llama.cpp#28243, still an OPEN pull request as of 2026-09-17 --
# mainline has no MTP graph for this arch and no cross-model tensor borrowing,
# so on the normal build `-md` is silently ignored and you get zero speedup with
# no warning. The PR lives in a worktree off the canonical repo:
#
#   git worktree add ../llama.cpp-mtp pr-28243-mtp   # refs/pull/28243/head
#
# When #28243 merges, delete this script and just add the -md/--spec-type flags
# to llama-serve-qwen38-flash-next.sh.

LLAMA_MTP_BIN="${LLAMA_MTP_BIN:-/home/sum/Downloads/AI-Runtime/llama.cpp-mtp/build/bin/llama-server}"

if [[ ! -x "$LLAMA_MTP_BIN" ]]; then
    echo "error: MTP build not found at $LLAMA_MTP_BIN" >&2
    echo "build it with the same flags as the main checkout:" >&2
    echo "  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON \\" >&2
    echo "        -DCMAKE_CUDA_ARCHITECTURES=89-real -DGGML_CUDA_FA_QUANTS=all -DGGML_CUDA_NCCL=OFF" >&2
    exit 1
fi

MODEL_DIR="/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF"

export LLAMA_ARG_MODEL="${LLAMA_ARG_MODEL:-$MODEL_DIR/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf}"
export LLAMA_ARG_ALIAS="${LLAMA_ARG_ALIAS:-qwen3.8-flash-next-mtp}"
export LLAMA_ARG_HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
export LLAMA_ARG_PORT="${LLAMA_ARG_PORT:-8080}"

# The draft head. We have shared-Q4_K_M (1.9GB); unsloth call shared-Q8_0
# (2.8GB) their fastest, but on 8GB VRAM the extra ~0.9GB is worth more to us as
# KV than as the ~2 points of acceptance they say it buys.
# "shared-" borrows token_embd + output.weight from the target model
# (qwen4exp.nextn_shared_target_tensors=True) instead of carrying its own.
export LLAMA_ARG_SPEC_DRAFT_MODEL="${LLAMA_ARG_SPEC_DRAFT_MODEL:-$MODEL_DIR/mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf}"
export LLAMA_ARG_SPEC_TYPE="${LLAMA_ARG_SPEC_TYPE:-draft-mtp}"

# unsloth's docs use 5, their own MTP README uses 2. Start at 3 and tune off the
# draft_n / draft_n_accepted numbers the server reports per response.
SPEC_DRAFT_N_MAX="${SPEC_DRAFT_N_MAX:-3}"

export LLAMA_ARG_CPU_MOE="${LLAMA_ARG_CPU_MOE:-1}"
export LLAMA_ARG_N_GPU_LAYERS="${LLAMA_ARG_N_GPU_LAYERS:-999}"
export LLAMA_ARG_THREADS="${LLAMA_ARG_THREADS:-10}"

# --cpu-moe does NOT reach the draft model: common_params_speculative carries
# its own tensor_buft_overrides list, separate from common_params. Without this
# second flag the head's ~1.8GB of blk.48.ffn_*_exps goes straight onto the 8GB
# card and blows the budget.
export LLAMA_ARG_SPEC_DRAFT_CPU_MOE="${LLAMA_ARG_SPEC_DRAFT_CPU_MOE:-1}"

# NOTE the difference from the non-MTP launcher: token_embd is left on the GPU
# here. The shared draft head borrows that exact tensor from the target model,
# so pushing it to CPU would drag the draft's embedding lookup onto the CPU
# every draft step. Costs ~0.68GB of KV budget -- hence the smaller default ctx.
# If MTP turns out not to care, re-add:
#   export LLAMA_ARG_OVERRIDE_TENSOR="token_embd.weight=CPU"
#
# --cpu-moe also matches the draft's own blk.48.ffn_*_exps (the head has a full
# 512-expert MoE of its own, ~1.8GB of its 1.9GB), so the head only costs about
# 100MB of VRAM. Drafting is one layer of expert compute against the target's
# 48, so it stays cheap even with those experts in RAM.

export LLAMA_ARG_CTX_SIZE="${LLAMA_ARG_CTX_SIZE:-32768}"
export LLAMA_ARG_CACHE_TYPE_K="${LLAMA_ARG_CACHE_TYPE_K:-q8_0}"
export LLAMA_ARG_CACHE_TYPE_V="${LLAMA_ARG_CACHE_TYPE_V:-q8_0}"
export LLAMA_ARG_FLASH_ATTN="${LLAMA_ARG_FLASH_ATTN:-on}"

exec "$LLAMA_MTP_BIN" \
    --spec-draft-n-max "$SPEC_DRAFT_N_MAX" \
    --jinja \
    --no-mmproj \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 0.0 \
    "$@"
