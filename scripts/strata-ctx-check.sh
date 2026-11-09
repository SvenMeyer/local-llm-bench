#!/usr/bin/env bash
# Context-size check (copy of strata-mem-check.sh): Qwen3.8 IQ3_S, DFlash2, tail skip off + route prior 1.5, KV int8.
# Setups are context sizes; prompts: code, ~5K agent-style, ~40K (many BenchKit source files). Order 64k first and last
# so a run-order drift shows up.
# Setups: base (KV int8, 32768 cells on the card), k8v4 KV, 20480 cells on the card, and both. Freed VRAM goes to
# expert slots automatically. Per start: one discarded warm-up, then the 3 prompts of strata-drafter-check.sh.
# Records expert slots, free VRAM at load, lowest free VRAM during the prompts (nvidia-smi, 1 s), decode/prompt t/s.
# Usage: setsid -f ./strata-ctx-check.sh > strata-ctx-check-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
STRATA=~/.local/bin/strata; PORT=8099; COOL=${COOL:-65}; MAXTOK=${MAXTOK:-700}
MODEL_DIR=/home/sum/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF
SETUPS=${SETUPS:-"64k 128k 96k 64k"}
TSV=strata-ctx-check-$(date +%Y%m%d-%H%M).tsv
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }
args_for() { echo "--context $1"; }

SRC=benchkit-src/BenchKit/src/benchkit
LONG="Below are two Python modules from a benchmark harness.

### jobs.py
$(cat $SRC/jobs.py)

### config.py
$(cat $SRC/config.py)

Task: review parse_slice and slice_label in jobs.py. List every input that is handled wrongly or inconsistently, then write a corrected version of both functions and pytest cases that cover the edge cases."
CODE="Write a Python function parse_iso8601_duration(s) that turns strings like 'P3DT4H5M6.5S' or 'PT0.25S' into seconds as a float. Reject invalid input with ValueError. Then write pytest tests for it."
HUGE="Below is the source of a benchmark harness.

$(for f in $SRC/engine.py $SRC/client.py $SRC/sandbox.py $SRC/report.py; do echo "### $f"; cat $f; done | head -c 150000)

Task: summarise how a Pi agent task flows from job start to grading, naming the functions involved, in at most 400 words."
BIG() {  # ~N KB of BenchKit source (about 3.9 chars per token) + one question
    echo "Below is the source of a benchmark harness."; echo
    for f in $SRC/*.py $SRC/benchmarks/*.py; do echo "### $f"; cat $f; done | head -c ${1}000
    echo; echo "Task: summarise how a Pi agent task flows from job start to grading, naming the functions involved, in at most 400 words."
}
PROSE="Explain to a new backend engineer how a hash map handles collisions, why the load factor matters, and when you would pick open addressing over separate chaining. Use one small worked example."

ask() {  # name prompt -> prints one TSV row
    local pf; pf=$(mktemp); printf '%s' "$2" > $pf   # prompt via file: one argv string is capped at 128 KB
    python3 -I - "$1" "$pf" "$MAXTOK" "$PORT" <<'EOF'
import json,sys,time,urllib.request
name,maxtok,port=sys.argv[1],int(sys.argv[3]),sys.argv[4]; prompt=open(sys.argv[2]).read()
body=json.dumps({"model":"qwen3.8-flash-next-iq3_s","max_tokens":maxtok,"seed":7,
                 "messages":[{"role":"user","content":prompt}]}).encode()
req=urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",body,{"Content-Type":"application/json"})
t=time.time(); r=json.load(urllib.request.urlopen(req,timeout=900)); wall=time.time()-t
tm=r.get("timings",{}); u=r.get("usage",{})
acc=tm.get("draft_n_accepted",0); dn=tm.get("draft_n",0)
print(f'{name}\t{u.get("prompt_tokens")}\t{tm.get("predicted_n")}\t{tm.get("predicted_per_second")}\t{tm.get("prompt_per_second")}\t{acc}/{dn}\t{wall:.1f}')
EOF
    local rc=$?; rm -f $pf; return $rc
}

echo -e "setup\tslots\tfree_load_mib\tmin_free_mib\tkv_line\tprompt\tprompt_tok\tgen_tok\tdecode_tps\tprompt_tps\tdrafts_acc\twall_s" > $TSV
say "# mem check  setups: $SETUPS  engine: $($STRATA --version | awk '{print $4}' | tr -d ';')  max_tokens $MAXTOK"
for s in $SETUPS; do
    $STRATA launch --stop </dev/null >/dev/null 2>&1
    for k in $(seq 1 60); do [[ $(cpu_t) -lt $COOL ]] && break; sleep 10; done
    say "=== $s: $(args_for $s) (CPU $(cpu_t)C)"
    LOG=~/.local/state/strata/launch/iq3_s-$s.engine.log; touch $LOG; n0=$(wc -l < $LOG)
    $STRATA launch --model-path $MODEL_DIR --model iq3_s --vision off --access local --port $PORT \
        --no-api-key --yes --no-tui --restart --drafting dflash2 \
        --set STRATA_ROUTE_TAIL_SKIP=0 --set STRATA_ROUTE_PRIOR=1.5 $(args_for $s) </dev/null 2>&1 | tail -1
    ok=0; for k in $(seq 1 90); do curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"' && { ok=1; break; }; sleep 5; done
    (( ok )) || { say "=== $s: server not ready, skipped"; tail -n +$n0 $LOG | grep -iE 'error|out of memory|fail' | tail -3; continue; }
    L=$(tail -n +$n0 $LOG)
    slots=$(grep -oE 'expert cache [0-9]+ slots' <<<"$L" | tail -1 | grep -oE '[0-9]+')
    free=$(grep -oE '[0-9]+ MiB of VRAM free with everything loaded' <<<"$L" | tail -1 | grep -oE '^[0-9]+')
    kvl=$(grep -oE 'KV streaming: [0-9]+ of [0-9]+ cells' <<<"$L" | tail -1 | grep -oE '[0-9]+ of' | tr -d ' of')
    kvt=$(grep 'engine started' <<<"$L" | tail -1 | grep -oE -- '--kv [a-z0-9_]+' | awk '{print $2}')
    say "    slots $slots, free ${free} MiB at load, KV $kvt, ${kvl:-all} cells on the card"
    ask warmup "Say hi." >/dev/null
    MF=$(mktemp); ( while :; do nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits >> $MF; sleep 1; done ) & mp=$!
    for p in ${PROMPTS:-code agent8k huge40k}; do
        case $p in code) txt=$CODE;; agent8k) txt=$LONG;; huge40k) txt=$HUGE;; big60k) txt=$(BIG 235);; big95k) txt=$(BIG 370);; esac
        row=$(ask $p "$txt") || { say "    $p: request failed"; continue; }
        mf=$(sort -n $MF | head -1)
        echo -e "$s\t$slots\t$free\t$mf\t$kvt/${kvl:-all}\t$row" >> $TSV; say "    $row  (min free so far ${mf} MiB)"
    done
    kill $mp 2>/dev/null; rm -f $MF
done
$STRATA launch --stop </dev/null >/dev/null 2>&1
say "# done; table: $TSV"
python3 -I - $TSV <<'EOF'
import csv,sys
rows=list(csv.DictReader(open(sys.argv[1]),delimiter="\t"))
for s in dict.fromkeys(x["setup"] for x in rows):
    r=[x for x in rows if x["setup"]==s]
    g=sum(int(x["gen_tok"]) for x in r); t=sum(int(x["gen_tok"])/float(x["decode_tps"]) for x in r)
    a8=[x for x in r if x["prompt"] in ("huge40k","big60k","big95k")][-1:]
    print(f'{s:7} slots {r[0]["slots"]}  free at load {r[0]["free_load_mib"]}  min free {min(int(x["min_free_mib"]) for x in r)} MiB  '
          f'decode {g/t:.1f} t/s  ' + "  ".join(f'{x["prompt"]} {x["decode_tps"]}' for x in r) +
          (f'  longest prompt {a8[0]["prompt_tok"]} tok, prefill {a8[0]["prompt_tps"]} t/s' if a8 else ''))
EOF
