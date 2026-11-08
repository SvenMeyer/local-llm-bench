#!/usr/bin/env bash
# Queue 3 (added 2026-10-29 01:55): after queue 2. IQ3_S with the route tail skip off, the setting that won for IQ3_XXS
# (noskip 24/24 in 64 min vs default 23/24 in 93 min). The suite's arm E runs IQ3_S on Strata defaults.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099
IQ3S=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF
say() { echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for the suite, pi follow-up and queue 2"
while pgrep -f 'llama-strata-overnight.sh|pi-strata-followup.sh|llama-strata-queue2.sh' >/dev/null; do sleep 30; done
say "=== strata-iq3s-noskip: launching"
$STRATA launch --model-path "$IQ3S" --model iq3_s --context 64k --vision off --access local --port $PORT --no-api-key \
    --yes --no-tui --restart --set STRATA_ROUTE_TAIL_SKIP=0 < /dev/null 2>&1 | tail -2
if curl -s --max-time 5 http://127.0.0.1:$PORT/v1/models | grep -q '"loaded"'; then
    LABEL=strata-iq3s-noskip PORT=$PORT SEEDS=1,2,3 MAX_TOKENS=21846 python3 llama-agent-eval.py < /dev/null 2>&1 | tee -a llama-agent-eval-strata-iq3s-noskip.log
    cp ~/.local/state/strata/launch/iq3_s-64k.engine.log llama-serve-strata-iq3s-noskip.engine.log 2>/dev/null
else say "=== strata-iq3s-noskip: SKIPPED (no server)"; fi
$STRATA launch --stop < /dev/null 2>&1 | tail -1
have=""; for l in gsq-iq3xxs strata-iq3xxs strata-iq3xxs-noskip strata-iq3xxs-faithful strata-ud-iq4xs strata-iq3s strata-iq3s-noskip; do
    [[ -s llama-agent-eval-$l.jsonl ]] && have+=" $l"; done
say "=== summary (all setups)"; python3 llama-agent-eval-summary.py $have
say "=== queue 3 done"
