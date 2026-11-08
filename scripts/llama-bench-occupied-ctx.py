#!/usr/bin/env python3
"""Occupied-context probe: the number you actually feel.

The allocation sweep (llama-bench-ctx-sweep.sh) reserves context with an empty KV
and says 180k costs ~12%. This fills the window with REAL tokens and tells a very
different story -- on Qwen3.6-35B-A3B, 65k of real context cost 23% and 129k cost
83%. Always run both; quoting only the allocation number overstates usable context.

Feeds real llama.cpp source files as the prompt and asks one short question.
cache_prompt is disabled so a shared prefix cannot skip prefill and flatter PP.
(In normal use the prefix IS cached, so only the first long turn pays prefill.)

Assumes a llama-server already running -- start it once, probe many sizes, rather
than reloading a 90 GB model per point.

Usage:
  python3 llama-bench-occupied-ctx.py
  CHARS="2000,56000,224000" PORT=8099 python3 llama-bench-occupied-ctx.py
"""
import glob
import json
import os
import time
import urllib.error
import urllib.request

PORT = os.environ.get("PORT", "8099")
BASE = f"http://127.0.0.1:{PORT}"
URL = f"{BASE}/completion"
SRC = os.environ.get("SRC", "/home/sum/Downloads/AI-Runtime/llama.cpp/src")
NPREDICT = int(os.environ.get("NPREDICT", "128"))
# ~3.5 chars/token for C++ source: 56k chars ~ 16k tok, 224k ~ 65k tok, 450k ~ 129k tok.
CHARS = [int(x) for x in os.environ.get("CHARS", "2000,56000,224000,450000").split(",")]


# Unsloth engines from b11541 start llama-server with --api-key-file; point this at it.
_KEY_FILE = os.environ.get("LLAMA_API_KEY_FILE")
AUTH = {"Authorization": "Bearer " + open(_KEY_FILE).read().strip()} if _KEY_FILE else {}


def http_json(url, payload=None, timeout=120):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json", **AUTH} if data else dict(AUTH)
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def n_ctx_from_server():
    d = http_json(f"{BASE}/props", timeout=5)
    return int(d.get("default_generation_settings", {}).get("n_ctx") or 0)


def n_tokens(text):
    d = http_json(f"{BASE}/tokenize", {"content": text}, timeout=120)
    toks = d.get("tokens") if isinstance(d, dict) else d
    return len(toks) if isinstance(toks, list) else int(d["tokens"])


def fit_chars(nchars, question, n_ctx):
    """Shrink a char budget until prompt + n_predict fits in n_ctx."""
    if n_ctx <= NPREDICT:
        raise RuntimeError(f"n_ctx {n_ctx} too small for n_predict {NPREDICT}")
    hi = min(nchars, len(blob))
    prompt = blob[:hi] + question
    used = n_tokens(prompt)
    budget = n_ctx - NPREDICT
    if used <= budget:
        return hi, used, False
    lo, best = 1, 1
    while lo <= hi:
        mid = (lo + hi) // 2
        used_mid = n_tokens(blob[:mid] + question)
        if used_mid <= budget:
            best, lo = mid, mid + 1
        else:
            hi = mid - 1
    return best, n_tokens(blob[:best] + question), True

corpus, files = [], 0
for path in sorted(glob.glob(f"{SRC}/*.cpp")) + sorted(glob.glob(f"{SRC}/*.h")):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            corpus.append(f"\n\n===== FILE: {os.path.basename(path)} =====\n" + fh.read())
            files += 1
    except OSError:
        pass
blob = "".join(corpus)
if not blob:
    raise SystemExit(f"no source found under {SRC}")
print(f"corpus: {files} files, {len(blob)} chars available", flush=True)

QUESTION = "\n\nQuestion: In one short sentence, what is this codebase?"
N_CTX = n_ctx_from_server()
print(f"# n_ctx {N_CTX} n_predict {NPREDICT} fit_budget {N_CTX - NPREDICT}", flush=True)


def probe(nchars):
    fitted, prompt_toks, trimmed = fit_chars(nchars, QUESTION, N_CTX)
    if trimmed:
        print(f"# trim CHARS {nchars} -> {fitted} (~{prompt_toks} tok, "
              f"leave {NPREDICT} gen in {N_CTX})", flush=True)
    body = json.dumps({
        "prompt": blob[:fitted] + QUESTION,
        "n_predict": NPREDICT,
        "temperature": 0,
        "ignore_eos": True,
        "cache_prompt": False,
    }).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json", **AUTH})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=7200) as resp:
            d = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        err = exc.read().decode()[:500]
        raise RuntimeError(f"HTTP {exc.code} {err}") from exc
    wall = time.time() - t0
    t = d["timings"]
    draft = ""
    if t.get("draft_n") or t.get("draft_n_accepted") is not None:
        acc = t.get("draft_n_accepted", 0)
        gen = t.get("draft_n", 0) or t.get("drafted_n", 0)
        draft = f" | draft {acc}/{gen}"
    print(f"{t['prompt_n']:>8} | {t['prompt_per_second']:>8.1f} | {t['predicted_per_second']:>7.2f} | "
          f"{t['prompt_ms']/1000:>8.1f}s | {wall:>7.1f}s{draft}", flush=True)


print(f"{'ctx_tok':>8} | {'PP t/s':>8} | {'TG t/s':>7} | {'prefill':>9} | {'wall':>8}")
for n in CHARS:
    try:
        probe(n)
    except Exception as exc:  # noqa: BLE001 - report and continue to next size
        print(f"{n:>8} | FAILED: {exc}", flush=True)
