#!/usr/bin/env bash
# Samples GPU memory (used/free/total MiB), GPU temp, GPU power and CPU package temp every 5 s until killed or PID exits.
# Usage: ./gpu-vram-log.sh OUT [PID_TO_FOLLOW]
# Line: HH:MM:SS used=MiB free=MiB total=MiB gpu=C W=watts cpu=C
OUT=$1; P=${2:-}
while :; do
  [[ -n $P ]] && ! kill -0 "$P" 2>/dev/null && exit 0
  pk=$(sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}')
  nvidia-smi --query-gpu=memory.used,memory.free,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits \
    | awk -v t="$(date +%T)" -v c="$pk" -F', ' '{printf "%s used=%s free=%s total=%s gpu=%s W=%s cpu=%s\n", t,$1,$2,$3,$4,$5,c}' >> "$OUT"
  sleep 5
done
