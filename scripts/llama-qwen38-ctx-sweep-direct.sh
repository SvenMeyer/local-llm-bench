#!/usr/bin/env bash
# Max-context probe for Qwen3.8 via llama-serve-qwen38-direct.sh: for each CTX,
# load once, check n_ctx, run a SHORT prompt (the case that CUDA-OOMed the
# decode graph at 64k+MTP in September), report VRAM, stop. One load per CTX.
#
# Usage: QUANT=iq4xs UB=512 CTXS="65536 98304 131072" ./llama-qwen38-ctx-sweep-direct.sh [extra flags]
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
CTXS="${CTXS:-65536 98304 131072}"
OUT="${OUT:-llama-ctx-sweep-qwen38-${QUANT:-q2_0}-$(date +%Y%m%d-%H%M%S).log}"
echo "# QUANT=${QUANT:-q2_0} UB=${UB:-def} MTP=${MTP:-1} BIN=${BIN:-studio} extra: $*" | tee -a "$OUT"
for CTX in $CTXS; do
    pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || break; sleep 1; done
    log=llama-serve-qwen38-sweep-$CTX.log
    CTX=$CTX setsid nohup ./llama-serve-qwen38-direct.sh "$@" > "$log" 2>&1 < /dev/null &
    if ! r=$(./llama-wait-ready.sh 8099 240); then
        echo "$CTX | LOAD FAILED: $r | $(grep -m1 -oE 'cudaMalloc failed.*|allocating [0-9.]+ MiB on device 0' "$log")" | tee -a "$OUT"
        continue
    fi
    nctx=$(curl -s http://127.0.0.1:8099/props | python3 -c "import json,sys; print(json.load(sys.stdin)['default_generation_settings']['n_ctx'])")
    idle=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader)
    res=$(curl -s --max-time 120 http://127.0.0.1:8099/completion -H 'Content-Type: application/json' \
          -d '{"prompt":"Write one sentence about the sea.","n_predict":64,"temperature":1.0,"min_p":0}' \
          | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); t=d['timings']; print('ok TG %.2f' % t['predicted_per_second'])
except Exception as e: print('FAILED', e)")
    alive=$(pgrep -x llama-server >/dev/null && echo alive || echo DIED)
    echo "$CTX | n_ctx $nctx | idle $idle | after $(nvidia-smi --query-gpu=memory.used --format=csv,noheader) | short prompt: $res | $alive" | tee -a "$OUT"
done
pkill -TERM -x llama-server
echo "# done $(date -Iseconds)" | tee -a "$OUT"
