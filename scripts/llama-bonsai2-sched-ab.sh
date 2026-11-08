#!/usr/bin/env bash
# A/B: CUDA host wait mode for Bonsai 2 on the Ada runtime (local patch llama-cuda-schedule-env.patch).
#   default = driver default (auto -> spin, one core at 100 %), blocking = GGML_CUDA_SCHEDULE=blocking
# Question: does a sleeping wait keep the CPU cooler, the GPU at its 35 W ceiling, and decode as fast?
# Each arm: cool to < COOL C and GPU ceiling back at 35 W, fresh server (LOOKUP=0: MTP only, so rounds do not learn),
# 3 rounds of the occupied probe at ~4k and ~8k, GPU power/clock + CPU temp every 5 s.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
COOL=${COOL:-65}
ARMS=${ARMS:-"default blocking"}
TAG=$(date +%Y%m%d-%H%M%S)
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }
for arm in $ARMS; do
  stop
  for i in $(seq 1 60); do [[ $(cpu_t) -lt $COOL && $(ceil) -ge 35 ]] && break; sleep 15; done
  echo "## arm $arm  start cpu=$(cpu_t)C  gpu ceiling $(ceil) W"
  S=""; [[ $arm != default ]] && S=$arm
  LOG=llama-serve-bonsai2-ada-sched-$arm-$TAG.log
  SCHED=$S LOOKUP=0 setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
  ./llama-wait-ready.sh 8099 120 >/dev/null || { echo "arm $arm failed to start"; tail -3 $LOG; continue; }
  OUT=llama-bench-bonsai2-ada-sched-$arm-$TAG.log
  ( for r in 1 2 3; do PORT=8099 NPREDICT=256 CHARS=14000,28000 python3 llama-bench-occupied-ctx.py; done ) > $OUT 2>&1 &
  BP=$!
  ./llama-gpu-power-log.sh $OUT.power $BP &
  sleep 25; top -b -n1 -o %CPU | awk 'NR>7 && /llama-s/{print "   llama-server CPU% during decode: " $9; exit}'
  wait $BP
  grep -E '^ +[0-9]' $OUT | sed 's/^/   /'
  awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; n++} END{printf "   mean GPU W %.1f  samples<30W %d/%d  mean CPU %.0fC max %dC\n", w/n, low, n, c/n, m}' $OUT.power
  echo "   CUDA errors: $(grep -c 'CUDA error' $LOG)  schedule line: $(grep -c 'GGML_CUDA_SCHEDULE=' $LOG)"
done
stop
echo "## done $(date -Iseconds)"
