#!/usr/bin/env bash
# Follow-up to llama-bonsai2-eval-pipeline.sh: does the K/V cache type matter for Bonsai 2 on this box?
#  k. wikitext KLD at 16k context: q8_0 cache as base, q4_0 and q3_0 against it (new runtime, MTP-free perplexity tool)
#  a. agent eval (8 tasks x SEEDS) with KV=q4_0, then KV=q8_0; same 262k window, THINK=0, blocking wait, lookup on.
#     (q3_0 is the pipeline's stage 3, label bonsai2-ada.)
# Usage: WAIT_FILE=<pipeline output> ./llama-bonsai2-kv-arms.sh   (waits for "pipeline done" in that file first)
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
SEEDS="${SEEDS:-1,2,3}"
COOL=${COOL:-65}
TAG=$(date +%Y%m%d-%H%M%S)
BIN=bonsai-ada-surgery/vendor/prism-llama/build-linux/bin
M=/home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf
W=eval-data/wikitext-2-raw/wiki.test.raw
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }
cool() { for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL && $(ceil) -ge 35 ]] && break; sleep 15; done; echo "#   start cpu=$(cpu_t)C ceiling=$(ceil)W"; }
power_summary() { awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; n++} END{if(n) printf "#   mean GPU W %.1f  samples<30W %d/%d  mean CPU %.0fC max %dC\n", w/n, low, n, c/n, m}' "$1"; }

if [[ -n ${WAIT_FILE:-} ]]; then
  until grep -q 'pipeline done' "$WAIT_FILE" 2>/dev/null; do sleep 30; done
fi
echo "# kv arms start $(date -Iseconds) profile=$(cat /sys/firmware/acpi/platform_profile)"
stop

echo "## k: KLD at 16k context, q8_0 cache = base"
BASE=eval-data/kld-base-bonsai2-ptq1-kvq8-c16384x8.bin
export GGML_CUDA_SCHEDULE=blocking
for kv in q8_0 q4_0 q3_0; do
  log=llama-ppl-kld-bonsai2-ptq1-ada-kv$kv-c16384x8-$TAG.log
  if [[ $kv == q8_0 ]]; then K=(--kl-divergence-base $BASE); else K=(--kl-divergence-base $BASE --kl-divergence); fi
  $BIN/llama-perplexity -m $M -f $W -c 16384 --chunks 8 -b 2048 -ub 512 -ngl 99 -fa on -ctk $kv -ctv $kv -t 6 "${K[@]}" > $log 2>&1
  echo "#   $kv exit $?: $(grep -E 'Final estimate' $log | sed 's/^[0-9.]* I //')"
  grep -E 'Mean +KLD|Same top p|99.0% +KLD' $log | sed 's/^[0-9.]* I /#     /' | sort -u
done
unset GGML_CUDA_SCHEDULE

for kv in q4_0 q8_0; do
  echo "## a: agent eval KV=$kv"; cool
  LOG=llama-serve-bonsai2-ada-agent-kv$kv-$TAG.log
  SCHED=blocking THINK=0 KV=$kv setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
  ./llama-wait-ready.sh 8099 120 || { echo "# start FAILED"; tail -3 $LOG; continue; }
  grep -E '^# (window|kv)' $LOG
  L=bonsai2-ada-kv$kv
  LABEL=$L SEEDS=$SEEDS python3 llama-agent-eval.py > llama-agent-eval-$L.log 2>&1 & bp=$!
  ./llama-gpu-power-log.sh llama-agent-eval-$L.log.power $bp & wait $bp
  power_summary llama-agent-eval-$L.log.power
  echo "#   CUDA errors: $(grep -c 'CUDA error' $LOG)"
done
stop
python3 llama-agent-eval-summary.py bonsai2-ada bonsai2-ada-kvq4_0 bonsai2-ada-kvq8_0 q2_0 gsq-iq3xxs 2>&1 | tail -10
echo "# kv arms done $(date -Iseconds)"
