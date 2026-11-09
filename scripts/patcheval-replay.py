#!/usr/bin/env python3
"""Replay a PatchEval agent transcript and grade the workspace at its first green test run.

Question: did the work after the agent's own tests first passed change the hidden-test result?
For each task: rebuild BenchKit's task image and workspace, replay the agent's tool calls in order
(bash commands are rerun, edit/write applied exactly as pi does, read skipped, calls that errored in
the original skipped), grade with BenchKit's own hidden-test grader at the first green pytest run,
then continue to the end and grade again. The end grade must match the original run, and the end
patch hash should match the saved one; that checks the replay.

Run from the BenchKit checkout:  uv run python ../../patcheval-replay.py RESULTS_DIR [...] [--jobs 3] [--tasks a,b]
Writes patcheval-replay-<date>.tsv next to this script.
"""
import argparse, hashlib, json, os, re, sys, threading, time, types
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).with_name("patcheval-after-fix.py").parent))
import importlib.util
_spec = importlib.util.spec_from_file_location("after_fix", Path(__file__).with_name("patcheval-after-fix.py"))
after_fix = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(after_fix)

from benchkit.benchmarks.patcheval import PatchEval
from benchkit.sandbox import DockerTaskEnvironment

REPO = "/workspace/repo"
LOCK = threading.Lock()


def say(msg):
    with LOCK:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def abspath(p):
    return p if p.startswith("/") else f"{REPO}/{p}"


def put(env, path, text):
    """Write text to a file in the container (env.exec has no stdin, so copy a local file in)."""
    import tempfile
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".replay") as fh:
        fh.write(text); local = fh.name
    try:
        env.exec(["mkdir", "-p", os.path.dirname(path)])
        env.upload(Path(local), path)
    finally:
        os.unlink(local)


def apply_edit(env, args):
    path = abspath(args["path"])
    src = env.exec(["cat", path], check=False)
    if src.returncode != 0:
        return f"cannot read {path}"
    text = src.stdout
    spots = []
    for e in args["edits"]:
        i = text.find(e["oldText"])
        if i < 0 or text.find(e["oldText"], i + 1) >= 0:
            return f"oldText {'missing' if i < 0 else 'not unique'} in {path}"
        spots.append((i, len(e["oldText"]), e["newText"]))
    for i, n, new in sorted(spots, reverse=True):
        text = text[:i] + new + text[i + n:]
    put(env, path, text)
    return ""


def write_file(env, args):
    put(env, abspath(args["path"]), args["content"])


def step(env, t):
    """Replay one tool call. Returns a note when it could not be reproduced exactly."""
    if t.get("is_error") and t["name"] in ("edit", "write"):
        return ""  # failed in the original too: no effect
    a = t["arguments"]
    if t["name"] == "read" or not a:
        return ""
    if t["name"] == "edit":
        return apply_edit(env, a)
    if t["name"] == "write":
        write_file(env, a); return ""
    if t["name"] == "bash":
        limit = a.get("timeout") or max(60, 3 * (t.get("duration_s") or 0) + 30)
        try:
            env.exec(["bash", "-c", a["command"]], workdir=REPO, timeout=limit, check=False)
        except Exception as exc:  # a hung command: note it and go on
            return f"bash {type(exc).__name__}"
    return ""


def grade(bench, task, env):
    r = bench.verify_workspace(task, env)
    d = r.details or {}
    if os.environ.get("REPLAY_DUMP"):
        Path(os.environ["REPLAY_DUMP"]).mkdir(parents=True, exist_ok=True)
        (Path(os.environ["REPLAY_DUMP"]) / f"{task.id}-{int(time.time())}.patch").write_text(d.get("patch", "") or json.dumps(d)[:20000])
    return dict(score=r.score, f2p=d.get("f2p_exit_code"), reg=d.get("regression_exit_code"),
                sha=d.get("patch_sha256", ""), rejected=d.get("submission_rejected", ""), error=r.error or "")


def replay(bench, tasks_by_id, run, rec):
    task = tasks_by_id[rec["task_id"]]
    tt = rec["tool_trace"]
    first_edit = next((i for i, t in enumerate(tt) if after_fix.kind(t) == "edit"), None)
    green = next((i for i, t in enumerate(tt) if first_edit is not None and i > first_edit and after_fix.green(t)), None)
    image = bench.pi_image_for_task(task)
    image.prepare()  # shared by every run of this task; removed by the caller
    client = types.SimpleNamespace(host="http://127.0.0.1:9/v1", timeout=60, provider="openai", api_key="", context_length=None)
    out = dict(run=run, task=rec["task_id"], original=rec["outcome"], calls=len(tt), green_call=green,
               orig_sha=(rec.get("workspace") or {}).get("patch_sha256", ""), notes=[])
    t0 = time.time()
    try:
        with DockerTaskEnvironment(client, "replay", image) as env:
            bench.prepare_workspace(task, env)
            for i, t in enumerate(tt):
                n = step(env, t)
                if n:
                    out["notes"].append(f"{i}:{n}")
                if i == green:
                    out["at_green"] = grade(bench, task, env)
                    say(f"{run} {rec['task_id']}: at first green (call {i}/{len(tt)}) score {out['at_green']['score']}")
            out["at_end"] = grade(bench, task, env)
    finally:
        pass
    out["secs"] = round(time.time() - t0)
    e = out["at_end"]
    say(f"{run} {rec['task_id']}: end score {e['score']} (original {rec['outcome']}), patch {'same' if e['sha'] == out['orig_sha'] else 'DIFFERENT'}, {out['secs']} s, notes {len(out['notes'])}")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--tasks", default="")
    args = ap.parse_args()
    bench = PatchEval()
    tasks_by_id = {t.id: t for t in bench.load_tasks()}
    work = []
    for d in args.dirs:
        for job in json.load(open(f"{d}/results.json")):
            for rec in job["tasks"]:
                if not args.tasks or rec["task_id"] in args.tasks.split(","):
                    work.append((Path(d).name, rec))
    say(f"replaying {len(work)} tasks, {args.jobs} at a time")
    rows = []
    groups = {}
    for run, rec in work:
        groups.setdefault(rec["task_id"], []).append((run, rec))

    def one_task(items):  # every run of one task, one after another, then remove its image
        done = []
        try:
            for run, rec in items:
                try:
                    done.append(replay(bench, tasks_by_id, run, rec))
                except Exception as exc:
                    say(f"{run} {rec['task_id']}: replay failed: {type(exc).__name__}: {exc}")
        finally:
            try:
                bench.pi_image_for_task(tasks_by_id[items[0][1]["task_id"]]).cleanup()
            except Exception:
                pass
        return done

    with ThreadPoolExecutor(args.jobs) as pool:
        for f in [pool.submit(one_task, items) for items in groups.values()]:
            rows.extend(f.result())
    tsv = Path(__file__).with_name(f"patcheval-replay-{time.strftime('%Y%m%d')}.tsv")
    with open(tsv, "w") as fh:
        fh.write("run\ttask\toriginal\tcalls\tgreen_call\tgreen_score\tgreen_f2p\tgreen_reg\tend_score\tend_f2p\tend_reg\tend_patch_same\tsecs\tnotes\n")
        for r in rows:
            g, e = r.get("at_green") or {}, r.get("at_end") or {}
            fh.write("\t".join(str(x) for x in [r["run"], r["task"], r["original"], r["calls"], r["green_call"],
                     g.get("score", "-"), g.get("f2p", "-"), g.get("reg", "-"), e.get("score", "-"), e.get("f2p", "-"),
                     e.get("reg", "-"), e.get("sha") == r["orig_sha"], r["secs"], ";".join(r["notes"])]) + "\n")
    say(f"done: {tsv}")


if __name__ == "__main__":
    main()
