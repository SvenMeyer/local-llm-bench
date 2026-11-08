#!/usr/bin/env python3
"""House quality probe: the Solidity whitelist / bytes32 prompt, greedy, via chat.

Same prompt text as llama.cpp-test.sh. temperature 0 by default so two quants on
the same engine can be diffed; TEMPERATURE=1.0 SEED=n is the model's recommended
sampling. Writes reasoning + answer + timings to OUT (markdown).
Env: PORT (llama-server port), OUT, MAX_TOKENS (default 3072), TEMPERATURE, SEED.
"""
import json
import os
import time
import urllib.request

PORT = os.environ.get("PORT")
OUT = os.environ.get("OUT")
if not PORT or not OUT:
    raise SystemExit("set PORT and OUT")
BASE = f"http://127.0.0.1:{PORT}"
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "3072"))
TEMPERATURE = float(os.environ.get("TEMPERATURE", "0"))
SEED = int(os.environ.get("SEED", "-1"))

PROMPT = (
    "create a whitelist in solidity with some basic functions to add accounts "
    "with a name of type `bytes32`(which we use to represent a short string), "
    "and a delete function"
)


def http_json(url, payload=None, timeout=1800):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


props = http_json(f"{BASE}/props", timeout=5)
model = os.path.basename(props.get("model_path", "?"))
build = props.get("build_info", "?")

t0 = time.time()
d = http_json(f"{BASE}/v1/chat/completions", {
    "messages": [{"role": "user", "content": PROMPT}],
    "temperature": TEMPERATURE,
    "min_p": 0.0,
    "seed": SEED,
    "max_tokens": MAX_TOKENS,
    "cache_prompt": False,
})
wall = time.time() - t0
msg = d["choices"][0]["message"]
tm = d.get("timings", {})
summary = (
    f"TG {tm.get('predicted_per_second', 0):.2f} t/s, {tm.get('predicted_n', '?')} tok, "
    f"draft {tm.get('draft_n_accepted', '?')}/{tm.get('draft_n', '?')}, "
    f"finish {d['choices'][0].get('finish_reason')}, wall {wall:.1f}s"
)
with open(OUT, "w") as f:
    f.write(f"# Quality probe — {model}\n\n")
    f.write(f"- engine: {build}\n- {summary}\n- max_tokens {MAX_TOKENS}, temperature {TEMPERATURE}, min_p 0, seed {SEED}\n\n")
    f.write(f"## Prompt\n\n{PROMPT}\n\n")
    f.write(f"## Reasoning\n\n{msg.get('reasoning_content') or '(none)'}\n\n")
    f.write(f"## Answer\n\n{msg.get('content') or '(none)'}\n")
print(summary)
print(f"wrote {OUT}")
