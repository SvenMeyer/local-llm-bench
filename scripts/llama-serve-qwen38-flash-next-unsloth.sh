#!/usr/bin/env bash
# Unsloth Desktop / Studio launcher for Qwen3.8-Flash-Next
# (GSQ-RCO Q2_0 by default since 2026-09-27; QUANT=iq4xs for Unsloth UD-IQ4_XS).
#
# Why this script exists:
#   - `unsloth run` defaults server-side tools ON (web search, code exec).
#     That intercepts Pi/agent tool calls. --disable-tools is a process
#     flag, not a persisted Desktop setting, so it lives here.
#   - Model Memory toggles are GLOBAL. Both-on is mmap + no host copy.
#     Full RAM load needs them OFF, plus:
#       --load-mode none   (no mmap for ordinary tensors)
#       --lazy-mode off    (PLE/n-gram table is NOT streamed from SSD)
#   - Live engine is the official mix-pr220 MTP pin (unslothai/llama.cpp#220,
#     #144@ca1426903), not the stock b11007/b11027-mix-3e83366 abort. To
#     enable MTP: MTP=1 (drops token_embd.weight=CPU, which breaks the
#     shared draft head).
#   - Q2_0 needs the engine with the x86 Q2_0 kernel (mix-pr220-q2_0, 11170)
#     or its experts run scalar. Studio only attaches an MTP drafter found in
#     the model's own dir, so the GSQ dir holds a symlink to Unsloth's
#     mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf.
#
# Full write-up: llama-qwen38-flash-next-unsloth.md
# Usage: MTP=1 LLAMA_ARG_CTX_SIZE=16384 ./llama-serve-qwen38-flash-next-unsloth.sh
#        QUANT=iq4xs MTP=1 LLAMA_ARG_CTX_SIZE=16384 ./llama-serve-qwen38-flash-next-unsloth.sh
# Extra llama-server flags pass through, last-wins.

set -euo pipefail

MODELS=/home/sum/.cache/lm-studio/models
# Studio 2026.10.5+ passes --ubatch-size 2048 (Sept builds used the 512 default).
# Q2_0 keeps it (PP ~300 vs ~180 t/s); UD-IQ4_XS + MTP OOMs at 2048, so cap it.
UB_ARGS=()
case "${QUANT:-q2_0}" in
    q2_0)  DEF_MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf
           DEF_VARIANT=Q2_0 ;;
    iq4xs) DEF_MODEL=$MODELS/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf
           DEF_VARIANT=UD-IQ4_XS
           UB_ARGS=(--ubatch-size 1024) ;;
    gsq-iq3xxs) DEF_MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
           DEF_VARIANT=IQ3_XXS ;;
    # GSQ Coder: 256 of 512 experts kept (code/agentic/vision); the file is labelled IQ1_M.
    coder) DEF_MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-00001-of-00002.gguf
           DEF_VARIANT=IQ1_M ;;
    *) echo "QUANT must be q2_0, iq4xs, gsq-iq3xxs or coder" >&2; exit 1 ;;
esac
MODEL="${LLAMA_ARG_MODEL:-$DEF_MODEL}"
CTX="${LLAMA_ARG_CTX_SIZE:-8192}"
PORT="${LLAMA_ARG_PORT:-8888}"
HOST="${LLAMA_ARG_HOST:-127.0.0.1}"
# Label only; must match the GGUF.
VARIANT="${VARIANT:-$DEF_VARIANT}"
# MTP=1: draft-mtp n_max 3 and token_embd stays on GPU (the shared draft head
# borrows it). MTP=0: token_embd pushed to CPU to save VRAM.
if [[ "${MTP:-0}" == "1" ]]; then
    SPEC_ARGS=(--speculative-type mtp --spec-draft-n-max 3 --spec-draft-cpu-moe)
else
    SPEC_ARGS=(--speculative-type off --override-tensor token_embd.weight=CPU)
fi

exec unsloth run \
    --model "$MODEL" \
    --gguf-variant "$VARIANT" \
    --max-seq-length "$CTX" \
    --parallel 1 \
    --gpu-memory-mode auto \
    "${SPEC_ARGS[@]}" \
    --disable-tools \
    --api-only \
    --host "$HOST" \
    --port "$PORT" \
    --cpu-moe \
    --n-gpu-layers 999 \
    --flash-attn on \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --threads 10 \
    --jinja \
    --no-mmproj \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --load-mode none \
    --lazy-mode off \
    "${UB_ARGS[@]}" \
    "$@"
