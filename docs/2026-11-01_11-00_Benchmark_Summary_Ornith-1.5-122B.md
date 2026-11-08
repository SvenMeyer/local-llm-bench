# 2026-11-01_11-00 Benchmark Summary Ornith-1.5-122B (UD-Q4_K_XL)

Ornith-1.5-122B finished PatchEval with **9/20**, against 14/20 for both Qwen3.8 IQ3 quants. It ran on llama.cpp, not
Strata: Strata cannot load this file. The GPU is free and no server is running.

| | Passed | Passed before the 30-min limit | Broke existing tests | Avg time per task | Output tokens per task | Decode |
|---|---:|---:|---:|---:|---:|---:|
| Qwen3.8 IQ3_XXS (Strata) | 14/20 | 4 | 1 | 25.6 min | 31k | 24.0 t/s |
| Qwen3.8 IQ3_S (Strata) | 14/20 | 7 | 2 | 24.5 min | 23k | 17.4 t/s |
| Qwen3.8 UD-IQ4_XS (Strata) | 13/20 | 4 | 2 | 26.6 min | 25k | 16.4 t/s |
| **Ornith-1.5 UD-Q4_K_XL (llama.cpp)** | **9/20** | 4 | 1 | 25.0 min | **10k** | **7.2 t/s** |
| Bonsai 2 (reference) | 9/20 | 4 | - | 27 min | - | 25 t/s |

## What I found

- **Strata refuses the file.** Ornith is a Qwen3.5-family model (`qwen35moe`). Strata runs that family on a separate
  engine path whose expert kernels do not take IQ4_XS or Q6_K, and Unsloth's UD-Q4_K_XL has IQ4_XS experts in 10 layers
  and one Q6_K layer. Engine 0.1.52 and 0.1.55 both refuse it. That path also has no KV-format option (fp32 only).
- **On llama.cpp it only fits at 32k context** (q8_0 KV, experts on the CPU, no MTP). 64k and MTP at 32k ran out of VRAM.
  Decode 7-9 t/s, prompt reading 55 t/s (Strata reads prompts at 1,000+). 1.5 h of the 8.9 h run went to reading prompts.
- **Ornith is very token-efficient.** It used 10k output tokens per task, 2.3-3x fewer than Qwen3.8. But it decodes
  2.4-3.3x slower, so its time per task ends up the same, and 9 of its 11 misses were the 30-minute limit, not wrong fixes.
  It was still working on those when time ran out; no prompt was ever truncated.
- **Where it lost:** pypdf-3982, structlog-710, tomlkit-440 (all three Qwen3.8 quants passed these, mostly right at the
  limit), typeguard-499 (both IQ3 quants passed) and sqlit-260 (wrong fix; IQ3_S failed it too). It won city2graph-121,
  which IQ3_XXS lost.
- **Where it was fast:** sqlit-246 in 17 min (fastest of all four), click-2790 in 7.9 min (faster than every Qwen3.8
  quant) and click-3360 in 8.6 min, all at a third of Qwen3.8's decode speed.
- **Tool calls were clean:** no invalid calls, no loops, no errors in 523 calls.

**For daily use: stay on Qwen3.8 IQ3_XXS.** On this box Ornith is too slow to finish real tasks in time. The score says
what Ornith can do here in 30 minutes, not what the model can do. With Qwen3.8's speed and its token count, most of its
timeouts would likely have finished, but that is a guess, not a measurement.

## Strata 0.2.9 (engine 0.1.55) replay, Qwen3.8 IQ3_S, 24-run agent suite

| | Passed | Avg tokens/task | Decode | Avg min/task | Total |
|---|---:|---:|---:|---:|---:|
| engine 0.1.52 | 24/24 | 3,992 | 24.2 t/s | 3.2 | 1.3 h |
| engine 0.1.55 | 24/24 | 3,536 | 16.3 t/s | 4.1 | 1.6 h |

Why it is slower: 0.1.52 ran with residency-biased routing on (`STRATA_ROUTE_PRIOR=1.5`, default on cards of 13 GB or
less): the router prefers experts already on the GPU. Strata 0.2.8 turned it off by default after reports of repeated
text in long sessions. The decode expert-cache hit rate fell from 46% to 21%, more experts come over PCIe (11.3% vs 7.6%),
and decode drops a third. The hit rate stays flat through the run, so nothing builds up over time. The token-count
differences per task are sampling noise: same seed, but the new engine rounds slightly differently, so each run takes
another path. CPU heat (86-100C, fans at max) may add some throttling on long tasks.

To get the old speed back on 0.1.55: `--set STRATA_ROUTE_PRIOR=1.5` (with the repeated-text risk that made Strata turn it
off). `strata components rollback` returns to engine 0.1.52.

## Next

- **Ornith on Strata** needs a file without IQ4_XS/Q6_K experts: requantize those tensors to Q4_K/Q5_K (needs ~80 GB
  free, so after the new disk is in), or a different uploader's quant. Check expert types with `gguf_head.py` first.
- **MiniMax-M3.1-Flash Maya-XS** (93 GB, Project Maya engine) once the new disk is in.
- **Fans:** check them for dust. CPU sat at 86-100C during the replay with both fans at max; the October PatchEval runs
  averaged 78-80C.

Logs: `benchkit-patcheval-ornith15-udq4kxl-llamacpp.log`, `llama-serve-ornith15-udq4kxl-llamacpp.log`,
`patcheval-llamacpp-ornith-20261101-0158.txt`, `llama-agent-eval-strata-iq3s-noskip-0155.{jsonl,log}`,
`overnight-ornith-chain-20261031-2148.txt`. BenchKit results: `benchkit-src/BenchKit/results/2026-11-01_10-55-28`.
