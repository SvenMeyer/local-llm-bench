#!/usr/bin/env bash
# Real-world generation on the live Unsloth Qwen3.8 llama-server.
# Native /completion (chat completions at 64k + max_tokens=6144 CUDA-OOM'd
# a 1.7 GiB graph and killed llama-server). Erases slot 0 first.
set -euo pipefail
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-qwen38-realworld-staking.log}"
NPREDICT="${NPREDICT:-2048}"
PROMPT="${PROMPT:-write a Solidity staking contract and a test suite in typescript}"

llama_cmd() {
  pgrep -a -f '/.unsloth/llama.cpp/llama-server -m' | grep -v grok || true
}

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds)  profile=$(powerprofilesctl get 2>/dev/null || echo unknown)"
echo "# NPREDICT=$NPREDICT"
echo "# prompt: $PROMPT"

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
erase=$(curl -sS -o /tmp/slot-erase.json -w '%{http_code}' --max-time 10 \
  -X POST "http://127.0.0.1:$PORT/slots/0?action=erase" || true)
echo "# slot0 erase http=${erase:-none}"

export PORT NPREDICT PROMPT OUT
python3 - <<'PY'
import json, os, time, urllib.request, urllib.error, http.client, sys

port = os.environ["PORT"]
prompt = os.environ["PROMPT"]
npredict = int(os.environ["NPREDICT"])
base = os.environ["OUT"].rsplit(".", 1)[0]
url = f"http://127.0.0.1:{port}/completion"

def once(npred):
    body = {
        "prompt": prompt,
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
for npred in (npredict, 1024, 512):
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
    except (http.client.RemoteDisconnected, ConnectionError, TimeoutError) as e:
        err = f"{type(e).__name__}: {e}"
        print(f"# {err}", flush=True)
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
print(text[:2000], flush=True)
if len(text) > 2000:
    print(f"# … truncated preview, full output in {base}-output.md", flush=True)
PY
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)"
echo "# done $(date -Iseconds)"
