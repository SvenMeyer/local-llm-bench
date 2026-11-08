#!/usr/bin/env bash
# Fresh 32k + MTP load, then a short /v1/chat/completions (Pi's failure mode).
set -euo pipefail
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-qwen38-32k-mtp-probe.log}"
exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds)"

STUDIO=http://127.0.0.1:8888
KEY=$(cat /home/sum/.unsloth/studio/auth/.cli_api_key_cli_99bb88401742)
MODEL=/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf

gpu() { nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader; }

old=$(ps -eo pid,cmd | awk '/\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/{print $1; exit}')
if [[ -n "${old:-}" ]]; then
  echo "# SIGTERM llama-server $old"
  kill "$old" 2>/dev/null || true
  for i in $(seq 1 60); do
    kill -0 "$old" 2>/dev/null || break
    sleep 2
  done
  kill -9 "$old" 2>/dev/null || true
  sleep 2
fi
echo "# after unload $(free -h | awk 'NR==2')  gpu $(gpu)"

python3 - "$STUDIO" "$KEY" "$MODEL" <<'PY'
import json, sys, urllib.error, urllib.request
studio, key, model = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "model_path": model,
    "gguf_variant": "UD-IQ4_XS",
    "max_seq_length": 32768,
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
print("loading 32768 MTP...", flush=True)
try:
    with urllib.request.urlopen(req, timeout=600) as resp:
        d = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    print("LOAD_HTTP", e.code, e.read().decode()[:2000], file=sys.stderr)
    sys.exit(1)
print("loaded context", d.get("context_length"), "spec", d.get("speculative_type"),
      "n_max", d.get("spec_draft_n_max"), flush=True)
PY

echo "# empty $(gpu)  $(free -h | awk 'NR==2')"
ps -eo cmd | awk '/llama-server -m/ && !/awk/' | tr '\n' ' '; echo

python3 - "$STUDIO" "$KEY" <<'PY'
import json, sys, urllib.error, urllib.request
studio, key = sys.argv[1], sys.argv[2]
body = json.dumps({
    "model": "Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003",
    "messages": [
        {"role": "system", "content": "You are a coding assistant. Be brief."},
        {"role": "user", "content": "Reply with exactly the single word pong."},
    ],
    "max_tokens": 64,
    "temperature": 0,
    "chat_template_kwargs": {"enable_thinking": False},
}).encode()
req = urllib.request.Request(
    studio.rstrip("/") + "/v1/chat/completions",
    data=body,
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
)
print("short chat...", flush=True)
try:
    with urllib.request.urlopen(req, timeout=180) as resp:
        d = json.loads(resp.read())
except urllib.error.HTTPError as e:
    print("CHAT_HTTP", e.code, e.read().decode()[:2000], file=sys.stderr)
    sys.exit(1)
msg = d["choices"][0]["message"]
print("content", repr((msg.get("content") or "")[:80]), "usage", d.get("usage"), flush=True)
PY

echo "# after short chat $(gpu)"
echo "# done $(date -Iseconds)"
