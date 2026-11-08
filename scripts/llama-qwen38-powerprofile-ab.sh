#!/usr/bin/env bash
# A/B: platform profile balanced vs performance for Qwen3.8-Flash-Next UD-IQ4_XS (experts on CPU, so CPU-thermal
# bound as well as GPU). One server load (direct launcher, 16384 + MTP, ub 1024 = the 2026-10-26 Studio argv), then per
# arm: cool to < COOL C (max ~5 min), one occupied probe ~0.5k/2k/4k/8k with GPU W / CPU temp / GPU ceiling logged.
# Profile is restored and the server stopped on any exit.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
COOL=${COOL:-65}
TAG=$(date +%Y%m%d-%H%M%S)
PP=(org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)
getp() { busctl get-property "${PP[@]}" | awk '{gsub(/"/,"",$2); print $2}'; }
setp() { busctl set-property "${PP[@]}" s "$1"; }
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
ceil() { nvidia-smi -q -d POWER | awk '/Current Power Limit/{print int($5); exit}'; }
stop() { pkill -TERM -x llama-server; for i in $(seq 1 60); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }

START=$(getp)
trap 'setp "$START"; stop; echo "# profile restored to $(getp)"' EXIT
echo "# qwen3.8 IQ4_XS power-profile A/B start $(date -Iseconds), profile now $START"
echo "# engine $(head -1 ~/.unsloth/llama.cpp/BUILD_INFO.txt)"
stop
LOG=llama-serve-qwen38-udiq4xs-profile-ab-$TAG.log
T0=$(date +%s)
QUANT=iq4xs setsid nohup ./llama-serve-qwen38-direct.sh > $LOG 2>&1 < /dev/null &
./llama-wait-ready.sh 8099 900 || { echo "# server start FAILED"; tail -5 $LOG; exit 1; }
echo "# server ready in $(( $(date +%s) - T0 )) s; $(nvidia-smi --query-gpu=memory.used --format=csv,noheader) VRAM; $(/usr/bin/free -h | awk 'NR==2{print $3" RAM used"}')"

for arm in balanced performance; do
  setp $arm; sleep 5
  echo "## arm $arm  (profile now $(getp), platform_profile $(cat /sys/firmware/acpi/platform_profile))"
  for i in $(seq 1 20); do [[ $(cpu_t) -lt $COOL ]] && (( $(ceil) >= 35 )) && break; sleep 15; done
  echo "#   start cpu=$(cpu_t)C  GPU ceiling $(ceil) W"
  OUT=llama-bench-qwen38-udiq4xs-profile-$arm-occupied-$TAG.log
  ( PORT=8099 NPREDICT=128 CHARS=2000,7000,14000,28000 python3 llama-bench-occupied-ctx.py ) > $OUT 2>&1 & bp=$!
  ( while kill -0 $bp 2>/dev/null; do echo "$(date +%T) ceiling $(ceil)" >> $OUT.ceiling; sleep 10; done ) &
  ./llama-gpu-power-log.sh $OUT.power $bp & wait $bp
  grep -E '^ +[0-9]' $OUT | sed 's/^/   /'
  awk '{c6=$NF; gsub(/cpu=|C/,"",c6); w+=$3; c+=c6; if(c6+0>m)m=c6+0; if($3>mw)mw=$3; n++} END{printf "   probe GPU W mean %.1f max %.1f  CPU mean %.0fC max %dC  (%d samples)\n", w/n, mw, c/n, m, n}' $OUT.power
  echo "   GPU ceiling seen: $(awk '{print $3}' $OUT.ceiling | sort -n | uniq -c | tr '\n' ' ')"
  echo "   fans at end: $(sensors 2>/dev/null | awk '/CPU Fan|Video Fan/{printf "%s %s ", $1, $3}')"
done
echo "# A/B done $(date -Iseconds)"
