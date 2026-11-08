#!/usr/bin/env bash
# Ornith-1.5-122B UD-Q4_K_XL on llama.cpp (Unsloth build), then BenchKit PatchEval through pi, same limits as the
# Qwen3.8 Strata runs (1800 s per task, 1 task at a time, Docker sandbox).
# Why llama.cpp: Strata 0.1.55's Qwen3.6-family path refuses this file ("blk.0.experts are IQ4_XS/Q4_K, which the
# native expert kernels do not take"; Unsloth's UD mix has IQ4_XS experts in 10 layers and one Q6_K layer).
# Fits the 8 GB card only at 32k context, q8_0 KV, experts on CPU, no MTP (MTP needs ~0.9 GB more VRAM: OOM).
# Smoke test 2026-11-01 02:05: correct tool call, ~10 t/s decode.
# Usage: setsid nohup ./patcheval-llamacpp-ornith.sh > patcheval-llamacpp-ornith-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
PORT=8099; LABEL=ornith15-udq4kxl-llamacpp
B=/home/sum/.unsloth/llama.cpp/build/bin
GGUF=/home/sum/.cache/lm-studio/models/unsloth/Ornith-1.5-122B-GGUF/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
OUT=benchkit-patcheval-$LABEL.log
SRV=llama-serve-$LABEL.log
say() { echo "[$(date +%H:%M:%S)] $*"; }
stop() { kill $(pidof llama-server) 2>/dev/null; pkill -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1"; }

say "# $LABEL start"
docker info >/dev/null 2>&1 || { say "STOP: Docker daemon not running"; exit 1; }
kill $(pidof llama-server) 2>/dev/null; sleep 3
setsid nohup $B/llama-server -m "$GGUF" --alias ornith-1.5-122b-ud-q4_k_xl --host 127.0.0.1 --port $PORT \
    -c 32768 -ctk q8_0 -ctv q8_0 --flash-attn on --cpu-moe -ngl 999 -t 10 -ub 512 \
    --jinja --no-mmproj --parallel 1 > $SRV 2>&1 < /dev/null &
until curl -s -m3 localhost:$PORT/health 2>/dev/null | grep -q '"ok"' || grep -q "exiting due" $SRV; do sleep 3; done
grep -q "exiting due" $SRV && { say "STOP: llama-server did not start"; tail -3 $SRV; exit 1; }
say "server ready, VRAM $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"

pgrep -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1" >/dev/null || \
    { setsid nohup socat TCP-LISTEN:$PORT,bind=172.17.0.1,reuseaddr,fork TCP:127.0.0.1:$PORT >/dev/null 2>&1 </dev/null & sleep 1; }
id=$(curl -s -m5 http://172.17.0.1:$PORT/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])') \
    || { say "STOP: docker bridge check failed"; stop; exit 1; }
say "=== $LABEL: PatchEval start (model $id, context 32768)"
(cd $BK && BENCHKIT_PI_TIMEOUT=1800 BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:$PORT/v1 \
    BENCHKIT_HARDWARE="RTX 4070 Laptop 8GB (llama.cpp b11170 Unsloth, $LABEL, ctx 32k)" \
    uv run benchkit --headless --models "$id" --benchmarks patcheval --harness pi) > $OUT 2>&1 & bp=$!
./llama-gpu-power-log.sh $OUT.power $bp & wait $bp
say "=== $LABEL: benchkit exit $?"
grep -E '^\[.*(PASS|FAIL|TIMEOUT|ERR)|^Saved:' $OUT | tail -25
awk '{c=$8; gsub(/cpu=|C/,"",c); w+=$3; t+=c; if(c+0>m)m=c+0; n++} END{if(n) printf "    mean GPU W %.1f  mean CPU %.0fC max %dC\n", w/n, t/n, m}' $OUT.power
stop
say "# $LABEL done"
