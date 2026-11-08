#!/usr/bin/env bash
# Hand a running PatchEval run over to a fresh BenchKit process at a task boundary, without re-running
# finished tasks: wait for the next task to complete, send ONE SIGINT to that run's benchkit python process
# (BenchKit then saves every finished task; a second SIGINT would abort and save nothing), wait for "Saved:",
# then start the remaining slice (patcheval:N-20) with the current BenchKit code under a new label.
# Usage: patcheval-handoff.sh pi-minimax|pi-deepseek|mcode-minimax
#        LOG_OVERRIDE=benchkit-patcheval-...-from5.log patcheval-handoff.sh pi-minimax   # hand off a resumed run again
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
say() { echo "[$(date +%H:%M:%S)] $*"; }
case ${1:?run name} in
    pi-minimax)    LOG=benchkit-patcheval-pi-minimax-minimax-m3-1-flash-max-65536.log
                   MODEL=minimax/minimax-m3.1-flash; AGENT=pi; SCRIPT=./patcheval-hosted.sh
                   ENVS=(PROVIDER=vercel-gateway-free MODEL=$MODEL) ;;
    pi-deepseek)   LOG=benchkit-patcheval-pi-deepseek-deepseek-v4-1-flash-1017-max-65536.log
                   MODEL=deepseek/deepseek-v4.1-flash-1017; AGENT=pi; SCRIPT=./patcheval-hosted.sh
                   ENVS=(PROVIDER=openrouter MODEL=$MODEL) ;;
    mcode-minimax) LOG=benchkit-patcheval-mcode-minimax-minimax-m3-1-flash-max.log
                   MODEL=minimax/minimax-m3.1-flash; AGENT=mcode; SCRIPT=./patcheval-mcode.sh
                   ENVS=() ;;
    *) echo "unknown run $1"; exit 2 ;;
esac
LOG=${LOG_OVERRIDE:-$LOG}
OFFSET=$(grep -oE -- '-from[0-9]+\.log$' <<<"$LOG" | tr -dc 0-9); OFFSET=${OFFSET:-0}
done_count() { echo $(( OFFSET + $(grep -cE '^\[[0-9:]+\] +[✓✗!] +[0-9]+/[0-9]+ ' "$LOG") )); }

# The benchkit python process of this run: same --models for pi-minimax and mcode, so tell them apart by
# BENCHKIT_AGENT in its environment.
pid=""
for p in $(pgrep -f "[.]venv/bin/benchkit --headless --models $MODEL "); do
    is_mcode=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -c '^BENCHKIT_AGENT=mcode$')
    # Several runs can share model and agent (a resumed run next to a one-task retry): match the slice too.
    slice=$(tr '\0' ' ' < /proc/$p/cmdline | grep -oE -- '--benchmarks [^ ]+' | cut -d' ' -f2)
    if (( OFFSET > 0 )); then [[ $slice == patcheval:$OFFSET-20 ]] || continue
    else [[ $slice == patcheval ]] || continue; fi
    [[ $AGENT == mcode && $is_mcode == 1 ]] && pid=$p
    [[ $AGENT == pi && $is_mcode == 0 ]] && pid=$p
done
[[ -n $pid ]] || { say "STOP: no running benchkit process for $1"; exit 1; }

start=$(done_count)
say "$1: pid $pid, $start/20 done; waiting for the next task to finish"
while (( $(done_count) == start )); do
    kill -0 $pid 2>/dev/null || { say "$1: process ended on its own"; break; }
    sleep 15
done
n=$(done_count)
grep -qE '^Saved:' "$LOG" || {
    kill -INT $pid
    say "$1: sent one SIGINT after task $n"
    while kill -0 $pid 2>/dev/null; do sleep 5; done
}
grep -E '^Saved:|Aborted|No results' "$LOG" | tail -1
grep -qE '^Saved:' "$LOG" || { say "STOP: $1 did not save its results; not resuming"; exit 1; }
(( n >= 20 )) && { say "$1: all 20 done, nothing to resume"; exit 0; }

label="$(basename "$LOG" .log | sed -E 's/^benchkit-patcheval-//; s/-from[0-9]+$//')-from$n"
say "$1: resuming tasks $n-20 as $label"
env "${ENVS[@]}" SLICE="patcheval:$n-20" LABEL="$label" setsid nohup $SCRIPT \
    > "patcheval-$label-$(date +%Y%m%d-%H%M).txt" 2>&1 < /dev/null &
sleep 20; say "$1: resume started: $(tail -1 benchkit-patcheval-$label.log 2>/dev/null)"
