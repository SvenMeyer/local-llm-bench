#!/usr/bin/env bash
# Overnight: full in-house agent eval (llama-agent-eval.py, 8 tasks x 3 seeds = 24 runs) on Strata,
# one setup after another. Pass bar for a setup worth keeping: 23/24.
#
#   A  strata-iq3xxs         Qwen3.8 GSQ IQ3_XXS, Strata defaults (route tail skip on)
#   B  strata-iq3xxs-noskip  same, STRATA_ROUTE_TAIL_SKIP=0 (every routed expert computed; quality control)
#   D  strata-ud-iq4xs       Qwen3.8 Unsloth UD-IQ4_XS (4-bit, already on disk), Strata defaults
#   E  strata-iq3s           Qwen3.8 GSQ IQ3_S, Strata defaults. Downloaded (shard 1, 54.8 GB, sha256-checked) in the
#                            background when the suite starts; runs last, once the download is verified.
#   C  strata-q2_0           Qwen3.8 GSQ Q2_0, Strata defaults (optional speed alternative, not in default ARMS)
#
# An arm whose llama-agent-eval-<label>.jsonl already holds 24 runs is skipped. (The 2026-10-28 A run is kept as
# strata-iq3xxs-v1: it ran before the answer_room / rejected-tool-call fixes, so A runs again.)
#
# Baselines (llama.cpp / Unsloth engine, 2026-10-27): IQ3_XXS 24/24 in 140 min, Q2_0 24/24 in 122 min.
# Probe 2026-10-28 (t8-scheduler s1): Strata IQ3_XXS PASS 246 s, 38.2 t/s vs llama.cpp 842 s, 9.3 t/s.
#
# Usage: nohup ./llama-strata-overnight.sh > llama-strata-overnight-$(date +%Y%m%d-%H%M).txt 2>&1 &
#        ARMS="A C" ./llama-strata-overnight.sh     # subset
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime

STRATA=~/.local/bin/strata
PORT=8099
MODELS=/home/sum/.cache/lm-studio/models/ISTA-DASLab
IQ3=$MODELS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF
Q2=$MODELS/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF
UD4=/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF
IQ3S=$MODELS/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF
IQ3S_SHARD1=$IQ3S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf
ARMS="${ARMS:-A B D E}"
SEEDS="${SEEDS:-1,2,3}"
STAMP=$(date +%Y%m%d-%H%M%S)

say() { echo "[$(date +%H:%M:%S)] $*"; }

# CPU package / GPU temperature and power every 30 s (the CPU ran at 97 C during the probe).
THERM=llama-strata-overnight-thermal-$STAMP.tsv
( echo -e "time\tcpu_pkg_C\tgpu_C\tgpu_W\tgpu_util"
  while :; do
    c=$(sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print $4; exit}')
    g=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits | tr -d ' ' | tr ',' '\t')
    echo -e "$(date +%H:%M:%S)\t$c\t$g"; sleep 30
  done ) > "$THERM" &
THERM_PID=$!
trap 'kill $THERM_PID 2>/dev/null; $STRATA launch --stop >/dev/null 2>&1' EXIT

# IQ3_S download runs alongside the other arms (network-bound; the evals are CPU/GPU-bound).
DL_PID=""
if [[ " $ARMS " == *" E "* && ! -f "$IQ3S_SHARD1" ]]; then
    say "starting IQ3_S download (log: llama-gsq-iq3s-download.log)"
    ./llama-gsq-download.sh iq3s >> llama-gsq-iq3s-download.log 2>&1 &
    DL_PID=$!
fi

wait_ready() {  # Strata's /v1/models lists the model once it answers
    local t0=$SECONDS
    until curl -s --max-time 2 "http://127.0.0.1:$PORT/v1/models" | grep -q '"loaded"'; do
        (( SECONDS - t0 > 1800 )) && { say "TIMEOUT waiting for server"; return 1; }
        sleep 3
    done
    say "server ready after $((SECONDS - t0)) s, VRAM $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
}

run_arm() {  # label model-path model-name [extra strata launch args...]
    local label=$1 path=$2 model=$3; shift 3
    local done_runs=$(wc -l < "llama-agent-eval-$label.jsonl" 2>/dev/null || echo 0)
    if (( done_runs >= 24 )); then say "=== $label: already has $done_runs runs, skipped"; return; fi
    say "=== $label: launching"
    $STRATA launch --model-path "$path" --model "$model" --context 64k --vision off \
        --access local --port $PORT --no-api-key --yes --no-tui --restart "$@" 2>&1 | tail -4
    wait_ready || { say "=== $label: SKIPPED (no server)"; $STRATA launch --stop; return; }
    local t0=$SECONDS
    # Strata's "answer_room" caps thinking at max_tokens minus a quarter (6144 of 8192); the launcher drops the
    # config key that turns it off. 21846 puts the thinking cap at 16384 (user, 2026-10-28: let the model decide
    # when it has thought enough; llama.cpp never needed more than 6.3k, so this is effectively uncapped on both).
    LABEL=$label PORT=$PORT SEEDS=$SEEDS MAX_TOKENS=${MAX_TOKENS:-21846} python3 llama-agent-eval.py 2>&1 | tee -a llama-agent-eval-$label.log
    say "=== $label: eval done in $(( (SECONDS - t0) / 60 )) min"
    cp ~/.local/state/strata/launch/"$model"-64k.engine.log "llama-serve-$label-$STAMP.engine.log" 2>/dev/null
    $STRATA launch --stop 2>&1 | tail -1
    sleep 10
}

for arm in $ARMS; do
    case $arm in
        A) run_arm strata-iq3xxs        "$IQ3" iq3_xxs ;;
        B) run_arm strata-iq3xxs-noskip "$IQ3" iq3_xxs --set STRATA_ROUTE_TAIL_SKIP=0 ;;
        C) run_arm strata-q2_0          "$Q2"  q2_0 ;;
        # UD-IQ4_XS: 3.6 GiB of Q8_0 dense weights leave the default draft head ~130 MiB short on 8 GB
        # ("mtp: the draft head does not fit"); the English+code draft vocabulary (~81 MiB) fits.
        D) run_arm strata-ud-iq4xs      "$UD4" ud-iq4_xs --family unsloth \
               --set mtp-draft-vocab=/home/sum/.local/share/strata/terminal/0.1.52/data/draft_vocab_en.bin ;;
        E) if [[ -n "$DL_PID" ]]; then say "=== strata-iq3s: waiting for the IQ3_S download"; wait "$DL_PID"; fi
           if [[ -f "$IQ3S_SHARD1" ]]; then run_arm strata-iq3s "$IQ3S" iq3_s
           else say "=== strata-iq3s: SKIPPED (download failed, see llama-gsq-iq3s-download.log)"; fi ;;
        *) say "unknown arm $arm" ;;
    esac
done

say "=== summary"
labels=""
for arm in $ARMS; do case $arm in A) labels+=" strata-iq3xxs";; B) labels+=" strata-iq3xxs-noskip";; C) labels+=" strata-q2_0";; D) labels+=" strata-ud-iq4xs";; E) labels+=" strata-iq3s";; esac; done
have=""; for l in $labels; do [[ -s llama-agent-eval-$l.jsonl ]] && have+=" $l"; done
python3 llama-agent-eval-summary.py gsq-iq3xxs $have
say "thermal log: $THERM"
