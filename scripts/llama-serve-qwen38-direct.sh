#!/usr/bin/env bash
# Run Qwen3.8-Flash-Next on any llama-server build WITHOUT Unsloth Studio,
# using the same argv Studio passes (captured 2026-10-26 from Studio 2026.10.5).
# For engine A/B and context sweeps: Studio's own engine dir stays untouched.
#
# Usage:
#   BIN=~/.unsloth/llama.cpp-b11876-stock/bin ./llama-serve-qwen38-direct.sh
#   QUANT=iq4xs CTX=65536 UB=512 ./llama-serve-qwen38-direct.sh
#   MTP=0 ...   (no draft; token_embd stays on GPU unless extra -ot is passed)
# Then: SKIP_RELOAD=1 ./llama-bench-qwen38-unsloth-occupied.sh   (port 8099)
# Extra llama-server flags pass through, last-wins.
set -euo pipefail

BIN="${BIN:-$HOME/.unsloth/llama.cpp/build/bin}"
MODELS=/home/sum/.cache/lm-studio/models
case "${QUANT:-q2_0}" in
    q2_0)  MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00001-of-00002.gguf
           DEF_UB=2048 ;;
    iq4xs) MODEL=$MODELS/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf
           DEF_UB=1024 ;;
    gsq-iq3xxs) MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
           DEF_UB=2048 ;;
    coder) MODEL=$MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-00001-of-00002.gguf
           DEF_UB=2048 ;;
    *) echo "QUANT must be q2_0, iq4xs, gsq-iq3xxs or coder" >&2; exit 1 ;;
esac
CTX="${CTX:-16384}"
UB="${UB:-$DEF_UB}"
PORT="${PORT:-8099}"
DRAFT=$MODELS/unsloth/Qwen3.8-Flash-Next-GGUF/mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf
SPEC_ARGS=()
[[ "${MTP:-1}" == "1" ]] && SPEC_ARGS=(--model-draft "$DRAFT" --spec-type draft-mtp
                                       --spec-draft-n-max 3 --spec-draft-cpu-moe)

exec "$BIN/llama-server" \
    -m "$MODEL" \
    --host 127.0.0.1 --port "$PORT" \
    --parallel 1 --no-context-shift \
    -c "$CTX" --fit on --fit-ctx "$CTX" \
    --metrics \
    "${SPEC_ARGS[@]}" \
    --reasoning on --chat-template-kwargs '{"preserve_thinking": true}' \
    --cpu-moe --n-gpu-layers 999 \
    --flash-attn on \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --threads 10 \
    --jinja --no-mmproj \
    --temp 1.0 \
    --load-mode none --lazy-mode off \
    --ubatch-size "$UB" \
    "$@"
