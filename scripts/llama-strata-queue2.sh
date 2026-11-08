#!/usr/bin/env bash
# Queue 2 (added 2026-10-29 00:25): runs after pi-strata-followup.sh.
#  1. in-house eval, IQ3_XXS "faithful": STRATA_ROUTE_TAIL_SKIP=0 and STRATA_ROUTE_PRIOR=0. 0.2.7 turns residency-biased
#     routing (ROUTE_PRIOR=1.5) on by itself on cards <= 13 GiB: +15-37% speed, but Strata's own check had agent loops
#     4.5/10 vs 5.6/10. This arm shows what the exact model scores on Strata.
#  2. pi on UD-IQ4_XS (moved here from pi-eval/plan.txt), 1 sample.
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099
IQ3=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF
UD4=/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF
VOCAB=/home/sum/.local/share/strata/terminal/0.1.52/data/draft_vocab_en.bin
say() { echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for llama-strata-overnight.sh and pi-strata-followup.sh"
while pgrep -f 'llama-strata-overnight.sh|pi-strata-followup.sh' >/dev/null; do sleep 30; done
launch() { $STRATA launch --model-path "$1" --model "$2" --context 64k --vision off --access local --port $PORT \
             --no-api-key --yes --no-tui --restart "${@:3}" < /dev/null 2>&1 | tail -2; }
model_id() { curl -s --max-time 5 http://127.0.0.1:$PORT/v1/models | python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null; }

say "=== strata-iq3xxs-faithful: launching"
launch "$IQ3" iq3_xxs --set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=0
grep -E 'residency-biased|ROUTE_PRIOR|tail skip' ~/.local/state/strata/launch/iq3_xxs-64k.engine.log | tail -3
if [[ -n "$(model_id)" ]]; then
    LABEL=strata-iq3xxs-faithful PORT=$PORT SEEDS=1,2,3 MAX_TOKENS=21846 python3 llama-agent-eval.py < /dev/null 2>&1 | tee -a llama-agent-eval-strata-iq3xxs-faithful.log
    cp ~/.local/state/strata/launch/iq3_xxs-64k.engine.log llama-serve-strata-iq3xxs-faithful.engine.log
else say "=== strata-iq3xxs-faithful: SKIPPED (no server)"; fi
$STRATA launch --stop < /dev/null 2>&1 | tail -1; sleep 10

say "=== pi-strata-ud-iq4xs: launching"
launch "$UD4" ud-iq4_xs --family unsloth --set mtp-draft-vocab=$VOCAB
id=$(model_id)
if [[ -n "$id" ]]; then
    LABEL=pi-strata-ud-iq4xs MODEL=$id PORT=$PORT SAMPLES=1 python3 pi-agent-eval.py < /dev/null 2>&1 | tee -a pi-agent-eval-pi-strata-ud-iq4xs.log
else say "=== pi-strata-ud-iq4xs: SKIPPED (no server)"; fi
$STRATA launch --stop < /dev/null 2>&1 | tail -1
say "=== summary"
python3 llama-agent-eval-summary.py gsq-iq3xxs strata-iq3xxs strata-iq3xxs-noskip strata-iq3xxs-faithful 2>&1
say "=== queue 2 done"
