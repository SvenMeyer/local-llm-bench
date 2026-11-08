#!/usr/bin/env bash
# TwIL-8B fit + speed test on stock llama.cpp.
# Per KV arm: (1) start llama-serve-twil8b.sh at 32k, read --fit result and VRAM,
# stop it; (2) llama-bench PP512/TG128 at depth 0 / 8k / 16k / 24k (equal ctx across arms).
# Usage: ./llama-twil8b-fit-bench.sh [q8_0 q4_0 ...]
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
MODEL="${MODEL:-/home/sum/.cache/lm-studio/models/mradermacher/TwIL-8B-i1-GGUF/TwIL-8B.i1-Q4_K_M.gguf}"
TS=$(date +%Y%m%d-%H%M%S)
OUT=llama-twil8b-fit-bench-$TS.txt
ARMS=("${@:-q8_0}")
echo "TwIL-8B fit+bench $TS  model=$(basename "$MODEL")  build=$(llama-server --version 2>&1 | grep -o 'build [0-9]*')" | tee "$OUT"

for KV in "${ARMS[@]}"; do
    LOG=llama-serve-twil8b-$KV-32k-$TS.log
    echo "== arm KV=$KV ctx=32768" | tee -a "$OUT"
    LLAMA_ARG_MODEL="$MODEL" LLAMA_ARG_CACHE_TYPE_K=$KV LLAMA_ARG_CACHE_TYPE_V=$KV \
        ./llama-serve-twil8b.sh > "$LOG" 2>&1 &
    SPID=$!
    if ./llama-wait-ready.sh 8080 180 | tee -a "$OUT"; then
        grep -E "offloaded [0-9]+/[0-9]+ layers|n_ctx *=|KV buffer size|CUDA0 compute buffer|model buffer size" "$LOG" | sed 's/^/  /' | tee -a "$OUT"
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | sed 's/^/  VRAM /' | tee -a "$OUT"
    else
        echo "  server failed, tail:" | tee -a "$OUT"; tail -15 "$LOG" | tee -a "$OUT"
    fi
    kill $SPID 2>/dev/null; wait $SPID 2>/dev/null
    until ! pgrep -x llama-server >/dev/null; do sleep 1; done

    /home/sum/Downloads/AI-Runtime/llama.cpp/build/bin/llama-bench -m "$MODEL" -ngl 99 -fa on -ctk $KV -ctv $KV -t 10 \
        -p 512 -n 128 -d 0,8192,16384,24576 -r 2 -o md 2>&1 | grep -E '^\|' | tee -a "$OUT"
done
echo "done $(date +%T) -> $OUT"
