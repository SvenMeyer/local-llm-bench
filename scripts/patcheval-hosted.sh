#!/usr/bin/env bash
# BenchKit PatchEval through pi against a HOSTED model, same limits as the local runs
# (1800 s per task, 1 task at a time, Docker sandbox, hidden-test grading), so scores compare directly.
# The model entry (reasoning, thinkingLevelMap, compat, contextWindow) is copied from the user's own
# ~/.pi/agent/models.json, so pi behaves as it does for the user; only maxTokens is set here (MAX_TOKENS).
# The key is read from the same file (or the env var it names) and never printed; BenchKit's sandbox proxy
# carries it, the agent container never sees it.
# Needs the local BenchKit patch: BENCHKIT_PI_MODEL / BENCHKIT_PI_THINKING (src/benchkit/sandbox.py).
# Usage: setsid nohup ./patcheval-hosted.sh > patcheval-hosted-<label>-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
#        PROVIDER=openrouter MODEL=deepseek/deepseek-v4.1-flash-1017 ./patcheval-hosted.sh
#        SLICE=patcheval:1 ...    # smoke test
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
PROVIDER=${PROVIDER:-vercel-gateway-free}
MODEL=${MODEL:-minimax/minimax-m3.1-flash}
SLICE=${SLICE:-patcheval}
THINKING=${THINKING:-max}
MAX_TOKENS=${MAX_TOKENS:-65536}
LABEL=${LABEL:-pi-$(echo "$MODEL" | tr '/.' '--')-$THINKING-${MAX_TOKENS}}
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
OUT=benchkit-patcheval-$LABEL.log
say() { echo "[$(date +%H:%M:%S)] $*"; }

# Prints three lines: base URL, key, model-entry JSON. Never echoed.
cfg=$(python3 - "$PROVIDER" "$MODEL" "$MAX_TOKENS" <<'EOF'
import json, os, re, subprocess, sys
prov, model_id, max_tokens = sys.argv[1], sys.argv[2], int(sys.argv[3])
p = json.load(open(os.path.expanduser("~/.pi/agent/models.json")))["providers"][prov]
builtin = {"openrouter": "https://openrouter.ai/api/v1", "vercel-ai-gateway": "https://ai-gateway.vercel.sh/v1"}
base = p.get("baseUrl") or builtin[prov]
key = p.get("apiKey") or ""
if key.startswith("!"):
    key = subprocess.run(key[1:], shell=True, capture_output=True, text=True).stdout.strip()
elif (ref := re.fullmatch(r"\$?\{?([A-Za-z_][A-Za-z0-9_]*)\}?", key)) and ref.group(1) in os.environ:
    key = os.environ[ref.group(1)]  # "NAME", "$NAME" or "${NAME}"
if not key and prov == "openrouter":
    key = os.environ.get("OPENROUTER_API_KEY", "")
m = next(m for m in p["models"] if m["id"] == model_id)
entry = {k: m[k] for k in ("name", "reasoning", "input", "contextWindow", "compat", "thinkingLevelMap", "cost") if k in m}
if "compat" in p:
    entry["compat"] = {**p["compat"], **entry.get("compat", {})}
entry["maxTokens"] = max_tokens
# pi offers xhigh/max only when thinkingLevelMap names them; the gateway lists low..max for MiniMax M3.1.
if model_id == "minimax/minimax-m3.1-flash":
    entry.setdefault("thinkingLevelMap", {}).update({"xhigh": "xhigh", "max": "max"})
print(base); print(key); print(json.dumps(entry))
EOF
) || { say "STOP: $PROVIDER/$MODEL not found in ~/.pi/agent/models.json"; exit 1; }
HOST=$(sed -n 1p <<<"$cfg"); KEY=$(sed -n 2p <<<"$cfg"); PI_MODEL=$(sed -n 3p <<<"$cfg")
[[ -n $KEY ]] || { say "STOP: no API key for $PROVIDER"; exit 1; }

say "# $LABEL start  provider=$PROVIDER model=$MODEL thinking=$THINKING maxTokens=$MAX_TOKENS slice=$SLICE"
say "  pi model entry: $PI_MODEL"
docker info >/dev/null 2>&1 || { say "STOP: Docker daemon not running (sudo systemctl start docker)"; exit 1; }
# A real 1-token call: /models is public on some gateways, so it cannot catch a bad key.
code=$(curl -s -m120 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_completion_tokens\":256}" \
    "$HOST/chat/completions")
[[ $code == 200 ]] || { say "STOP: test call to $MODEL returned HTTP $code"; exit 1; }

say "=== $LABEL: PatchEval start"
(cd $BK && BENCHKIT_PI_TIMEOUT=1800 BENCHKIT_PROVIDER=openai BENCHKIT_HOST="$HOST" BENCHKIT_API_KEY="$KEY" \
    BENCHKIT_PI_MODEL="$PI_MODEL" BENCHKIT_PI_THINKING="$THINKING" \
    BENCHKIT_CONCURRENCY=1 BENCHKIT_HARDWARE="hosted: $PROVIDER ($MODEL), pi thinking=$THINKING maxTokens=$MAX_TOKENS" \
    uv run benchkit --headless --models "$MODEL" --benchmarks "$SLICE" --harness pi) > $OUT 2>&1
say "=== $LABEL: benchkit exit $?"
grep -E '^\[.*(PASS|FAIL|TIMEOUT|LENGTH|ERR)|^Saved:' $OUT | tail -25
say "# $LABEL done"
