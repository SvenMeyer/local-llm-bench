#!/usr/bin/env bash
# Bonsai 2 27B evaluation on this box, same stages as llama-qwen38-eval-pipeline.sh (stage 1 PPL is run separately):
#  2a. new runtime (Ada surgery), 262k q3_0, MTP only (LOOKUP=0), GGML_CUDA_SCHEDULE=blocking: occupied probe 0.5k..~128k
#  2b. stock Prism engine b10706, PTQ1_0, 65536 q4_0 all-VRAM (the tweet's "stock prism" arm): occupied probe 0.5k..61k
#  3.  agent eval (llama-agent-eval.py, 8 tasks x SEEDS) on the new runtime, 262k preset, THINK=0, blocking
# Every arm waits for CPU < COOL C and GPU ceiling 35 W first; GPU power / clock / CPU temp logged every 5 s.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STAGES="${STAGES:-2a 2b 3}"
SEEDS="${SEEDS:-1,2,3}"
COOL=${COOL:-65}
TAG=$(date +%Y%m%d-%H%M%S)
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }
cool() { for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL && $(ceil) -ge 35 ]] && break; sleep 15; done; echo "#   start cpu=$(cpu_t)C ceiling=$(ceil)W"; }
power_summary() { awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; n++} END{if(n) printf "#   mean GPU W %.1f  samples<30W %d/%d  mean CPU %.0fC max %dC\n", w/n, low, n, c/n, m}' "$1"; }
probe() {  # $1 out-log, $2 chars
  PORT=8099 NPREDICT=128 CHARS=$2 python3 llama-bench-occupied-ctx.py > "$1" 2>&1 & local bp=$!
  ./llama-gpu-power-log.sh "$1.power" $bp & wait $bp
  grep -E '^ +[0-9]|FAIL|trim' "$1"; power_summary "$1.power"
}
echo "# bonsai2 pipeline STAGES=$STAGES SEEDS=$SEEDS start $(date -Iseconds) profile=$(cat /sys/firmware/acpi/platform_profile)"
for s in $STAGES; do
  stop; echo "## stage $s"; cool
  case $s in
    2a)
      LOG=llama-serve-bonsai2-ada-pipeline-2a-$TAG.log
      SCHED=blocking LOOKUP=0 setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
      ./llama-wait-ready.sh 8099 120 || { echo "# 2a start FAILED"; tail -3 $LOG; continue; }
      grep -E '^# (model|window|kv)' $LOG
      probe llama-bench-bonsai2-ada-ptq1-q3_0-262k-mtponly-blocking-occupied-$TAG.log 2000,7000,14000,28000,112000,210000,450000
      echo "#   CUDA errors: $(grep -c 'CUDA error' $LOG)"
      ;;
    2b)
      LOG=llama-serve-bonsai2-stock-pipeline-2b-$TAG.log
      QUANT=PTQ1_0 CTX=65536 KV=q4_0 setsid nohup ./llama-serve-ternary-bonsai2.sh > $LOG 2>&1 < /dev/null &
      ./llama-wait-ready.sh 8099 120 || { echo "# 2b start FAILED"; tail -3 $LOG; continue; }
      probe llama-bench-bonsai2-stock-ptq1-q4_0-64k-occupied-$TAG.log 2000,7000,14000,28000,112000,210000
      ;;
    3)
      LOG=llama-serve-bonsai2-ada-pipeline-agent-$TAG.log
      SCHED=blocking THINK=0 setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
      ./llama-wait-ready.sh 8099 120 || { echo "# 3 start FAILED"; tail -3 $LOG; continue; }
      LABEL=bonsai2-ada SEEDS=$SEEDS python3 llama-agent-eval.py > llama-agent-eval-bonsai2-ada.log 2>&1 & bp=$!
      ./llama-gpu-power-log.sh llama-agent-eval-bonsai2-ada.log.power $bp & wait $bp
      tail -n 30 llama-agent-eval-bonsai2-ada.log | grep -E 'PASS|fail' ; power_summary llama-agent-eval-bonsai2-ada.log.power
      python3 llama-agent-eval-summary.py bonsai2-ada q2_0 gsq-iq3xxs 2>&1 | tail -8
      echo "#   CUDA errors: $(grep -c 'CUDA error' $LOG)"
      ;;
  esac
done
stop
echo "# bonsai2 pipeline done $(date -Iseconds)"
