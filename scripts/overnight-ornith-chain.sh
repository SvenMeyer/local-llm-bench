#!/usr/bin/env bash
# Overnight chain, 2026-10-31. Nothing touches the GPU or loads a model until the user's backup rsync is finished.
#  1. wait for the backup rsync (to /run/media/sum/WD4TB) to end
#  2. finish the Strata 0.1.55 update (download is already complete; its test start loads IQ3_S once)
#  3. if the Ornith download is still running: replay the 24-run agent suite on Qwen3.8 IQ3_S, tail skip off
#     (0.1.52 baseline: 24/24 in 76 min, 3992 tok/task, 24.2 t/s) -> llama-agent-eval-strata-iq3s-noskip-0155.*
#  4. Ornith-1.5 PatchEval: patcheval-strata-ornith.sh (waits for the download itself)
# Usage: setsid nohup ./overnight-ornith-chain.sh > overnight-ornith-chain-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099
IQ3S=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF
say() { echo "[$(date +%H:%M:%S)] $*"; }

say "1. waiting for the backup rsync to finish"
while pgrep -f "rsync .*/run/media/sum/WD4TB" >/dev/null; do sleep 60; done
say "1. rsync finished"

say "2. Strata update"
for i in 1 2 3; do
    ls ~/.local/share/strata/components/engine/ | grep -q 0.1.55 && break
    $STRATA update < /dev/null 2>&1 | grep -v "downloading engine" | tail -8; sleep 10
done
say "2. engines: $(ls ~/.local/share/strata/components/engine/ | tr '\n' ' '); $($STRATA --version 2>&1 | cut -c1-60)"

if ! grep -q "all shards done" ornith15-download.log; then
    L=strata-iq3s-noskip-0155
    say "3. IQ3_S replay on the new engine ($L)"
    $STRATA launch --model-path "$IQ3S" --model iq3_s --context 64k --vision off --access local --port $PORT --no-api-key \
        --yes --no-tui --restart --set STRATA_ROUTE_TAIL_SKIP=0 < /dev/null 2>&1 | tail -2
    if curl -s --max-time 5 http://127.0.0.1:$PORT/v1/models | grep -q '"loaded"'; then
        LABEL=$L PORT=$PORT SEEDS=1,2,3 MAX_TOKENS=21846 python3 llama-agent-eval.py < /dev/null > llama-agent-eval-$L.log 2>&1
        cp ~/.local/state/strata/launch/iq3_s-64k.engine.log llama-serve-$L.engine.log 2>/dev/null
        say "3. summary vs 0.1.52"; python3 llama-agent-eval-summary.py strata-iq3s-noskip $L
    else say "3. IQ3_S replay SKIPPED (server did not start)"; fi
    $STRATA launch --stop < /dev/null 2>&1 | tail -1
else say "3. Ornith download already done: IQ3_S replay skipped"; fi

say "4. Ornith-1.5 PatchEval"
./patcheval-strata-ornith.sh
say "# chain done"
