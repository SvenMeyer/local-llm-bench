#!/usr/bin/env bash
# Retry real-world generation on the LIVE 64k server. Does not reload.
# Uses a chat-shaped prompt so the model does not EOS on the C++ dump.
set -euo pipefail
OUT="${OUT:-/home/sum/Downloads/AI-Runtime/llama-qwen38-realworld-staking-retry.log}"
NPREDICT="${NPREDICT:-1024}"
CHARS="${CHARS:-54000}"
PROMPT="${PROMPT:-write a Solidity staking contract and a test suite in typescript}"
SRC="${SRC:-/home/sum/Downloads/AI-Runtime/llama.cpp/src}"

llama_cmd() {
  pgrep -a -f '/.unsloth/llama.cpp/llama-server -m' | grep -v grok || true
}

exec > >(tee -a "$OUT") 2>&1
echo "# $OUT"
echo "# start $(date -Iseconds)"
echo "# NPREDICT=$NPREDICT CHARS=$CHARS"
cmd=$(llama_cmd)
if [[ -z "$cmd" ]]; then
  echo "FAILED: no llama-server" >&2
  exit 1
fi
echo "# argv: $cmd"
PORT=$(grep -oE -- '--port [0-9]+' <<<"$cmd" | awk '{print $2}' | tail -1)
echo "# llama-server port $PORT"
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader)"
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
            corpus.append(fh.read())
    except OSError:
        pass
blob = "\n".join(corpus)
full = (
    "<|im_start|>user\n"
    "Reference context (unrelated C++; ignore for the task):\n"
    + blob[:nchars]
    + "\n\nTask: "
    + prompt
    + "\nReply with the Solidity contract and the TypeScript test suite only.\n"
    "<|im_end|>\n"
    "<|im_start|>assistant\n"
)
print(f"# prompt_chars {len(full)}", flush=True)

body = {
    "prompt": full,
    "n_predict": npredict,
    "temperature": 1.0,
    "top_p": 0.95,
    "top_k": 20,
    "min_p": 0.0,
    "cache_prompt": False,
    "ignore_eos": False,
}
req = urllib.request.Request(
    url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}
)
print(f"# POST /completion n_predict={npredict}", flush=True)
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=7200) as resp:
        d = json.loads(resp.read().decode())
except Exception as e:
    print(f"FAILED: {type(e).__name__}: {e}", flush=True)
    sys.exit(1)
wall = time.time() - t0
text = d.get("content") or ""
timings = d.get("timings") or {}
print(f"# wall_s {wall:.1f} stop={d.get('stop_type')} predicted={d.get('tokens_predicted')}", flush=True)
print(f"# timings {json.dumps(timings)}", flush=True)
if timings:
    extra = ""
    dn = timings.get("draft_n") or timings.get("drafted_n")
    if dn:
        extra = f" draft {timings.get('draft_n_accepted')}/{dn}"
    print(
        f"# summary prompt_n={timings.get('prompt_n')} predicted_n={timings.get('predicted_n')} "
        f"PP={timings.get('prompt_per_second')} TG={timings.get('predicted_per_second')}{extra}",
        flush=True,
    )
with open(base + "-response.json", "w", encoding="utf-8") as fh:
    json.dump({k: v for k, v in d.items() if k != "prompt"}, fh, indent=2)
with open(base + "-output.md", "w", encoding="utf-8") as fh:
    fh.write(text)
print(f"# wrote {len(text)} chars", flush=True)
print(text[:3000], flush=True)
if len(text) > 3000:
    print(f"# … truncated preview, full output in {base}-output.md", flush=True)
if len(text.strip()) < 40:
    print("FAILED: empty or trivial generation", flush=True)
    sys.exit(1)
PY
echo "# $(nvidia-smi --query-gpu=memory.used,memory.free,temperature.gpu,power.draw --format=csv,noheader)"
echo "# done $(date -Iseconds)"
