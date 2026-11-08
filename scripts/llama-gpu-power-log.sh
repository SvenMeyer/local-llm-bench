#!/usr/bin/env bash
# Samples GPU power cap / draw / SM clock / temps + CPU package temp every 5 s until killed or PID exits.
# Usage: ./llama-gpu-power-log.sh OUT [PID_TO_FOLLOW]
OUT=$1; P=${2:-}
while :; do
  [[ -n $P ]] && ! kill -0 "$P" 2>/dev/null && exit 0
  pk=$(sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}')
  echo "$(date +%T) $(nvidia-smi --query-gpu=power.limit,power.draw,clocks.sm,temperature.gpu --format=csv,noheader) cpu=${pk}C" >> "$OUT"
  sleep 5
done
