#!/usr/bin/env bash
# Full evaluation of one Qwen3.8 quant on engine 11170, one model in RAM at a time:
#   1. wikitext-2 PPL (c512 x 40) + KLD against the UD-IQ4_XS logits base
#      (QUANT=iq4xs instead WRITES the base file)
#   2. occupied-context speed probe x2 (16384 alloc, MTP n3, ub from the direct launcher)
#   3. agent tool-use eval (llama-agent-eval.py, 65536 ctx, ub 512, MTP n3), SEEDS
# Usage: QUANT=coder ./llama-qwen38-eval-pipeline.sh      STAGES="1 2 3" SEEDS=1,2,3 by default
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
QUANT="${QUANT:?set QUANT}"
STAGES="${STAGES:-1 2 3}"
SEEDS="${SEEDS:-1,2,3}"
BIN=$HOME/.unsloth/llama.cpp-mix-pr220-q2_0/build/bin
export BIN
KLD_BASE=eval-data/kld-base-udiq4xs-c512x40.bin
WIKI=eval-data/wikitext-2-raw/wiki.test.raw
TAG=$(date +%Y%m%d-%H%M%S)
stop_server() { pkill -TERM -x llama-server; for i in $(seq 1 40); do pgrep -x llama-server >/dev/null || return 0; sleep 1; done; pkill -KILL -x llama-server; }
model_path() { grep -A1 "^    $QUANT)" llama-serve-qwen38-direct.sh | grep -oE 'MODEL=[^ ]+' | head -1 | cut -d= -f2- | sed "s#\$MODELS#/home/sum/.cache/lm-studio/models#"; }

echo "# pipeline QUANT=$QUANT STAGES=$STAGES SEEDS=$SEEDS start $(date -Iseconds)"
for s in $STAGES; do
  stop_server
  case $s in
  1)
    M=$(model_path)
    if [[ "$QUANT" == iq4xs ]]; then KARGS=(--kl-divergence-base "$KLD_BASE"); else KARGS=(--kl-divergence-base "$KLD_BASE" --kl-divergence); fi
    log=llama-ppl-kld-qwen38-$QUANT-b11170-c512x40-$TAG.log
    "$BIN/llama-perplexity" -m "$M" -f "$WIKI" -c 512 --chunks 40 --cpu-moe -ngl 999 -fa on \
        -ctk q8_0 -ctv q8_0 -t 10 "${KARGS[@]}" > "$log" 2>&1
    echo "# stage 1 exit $? -> $log"
    grep -E "Final estimate|Mean +KLD|Same top p|Mean +PPL\(Q\)" "$log" | sed 's/^[0-9.]* I //'
    ;;
  2)
    QUANT=$QUANT CTX=16384 setsid nohup ./llama-serve-qwen38-direct.sh > llama-serve-pipeline-$QUANT-16k.log 2>&1 < /dev/null &
    ./llama-wait-ready.sh 8099 300 || { echo "# stage 2 FAILED to start"; tail -3 llama-serve-pipeline-$QUANT-16k.log; continue; }
    for r in r1 r2; do
      SKIP_RELOAD=1 VARIANT=$QUANT OUT=llama-bench-qwen38-$QUANT-b11170-occupied-$TAG-$r.log ./llama-bench-qwen38-unsloth-occupied.sh > /dev/null 2>&1
      echo "# stage 2 $r"; grep -E '^ +[0-9]|FAILED|MiB' llama-bench-qwen38-$QUANT-b11170-occupied-$TAG-$r.log
    done
    ;;
  3)
    QUANT=$QUANT CTX=65536 UB=512 setsid nohup ./llama-serve-qwen38-direct.sh > llama-serve-pipeline-$QUANT-64k.log 2>&1 < /dev/null &
    ./llama-wait-ready.sh 8099 300 || { echo "# stage 3 FAILED to start"; tail -3 llama-serve-pipeline-$QUANT-64k.log; continue; }
    LABEL=$QUANT SEEDS=$SEEDS python3 llama-agent-eval.py 2>&1 | tee -a llama-agent-eval-$QUANT.log
    ;;
  esac
done
stop_server
echo "# pipeline QUANT=$QUANT done $(date -Iseconds)"
