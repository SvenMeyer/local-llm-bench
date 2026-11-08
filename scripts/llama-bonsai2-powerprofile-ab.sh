#!/usr/bin/env bash
# A/B: laptop platform profile balanced vs performance for Bonsai 2 on the Ada runtime (GPU-bound decode/prefill).
# Profile switched over D-Bus (power-profiles-daemon, ActiveProfile is writable for the desktop user), restored to the
# starting profile on any exit. Each arm: cool to < COOL C and GPU ceiling >= its baseline, fresh server
# (262k q3_0, MTP only, blocking wait), then
#   1. llama-bench pp512 / tg128 (short burst, peak numbers)
#   2. occupied probe ~4k/~8k x ROUNDS (sustained, several minutes)  with GPU W / ceiling / clocks / CPU temp logged.
# Usage: WAIT_FILE=<patcheval output> ./llama-bonsai2-powerprofile-ab.sh
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
COOL=${COOL:-65}
ROUNDS=${ROUNDS:-6}
TAG=$(date +%Y%m%d-%H%M%S)
BIN=bonsai-ada-surgery/vendor/prism-llama/build-linux/bin
M=/home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf
PP=(org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)
getp() { busctl get-property "${PP[@]}" | awk '{gsub(/"/,"",$2); print $2}'; }
setp() { busctl set-property "${PP[@]}" s "$1"; }
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }

if [[ -n ${WAIT_FILE:-} ]]; then until grep -q 'patcheval done' "$WAIT_FILE" 2>/dev/null; do sleep 30; done; fi
START=$(getp)
trap 'setp "$START"; stop; echo "# profile restored to $(getp)"' EXIT
echo "# power-profile A/B start $(date -Iseconds), profile now $START"
export GGML_CUDA_SCHEDULE=blocking
for arm in balanced performance; do
  stop
  setp $arm; sleep 5
  echo "## arm $arm  (profile now $(getp), platform_profile $(cat /sys/firmware/acpi/platform_profile))"
  for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL ]] && (( $(ceil) >= 35 )) && break; sleep 15; done
  echo "#   start cpu=$(cpu_t)C  GPU ceiling $(ceil) W  (max $(nvidia-smi -q -d POWER | awk '/Max Power Limit/{print $5; exit}') W)"
  B=llama-bench-bonsai2-ada-profile-$arm-$TAG.log
  $BIN/llama-bench -m $M -ngl 99 -fa 1 -ctk q8_0 -ctv q8_0 -p 512 -n 128 -r 3 -t 6 > $B 2>&1 & bp=$!
  ./llama-gpu-power-log.sh $B.power $bp & wait $bp
  grep -E '^\|' $B | tail -2 | sed 's/^/   /'
  awk '{w+=$3; if($3>m)m=$3; n++} END{if(n) printf "   llama-bench GPU W mean %.1f max %.1f\n", w/n, m}' $B.power
  LOG=llama-serve-bonsai2-ada-profile-$arm-$TAG.log
  SCHED=blocking LOOKUP=0 setsid nohup ./llama-serve-bonsai2-ada.sh > $LOG 2>&1 < /dev/null &
  ./llama-wait-ready.sh 8099 120 >/dev/null || { echo "#   server start FAILED"; tail -3 $LOG; continue; }
  OUT=llama-bench-bonsai2-ada-profile-$arm-occupied-$TAG.log
  ( for r in $(seq 1 $ROUNDS); do PORT=8099 NPREDICT=256 CHARS=14000,28000 python3 llama-bench-occupied-ctx.py; done ) > $OUT 2>&1 & bp=$!
  ( while kill -0 $bp 2>/dev/null; do echo "$(date +%T) ceiling $(ceil)" >> $OUT.ceiling; sleep 10; done ) &
  ./llama-gpu-power-log.sh $OUT.power $bp & wait $bp
  grep -E '^ +[0-9]' $OUT | sed 's/^/   /'
  awk '{c6=$8; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3+0<30)low++; if($3>mw)mw=$3; n++} END{printf "   probe GPU W mean %.1f max %.1f  samples<30W %d/%d  CPU mean %.0fC max %dC\n", w/n, mw, low, n, c/n, m}' $OUT.power
  echo "   GPU ceiling seen: $(awk '{print $3}' $OUT.ceiling | sort -n | uniq -c | tr '\n' ' ')"
  fans=$(sensors 2>/dev/null | awk '/CPU Fan|Video Fan/{printf "%s %s ", $1, $3}'); echo "   fans at end: $fans"
done
echo "# power-profile A/B done $(date -Iseconds)"
