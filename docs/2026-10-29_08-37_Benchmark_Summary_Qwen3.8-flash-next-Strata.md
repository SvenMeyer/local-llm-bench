# Benchmark Summary Qwen3.8-flash-next - Strata 

## Session Info

finished : 29 Oct 2026 08:37

session : claude f568da57-e596-43ed-a0fa-f37b4508df9c

## Summary

The overnight evaluation finished at 08:37. **Qwen3.8 IQ3_XXS on Strata, with one setting changed (`STRATA_ROUTE_TAIL_SKIP=0`), passes 24/24 and is 2.2× faster end to end than today's llama.cpp setup.** Your pi coding agent also passed all 24 tasks on it. The machine is idle now: Strata is stopped and the GPU is free.

| Setup                                         | Passed    | Total time   | Decode speed in agent tasks |
| --------------------------------------------- | --------: | -----------: | --------------------------: |
| llama.cpp IQ3_XXS (today)                     | 24/24     | 140 min      | 9.8 t/s                     |
| Strata IQ3_XXS, default settings              | 23/24     | 93 min       | 29.5 t/s                    |
| **Strata IQ3_XXS, skipping off**              | **24/24** | **64.5 min** | **28.0 t/s**                |
| Strata IQ3_XXS, skipping and routing bias off | 24/24     | 79 min       | 22.6 t/s                    |
| Strata IQ3_S, skipping off                    | 24/24     | 76 min       | 24.2 t/s                    |
| Strata UD-IQ4_XS (4-bit)                      | 24/24     | 110 min      | 20.2 t/s                    |
| **pi agent on IQ3_XXS, skipping off**         | **24/24** | 92 min       |                             |
| pi agent on UD-IQ4_XS                         | 8/8       | 44 min       |                             |

**What I found**
- **Expert skipping, one of Strata's default shortcuts, costs more than it saves.** Its own speed gain is tiny, but it makes the model think and loop far more: about 50% more tokens per task, and it hit the 16-turn limit twice. Turning it off gives the best result.
- **Keep Strata's other default, routing bias, on.** It adds about 24% speed, and turning it off showed no quality gain.
- **IQ3_S is your middle ground:** about 15% slower than IQ3_XXS, with slightly better quality on paper. **UD-IQ4_XS** is the slowest and showed no advantage here.
- **This suite can no longer separate quality.** Every setup with skipping off scores 24/24. A harder test, like PatchEval run through pi, is needed to choose between IQ3_XXS and IQ3_S.

**pi-specific findings**
- **Hallucinated tool names:** pi made none in 32 runs. With Strata the risk still exists, because a call to a non-existent tool comes back as plain text and silently ends a pi run. llama.cpp's grammar prevents such calls entirely. Our own test harness hit these calls about 5 times per 24 runs, but pi's tool names (`read`, `bash`, `edit`, `write`) apparently don't provoke them.
- **No default timeout on `bash`:** once, the model started a calculation that never finished, and pi waited on it forever. I stopped that one process by hand after 8 minutes. pi then carried on and passed that task, and I've marked the run as "intervened". For daily use, set a default timeout or be ready to interrupt.

**Changes overnight**
- The IQ3_S download (55 GB, checksum verified) is in place. 91 GB of disk is free.
- I skipped the "IQ3_S on default settings" run to stay within the night. By then defaults were clearly the worse setting, and IQ3_S with skipping off was tested instead.
- New scripts:
  - `pi-agent-eval.py` runs the tasks through pi in a sandbox.
  - `llama-strata-overnight.sh` and the two queue scripts ran tonight's setups.
- The eval script now measures fairly across engines: it handles bad tool calls and records the longest reply.
- Everything is in `handover-strata-evaluation.md`. The README status line and memory are updated.

**Next steps, when you're ready**
1. Use Strata with `--set STRATA_ROUTE_TAIL_SKIP=0` as your daily Qwen3.8 setup. The launch command is in the handover note.
2. Run a harder test, like PatchEval through pi, to choose between IQ3_XXS and IQ3_S. It needs the Docker daemon (`sudo systemctl start docker`), which would also let us try OpenShell as pi's sandbox.
3. Give pi's `bash` tool a default timeout.
