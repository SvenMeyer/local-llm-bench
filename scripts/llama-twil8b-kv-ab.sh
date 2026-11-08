#!/usr/bin/env bash
# Clean KV A/B for TwIL-8B: each arm waits for GPU <= 50C, then TG128/PP512 at 16k and 24k depth.
# Samples GPU temp/SM clock every 2 s during each arm (thermal confound check).
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
B=llama.cpp/build/bin
M=/home/sum/.cache/lm-studio/models/mradermacher/TwIL-8B-i1-GGUF/TwIL-8B.i1-Q4_K_M.gguf
OUT=llama-twil8b-kv-ab-$(date +%Y%m%d-%H%M%S).txt
for arm in "q8_0 q8_0" "q4_0 q4_0" "q8_0 q4_0" "q8_0 q8_0"; do
  set -- $arm
  until (( $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader) <= 50 )); do sleep 5; done
  echo "== K=$1 V=$2 start $(date +%T)" | tee -a $OUT
  nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader -lms 2000 > /tmp/claude-1000/-home-sum-Downloads-AI-Runtime/311e80d0-f85e-4d68-aaa6-f1eedc1fb93e/scratchpad/gpu.csv &
  MON=$!
  $B/llama-bench -m $M -ngl 99 -fa on -ctk $1 -ctv $2 -t 10 -p 512 -n 128 -d 16384,24576 -r 2 -o md 2>&1 | grep -E '^\| granite' | awk -F'|' '{print "  "$8,$9,$11,$12}' | tee -a $OUT
  kill $MON
  awk -F', ' '{t+=$1; c+=$2; n++; if($1>tm)tm=$1; if(cm==""||$2<cm)cm=$2} END{printf "  GPU mean %.0fC max %dC, SM clock mean %.0f min %d MHz\n", t/n, tm, c/n, cm}' /tmp/claude-1000/-home-sum-Downloads-AI-Runtime/311e80d0-f85e-4d68-aaa6-f1eedc1fb93e/scratchpad/gpu.csv | tee -a $OUT
done
echo "done $(date +%T) -> $OUT"
