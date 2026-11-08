#!/usr/bin/env bash
# Block until llama-server answers /health with "ok", the process dies, or a
# timeout. Does not depend on log wording (which changes between builds).
#
# Usage: ./llama-wait-ready.sh [PORT] [TIMEOUT_S]
#   PORT omitted: taken from the running llama-server's --port (Studio picks a
#   random one). Exit 0 = ready, 1 = process died, 2 = timeout.
set -uo pipefail
PORT="${1:-}"
TIMEOUT="${2:-300}"
T0=$(date +%s)
sleep 2  # let a just-launched process appear
while :; do
    PID=$(pgrep -x llama-server | head -1)
    el=$(( $(date +%s) - T0 ))
    if [[ -z "$PID" ]]; then
        # Studio's `unsloth run` may still be spawning it; allow 30 s.
        (( el > 30 )) && { echo "FAILED: no llama-server process after ${el}s"; exit 1; }
    else
        p="$PORT"
        [[ -z "$p" ]] && p=$(tr '\0' '\n' < /proc/$PID/cmdline 2>/dev/null | grep -A1 -x -- '--port' | tail -1)
        if [[ -n "$p" ]] && curl -s --max-time 2 "http://${WAIT_HOST:-127.0.0.1}:$p/health" | grep -q '"ok"'; then
            echo "READY port $p after ${el}s, VRAM $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
            exit 0
        fi
    fi
    (( el > TIMEOUT )) && { echo "TIMEOUT after ${el}s"; exit 2; }
    sleep 2
done
