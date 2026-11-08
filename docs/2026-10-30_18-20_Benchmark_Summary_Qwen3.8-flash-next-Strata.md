# 2026-10-30_18-20 Benchmark_Summary Qwen3.8-flash-next-Strata

IQ3_S finished at 18:19 with 14/20, the same score as IQ3_XXS. PatchEval doesn't separate the two on quality. The queue stopped before UD-IQ4_XS as you asked, and Strata is off, so the GPU is free.

┌───────────────────┬────────┬─────────────────────┬────────────────┬─────────────┬────────────────┬─────────┐
│                   │ Passed │ Passed before the   │ Broke existing │  Avg time   │ Output tokens  │ Decode  │
│                   │        │    30-min limit     │      tests     │  per task   │    per task    │         │
├───────────────────┼────────┼─────────────────────┼────────────────┼─────────────┼────────────────┼─────────┤
│ Bonsai 2 (for     │   9/20 │                   4 │              – │      27 min │              – │  25 t/s │
│ reference)        │        │                     │                │             │                │         │
├───────────────────┼────────┼─────────────────────┼────────────────┼─────────────┼────────────────┼─────────┤
│ IQ3_XXS           │  14/20 │                   4 │              1 │    25.6 min │            31k │   24.0  │
│                   │        │                     │                │             │                │     t/s │
├───────────────────┼────────┼─────────────────────┼────────────────┼─────────────┼────────────────┼─────────┤
│ IQ3_S             │  14/20 │                   7 │              2 │    24.5 min │            23k │   17.4  │
│                   │        │                     │                │             │                │     t/s │
└───────────────────┴────────┴─────────────────────┴────────────────┴─────────────┴────────────────┴─────────┘

What I found
- Each quant beat the other on 2 tasks. Both passed the same 12; IQ3_XXS alone solved sqlit-260 and json-repair-191, IQ3_S alone solved city2graph-121 and pypdf-3878. With one run per quant, a 2-task difference is within run-to-run noise. 4 tasks were solved by neither.
- The speed gap cancels out. IQ3_S decodes 27% slower, but it uses 25% fewer tokens to reach a fix. The time per task ends up the same, and IQ3_S finished inside the limit more often (7 vs 4). IQ3_XXS is the snappier one when you're watching it work.
- Both clearly beat Bonsai. Together they solved 7 of the 11 tasks Bonsai failed.
- 64k context is enough. When pi ran out of room it compacted the conversation (57k → 28k tokens) and carried on.
- Tool calls were clean. There were no rejected or made-up tool names in 40 runs.
- One incident: on city2graph-121, IQ3_XXS returned an empty reply after 75 seconds, so pi stopped without changing anything. It didn't happen on IQ3_S.

For daily use: I'd stay on IQ3_XXS. Quality ties and time per task ties, but 24 t/s feels noticeably quicker in interactive use. IQ3_S is a reasonable alternative, not an upgrade.

About UD-IQ4_XS tonight: it is slower again (about 20 t/s in earlier evals, likely about 14 here), so it would need about 16/20 to show a real gain. This command starts it:
cd ~/Downloads/AI-Runtime && ARMS=udiq4xs nohup ./patcheval-strata-quants.sh > patcheval-strata-quants-$(date +%Y%m%d-%H%M).txt 2>&1 &

I've added the results to handover-strata-evaluation.md, the README status line and memory. The OpenShell session is still to come.

---

My new insight : I assumed that tokens / s would be easy to measure and would replicate 1:1 to the time to solve a problem. However, this is disproven here. Eventually, tokens / s is not relevant as the final goal is to solve a problem in as little time as possible, that's what a user/developer is interested in. If a solution has the same (code) quality, then whatever model comes back with that in a little time as possible wins. Model A with 10 t/s beats model B with 20 t/s if model A delivers the same or a better result with less than 50% of tokens than model B, thus delivers the solution faster.
