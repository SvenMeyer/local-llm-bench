#!/usr/bin/env bash
# A/B: llama-server --poll 100 (runtime default, a CPU thread busy-waits) vs --poll 0, Bonsai 2 on the Ada runtime.
# Question: does the busy-wait heat the CPU enough to make Dynamic Boost cut the GPU to 20 W, and what does poll 0 cost?
# Each arm: cool to < COOL C, start server, 3 rounds of the occupied probe at ~4k and ~8k (sustained ~3 min),
# log GPU power/clock + CPU package temp every 5 s.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
COOL=${COOL:-65}
TAG=$(date +%Y%m%d-%H%M%S)
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }
for arm in 100 0; do
  stop
  for i in $(seq 1 40); do t=$(cpu_t); [[ $t -lt $COOL ]] && break; sleep 15; done
  echo "## arm poll=$arm  start cpu=$(cpu_t)C  $(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader)C gpu"
  LOG=llama-serve-bonsai2-ada-poll$arm-$TAG.log
  setsid nohup ./llama-serve-bonsai2-ada.sh --poll $arm > $LOG 2>&1 < /dev/null &
  ./llama-wait-ready.sh 8099 120 >/dev/null || { echo "arm $arm failed to start"; tail -3 $LOG; continue; }
  OUT=llama-bench-bonsai2-ada-poll$arm-$TAG.log
  ( for r in 1 2 3; do PORT=8099 NPREDICT=256 CHARS=14000,28000 python3 llama-bench-occupied-ctx.py; done ) > $OUT 2>&1 &
  BP=$!
  ./llama-gpu-power-log.sh $OUT.power $BP &
  sleep 20; top -b -n1 -o %CPU | awk 'NR>7 && /llama-s/{print "   llama-server CPU% " $9; exit}'
  wait $BP
  grep -E '^ +[0-9]' $OUT | sed 's/^/   /'
  awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; n++} END{printf "   mean GPU W %.1f  samples<30W %d/%d  mean CPU %.0fC max %dC\n", w/n, low, n, c/n, m}' $OUT.power
  grep -c 'CUDA error' $LOG | sed 's/^/   CUDA errors: /'
done
stop
echo "## done $(date -Iseconds)"
