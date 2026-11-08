#!/usr/bin/env bash
# Drafter A/B on one engine: MTP vs DFlash2, Qwen3.8 IQ3_S, 64k, tail skip off + route prior 1.5 (our run setup).
# Starts alternate (mtp dflash2 mtp dflash2) so drift and heat hit both arms. Each start: one discarded warm-up,
# then 3 fixed prompts (code, prose, ~8K-token agent-style) with the server's default sampling and a fixed seed.
# Records expert-cache slots, free VRAM, decode t/s and draft acceptance per request.
# Usage: setsid -f ./strata-drafter-check.sh > strata-drafter-check-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099; COOL=${COOL:-65}; MAXTOK=${MAXTOK:-700}
MODEL_DIR=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF
LOG=~/.local/state/strata/launch/iq3_s-64k.engine.log
ORDER=${ORDER:-"mtp dflash2 mtp dflash2"}
TSV=strata-drafter-check-$(date +%Y%m%d-%H%M).tsv
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

SRC=benchkit-src/BenchKit/src/benchkit
LONG="Below are two Python modules from a benchmark harness.

### jobs.py
$(cat $SRC/jobs.py)

### config.py
$(cat $SRC/config.py)

Task: review parse_slice and slice_label in jobs.py. List every input that is handled wrongly or inconsistently, then write a corrected version of both functions and pytest cases that cover the edge cases."
CODE="Write a Python function parse_iso8601_duration(s) that turns strings like 'P3DT4H5M6.5S' or 'PT0.25S' into seconds as a float. Reject invalid input with ValueError. Then write pytest tests for it."
PROSE="Explain to a new backend engineer how a hash map handles collisions, why the load factor matters, and when you would pick open addressing over separate chaining. Use one small worked example."

ask() {  # name prompt -> prints one TSV row
    python3 -I - "$1" "$2" "$MAXTOK" "$PORT" <<'EOF'
import json,sys,time,urllib.request
name,prompt,maxtok,port=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
body=json.dumps({"model":"qwen3.8-flash-next-iq3_s","max_tokens":maxtok,"seed":7,
                 "messages":[{"role":"user","content":prompt}]}).encode()
req=urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",body,{"Content-Type":"application/json"})
t=time.time(); r=json.load(urllib.request.urlopen(req,timeout=900)); wall=time.time()-t
tm=r.get("timings",{}); u=r.get("usage",{})
acc=tm.get("draft_n_accepted",0); dn=tm.get("draft_n",0)
print(f'{name}\t{u.get("prompt_tokens")}\t{tm.get("predicted_n")}\t{tm.get("predicted_per_second")}\t{tm.get("prompt_per_second")}\t{acc}/{dn}\t{wall:.1f}')
EOF
}

echo -e "start\tdrafter\tslots\tfree_mib\tprompt\tprompt_tok\tgen_tok\tdecode_tps\tprompt_tps\tdrafts_acc\twall_s" > $TSV
say "# drafter check  order: $ORDER  engine: $($STRATA --version | awk '{print $4}' | tr -d ';')  max_tokens $MAXTOK"
i=0
for d in $ORDER; do
    i=$((i+1))
    $STRATA launch --stop </dev/null >/dev/null 2>&1
    for k in $(seq 1 60); do [[ $(cpu_t) -lt $COOL ]] && break; sleep 10; done
    say "=== start $i: $d (CPU $(cpu_t)C)"
    n0=$(wc -l < $LOG)
    $STRATA launch --model-path $MODEL_DIR --model iq3_s --context 64k --vision off --access local --port $PORT \
        --no-api-key --yes --no-tui --restart --drafting $d \
        --set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5 </dev/null 2>&1 | tail -1
    ok=0; for k in $(seq 1 90); do curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"' && { ok=1; break; }; sleep 5; done
    (( ok )) || { say "=== start $i: server not ready, skipped"; continue; }
    slots=$(tail -n +$n0 $LOG | grep -oE 'expert cache [0-9]+ slots' | tail -1 | grep -oE '[0-9]+')
    free=$(tail -n +$n0 $LOG | grep -oE '[0-9]+ MiB of VRAM free with everything loaded' | tail -1 | grep -oE '^[0-9]+')
    drafter=$(tail -n +$n0 $LOG | grep -oE 'DFlash2 drafter on|mtp: draft layer loaded' | tail -1)
    say "    slots $slots, free ${free} MiB, drafter: $drafter"
    ask warmup "Say hi." >/dev/null
    for p in code prose agent8k; do
        case $p in code) txt=$CODE;; prose) txt=$PROSE;; agent8k) txt=$LONG;; esac
        row=$(ask $p "$txt") || { say "    $p: request failed"; continue; }
        echo -e "$i\t$d\t$slots\t$free\t$row" >> $TSV; say "    $row"
    done
done
$STRATA launch --stop </dev/null >/dev/null 2>&1
say "# done; table: $TSV"
python3 -I - $TSV <<'EOF'
import csv,sys,statistics as st
rows=list(csv.DictReader(open(sys.argv[1]),delimiter="\t"))
for d in ("mtp","dflash2"):
    r=[x for x in rows if x["drafter"]==d]
    if not r: continue
    g=sum(int(x["gen_tok"]) for x in r); s=sum(int(x["gen_tok"])/float(x["decode_tps"]) for x in r)
    print(f'{d:8} slots {",".join(sorted({x["slots"] for x in r}))}  free MiB {",".join(sorted({x["free_mib"] for x in r}))}  '
          f'decode {g/s:.1f} t/s over {g} tokens  per prompt: ' +
          ", ".join(f'{p} {st.median(float(x["decode_tps"]) for x in r if x["prompt"]==p):.1f}' for p in ("code","prose","agent8k")))
EOF
