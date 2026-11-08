# Summary Benchmak IQ3_XXS IQ3_S UD-IQ4_XS

UD-IQ4_XS finished at 09:58 with 13/20. It is the slowest quant and no better than the other two, so IQ3_XXS stays your daily quant. Strata and the Docker bridge are stopped and the GPU is free.

┌────────────────────┬────────┬────────────────────────────┬────────────────────┬─────────────────┬─────────┐
│       Quant        │ Passed │ Passed before the 30-min   │  Broke existing    │  Avg time per   │ Decode  │
│                    │        │           limit            │       tests        │      task       │         │
├────────────────────┼────────┼────────────────────────────┼────────────────────┼─────────────────┼─────────┤
│ IQ3_XXS            │  14/20 │                          4 │                  1 │        25.6 min │   24.0  │
│                    │        │                            │                    │                 │     t/s │
├────────────────────┼────────┼────────────────────────────┼────────────────────┼─────────────────┼─────────┤
│ IQ3_S              │  14/20 │                          7 │                  2 │        24.5 min │   17.4  │
│                    │        │                            │                    │                 │     t/s │
├────────────────────┼────────┼────────────────────────────┼────────────────────┼─────────────────┼─────────┤
│ UD-IQ4_XS          │  13/20 │                          4 │                  2 │        26.6 min │   16.4  │
│                    │        │                            │                    │                 │     t/s │
├────────────────────┼────────┼────────────────────────────┼────────────────────┼─────────────────┼─────────┤
│ Bonsai 2           │   9/20 │                          4 │                  – │          27 min │  25 t/s │
│ (reference)        │        │                            │                    │                 │         │
└────────────────────┴────────┴────────────────────────────┴────────────────────┴─────────────────┴─────────┘

What I found
- All three quants solve the same core set. 11 tasks passed on all three, and the same 4 failed on all three. The differences are on 5 tasks, each run once, so a one-point gap is within run-to-run noise.
- The extra bits in UD-IQ4_XS bought nothing. It decodes slowest, spends the most time per task, and lost typeguard-499, which both IQ3 quants solved.
- It ran cleanly. No made-up tool names and no early empty replies in this run.
- What PatchEval can't tell you: with one run per quant, it can't separate these three. Telling them apart would take several runs of each quant, at about 9 hours per run. Since none of them is clearly better, IQ3_XXS gets the call for being 40–50% faster.

I've updated the README status line, handover-strata-evaluation.md and memory with the result. The open items left are the OpenShell session for daily pi use and a default timeout for pi's bash tool.
