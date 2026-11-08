#!/usr/bin/env python3
"""The in-house agent tasks (eval-data/agent-tasks), driven by the real `pi` coding agent instead of our own loop.

Why: pi is the agent the user will run these models with. Our own loop (llama-agent-eval.py) is a lab harness;
this shows what pi does with the same model and server, including how it reacts when the server returns a tool
call as plain text (Strata does that for a call to an undeclared tool; pi then ends the run, see handover).

Each run: fresh sandbox copy of the task (without TASK.md), `pi --mode json` with read/bash/edit/write, inside
bubblewrap (read-only system, writable sandbox + pi's own config dir, network kept for the local server).
Scoring restores pristine tests/ and runs them, exactly as llama-agent-eval.py does. One JSON line per run to OUT.

pi gets its own config dir (PI_CODING_AGENT_DIR), so ~/.pi is never read or written.

Usage:
  LABEL=pi-strata-iq3xxs MODEL=qwen3.8-flash-next-iq3_xxs python3 pi-agent-eval.py            # all tasks, 1 sample
  LABEL=... MODEL=... TASKS=t7-calc,t8-scheduler SAMPLES=3 python3 pi-agent-eval.py
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time

HERE = pathlib.Path("/home/sum/Downloads/AI-Runtime")
PORT = os.environ.get("PORT", "8099")
LABEL = os.environ.get("LABEL", "pi")
MODEL = os.environ["MODEL"]                       # the id the server lists at /v1/models
CTX = int(os.environ.get("CTX", "65536"))
MAX_TOKENS = int(os.environ.get("MAX_TOKENS", "21846"))  # Strata: thinking cap = 3/4 of this (16384)
THINKING = os.environ.get("THINKING", "high")     # pi level; Strata maps high -> template xhigh
TASK_DIR = HERE / "eval-data/agent-tasks"
TASKS = [t for t in os.environ.get("TASKS", "").split(",") if t] or sorted(p.name for p in TASK_DIR.iterdir() if p.is_dir())
SAMPLES = int(os.environ.get("SAMPLES", "1"))
TASK_TIMEOUT = int(os.environ.get("TASK_TIMEOUT", "2400"))
OUT = pathlib.Path(os.environ.get("OUT", HERE / f"pi-agent-eval-{LABEL}.jsonl"))
EVENTS_DIR = HERE / "pi-eval" / "events" / LABEL
AGENT_DIR = HERE / "pi-eval" / "agent-dir"
PI = shutil.which("pi") or "/home/sum/.nvm/versions/node/v24.22.1/bin/pi"
NODE_BIN = str(pathlib.Path(os.path.realpath(PI)).parents[0])

# A tool call the server handed back as text (Strata) or the model wrote outside the tool-call channel.
TEXT_CALL = re.compile(r"<tool_call>|<function=|\"name\"\s*:\s*\"\w+\"\s*,\s*\"arguments\"")


def write_agent_dir():
    AGENT_DIR.mkdir(parents=True, exist_ok=True)
    models = {"providers": {"local": {
        "name": "local eval server", "baseUrl": f"http://127.0.0.1:{PORT}/v1", "api": "openai-completions",
        "apiKey": "none",
        "compat": {"supportsDeveloperRole": False, "supportsReasoningEffort": True},
        "models": [{"id": MODEL, "name": MODEL, "reasoning": True, "input": ["text"],
                    "contextWindow": CTX, "maxTokens": MAX_TOKENS,
                    "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}}]}}}
    (AGENT_DIR / "models.json").write_text(json.dumps(models, indent=2))
    settings = AGENT_DIR / "settings.json"
    if not settings.exists():
        settings.write_text("{}\n")


def run_unittest(root):
    try:
        p = subprocess.run(["python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                           cwd=root, capture_output=True, text=True, timeout=120)
        return p.returncode == 0, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"


def bwrap_cmd(root, prompt):
    home = os.path.expanduser("~")
    return ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
            "--bind", str(root), str(root), "--bind", str(AGENT_DIR), str(AGENT_DIR),
            "--tmpfs", f"{home}/.cache", "--tmpfs", f"{home}/.npm",
            "--chdir", str(root), "--die-with-parent", "--new-session",
            "--setenv", "PI_CODING_AGENT_DIR", str(AGENT_DIR),
            "--setenv", "PATH", f"{NODE_BIN}:/usr/local/bin:/usr/bin:/bin",
            PI, "--mode", "json", "--no-session", "--provider", "local", "--model", MODEL,
            "--thinking", THINKING, "--tools", "read,bash,edit,write", prompt]


def run_task(task, sample):
    src = TASK_DIR / task
    root = pathlib.Path(tempfile.mkdtemp(prefix=f"pi-{task}-", dir="/var/tmp")).resolve()
    shutil.copytree(src, root, dirs_exist_ok=True, ignore=shutil.ignore_patterns("TASK.md", "__pycache__"))
    prompt = ((src / "TASK.md").read_text() + "\nWork in the current directory. When the task is complete and the "
              "tests pass (python3 -m unittest discover -s tests -v), reply with a short summary.")
    st = {"label": LABEL, "task": task, "sample": sample, "turns": 0, "tool_calls": 0, "tool_errors": 0,
          "unknown_tool": 0, "output_tokens": 0, "max_msg_tokens": 0, "stop_reason": None,
          "ended_on_text_call": False, "error": None}
    EVENTS_DIR.mkdir(parents=True, exist_ok=True)
    ev_path = EVENTS_DIR / f"{task}-s{sample}.jsonl"
    t0 = time.time()
    last_assistant = None
    try:
        with open(ev_path, "w") as ev:
            p = subprocess.run(bwrap_cmd(root, prompt), stdout=ev, stderr=subprocess.PIPE, text=True,
                               timeout=TASK_TIMEOUT)
        if p.returncode != 0:
            st["error"] = f"pi exit {p.returncode}: {p.stderr[-300:]}"
    except subprocess.TimeoutExpired:
        st["error"] = "task timeout"
    st["wall_s"] = round(time.time() - t0, 1)
    for line in open(ev_path, errors="replace"):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("type") == "message_end" and (e.get("message") or {}).get("role") == "assistant":
            m = e["message"]
            st["turns"] += 1
            out = (m.get("usage") or {}).get("output", 0) or 0
            st["output_tokens"] += out
            st["max_msg_tokens"] = max(st["max_msg_tokens"], out)
            last_assistant = m
        elif e.get("type") == "tool_execution_end":
            st["tool_calls"] += 1
            if e.get("isError") or (e.get("result") or {}).get("isError"):
                st["tool_errors"] += 1
            text = json.dumps(e.get("result"))[:400]
            if "not found" in text and "Tool" in text:
                st["unknown_tool"] += 1
    if last_assistant:
        st["stop_reason"] = last_assistant.get("stopReason")
        final = " ".join(c.get("text", "") for c in last_assistant.get("content", []) if c.get("type") == "text")
        st["ended_on_text_call"] = bool(TEXT_CALL.search(final))
        st["final_text_tail"] = final[-300:]
    shutil.rmtree(root / "tests", ignore_errors=True)
    shutil.copytree(src / "tests", root / "tests")
    st["passed"], out = run_unittest(root)
    st["score_tail"] = out[-300:]
    st["out_tps"] = round(st["output_tokens"] / st["wall_s"], 2) if st["wall_s"] else None
    shutil.rmtree(root, ignore_errors=True)
    return st


def main():
    write_agent_dir()
    for s in range(1, SAMPLES + 1):
        for task in TASKS:
            st = run_task(task, s)
            with open(OUT, "a") as f:
                f.write(json.dumps(st) + "\n")
            flag = " ENDED-ON-TEXT-CALL" if st["ended_on_text_call"] else ""
            print(f"{LABEL:22} {task:18} s{s} {'PASS' if st['passed'] else 'FAIL'}  turns {st['turns']:2}  "
                  f"tools {st['tool_calls']:2} err {st['tool_errors']} unk {st['unknown_tool']}  "
                  f"tok {st['output_tokens']:6}  {st['wall_s']:6.0f}s  stop {st['stop_reason']}{flag}"
                  f"{'  ERROR ' + st['error'] if st['error'] else ''}", flush=True)


if __name__ == "__main__":
    main()
