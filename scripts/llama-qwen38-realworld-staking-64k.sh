#!/usr/bin/env bash
# 64k-alloc real-world generation. Short prompts at 65536+MTP CUDA-OOM the
# decode graph (~1.7 GiB) and kill llama-server. Long /completion prefills
# work. This reloads 65536+MTP then sends ~15k tokens of llama.cpp/src plus
# the staking prompt in ONE request.
set -euo pipefail

STUDIO="${STUDIO:-http://127.0.0.1:8888}"
CTX="${CTX:-65536}"
NPREDICT="${NPREDICT:-1024}"
CHARS="${CHARS:-54000}"
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-qwen38-realworld-staking.log}"
MODEL="/home/sum/.cache/lm-studio/models/unsloth/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf"
PROMPT="${PROMPT:-write a Solidity staking contract and a test suite in typescript}"
SRC="${SRC:-/home/sum/Downloads/AI-Runtime/llama.cpp/src}"

llama_cmd() {
  pgrep -a -f '/.unsloth/llama.cpp/llama-server -m' | grep -v grok || true
}

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds)  profile=$(powerprofilesctl get 2>/dev/null || echo unknown)"
echo "# CTX=$CTX NPREDICT=$NPREDICT CHARS=$CHARS"
echo "# prompt: $PROMPT"

KEY="${UNSLOTH_API_KEY:?set UNSLOTH_API_KEY for reload}"
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

python3 - <<PY
import json, urllib.request, urllib.error, sys
key = ${KEY@Q}
studio = ${STUDIO@Q}
payload = {
    "model_path": ${MODEL@Q},
    "gguf_variant": "UD-IQ4_XS",
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

cmd=$(llama_cmd)
if [[ -z "$cmd" ]]; then
  echo "FAILED: no llama-server" >&2
  exit 1
fi
echo "# argv: $cmd"
PORT=$(grep -oE -- '--port [0-9]+' <<<"$cmd" | awk '{print $2}' | tail -1)
echo "# llama-server port $PORT"
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)  $(free -h | awk 'NR==2')"
curl -fsS --max-time 5 "http://127.0.0.1:$PORT/props" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('# n_ctx', d.get('default_generation_settings',{}).get('n_ctx'))"

export PORT NPREDICT PROMPT OUT SRC CHARS
python3 - <<'PY'
import glob, json, os, time, urllib.request, urllib.error, http.client, sys

port = os.environ["PORT"]
prompt = os.environ["PROMPT"]
npredict = int(os.environ["NPREDICT"])
nchars = int(os.environ["CHARS"])
src = os.environ["SRC"]
base = os.environ["OUT"].rsplit(".", 1)[0]
url = f"http://127.0.0.1:{port}/completion"

corpus = []
for path in sorted(glob.glob(src + "/*.cpp")) + sorted(glob.glob(src + "/*.h")):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            corpus.append("\n\n===== FILE: " + os.path.basename(path) + " =====\n" + fh.read())
    except OSError:
        pass
blob = "".join(corpus)
full = (
    blob[:nchars]
    + "\n\n===== END REFERENCE (unrelated C++ — ignore for the task) =====\n\n"
    + "Task: "
    + prompt
    + "\n"
)
print(f"# prompt_chars {len(full)} (filler {nchars})", flush=True)

def once(npred):
    body = {
        "prompt": full,
        "n_predict": npred,
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 20,
        "min_p": 0.0,
        "cache_prompt": False,
    }
    raw = json.dumps(body).encode()
    req = urllib.request.Request(url, data=raw, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=7200) as resp:
        d = json.loads(resp.read().decode())
    return time.time() - t0, d

tried = npredict
wall = d = None
err = None
for npred in (npredict, 512, 256):
    if npred > tried:
        continue
    tried = npred
    print(f"# trying /completion n_predict={npred}", flush=True)
    try:
        wall, d = once(npred)
        err = None
        break
    except urllib.error.HTTPError as e:
        err = f"HTTP {e.code} {e.read().decode()[:1500]}"
        print(f"# {err}", flush=True)
    except (http.client.RemoteDisconnected, ConnectionError, TimeoutError, urllib.error.URLError) as e:
        err = f"{type(e).__name__}: {e}"
        print(f"# {err}", flush=True)
        # process may be dead; do not retry smaller n_predict on a corpse
        break
if d is None:
    print(f"FAILED: {err}", flush=True)
    sys.exit(1)

text = d.get("content") or ""
timings = d.get("timings") or {}
print(f"# wall_s {wall:.1f}", flush=True)
print(f"# timings {json.dumps(timings)}", flush=True)
if timings:
    pp = timings.get("prompt_per_second")
    tg = timings.get("predicted_per_second")
    pn = timings.get("prompt_n")
    pred = timings.get("predicted_n")
    acc = timings.get("draft_n_accepted")
    dn = timings.get("draft_n") or timings.get("drafted_n")
    extra = f" draft {acc}/{dn}" if dn else ""
    print(f"# summary prompt_n={pn} predicted_n={pred} PP={pp} TG={tg}{extra}", flush=True)
with open(base + "-response.json", "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2)
with open(base + "-output.md", "w", encoding="utf-8") as fh:
    fh.write(text)
print(f"# wrote {base}-response.json and {base}-output.md ({len(text)} chars)", flush=True)
print(text[:2500], flush=True)
if len(text) > 2500:
    print(f"# … truncated preview, full output in {base}-output.md", flush=True)
PY
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)"
echo "# done $(date -Iseconds)"
