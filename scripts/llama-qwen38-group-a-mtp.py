#!/usr/bin/env python3
"""Short Group A probes against a live llama-server: digits (low entropy) then prose.

Hits native /completion. Prints PP/TG and draft accept. Env: PORT, NPREDICT.
"""
import json
import os
import time
import urllib.request

PORT = os.environ.get("PORT")
if not PORT:
    raise SystemExit("set PORT to the llama-server port")
BASE = f"http://127.0.0.1:{PORT}"
NPREDICT = int(os.environ.get("NPREDICT", "128"))

DIGITS = (
    "Write the integers from 1 to 400 inclusive, one per line, decimal digits only. "
    "No words, no punctuation, no thinking commentary after you start the list.\n"
)
PROSE = (
    "create a whitelist in solidity with some basic functions to add accounts "
    "with a name of type `bytes32`(short string), and a delete function\n"
)


def http_json(url, payload=None, timeout=600):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"} if data else {}
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def props():
    d = http_json(f"{BASE}/props", timeout=5)
    return int(d.get("default_generation_settings", {}).get("n_ctx") or 0)


def run(label, prompt, n_predict):
    t0 = time.time()
    d = http_json(
        f"{BASE}/completion",
        {
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": 0,
            "ignore_eos": True,
            "cache_prompt": False,
        },
        timeout=1800,
    )
    wall = time.time() - t0
    t = d["timings"]
    acc = t.get("draft_n_accepted")
    gen = t.get("draft_n") or t.get("drafted_n")
    draft = ""
    if acc is not None or gen:
        draft = f" draft {acc}/{gen}"
        if gen:
            draft += f" ({100.0 * acc / gen:.0f}%)"
    print(
        f"{label:8} | ctx_tok {t['prompt_n']:>5} | PP {t['prompt_per_second']:7.1f} | "
        f"TG {t['predicted_per_second']:7.2f} | prefill {t['prompt_ms']/1000:6.1f}s | "
        f"wall {wall:6.1f}s | pred {t['predicted_n']}{draft}",
        flush=True,
    )


n_ctx = props()
print(f"# n_ctx {n_ctx} n_predict {NPREDICT} port {PORT}", flush=True)
run("digits", DIGITS, NPREDICT)
run("prose", PROSE, max(NPREDICT, 256))
print("# group-a done", flush=True)
