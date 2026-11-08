#!/usr/bin/env bash
# BenchKit PatchEval (20 real Python bug fixes, Pi coding agent in Docker, hidden-test grading) against Bonsai 2 27B
# on the Ada runtime: the benchmark behind the tweet's "15/20" (github.com/DogukanUrker/BenchKit, v0.2.0 12f79c6).
# Server listens on the docker0 bridge (172.17.0.1): BenchKit's proxy container reaches the host through it, and a
# 127.0.0.1-only server is invisible from Docker. Not exposed to the LAN.
# Server: runtime 8 GB preset defaults (262k, q3_0, MTP + lookup, thinking on at medium, 20k budget) + blocking wait.
# Usage: WAIT_FILE=<kv-arms output> ./llama-bonsai2-patcheval.sh   (waits for "kv arms done" first)
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
COOL=${COOL:-65}
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }

if [[ -n ${WAIT_FILE:-} ]]; then until grep -q 'kv arms done' "$WAIT_FILE" 2>/dev/null; do sleep 30; done; fi
for i in $(seq 1 120); do docker info >/dev/null 2>&1 && break; [[ $i == 1 ]] && echo "# waiting for the Docker daemon (sudo systemctl start docker)"; sleep 30; done
docker info >/dev/null 2>&1 || { echo "# Docker daemon not running: PatchEval skipped"; exit 1; }
echo "# patcheval start $(date -Iseconds) profile=$(cat /sys/firmware/acpi/platform_profile)  docker $(docker info --format '{{.ServerVersion}}')"
stop
for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL && $(ceil) -ge 35 ]] && break; sleep 15; done
echo "#   start cpu=$(cpu_t)C ceiling=$(ceil)W"
LOG=llama-serve-bonsai2-ada-patcheval-$(date +%Y%m%d-%H%M%S).log
THINK=${THINK:-1} HOST=172.17.0.1 SCHED=blocking setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
WAIT_HOST=172.17.0.1 ./llama-wait-ready.sh 8099 120 || { echo "# server start FAILED"; tail -3 $LOG; exit 1; }
grep -E '^# (model|window|kv|think)' $LOG
cd $BK
export BENCHKIT_PI_TIMEOUT=${BENCHKIT_PI_TIMEOUT:-1800} BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:8099/v1 BENCHKIT_HARDWARE="RTX 4070 Laptop 8GB (35 W)"
OUT=/home/sum/Downloads/AI-Runtime/benchkit-patcheval-bonsai2-ada${LABEL:+-$LABEL}.log
uv run benchkit --headless --models bonsai-2-27b --benchmarks patcheval --harness pi > $OUT 2>&1 & bp=$!
/home/sum/Downloads/AI-Runtime/llama-gpu-power-log.sh $OUT.power $bp & wait $bp
echo "#   benchkit exit $?"
tail -n 40 $OUT
awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; n++} END{if(n) printf "#   mean GPU W %.1f  samples<30W %d/%d  mean CPU %.0fC max %dC\n", w/n, low, n, c/n, m}' $OUT.power
echo "#   CUDA errors: $(grep -c 'CUDA error' /home/sum/Downloads/AI-Runtime/$LOG)"
cd /home/sum/Downloads/AI-Runtime; stop
echo "# patcheval done $(date -Iseconds)"
