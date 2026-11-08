#!/usr/bin/env bash
# Load official mix-pr220 engine, run Group A at 8192 MTP, then occupied Group C at 16384.
set -euo pipefail
cd /home/sum/Downloads/AI-Runtime
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-bench-qwen38-pr220-$(date +%Y%m%d-%H%M%S).log}"
STUDIO="${STUDIO:-http://127.0.0.1:8888}"
MODEL="/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf"
KEYFILE=/home/sum/.unsloth/studio/auth/.cli_api_key_cli_99bb88401742
export UNSLOTH_API_KEY="${UNSLOTH_API_KEY:-$(cat "$KEYFILE")}"

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds) profile=$(powerprofilesctl get 2>/dev/null || echo unknown)"
echo "# engine $(~/.unsloth/llama.cpp/build/bin/llama-server --version | tr '\n' ' ')"
echo "# $(cat ~/.unsloth/llama.cpp/BUILD_INFO.txt | head -4 | tr '\n' ' | ')"
echo "# GPU $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)"
echo "# $(free -h | awk 'NR==2')"

load_mtp() {
  local ctx="$1"
  python3 - <<PY
import json, urllib.request, urllib.error, sys
key = ${UNSLOTH_API_KEY@Q}
studio = ${STUDIO@Q}
payload = {
    "model_path": ${MODEL@Q},
    "gguf_variant": "UD-IQ4_XS",
    "max_seq_length": int(${ctx@Q}),
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
}

kill_llama() {
  local old
  old=$(ps -eo pid,cmd | awk '/\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/{print $1; exit}')
  if [[ -n "${old:-}" ]]; then
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
}

llama_port() {
  ps -eo cmd | awk '/\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/' \
    | grep -oE -- '--port [0-9]+' | awk '{print $2}' | tail -1
}

echo "# --- load 8192 + MTP ---"
kill_llama
load_mtp 8192
PORT=$(llama_port)
[[ -n "$PORT" ]] || { echo "FAILED: no llama-server port after 8192 load"; exit 1; }
echo "# llama-server port $PORT"
ps -eo pid,cmd | awk '/\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/'
curl -fsS --max-time 5 "http://127.0.0.1:$PORT/props" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('# n_ctx', d.get('default_generation_settings',{}).get('n_ctx'))"
echo "# argv has draft-mtp? $(ps -eo cmd | awk '/llama-server -m/ && !/awk/' | grep -c -- '--spec-type draft-mtp' || true)"
echo "# GPU $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)  $(free -h | awk 'NR==2')"

echo "# --- Group A ---"
export PORT
python3 /home/sum/Downloads/AI-Runtime/llama-qwen38-group-a-mtp.py

echo "# --- occupied Group C 16384 ---"
kill_llama
load_mtp 16384
PORT=$(llama_port)
[[ -n "$PORT" ]] || { echo "FAILED: no llama-server port after 16384 load"; exit 1; }
echo "# llama-server port $PORT"
curl -fsS --max-time 5 "http://127.0.0.1:$PORT/props" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('# n_ctx', d.get('default_generation_settings',{}).get('n_ctx'))"
echo "# GPU $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)  $(free -h | awk 'NR==2')"
export PORT NPREDICT=128 CHARS=2000,7000,14000,28000
python3 /home/sum/Downloads/AI-Runtime/llama-bench-occupied-ctx.py

echo "# GPU $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)"
echo "# $(free -h | awk 'NR==2')"
echo "# done $(date -Iseconds)"
