#!/usr/bin/env bash
# Reload Qwen3.8 at 49152 + MTP, then a short /v1/chat/completions (Pi's failure mode).
set -euo pipefail
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-qwen38-48k-mtp-probe.log}"
CTX="${CTX:-49152}"
exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds) CTX=$CTX"

STUDIO=http://127.0.0.1:8888
KEYFILE=/home/sum/.unsloth/studio/auth/.cli_api_key_cli_99bb88401742
MODEL=/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf
MODEL_ID=Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003

gpu() { nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader; }

old=$(ps -eo pid,cmd | awk '/\/home\/sum\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/{print $1; exit}')
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

python3 - "$STUDIO" "$KEYFILE" "$MODEL" "$CTX" <<'PY'
import json, sys, pathlib, urllib.error, urllib.request
studio, keyfile, model, ctx = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
key = pathlib.Path(keyfile).read_text().strip()
payload = {
    "model_path": model,
    "gguf_variant": "UD-IQ4_XS",
    "max_seq_length": ctx,
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
print(f"loading {ctx} MTP...", flush=True)
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
ps -eo pid,cmd | awk '/\/home\/sum\/.unsloth\/llama.cpp\/llama-server -m/ && !/awk/{print}'

hp=$(ss -ltnp 2>/dev/null | awk '/llama-server/{if (match($4, /:([0-9]+)$/, a)) {print a[1]; exit}}')
echo "# llama-server port ${hp:-none}"
if [[ -z "${hp:-}" ]]; then
  echo "FAILED: no llama-server port after load" >&2
  exit 1
fi
python3 - "$hp" "$CTX" <<'PY'
import json, sys, urllib.request
hp, want = sys.argv[1], int(sys.argv[2])
with urllib.request.urlopen(f"http://127.0.0.1:{hp}/props", timeout=10) as resp:
    d = json.loads(resp.read().decode())
nctx = int((d.get("default_generation_settings") or {}).get("n_ctx") or 0)
print(f"# props n_ctx={nctx} want={want}", flush=True)
if nctx != want:
    print(f"FAILED: n_ctx {nctx} != requested {want}", flush=True)
    raise SystemExit(1)
PY

python3 - "$STUDIO" "$KEYFILE" "$MODEL_ID" <<'PY'
import json, sys, pathlib, urllib.error, urllib.request
studio, keyfile, model_id = sys.argv[1], sys.argv[2], sys.argv[3]
key = pathlib.Path(keyfile).read_text().strip()
body = json.dumps({
    "model": model_id,
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
