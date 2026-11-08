# 27 Oct 2026 - Summary qwen3.8-flash-next on ollama

All runs are finished: GSQ IQ3_XXS is the quality pick, Q2_0 stays the speed pick, and the Coder loses on both. No server is running, and the scheduled status checks have all fired.

┌────────────────────────────────┬─────────────┬──────────┬───────────┬─────────────────────┐
│                                │ GSQ IQ3 UD-IQ4_XS (current) │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ disk                           │     75.             93.7 GB │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ KLD vs IQ4_XS (lower = closer) │                           — │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ top token agrees with IQ4_XS   │                           — │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ perplexity (IQ4_XS = 2.74)     │                        2.74 │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ generation at 8k, t/s          │                         9.8 │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ prefill at 8k, t/s             │                        ~110 │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ agent eval (8 tasks × 3 seeds) │       2                   — │
├────────────────────────────────┼─────────────┼──────────┼───────────┼─────────────────────┤
│ avg minutes per agent task     │                           — │
└────────────────────────────────┴─────────────┴──────────┴───────────┴─────────────────────┘

- GSQ IQ3_XXS: it's very close to UD-IQ4_XS in quality, yet faster: generation +15%, prefill more than 2×, and
  it's 18 GB smaller. It beats your curren If quality matters most, this one shouldreplace UD-IQ4_XS.
- Q2_0: still almost twice as fast, with aity gap. It was even a little faster thanIQ3_XXS on the agent tasks.
- Coder: don't use it. It's the slowest ofD-IQ4_XS, because its non-expert layers are much heavier. My speed estimate for it was wrong (predicted ~12.5 t/s), because it only looked at the expert
  kernels. Its poor perplexity is partly eaway from general text, but nothing itscored makes up for half the speed.

About the agent eval:
- The good news: all three models passed al calls, no loops and no runaway outputs,including the multi-file refactor and the scheduler task. So tool-use mechanics work reliably even on Q2_0.
- The limitation: the tasks turned out too quality ranking above comes from KLD andperplexity only. Settling Q2_0 vs IQ3_XXS for your actual work needs harder, longer multi-step tasks, or simply
  a few days of real use with each.

Suggestion: use IQ3_XXS as your daily modeed matters, e.g. quick iterations. Thelauncher default is still Q2_0, since that choice is yours; I can switch it. You can also delete the Coder (29.6
GB) to free the space; its shard 2 is only

QUANT=gsq-iq3xxs MTP=1 LLAMA_ARG_CTX_SIZE=ash-next-unsloth.sh

New files:
- llama-agent-eval.py and its 8 tasks in eval-data/agent-tasks (reusable)
- llama-agent-eval-summary.py
- llama-qwen38-eval-pipeline.sh (runs the whole evaluation for one model)
- llama-gsq-download.sh (downloads a GSQ te shared shard)

Results are in llama-speed-table.md (groupEADME and memory. One mistake on my side:the starter that should have launched IQ3_XXS after the Coder never fired, because its wait loop was matching its own command line. I started it by hand abothe lesson to memory.
