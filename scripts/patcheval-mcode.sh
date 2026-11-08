#!/usr/bin/env bash
# BenchKit PatchEval with MiniMax Code (our fork, the code behind `mcode-or`) instead of pi, same sandbox,
# proxy, limits and grading as patcheval-hosted.sh, so pi-vs-mcode is an agent-only difference.
# mcode runs inside BenchKit's Docker sandbox (never on the host): `mcode exec --output-format stream-json`.
# The sandbox config is the user's ~/.minimax/config.yaml reduced to the one custom provider, with
# baseURL -> BenchKit's proxy and the key removed (the proxy adds it). Written to mcode-sandbox-<label>.yaml.
# One change to the model entry: thinking.effortOptions (default..max), as the built-in MiniMax entries have;
# without it `mcode exec --effort max` refuses ("does not support reasoning effort selection").
# Needs the local BenchKit patch: BENCHKIT_AGENT=mcode (src/benchkit/mcode_agent.py).
# Usage: setsid nohup ./patcheval-mcode.sh > patcheval-mcode-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null &
#        SLICE=patcheval:1 ./patcheval-mcode.sh     # smoke
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
PROVIDER=${PROVIDER:-vercel-gateway-free}
MODEL=${MODEL:-minimax/minimax-m3.1-flash}
EFFORT=${EFFORT:-max}
BASE_MODEL=${BASE_MODEL:-}  # copy settings from this model entry when MODEL is not in the config (e.g. a snapshot id)
MAX_TOKENS=${MAX_TOKENS:-}  # override limit.output (empty = keep the config value)
MAX_STEPS=${MAX_STEPS:-300}   # the 1800 s task limit is the real bound; the skill asks for a step cap
SLICE=${SLICE:-patcheval}
LABEL=${LABEL:-mcode-$(echo "$MODEL" | tr '/.' '--')-$EFFORT}
# dist/ + Node-24 native deps (better-sqlite3, ajv); rebuild after a fork update, see mcode-sandbox-dist/README
DIST=/home/sum/Downloads/AI-Runtime/mcode-sandbox-dist
BK=/home/sum/Downloads/AI-Runtime/benchkit-src/BenchKit
OUT=benchkit-patcheval-$LABEL.log
CFG=/home/sum/Downloads/AI-Runtime/mcode-sandbox-$LABEL.yaml
say() { echo "[$(date +%H:%M:%S)] $*"; }

# Writes the sandbox config; prints base URL and key (never echoed).
cfg=$(cd $BK && uv run -q --with pyyaml python3 - "$PROVIDER" "$MODEL" "$CFG" "$BASE_MODEL" "$MAX_TOKENS" <<'EOF'
import os, re, sys, yaml
prov, model_id, out, base_model, max_tokens = sys.argv[1:6]
user = yaml.safe_load(open(os.path.expanduser("~/.minimax/config.yaml")))
p = user["custom_provider"][prov]
options = dict(p.get("options") or {})
base, key = options["baseURL"], str(options.get("apiKey") or "")
if (ref := re.fullmatch(r"(?:\$\{?|\{env:|env:)([A-Za-z_][A-Za-z0-9_]*)\}?", key)):
    key = os.environ.get(ref.group(1), "")
model = dict(p["models"][model_id] if model_id in p["models"] else p["models"][base_model])
if max_tokens:
    model["limit"] = {**model.get("limit", {}), "output": int(max_tokens)}
model.setdefault("thinking", {"effortOptions": ["default", "low", "medium", "high", "xhigh", "max"],
                              "defaultEffort": "default"})
options.update(baseURL="http://inference:8080/v1", apiKey="benchkit-sandbox")
sandbox = {k: v for k, v in user.items() if k not in ("provider", "custom_provider", "defaultModel")}
sandbox["defaultModel"] = f"custom_provider:{prov}/{model_id}"
sandbox["custom_provider"] = {prov: {**p, "options": options, "models": {model_id: model}}}
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
with os.fdopen(fd, "w") as f:
    yaml.safe_dump(sandbox, f, sort_keys=False)
print(base.rstrip("/")); print(key)
EOF
) || { say "STOP: $PROVIDER/$MODEL not found in ~/.minimax/config.yaml"; exit 1; }
HOST=$(sed -n 1p <<<"$cfg"); KEY=$(sed -n 2p <<<"$cfg")
[[ -n $KEY ]] || { say "STOP: no API key for $PROVIDER"; exit 1; }

say "# $LABEL start  agent=mcode $(node -p "require('$DIST/package.json').version") provider=$PROVIDER model=$MODEL effort=$EFFORT slice=$SLICE"
say "  sandbox config: $CFG"
docker info >/dev/null 2>&1 || { say "STOP: Docker daemon not running (sudo systemctl start docker)"; exit 1; }
code=$(curl -s -m120 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_completion_tokens\":256}" \
    "$HOST/chat/completions")
[[ $code == 200 ]] || { say "STOP: test call to $MODEL returned HTTP $code"; exit 1; }

say "=== $LABEL: PatchEval start"
(cd $BK && BENCHKIT_PI_TIMEOUT=1800 BENCHKIT_PROVIDER=openai BENCHKIT_HOST="$HOST" BENCHKIT_API_KEY="$KEY" \
    BENCHKIT_AGENT=mcode BENCHKIT_MCODE_DIST="$DIST" BENCHKIT_MCODE_CONFIG="$CFG" \
    BENCHKIT_MCODE_MODEL="custom_provider:$PROVIDER/$MODEL" BENCHKIT_MCODE_EFFORT="$EFFORT" \
    BENCHKIT_MCODE_ARGS="--max-steps $MAX_STEPS" \
    BENCHKIT_CONCURRENCY=1 BENCHKIT_HARDWARE="hosted: $PROVIDER ($MODEL), mcode effort=$EFFORT" \
    uv run benchkit --headless --models "$MODEL" --benchmarks "$SLICE" --harness pi) > $OUT 2>&1
say "=== $LABEL: benchkit exit $?"
grep -E '^\[.*(PASS|FAIL|TIMEOUT|LENGTH|ERR)|^Saved:' $OUT | tail -25
say "# $LABEL done"
