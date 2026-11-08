#!/usr/bin/env bash
# Runs after llama-strata-overnight.sh: the in-house tasks through the real pi agent (pi-agent-eval.py) on Strata,
# one setup per line of pi-eval/plan.txt (read when the suite has finished, so it can be edited until then).
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099
say() { echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for llama-strata-overnight.sh to finish"
while pgrep -f llama-strata-overnight.sh >/dev/null; do sleep 30; done
say "suite finished; plan:"; grep -v '^#' pi-eval/plan.txt
grep -v '^#' pi-eval/plan.txt | grep -v '^\s*$' | while IFS='|' read -r label path model samples extra; do
    label=$(echo $label); path=$(echo $path); model=$(echo $model); samples=$(echo $samples)
    say "=== $label: launching Strata ($model)"
    # shellcheck disable=SC2086
    $STRATA launch --model-path "$path" --model "$model" --context 64k --vision off --access local --port $PORT \
        --no-api-key --yes --no-tui --restart $extra < /dev/null 2>&1 | tail -2
    id=$(curl -s --max-time 5 http://127.0.0.1:$PORT/v1/models | python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
    [[ -z "$id" ]] && { say "=== $label: SKIPPED (no server)"; continue; }
    say "=== $label: server model id $id"
    LABEL=$label MODEL=$id PORT=$PORT SAMPLES=$samples python3 pi-agent-eval.py < /dev/null 2>&1 | tee -a pi-agent-eval-$label.log
    $STRATA launch --stop < /dev/null 2>&1 | tail -1
    sleep 10
done
say "=== pi follow-up done"
