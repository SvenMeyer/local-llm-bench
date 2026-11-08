"""MiniMax Code (mcode) adapter for the Pi task sandbox. Local addition.

Runs ``mcode exec --output-format stream-json`` in the same container, behind the
same restricted inference proxy, as the Pi harness, so the workspace, grading and
isolation are identical and only the agent differs. Enabled with
``BENCHKIT_AGENT=mcode``; the engine then builds this runner wherever it would
build a ``PiAgentRunner``.

Settings (all required except where noted):
- ``BENCHKIT_MCODE_DIST``: host path of the built ``dist/`` directory (self-contained).
- ``BENCHKIT_MCODE_CONFIG``: host path of the config.yaml to install in the sandbox.
  Its provider must point at ``http://inference:8080/v1`` and carry no real key.
- ``BENCHKIT_MCODE_MODEL``: ``--model`` value, e.g. ``custom_provider:x/y``.
- ``BENCHKIT_MCODE_EFFORT`` (optional): ``--effort`` value.
- ``BENCHKIT_MCODE_ARGS`` (optional): extra exec arguments, split on whitespace.
"""

from __future__ import annotations

import contextlib
import json
import os
import queue
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

from benchkit.client import GenerationUpdate
from benchkit.evaluation import EvaluationResult, combine_attempts, repair_message
from benchkit.pi_agent import PiAgentRunner
from benchkit.sandbox import DockerTaskEnvironment, _run

MCODE_DIR = "/opt/mcode"
MCODE_HOME_CONFIG = "/home/node/.minimax/config.yaml"


def enabled() -> bool:
    return os.environ.get("BENCHKIT_AGENT", "pi").strip().lower() == "mcode"


def _tool_error(call: dict[str, Any]) -> bool:
    if call.get("isError") or call.get("error"):
        return True
    output = call.get("output") or {}
    if isinstance(output, dict) and output.get("isError"):
        return True
    details = output.get("details") if isinstance(output, dict) else None
    execution = (details or {}).get("execution") if isinstance(details, dict) else None
    if isinstance(execution, dict):
        status = execution.get("status")
        return status not in (None, "succeeded")
    return False


def _tool_text(call: dict[str, Any]) -> str:
    output = call.get("output") or {}
    content = output.get("content") if isinstance(output, dict) else None
    if not isinstance(content, list):
        return ""
    return "".join(
        str(part.get("text") or "")
        for part in content
        if isinstance(part, dict) and part.get("type") == "text"
    )


@dataclass
class _McodeTrace:
    """Normalize mcode stream-json events into BenchKit's generation shape."""

    final_response: str = ""
    thinking_parts: list[str] = field(default_factory=list)
    output_tokens: int = 0
    input_tokens: int = 0
    cache_read_tokens: int = 0
    turns: int = 0
    tool_calls_started: int = 0
    tool_trace: list[dict[str, Any]] = field(default_factory=list)
    done_reason: str = "stop"
    generation_time_s: float = 0.0
    status: str = ""
    call_usage: list[dict[str, Any]] = field(default_factory=list)
    _started_ms: dict[str, int] = field(default_factory=dict, repr=False)
    _steps: set[str] = field(default_factory=set, repr=False)
    _seen_text: dict[str, int] = field(default_factory=dict, repr=False)

    def handle(self, event: dict[str, Any]) -> tuple[str, str]:
        kind = event.get("type")
        stamp = int(event.get("timestampMs") or 0)
        item = event.get("item") or {}
        item_type = item.get("type")
        item_id = str(item.get("id") or "")
        thinking_delta = text_delta = ""
        if kind == "item.started":
            self._started_ms.setdefault(item_id, stamp)
            if item_type in ("reasoning", "agent_message"):
                self._steps.add(item_id.split(":", 1)[0])
            elif item_type == "tool_call":
                self.tool_calls_started += 1
        if kind in ("item.updated", "item.completed") and item_type in (
            "reasoning",
            "agent_message",
        ):
            content = str(item.get("content") or "")
            seen = self._seen_text.get(item_id, 0)
            delta = content[seen:] if len(content) >= seen else content
            self._seen_text[item_id] = len(content)
            if item_type == "reasoning":
                thinking_delta = delta
            else:
                text_delta = delta
        if kind == "item.completed":
            began = self._started_ms.pop(item_id, stamp)
            if item_type == "reasoning":
                self.generation_time_s += max(0, stamp - began) / 1000
                if item.get("content"):
                    self.thinking_parts.append(str(item["content"]))
            elif item_type == "agent_message":
                self.generation_time_s += max(0, stamp - began) / 1000
                if item.get("content"):
                    self.final_response = str(item["content"])
            elif item_type == "tool_call":
                call = item.get("toolCall") or {}
                if isinstance(call, str):
                    with contextlib.suppress(json.JSONDecodeError):
                        call = json.loads(call)
                if not isinstance(call, dict):
                    call = {}
                entry: dict[str, Any] = {
                    "name": str(call.get("name") or ""),
                    "arguments": call.get("input") or {},
                    "is_error": _tool_error(call),
                    "duration_s": round(max(0, stamp - began) / 1000, 3),
                }
                text = _tool_text(call)
                if text:
                    entry["output_truncated"] = len(text) > 8000
                    entry["output"] = text[-8000:]
                self.tool_trace.append(entry)
        if kind in ("turn.completed", "exec.completed"):
            usage = event.get("usage") or (event.get("result") or {}).get("usage")
            if isinstance(usage, dict):
                cached = int(usage.get("cacheReadTokens") or 0) + int(
                    usage.get("cacheWriteTokens") or 0
                )
                # Same convention as the Pi trace: input includes cache traffic.
                self.input_tokens = int(usage.get("inputTokens") or 0) + cached
                self.cache_read_tokens = int(usage.get("cacheReadTokens") or 0)
                self.output_tokens = int(usage.get("outputTokens") or 0)
        if kind == "exec.completed":
            result = event.get("result") or {}
            self.status = str(result.get("status") or "")
            if result.get("output"):
                self.final_response = str(result["output"])
            if self.status and self.status != "succeeded":
                self.done_reason = self.status
        self.turns = len(self._steps)
        return thinking_delta, text_delta


def _session_usage(environment: DockerTaskEnvironment) -> list[dict[str, Any]]:
    """Per-reply usage from mcode's session log; it is written as each reply ends,
    so it survives a timeout that cuts off the final turn.completed event."""
    result = _run(
        [
            environment.docker,
            "exec",
            environment.container_name,
            "sh",
            "-c",
            "find /home/node/.minimax/v2/sessions -name messages.jsonl 2>/dev/null"
            " | sort | xargs -r cat",
        ],
        check=False,
        timeout=60,
    )
    calls: list[dict[str, Any]] = []
    for line in (result.stdout or "").splitlines():
        with contextlib.suppress(json.JSONDecodeError, AttributeError):
            message = json.loads(line).get("message") or {}
            if message.get("role") != "assistant":
                continue
            usage = message.get("usage") or {}
            calls.append(
                {
                    key: int(usage.get(key) or 0)
                    for key in ("input", "cacheRead", "cacheWrite", "output")
                }
                | {"stop": str(message.get("stopReason") or "")}
            )
    return calls


@dataclass
class McodeAgentRunner(PiAgentRunner):
    """Run mcode in the Pi sandbox image instead of the Pi agent."""

    @property
    def version(self) -> str:
        dist = os.environ.get("BENCHKIT_MCODE_DIST", "")
        version = ""
        package = os.path.join(
            dist, "package.json"
        )  # dist/package.json is @minimax-ai/code
        with (
            contextlib.suppress(OSError, ValueError),
            open(package, encoding="utf-8") as handle,
        ):
            version = str(json.load(handle).get("version"))
        return f"mcode {version}".strip()

    def _install(self, environment: DockerTaskEnvironment) -> None:
        dist = os.environ["BENCHKIT_MCODE_DIST"]
        config = os.environ["BENCHKIT_MCODE_CONFIG"]
        docker = environment.docker
        name = environment.container_name
        _run([docker, "cp", dist.rstrip("/"), f"{name}:{MCODE_DIR}"], timeout=180)
        _run([docker, "exec", name, "mkdir", "-p", os.path.dirname(MCODE_HOME_CONFIG)])
        with open(config, encoding="utf-8") as handle:
            payload = handle.read()
        _run(
            [docker, "exec", "--interactive", name, "tee", MCODE_HOME_CONFIG],
            input_text=payload,
        )

    def _command(
        self, environment: DockerTaskEnvironment, remaining_s: float, attempt: int
    ) -> list[str]:
        command = [
            environment.docker,
            "exec",
            "--interactive",
            "--workdir",
            environment.workdir,
            environment.container_name,
            "node",
            f"{MCODE_DIR}/cli.js",
            "exec",
            "--config",
            MCODE_HOME_CONFIG,
            "--model",
            os.environ["BENCHKIT_MCODE_MODEL"],
            "--cwd",
            environment.workdir,
            "--timeout",
            f"{max(1, int(remaining_s))}s",
            "--output-format",
            "stream-json",
            "--input",
            "-",
        ]
        if effort := os.environ.get("BENCHKIT_MCODE_EFFORT"):
            command.extend(["--effort", effort])
        command.extend(os.environ.get("BENCHKIT_MCODE_ARGS", "").split())
        if attempt:
            command.append("--continue")
        return command

    def generate(
        self,
        model: str,
        prompt: str,
        on_progress=None,
        cancel_event: threading.Event | None = None,
        verifier: Callable[[str], EvaluationResult] | None = None,
        repair_attempts: int = 0,
        workspace_setup: Callable[[DockerTaskEnvironment], None] | None = None,
        workspace_verifier: Callable[
            [DockerTaskEnvironment, list[dict[str, Any]]], EvaluationResult
        ]
        | None = None,
        repair_prompt_builder: Callable[[str, int, int], str] | None = None,
    ) -> dict:
        self.prepare()
        started = time.perf_counter()
        try:
            timeout = max(0.1, float(os.environ.get("BENCHKIT_PI_TIMEOUT", "900")))
        except ValueError:
            timeout = 900.0
        generation_results: list[dict] = []
        attempts: list[tuple[dict, EvaluationResult]] = []
        feedback_sent: list[str] = []
        verification_time = 0.0
        timed_out = cancelled = False

        with DockerTaskEnvironment(
            self.client, model, self.image, owner_id=self.owner_id
        ) as environment:
            if workspace_setup is not None:
                workspace_setup(environment)
            self._install(environment)
            message = prompt
            for attempt in range(max(0, repair_attempts) + 1):
                trace = _McodeTrace()
                stderr_parts: list[str] = []
                events: queue.Queue[dict[str, Any] | None] = queue.Queue()
                turn_started = time.perf_counter()
                remaining = timeout - (turn_started - started)
                process = subprocess.Popen(
                    self._command(environment, remaining, attempt),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    bufsize=1,
                )
                assert process.stdin and process.stdout and process.stderr
                process.stdin.write(message)
                process.stdin.close()

                def read_stdout(stream=process.stdout, sink=events) -> None:
                    for line in stream:
                        with contextlib.suppress(json.JSONDecodeError):
                            sink.put(json.loads(line))
                    sink.put(None)

                def read_stderr(stream=process.stderr, parts=stderr_parts) -> None:
                    for line in stream:
                        parts.append(line)
                        if sum(map(len, parts)) > 16000:
                            del parts[: len(parts) // 2]

                threading.Thread(target=read_stdout, daemon=True).start()
                threading.Thread(target=read_stderr, daemon=True).start()
                try:
                    while True:
                        elapsed = time.perf_counter() - started
                        if cancel_event is not None and cancel_event.is_set():
                            cancelled = True
                            break
                        if elapsed >= timeout:
                            timed_out = True
                            break
                        try:
                            event = events.get(timeout=0.1)
                        except queue.Empty:
                            continue
                        if event is None:
                            break
                        thinking_delta, text_delta = trace.handle(event)
                        if on_progress is not None and (thinking_delta or text_delta):
                            on_progress(
                                GenerationUpdate(
                                    thinking=thinking_delta,
                                    response=text_delta,
                                    elapsed_s=elapsed,
                                    reasoning_channel_seen=bool(trace.thinking_parts)
                                    or bool(thinking_delta),
                                    attempt=attempt,
                                )
                            )
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            with contextlib.suppress(subprocess.TimeoutExpired):
                                process.wait(timeout=5)
                    # docker exec does not forward the kill, mcode renames itself
                    # ("minimax-code") and can leave background task processes, and
                    # the slim image has no pkill. The container belongs to this task
                    # only, so stop everything but PID 1 before anything is graded.
                    _run(
                        [
                            environment.docker,
                            "exec",
                            environment.container_name,
                            "sh",
                            "-c",
                            "for p in /proc/[0-9]*; do pid=${p#/proc/}; "
                            '[ "$pid" = 1 ] || [ "$pid" = "$$" ] || kill -9 "$pid" '
                            "2>/dev/null; done; true",
                        ],
                        check=False,
                        timeout=30,
                    )
                if trace.status in ("timeout", "timed_out") and not timed_out:
                    timed_out = True
                turn_elapsed = time.perf_counter() - turn_started
                calls = _session_usage(environment)
                consumed = sum(
                    len(g.get("call_usage") or []) for g in generation_results
                )
                trace.call_usage = calls[consumed:]
                if trace.call_usage:
                    # Same convention as the Pi trace: input includes cache traffic.
                    trace.input_tokens = sum(
                        c["input"] + c["cacheRead"] + c["cacheWrite"]
                        for c in trace.call_usage
                    )
                    trace.cache_read_tokens = sum(
                        c["cacheRead"] for c in trace.call_usage
                    )
                    trace.output_tokens = sum(c["output"] for c in trace.call_usage)
                    trace.turns = max(trace.turns, len(trace.call_usage))
                    if trace.call_usage[-1]["stop"] == "length":
                        trace.done_reason = "length"
                if on_progress is not None and not cancelled:
                    on_progress(
                        GenerationUpdate(
                            elapsed_s=time.perf_counter() - started,
                            reasoning_channel_seen=bool(trace.thinking_parts),
                            done=True,
                            attempt=attempt,
                        )
                    )
                error = "".join(stderr_parts).strip()
                length_exceeded = trace.done_reason in ("length", "max_tokens")
                if not trace.status and not (cancelled or timed_out):
                    raise RuntimeError(
                        "mcode exited without a result: "
                        + (error[-2000:] or "no exec.completed event")
                    )
                thinking = "\n\n".join(trace.thinking_parts)
                generation = {
                    "thinking": thinking,
                    "response": trace.final_response,
                    "trace_status": (
                        "observed"
                        if thinking
                        else "available_empty"
                        if trace.turns
                        else "unavailable"
                    ),
                    "tok_s": (
                        trace.output_tokens / trace.generation_time_s
                        if trace.generation_time_s > 0
                        else 0.0
                    ),
                    "eval_count": trace.output_tokens,
                    "eval_duration_ns": int(trace.generation_time_s * 1e9),
                    "response_time_s": turn_elapsed,
                    "done_reason": (
                        "cancelled"
                        if cancelled
                        else "timeout"
                        if timed_out
                        else trace.done_reason
                    ),
                    "timed_out": timed_out,
                    "timeout_s": timeout,
                    "cancelled": cancelled,
                    "length_exceeded": length_exceeded,
                    "harness": "pi",
                    "harness_version": self.version,
                    "input_tokens": trace.input_tokens,
                    "model_turns": trace.turns,
                    "tool_calls": trace.tool_calls_started,
                    "tool_trace": trace.tool_trace,
                    "call_usage": trace.call_usage,
                    "workspace_evaluated": workspace_verifier is not None,
                    "pi_scaffold": {"agent": self.version},
                }
                generation_results.append(generation)
                active_verifier = (
                    (
                        lambda _response, current=trace: workspace_verifier(
                            environment, current.tool_trace
                        )
                    )
                    if workspace_verifier is not None
                    else verifier
                )
                if active_verifier is None:
                    break
                terminal = cancelled or timed_out or length_exceeded
                verification_started = time.perf_counter()
                evaluation = (
                    EvaluationResult(score=0.0)
                    if cancelled or (terminal and workspace_verifier is None)
                    else active_verifier(trace.final_response)
                )
                verification_time += time.perf_counter() - verification_started
                attempts.append((generation, evaluation))
                if terminal or evaluation.passed or evaluation.error:
                    break
                if attempt >= repair_attempts:
                    break
                feedback_sent.append(evaluation.feedback)
                builder = repair_prompt_builder or repair_message
                message = builder(evaluation.feedback, attempt + 1, repair_attempts)

            if generation_results:
                generation_results[-1]["upstream_calls"] = environment.upstream_calls()

        elapsed = time.perf_counter() - started
        accounted = sum(
            float(g.get("response_time_s") or 0.0) for g in generation_results
        )
        generation_results[-1]["response_time_s"] += max(
            0.0, elapsed - accounted - verification_time
        )
        if verifier is None and workspace_verifier is None:
            return generation_results[-1]
        return combine_attempts(attempts, feedback_sent)
