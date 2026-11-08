#!/usr/bin/env bash
# Overnight 2026-11-07: Strata 0.2.10 -> 0.2.11 update, then 24-run agent suites on Strata:
#   A) GSQ IQ3_S      (engine check vs 0.1.52/0.1.56 runs; download paused so page cache is not disturbed)
#   B) Unsloth v3.1 UD-IQ3_XXS (after its download completes)
#   C) GSQ IQ3_XXS    (same-engine baseline for B; user's daily pick)
# All arms: --set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5 (the setup of every earlier Strata run),
# 64k context, SEEDS=1,2,3, MAX_TOKENS=21846 (as llama-strata-queue3.sh). Progress: overnight-strata0211-v31-<ts>.txt
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099; COOL=65
M=/home/sum/.cache/lm-studio/models
UD=$M/unsloth/Qwen3.8-Flash-Next-GGUF/UD-IQ3_XXS
ROUTE=(--set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5)
LOG=overnight-strata0211-v31-$(date +%Y%m%d-%H%M).txt
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a $LOG; }
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
gpu_pl() { nvidia-smi -q -d POWER | awk -F: '/Current Power Limit/{gsub(/ /,"",$2); print $2; exit}'; }
dl_pids() { pgrep -f "curl .*UD-IQ3_XXS-0000"; }
dl_done() { for i in 1 2 3; do [[ -f $UD/Qwen3.8-Flash-Next-UD-IQ3_XXS-0000$i-of-00004.gguf ]] || return 1; done; }

say "# overnight start; log $LOG"
# 0. wait for the TwIL no-preserve run, then free the GPU
while pgrep -f "LABEL=twil8b-i1q4km-nopreserve" >/dev/null || pgrep -fx "python3 -I llama-agent-eval.py" >/dev/null; do sleep 30; done
say "TwIL runs done:"; grep -h " s1 " llama-agent-eval-twil8b-i1q4km.log llama-agent-eval-twil8b-i1q4km-nopreserve.log | tee -a $LOG
pgrep -x llama-server >/dev/null && { kill $(pgrep -x llama-server); while pgrep -x llama-server >/dev/null; do sleep 1; done; }
python3 -I llama-agent-eval-summary.py twil8b-i1q4km twil8b-i1q4km-nopreserve strata-iq3xxs-noskip bonsai2-ada 2>&1 | tee -a $LOG

# 1. Strata update
say "=== strata update (before: $($STRATA --version 2>&1 | head -1))"
$STRATA update --yes --stop-model < /dev/null >> $LOG 2>&1; say "update exit $?"
say "after: $($STRATA --version 2>&1 | head -1)"

run_arm() {  # label  launch-args...
    local label=$1; shift
    if [[ -s llama-agent-eval-$label.jsonl ]] && (( $(wc -l < llama-agent-eval-$label.jsonl) >= 24 )); then say "=== $label: done before, skipped"; return; fi
    $STRATA launch --stop < /dev/null >> $LOG 2>&1
    say "=== $label: cooling to ${COOL}C (now $(cpu_t)C)"
    for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL ]] && break; sleep 15; done
    say "=== $label: launching (CPU $(cpu_t)C, GPU limit $(gpu_pl))"
    local t0=$(date +%s)
    $STRATA launch "$@" --context 64k --vision off --access local --port $PORT --no-api-key --yes --no-tui --restart \
        "${ROUTE[@]}" < /dev/null >> $LOG 2>&1
    say "launch exit $? after $(( $(date +%s)-t0 ))s"
    for i in $(seq 1 60); do curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"' && break; sleep 10; done
    if ! curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"'; then say "=== $label: NOT LOADED"; return 1; fi
    nvidia-smi --query-gpu=timestamp,temperature.gpu,clocks.sm,power.draw --format=csv,noheader -l 10 > llama-agent-eval-$label.log.power & local pw=$!
    LABEL=$label PORT=$PORT SEEDS=1,2,3 MAX_TOKENS=21846 python3 -I llama-agent-eval.py < /dev/null >> llama-agent-eval-$label.log 2>&1
    say "=== $label: eval exit $?"; kill $pw
    local el=$(ls -t ~/.local/state/strata/launch/*.engine.log | head -1)
    command cp -f "$el" llama-serve-$label.engine.log; say "engine log $el -> llama-serve-$label.engine.log"
    grep -iE "rout|prior|tail.skip" llama-serve-$label.engine.log | head -8 | tee -a $LOG
    $STRATA launch --stop < /dev/null >> $LOG 2>&1
    python3 -I llama-agent-eval-summary.py $label 2>&1 | sed -n 3p | tee -a $LOG
}

# 2. arm A: IQ3_S, with the download paused
P=$(dl_pids); [[ -n $P ]] && { kill -STOP $P; say "download paused ($P)"; }
run_arm strata0211-iq3s-noskip-prior15 --model-path $M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF --model iq3_s
P=$(dl_pids); [[ -n $P ]] && { kill -CONT $P; say "download resumed ($P)"; }

# 3. arm B: Unsloth v3.1 UD-IQ3_XXS once downloaded (wait up to 8 h)
for i in $(seq 1 960); do dl_done && break; sleep 30; done
if dl_done; then
    say "UD-IQ3_XXS download complete: $(ls -la $UD | tail -n +4 | awk '{print $5, $9}' | tr '\n' ' ')"
    run_arm strata0211-ud31-iq3xxs-noskip-prior15 --model-path $UD/Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00004.gguf \
    || run_arm strata0211-ud31-iq3xxs-noskip-prior15 --family unsloth --model ud-iq3_xxs --model-path $UD/Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00004.gguf
else say "=== UD-IQ3_XXS download NOT complete; arm B skipped"; fi

# 4. arm C: GSQ IQ3_XXS on the same engine
run_arm strata0211-iq3xxs-noskip-prior15 --model-path $M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF --model iq3_xxs

$STRATA launch --stop < /dev/null >> $LOG 2>&1
have=""; for l in strata-iq3xxs-noskip strata-iq3s-noskip strata-iq3s-noskip-0155 strata0211-iq3s-noskip-prior15 \
    strata0211-ud31-iq3xxs-noskip-prior15 strata0211-iq3xxs-noskip-prior15 twil8b-i1q4km twil8b-i1q4km-nopreserve bonsai2-ada; do
    [[ -s llama-agent-eval-$l.jsonl ]] && have+=" $l"; done
say "=== summary"; python3 -I llama-agent-eval-summary.py $have 2>&1 | tee -a $LOG
say "# overnight done"
