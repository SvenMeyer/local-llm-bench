#!/usr/bin/env bash
# One-shot occupied-context probe for the live Unsloth Qwen3.8-Flash-Next
# server. Reloads ONCE to 16384 ctx with MTP, then probes ~0.5k/2k/4k/8k
# tokens. Does not spawn extra llama-server processes (90 GB each).
#
# Usage:
#   UNSLOTH_API_KEY=sk-… ./llama-bench-qwen38-unsloth-occupied.sh
#   SKIP_RELOAD=1 ./llama-bench-qwen38-unsloth-occupied.sh   # already 16384+MTP
# Procedure: llama-qwen38-benchmark-run.md
set -euo pipefail

STUDIO="${STUDIO:-http://127.0.0.1:8888}"
CTX="${CTX:-16384}"
NPREDICT="${NPREDICT:-128}"
CHARS="${CHARS:-2000,7000,14000,28000}"
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-bench-qwen38-occupied-$(date +%Y%m%d-%H%M%S).log}"
MODEL="${MODEL:-/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf}"
VARIANT="${VARIANT:-UD-IQ4_XS}"
FORCE_RELOAD="${FORCE_RELOAD:-0}"
SKIP_RELOAD="${SKIP_RELOAD:-0}"

llama_cmd() {
  pgrep -a -x llama-server || true
}

already_target() {
  local cmd
  cmd=$(llama_cmd)
  [[ -n "$cmd" ]] || return 1
  grep -q -- '--spec-type draft-mtp' <<<"$cmd" || return 1
  grep -qE -- "-c ${CTX}|--fit-ctx ${CTX}" <<<"$cmd" || return 1
  return 0
}

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds)  profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo unknown)"
echo "# CTX=$CTX NPREDICT=$NPREDICT CHARS=$CHARS VARIANT=$VARIANT"
echo "# engine $(head -1 $HOME/.unsloth/llama.cpp/BUILD_INFO.txt)"

need_reload=1
if [[ "$FORCE_RELOAD" == "1" ]]; then
  echo "# FORCE_RELOAD=1"
elif [[ "$SKIP_RELOAD" == "1" ]]; then
  echo "# SKIP_RELOAD=1"
  need_reload=0
elif already_target; then
  echo "# skip reload: llama-server already ctx $CTX + draft-mtp"
  need_reload=0
fi

if [[ "$need_reload" == "1" ]]; then
  KEY="${UNSLOTH_API_KEY:?set UNSLOTH_API_KEY for reload (or SKIP_RELOAD=1)}"
  # Unsloth's load path only waits 5s for the previous llama-server to die.
  # A 90 GB process needs longer; SIGTERM it first.
  old=$(pgrep -f '/.unsloth/llama.cpp/llama-server -m' | head -1 || true)
  if [[ -n "$old" ]]; then
    echo "# SIGTERM llama-server pid $old"
    kill "$old" 2>/dev/null || true
    for i in $(seq 1 60); do
      kill -0 "$old" 2>/dev/null || break
      sleep 2
    done
    kill -9 "$old" 2>/dev/null || true
    sleep 2
    echo "# after unload: $(free -h | awk 'NR==2')"
  fi
fi

if [[ "$need_reload" == "1" ]]; then
python3 - <<PY
import json, urllib.request, urllib.error, sys
key = ${KEY@Q}
studio = ${STUDIO@Q}
payload = {
    "model_path": ${MODEL@Q},
    "gguf_variant": ${VARIANT@Q},
    "max_seq_length": int(${CTX@Q}),
    "load_in_4bit": True,
    "force_reload": True,
    "gpu_memory_mode": "auto",
    "speculative_type": "mtp",
    "spec_draft_n_max": 3,
    "n_parallel": 1,
    "cache_type_kv": "q8_0",
    "disable_vision": True,
    "load_mode": "none",
    "llama_extra_args": [
        "--cpu-moe", "--spec-draft-cpu-moe",
        "--n-gpu-layers", "999",
        "--flash-attn", "on",
        "--cache-type-k", "q8_0", "--cache-type-v", "q8_0",
        "--threads", "10", "--jinja", "--no-mmproj",
        "--temp", "1.0", "--min-p", "0.0",
        "--load-mode", "none", "--lazy-mode", "off",
    ],
}
req = urllib.request.Request(
    studio.rstrip("/") + "/api/inference/load",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    method="POST",
)
print("reloading to ctx", payload["max_seq_length"], "MTP on...", flush=True)
try:
    with urllib.request.urlopen(req, timeout=600) as resp:
        d = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    print("LOAD_HTTP", e.code, e.read().decode()[:2000], file=sys.stderr)
    sys.exit(1)
print("loaded context", d.get("context_length"), "spec", d.get("speculative_type"),
      "n_max", d.get("spec_draft_n_max"), flush=True)
PY
fi

# Unsloth picks a random llama-server port.
PORT=$(llama_cmd | grep -oE -- '--port [0-9]+' | awk '{print $2}' | tail -1)
if [[ -z "$PORT" ]]; then
  echo "FAILED: no llama-server port" >&2
  exit 1
fi
echo "# llama-server port $PORT"
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)  $(free -h | awk 'NR==2')"
# b11541+ engines require a bearer key; the path is in the server's argv.
if [[ -z "${LLAMA_API_KEY_FILE:-}" ]]; then
  LLAMA_API_KEY_FILE=$(llama_cmd | grep -oE -- '--api-key-file [^ ]+' | awk '{print $2}' | tail -1 || true)
fi
CURL_AUTH=()
[[ -n "${LLAMA_API_KEY_FILE:-}" ]] && CURL_AUTH=(-H "Authorization: Bearer $(<"$LLAMA_API_KEY_FILE")")
curl -fsS --max-time 5 "${CURL_AUTH[@]}" "http://127.0.0.1:$PORT/props" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('# n_ctx', d.get('default_generation_settings',{}).get('n_ctx'))"

export PORT NPREDICT CHARS LLAMA_API_KEY_FILE
python3 /home/sum/Downloads/AI-Runtime/llama-bench-occupied-ctx.py
echo "# done $(date -Iseconds)"
