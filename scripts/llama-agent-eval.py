#!/usr/bin/env python3
"""Agentic tool-use eval: the model fixes small coding tasks through OpenAI-style tool calls.

Each task in eval-data/agent-tasks/<task>/ has TASK.md (the prompt), source files and tests/.
The model works in a fresh sandbox copy with five tools (list_files, read_file, grep,
write_file, run_tests) until it stops calling tools. Scoring restores a pristine tests/ and
runs it, so editing tests does not help. One JSON line per run goes to OUT.

Talks to a llama-server on PORT via /v1/chat/completions (start it with
llama-serve-qwen38-direct.sh). Recommended Qwen thinking sampling, MTP is whatever the server has.

Usage:
  LABEL=q2_0 python3 llama-agent-eval.py               # all tasks, seed 1
  LABEL=q2_0 TASKS=t1-bugfix-stats SEEDS=1,2 python3 llama-agent-eval.py
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

PORT = os.environ.get("PORT", "8099")
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
LABEL = os.environ.get("LABEL", "model")
TASK_DIR = pathlib.Path(os.environ.get("TASK_DIR", "/home/sum/Downloads/AI-Runtime/eval-data/agent-tasks"))
TASKS = [t for t in os.environ.get("TASKS", "").split(",") if t] or sorted(p.name for p in TASK_DIR.iterdir() if p.is_dir())
SEEDS = [int(s) for s in os.environ.get("SEEDS", "1").split(",")]
MAX_TURNS = int(os.environ.get("MAX_TURNS", "16"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "8192"))
TASK_TIMEOUT = int(os.environ.get("TASK_TIMEOUT", "2400"))
OUT = os.environ.get("OUT", f"/home/sum/Downloads/AI-Runtime/llama-agent-eval-{LABEL}.jsonl")
EFFORT = os.environ.get("REASONING_EFFORT")  # unset = chat template default

SYSTEM = ("You are a careful software engineer working in a small repository. Use the provided tools "
          "to inspect files, edit them and run the tests. Paths are relative to the repository root. "
          "write_file replaces the whole file. When the task is complete and the tests pass, reply with a "
          "short summary and do not call any more tools.")

TOOLS = [
    {"type": "function", "function": {"name": "list_files", "description": "List all files in the repository, recursively.",
                                      "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {"name": "read_file", "description": "Return the full text of a file.",
                                      "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
    {"type": "function", "function": {"name": "grep", "description": "Search all files for a regular expression; returns path:line:text matches.",
                                      "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
    {"type": "function", "function": {"name": "write_file", "description": "Create or overwrite a file with the given content.",
                                      "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
                                                     "required": ["path", "content"]}}},
    {"type": "function", "function": {"name": "run_tests", "description": "Run the unit tests (python -m unittest discover -s tests -v) and return the output.",
                                      "parameters": {"type": "object", "properties": {}, "required": []}}},
]


def run_unittest(root):
    try:
        p = subprocess.run(["python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                           cwd=root, capture_output=True, text=True, timeout=60)
        return p.returncode == 0, (p.stdout + p.stderr)[-4000:]
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT after 60 s"


def inside(root, rel):
    p = (root / rel).resolve()
    if p != root and root not in p.parents:
        raise ValueError(f"path escapes the repository: {rel}")
    return p


def call_tool(root, name, args):
    if name == "list_files":
        return "\n".join(str(p.relative_to(root)) for p in sorted(root.rglob("*"))
                         if p.is_file() and "__pycache__" not in p.parts)
    if name == "read_file":
        return inside(root, args["path"]).read_text()[:20000]
    if name == "grep":
        rx, hits = re.compile(args["pattern"]), []
        for p in sorted(root.rglob("*")):
            if p.is_file() and "__pycache__" not in p.parts:
                for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
                    if rx.search(line):
                        hits.append(f"{p.relative_to(root)}:{i}:{line}")
        return "\n".join(hits[:200]) or "(no matches)"
    if name == "write_file":
        p = inside(root, args["path"])
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(args["content"])
        return f"wrote {len(args['content'])} chars to {args['path']}"
    if name == "run_tests":
        ok, out = run_unittest(root)
        return ("ALL TESTS PASSED\n" if ok else "TESTS FAILED\n") + out
    raise KeyError(f"unknown tool {name}")


def chat(messages, seed):
    body = {"messages": messages, "tools": TOOLS, "tool_choice": "auto", "seed": seed,
            "temperature": 1.0, "top_p": 0.95, "top_k": 20, "min_p": 0.0, "max_tokens": MAX_TOKENS}
    if EFFORT:
        body["chat_template_kwargs"] = {"reasoning_effort": EFFORT}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3600) as r:
        return json.loads(r.read())


def run_task(task, seed):
    src = TASK_DIR / task
    root = pathlib.Path(tempfile.mkdtemp(prefix=f"agent-{task}-")).resolve()
    shutil.copytree(src, root, dirs_exist_ok=True, ignore=shutil.ignore_patterns("TASK.md"))
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": (src / "TASK.md").read_text()}]
    st = {"label": LABEL, "task": task, "seed": seed, "turns": 0, "tool_calls": 0, "bad_calls": 0,
          "completion_tokens": 0, "max_req_tokens": 0, "rejected_calls": 0, "gen_s": 0.0, "model_s": 0.0, "length_stops": 0, "draft_acc": 0, "draft_n": 0, "error": None}
    t0 = time.time()
    try:
        for _ in range(MAX_TURNS):
            if time.time() - t0 > TASK_TIMEOUT:
                st["error"] = "task timeout"
                break
            tc = time.time()
            d = chat(messages, seed)
            st["model_s"] += time.time() - tc  # engine-neutral: request wall time
            st["turns"] += 1
            ch, msg = d["choices"][0], d["choices"][0]["message"]
            ct = d.get("usage", {}).get("completion_tokens", 0)
            st["completion_tokens"] += ct
            st["max_req_tokens"] = max(st["max_req_tokens"], ct)  # spots replies cut at a thinking cap
            tm = d.get("timings", {})
            st["gen_s"] += tm.get("predicted_ms", 0) / 1000
            st["draft_acc"] += tm.get("draft_n_accepted", 0) or 0
            st["draft_n"] += tm.get("draft_n", 0) or 0
            if ch.get("finish_reason") == "length":
                st["length_stops"] += 1
            calls = msg.get("tool_calls") or []
            am = {"role": "assistant", "content": msg.get("content") or ""}
            if msg.get("reasoning_content"):
                am["reasoning_content"] = msg["reasoning_content"]
            if calls:
                am["tool_calls"] = calls
            messages.append(am)
            # Strata turns a call to an undeclared tool into plain text and lists it here; llama.cpp passes it
            # through and call_tool() reports "unknown tool". Report it the same way instead of ending the task.
            rejected = d.get("strata_rejected_tool_calls") or []
            if not calls and rejected:
                st["bad_calls"] += len(rejected)
                st["rejected_calls"] += len(rejected)
                names = ", ".join(str(r.get("name", r) if isinstance(r, dict) else r) for r in rejected)
                tools = ", ".join(t["function"]["name"] for t in TOOLS)
                messages.append({"role": "user", "content": f"ERROR: unknown tool {names}. Available tools: {tools}."})
                continue
            if not calls:
                if ch.get("finish_reason") == "length":
                    messages.append({"role": "user", "content": "Continue."})
                    continue
                break
            for c in calls:
                st["tool_calls"] += 1
                fn = c.get("function", {})
                try:
                    args = json.loads(fn.get("arguments") or "{}")
                    result = call_tool(root, fn.get("name"), args)
                except Exception as e:  # noqa: BLE001 - every failure is reported back to the model
                    st["bad_calls"] += 1
                    result = f"ERROR: {type(e).__name__}: {e}"
                messages.append({"role": "tool", "tool_call_id": c.get("id", ""), "content": str(result)})
    except Exception as e:  # noqa: BLE001 - record and score whatever state the repo is in
        st["error"] = f"{type(e).__name__}: {e}"[:300]
    st["wall_s"] = round(time.time() - t0, 1)
    # score against pristine tests
    shutil.rmtree(root / "tests", ignore_errors=True)
    shutil.copytree(src / "tests", root / "tests")
    st["passed"], out = run_unittest(root)
    st["score_tail"] = out[-300:]
    st["tg_tps"] = round(st["completion_tokens"] / st["gen_s"], 2) if st["gen_s"] else None
    st["model_s"] = round(st["model_s"], 1)
    st["eff_tps"] = round(st["completion_tokens"] / st["model_s"], 2) if st["model_s"] else None  # incl. prefill
    shutil.rmtree(root, ignore_errors=True)
    return st


def main():
    for seed in SEEDS:
        for task in TASKS:
            st = run_task(task, seed)
            with open(OUT, "a") as f:
                f.write(json.dumps(st) + "\n")
            print(f"{LABEL:<10} {task:<18} s{seed} {'PASS' if st['passed'] else 'fail'}  turns {st['turns']:>2}  "
                  f"calls {st['tool_calls']:>2} bad {st['bad_calls']}  tok {st['completion_tokens']:>6}  "
                  f"{st['wall_s']:>6.0f}s  tg {st['tg_tps']}  draft {st['draft_acc']}/{st['draft_n']}"
                  f"{'  ERR ' + st['error'] if st['error'] else ''}", flush=True)


if __name__ == "__main__":
    main()
