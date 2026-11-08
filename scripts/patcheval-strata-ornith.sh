#!/usr/bin/env bash
# Overnight: Ornith-1.5-122B UD-Q4_K_XL (unsloth, arch qwen35moe) on Strata's Qwen3.6-family engine path, then BenchKit
# PatchEval through pi with the same limits as the Qwen3.8 runs (1800 s per task, 1 task at a time, Docker sandbox).
# Strata's setup has no Ornith entry, so this writes the config that setup writes for Qwen3.6-35B-A3B (install_own_path):
# tokenizer from the GGUF, --native <shard 1> --max-context N --prefill auto --mtp 2 --pool-workers 9.
# Steps: wait for ornith15-download.sh -> wait for the Strata 0.1.55 engine (max 30 min, else the installed one) ->
# tokenizer -> start at 64k (fallback 32k) -> smoke test (chat + tool call) -> PatchEval -> stop.
# Usage: setsid nohup ./patcheval-strata-ornith.sh > patcheval-strata-ornith-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
PORT=8099; COOL=${COOL:-65}; LABEL=ornith15-udq4kxl
M=/home/sum/.cache/lm-studio/models/unsloth/Ornith-1.5-122B-GGUF
GGUF=$M/Ornith-1.5-122B-UD-Q4_K_XL-00001-of-00003.gguf
SD=/home/sum/.local/share/strata
PACK=/home/sum/.cache/lm-studio/packs/ornith15-ud-q4_k_xl
CFG=$SD/install/strata-ornith15-ud-q4_k_xl.json
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
OUT=benchkit-patcheval-strata-$LABEL.log
SRV=$SD/install/strata-ornith15-server.log
cpu_t() { sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print int($4)}'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "STOP: $*"; pkill -f "serve/server.py.*$CFG" 2>/dev/null; exit 1; }

say "# patcheval-strata-ornith start"
until grep -q -E "all shards done|FAILED" ornith15-download.log; do sleep 60; done
grep -q FAILED ornith15-download.log && die "download failed: $(grep FAILED ornith15-download.log)"
say "download done ($(du -sh $M | cut -f1))"

for i in $(seq 1 30); do ls $SD/components/engine | grep -q 0.1.55 && break; sleep 60; done
pkill -f "strata update" 2>/dev/null
say "engines: $(ls $SD/components/engine | tr '\n' ' ')  terminal: $(readlink -f $SD/terminal/current)"
T=$(readlink -f $SD/terminal/current); PY=$T/python/bin/python3.12

if [[ ! -f $PACK/tokenizer/vocab.json ]]; then
    STRATA_GGUF_PY=$SD/install/third_party/llama.cpp/gguf-py $PY $T/tools/strata_tokenizer.py --gguf "$GGUF" --out "$PACK" \
        || die "tokenizer extraction failed"
fi
say "tokenizer: $PACK/tokenizer"

start() {  # context
    pkill -f "serve/server.py.*$CFG" 2>/dev/null; sleep 3
    cat > $CFG <<EOF
{"exe": "component:strata-engine", "arch": "qwen35moe",
 "args": ["--native", "$GGUF", "--max-context", "$1", "--prefill", "auto", "--mtp", "2", "--pool-workers", "9"],
 "cwd": "$T", "tokenizer": "$PACK/tokenizer", "model_name": "ornith-1.5-122b-ud-q4_k_xl",
 "log": "$SD/install/strata-ornith15-ud-q4_k_xl.log", "lib_dirs": [], "port": $PORT}
EOF
    say "cooling to ${COOL}C (now $(cpu_t)C)"
    for i in $(seq 1 80); do [[ $(cpu_t) -lt $COOL ]] && break; sleep 15; done
    say "starting Strata at context $1"
    (cd $T && setsid nohup $PY serve/server.py --engine strata --config $CFG --port $PORT >> $SRV 2>&1 < /dev/null &)
    for i in $(seq 1 180); do   # up to 30 min: 80 GB read from disk, experts pinned in RAM
        curl -s -m3 localhost:$PORT/v1/models | grep -q '"loaded"' && { say "ready after $((i*10)) s, VRAM $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"; return 0; }
        pgrep -f "serve/server.py.*$CFG" >/dev/null || break; sleep 10
    done
    say "server did not come up at context $1; last log lines:"; tail -8 $SRV; tail -5 $SD/install/strata-ornith15-ud-q4_k_xl.log
    return 1
}
start 65536 || start 32768 || die "Strata could not start Ornith"
CTX=$(python3 -c "import json; a=json.load(open('$CFG'))['args']; print(a[a.index('--max-context')+1])")

say "smoke test"
SMOKE=$(curl -s -m 600 localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"x","max_tokens":3000,
 "messages":[{"role":"user","content":"Use the bash tool to list the files in /tmp."}],
 "tools":[{"type":"function","function":{"name":"bash","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}}]}')
echo "$SMOKE" | python3 -c 'import json,sys; d=json.load(sys.stdin); m=d["choices"][0]["message"]; u=d.get("usage",{})
print("  tool_calls:", json.dumps(m.get("tool_calls"))[:300]); print("  content:", (m.get("content") or "")[:200].replace("\n"," "))
print("  usage:", u, " timings:", json.dumps(d.get("timings", {}))[:200])' || { echo "  raw: ${SMOKE:0:600}"; die "smoke test failed"; }
echo "$SMOKE" | grep -q '"tool_calls"' || die "smoke test: no tool call"

pgrep -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1" >/dev/null || \
    { setsid nohup socat TCP-LISTEN:$PORT,bind=172.17.0.1,reuseaddr,fork TCP:127.0.0.1:$PORT >/dev/null 2>&1 </dev/null & sleep 1; }
id=$(curl -s -m5 http://172.17.0.1:$PORT/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])') \
    || die "docker bridge check failed"
docker info >/dev/null 2>&1 || die "Docker daemon not running"
say "=== $LABEL: PatchEval start (model $id, context $CTX)"
(cd $BK && BENCHKIT_PI_TIMEOUT=1800 BENCHKIT_PROVIDER=openai BENCHKIT_HOST=http://172.17.0.1:$PORT/v1 \
    BENCHKIT_HARDWARE="RTX 4070 Laptop 8GB (Strata $(basename $(readlink -f $SD/terminal/current)), $LABEL, ctx $CTX)" \
    uv run benchkit --headless --models "$id" --benchmarks patcheval --harness pi) > $OUT 2>&1 & bp=$!
./llama-gpu-power-log.sh $OUT.power $bp & wait $bp
say "=== $LABEL: benchkit exit $?"
grep -E '^\[.*(PASS|FAIL|TIMEOUT|ERR)|^Saved:' $OUT | tail -25
awk '{c=$8; gsub(/cpu=|C/,"",c); w+=$3; t+=c; if(c+0>m)m=c+0; n++} END{if(n) printf "    mean GPU W %.1f  mean CPU %.0fC max %dC\n", w/n, t/n, m}' $OUT.power
pkill -f "serve/server.py.*$CFG"; pkill -f "socat TCP-LISTEN:$PORT,bind=172.17.0.1"
say "# patcheval-strata-ornith done"
