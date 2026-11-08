#!/usr/bin/env bash
# BenchKit PatchEval (20 real Python bug fixes, stock pi agent in BenchKit's Docker sandbox, hidden-test grading)
# against Qwen3.8-Flash-Next on Strata, one quant after another. Goal: which quant fixes the most bugs, and at what speed.
# Same limits as the Bonsai 2 run (2026-10-28): 1800 s per task, pi output cap 16384, 1 task at a time.
# Strata listens on 127.0.0.1 only; socat exposes it on docker0 (172.17.0.1), so BenchKit's proxy container can
# reach it without opening it to the LAN.
# Usage: nohup ./patcheval-strata-quants.sh > patcheval-strata-quants-$(date +%Y%m%d-%H%M).txt 2>&1 &
#        ARMS="iq3s" ./patcheval-strata-quants.sh     # subset; an arm whose log already has "Saved:" is skipped
#        ARMS=iq3s SLICE=patcheval:6 PI_TIMEOUT=3600 MAX_TOKENS=65536 SUFFIX=-prior-64k-t3600-first6 ./patcheval-strata-quants.sh
# Routing: Strata 0.2.8+ (engine 0.1.55) turns residency-biased routing OFF by default on <=12 GB cards; on this
# 8 GB card that costs a third of decode speed (IQ3_S 24.2 -> 16.3 t/s). ROUTE below restores the 0.1.52 setup
# our October results used: route tail skip off, route prior 1.5 on.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099; COOL=${COOL:-65}
MODELS=/home/sum/.cache/lm-studio/models
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
ARMS=${ARMS:-"iq3xxs iq3s"}   # also: ud31iq3xxs ud31iq4xs (Unsloth v3.1, see handover-unsloth-v31-patcheval.md)
SLICE=${SLICE:-patcheval}
PI_TIMEOUT=${PI_TIMEOUT:-1800}      # seconds per task
MAX_TOKENS=${MAX_TOKENS:-}          # pi output cap per reply; empty = pi default 16384
SUFFIX=${SUFFIX:-}                  # appended to the log label
ROUTE="--set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=${ROUTE_PRIOR:-1.5}"
DRAFT=${DRAFTING:+--drafting $DRAFTING}   # empty = Strata Auto (0.2.10: DFlash2 on one request); or mtp, dflash2, off
VER=$($STRATA --version 2>/dev/null | awk '{print $2, $3, $4}' | tr -d '(;')
PI_MODEL=${MAX_TOKENS:+{\"maxTokens\":$MAX_TOKENS\}}
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

bridge() {
    pgrep -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1" >/dev/null && return
    setsid nohup socat TCP-LISTEN:$PORT,bind=172.17.0.1,reuseaddr,fork TCP:127.0.0.1:$PORT >/dev/null 2>&1 </dev/null &
    sleep 1
}

ready() {  # wait until /v1/models lists a loaded model
    for i in $(seq 1 120); do
        curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"' && return 0; sleep 5
    done; return 1
}

run_arm() {  # label model-path strata-model [extra strata args...]
    local label=$1 path=$2 model=$3 id; shift 3
    label=$label$SUFFIX; local out=benchkit-patcheval-strata-$label.log
    if grep -q '^Saved:' "$out" 2>/dev/null; then say "=== $label: already done, skipped"; return; fi
    say "=== $label: cooling to ${COOL}C (now $(cpu_t)C)"
    $STRATA launch --stop </dev/null >/dev/null 2>&1
    for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL ]] && break; sleep 15; done
    say "=== $label: launching ($(cpu_t)C)"
    $STRATA launch --model-path "$path" --model "$model" --context 64k --vision off --access local --port $PORT \
        --no-api-key --yes --no-tui --restart "$@" </dev/null 2>&1 | tail -1
    ready || { say "=== $label: server not ready, skipped"; return; }
    bridge
    id=$(curl -s -m5 http://172.17.0.1:$PORT/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])') \
        || { say "=== $label: bridge check failed"; return; }
    if [[ -n $MAX_TOKENS ]]; then  # server must accept the cap (it can exceed the 64k context): first streamed chunk only
        # read into a variable: with pipefail, "| head | grep -q" fails when head closes the pipe early
        local r; r=$(curl -s -m 120 http://172.17.0.1:$PORT/v1/chat/completions -H "Content-Type: application/json" \
            -d "{\"model\":\"$id\",\"max_tokens\":$MAX_TOKENS,\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}]}" 2>/dev/null)
        [[ $r == *'"choices"'* ]] || { say "=== $label: max_tokens=$MAX_TOKENS rejected by server (${r:0:300}), skipped"; return; }
    fi
    say "=== $label: PatchEval start (model $id, timeout ${PI_TIMEOUT}s, maxTokens ${MAX_TOKENS:-16384}, $SLICE)"
    (cd $BK && BENCHKIT_PI_TIMEOUT=$PI_TIMEOUT BENCHKIT_PI_MODEL="$PI_MODEL" BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:$PORT/v1 \
        BENCHKIT_HARDWARE="RTX 4070 Laptop 8GB ($VER, $label, timeout ${PI_TIMEOUT}s, maxTokens ${MAX_TOKENS:-16384})" \
        uv run benchkit --headless --models "$id" --benchmarks $SLICE --harness pi) > $out 2>&1 & local bp=$!
    ./llama-gpu-power-log.sh $out.power $bp & wait $bp
    say "=== $label: benchkit exit $?"
    grep -E '^\[.*(PASS|FAIL|TIMEOUT|ERR)|^Saved:' $out | tail -25
    awk '{c=$8; gsub(/cpu=|C/,"",c); w+=$3; t+=c; if(c+0>m)m=c+0; n++} END{if(n) printf "    mean GPU W %.1f  mean CPU %.0fC max %dC\n", w/n, t/n, m}' $out.power
}

say "# patcheval-strata-quants start  arms: $ARMS  slice: $SLICE  $VER  route: $ROUTE ${DRAFT:-drafting auto}  timeout: ${PI_TIMEOUT}s  maxTokens: ${MAX_TOKENS:-16384}  profile=$(cat /sys/firmware/acpi/platform_profile)"
docker info >/dev/null 2>&1 || { say "# Docker daemon not running (sudo systemctl start docker)"; exit 1; }
for arm in $ARMS; do
    case $arm in
        iq3xxs)  run_arm iq3xxs-noskip $MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF iq3_xxs $ROUTE $DRAFT ;;
        iq3s)    run_arm iq3s-noskip $MODELS/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF iq3_s $ROUTE $DRAFT ;;
        # Unsloth Dynamic v3.1 (2026-11-04). The 09-30 UD-IQ4_XS arm was removed with its files (2026-11-07).
        ud31iq3xxs) run_arm ud31-iq3xxs-noskip $MODELS/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ3_XXS/Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00004.gguf ud-iq3_xxs $ROUTE $DRAFT ;;
        ud31iq4xs)  run_arm ud31-iq4xs-noskip $MODELS/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ4_XS/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf ud-iq4_xs-v31 $ROUTE $DRAFT ;;
        *) say "=== unknown arm $arm (iq3xxs iq3s ud31iq3xxs ud31iq4xs)" ;;
    esac
done
$STRATA launch --stop </dev/null >/dev/null 2>&1
pkill -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1"
say "# patcheval-strata-quants done"
