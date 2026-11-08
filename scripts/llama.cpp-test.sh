# run llama.cpp on RTX4070 8GB

# START HERE if you are picking this up fresh: README.md
#   llama-compile-guide.md              -- machine spec, cmake flags, toolchain, rebuilds
#   llama-run-guide.md                  -- Qwen3.8-Flash-Next: arch, memory, flags, MTP
#   llama-qwen38-flash-next-unsloth.md  -- this combo: Unsloth + UD-IQ4_XS + MTP patch
#   llama-qwen38-benchmark-run.md       -- how to run the scaled Group A/B/C bench
#   llama-benchmark-and-tuning-guide.md -- how to measure + results log of configs tried
#   llama-todo.md                       -- open work, known unknowns
# This file is the raw running log: commands actually run and numbers actually
# measured, newest at the bottom. The guides are the distilled version.

<https://gemini.google.com/app/c638ec02f1d9702a>

./build/bin/llama-cli -m /home/sum/.cache/lm-studio/models/unsloth/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf \
-t 12 \
-ngl all \
-ot "exps=CPU" \
-ctk q8_0 \
-ctv q8_0 \
-fa on \
-c 131072 \
-ub 512 \
--temp 0.6 \
--top-p 0.95 \
--min-p 0.05 \
--jinja \
-cnv \
-p "Write a typescript program to upload a file to IPFS"


## Results

[ Prompt: 274.2 t/s | Generation: 23.9 t/s ]
[ Prompt: 270.7 t/s | Generation: 23.5 t/s ]

llama_memory_breakdown_print: | memory breakdown [MiB]          | total   free     self   model   context   compute    unaccounted |
llama_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 4828 + ( 2753 =  2027 +     232 +     493) +         227 |
llama_memory_breakdown_print: |   - Host                        |                 20724 = 20684 +       0 +      40                |


### move some MoE back to GPU

./build/bin/llama-cli \
-m /home/sum/.cache/lm-studio/models/unsloth/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf \
-t 12 \
-ngl all \
-cmoe \
-ctk q8_0 \
-ctv q8_0 \
-fa on \
-c 131072 \
-ub 512 \
--temp 0.6 \
--jinja \
-cnv \
-p "Write a typescript program to upload a file to IPFS"




./build/bin/llama-cli \
-m /home/sum/.cache/lm-studio/models/unsloth/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf \
-t 12 \
-ngl all \
-ncmoe 28 \
-ctk q8_0 \
-ctv q8_0 \
-fa on \
-c 131072 \
-ub 512 \
--temp 0.6 \
--jinja \
-cnv \
-p "Write a typescript program to upload a file to IPFS"

---

./build/bin/llama-cli \
  -m ~/.cache/lm-studio/models/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_S.gguf \
  -p "Write a typescript program to upload a file to IPFS"
  -t 12 \
  -ngl all \
  -fa on \
  -ctk q4_0 \
  -ctv q4_0 \
  -c 16384 \
  --temp 0.1 \
  --jinja \
  -cnv

[ Prompt: 290.2 t/s | Generation: 37.5 t/s ]
common_memory_breakdown_print: | memory breakdown [MiB]          | total   free    self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 1108 + (6523 =  4588 +    1442 +     493) +         177 |
common_memory_breakdown_print: |   - Host                        |                  648 =   545 +       0 +     103                |
zsh: command not found: -t
$


---


./build/bin/llama-cli \
  -m ~/.cache/lm-studio/models/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_S.gguf \
  -p "Write a typescript program to upload a file to IPFS"
  -t 12 \
  -ngl all \
  -fa on \
  -ctk q4_0 \
  -ctv q4_0 \
  -c 65536 \
  --temp 0.1 \
  --jinja \
  -cnv \
  -ctk q8_0 \
  -ctv q8_0

  [ Prompt: 265.1 t/s | Generation: 37.4 t/s ] - 6.913Gi

common_memory_breakdown_print: | memory breakdown [MiB]          | total   free    self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 1108 + (6523 =  4588 +    1442 +     493) +         177 |
common_memory_breakdown_print: |   - Host                        |                  648 =   545 +       0 +     103                |

---

./build/bin/llama-cli \
  -m ~/.cache/lm-studio/models/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-Q4_K_M.gguf \
  -p "Write a typescript program to upload a file to IPFS"
  -t 12 \
  -ngl all \
  -fa on \
  -c 65536 \
  --temp 0.1 \
  --jinja \
  -cnv \
  -ctk q8_0 \
  -ctv q8_0

./build/bin/llama-cli                  6690MiB (nvidia-smi)
[ Prompt: 186.1 t/s | Generation: 28.2 t/s ] (35 W)


## Qwen3.5-9B-GGUF - Qwen3.5-9B-UD-Q5_K_XL

./build/bin/llama-cli \
  -m /home/sum/.cache/lm-studio/models/unsloth/Qwen3.5-9B-GGUF/Qwen3.5-9B-UD-Q5_K_XL.gguf \
  -p "Write a typescript program to upload a file to IPFS"
  -t 12 \
  -ngl all \
  -fa on \
  -c 65536 \
  --temp 0.1 \
  --jinja \
  -cnv \
  -ctk q8_0 \
  -ctv q8_0

[ Prompt: 163.0 t/s | Generation: 30.4 t/s ]
[ Prompt: 168.0 t/s | Generation: 29.6 t/s ] - 6.968 Gi (-ctk q8_0 / -ctv q8_0)
[ Prompt: 118.3 t/s | Generation: 24.0 t/s ] - 6.968 Gi (-ctk q8_0 / -ctv q4_0) 35W max
[ Prompt: 140.4 t/s | Generation: 24.4 t/s ] - 6.968 Gi (-ctk q8_0 / -ctv q8_0) 35W max

common_memory_breakdown_print: | memory breakdown [MiB]          | total   free    self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 1052 + (6569 =  5753 +     322 +     493) +         187 |
common_memory_breakdown_print: |   - Host                        |                  699 =   666 +       0 +      33                |



## Qwen3.5-4B-GGUF

./build/bin/llama-cli \
  -m ~/.cache/lm-studio/models/unsloth/Qwen3.5-4B-GGUF/Qwen3.5-4B-UD-Q4_K_XL.gguf \
  --mmproj ~/.cache/lm-studio/models/unsloth/Qwen3.5-4B-GGUF/mmproj-F32.gguf \
  --image ~/Pictures/Scans/handwritten-notes-YD.jpg \
  -t 12 \
  -ngl all \
  -fa on \
  -ctk q8_0 \
  -ctv q8_0 \
  -c 32768 \
  --temp 0.1 \
  --top-p 0.95 \
  --min-p 0.05 \
  --jinja \
  -cnv \
  -p "extract text from image"

  [ Prompt: 889.7 t/s | Generation: 53.6 t/s ] (10 May 2026)

  ---

cd /home/sum/Downloads/AI-Runtime/llama.cpp/

./build/bin/llama-cli \
-m ~/.cache/lm-studio/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf \
-t 12 \
-ngl all \
--cpu-moe \
-fa on \
-ctk q8_0 \
-ctv q8_0 \
-c 131072 \
--temp 0.1 \
--top-p 0.95 \
--min-p 0.05 \
--jinja \
-cnv \
-p "create a whitelist in solidity with some basic functions to add accounts with a name of type `bytes32`(short string), and a delete function"

[ Prompt: 42.7 t/s | Generation: 14.3 t/s ] (balanced)

> i think the array is not a good idea. looping over it is very gas intensive and eventually break if the array is long. also for string lets use bytes32 instead for a short string


[ Prompt: 174.7 t/s | Generation: 14.9 t/s ] (balanced)

common_memory_breakdown_print: | memory breakdown [MiB]          | total   free     self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 4646 + ( 2934 =  2038 +     402 +     493) +         228 |
common_memory_breakdown_print: |   - Host                        |                 29914 = 29841 +       0 +      72                |

nvtop ~ 3.1 GB + 0.39 overhead = 3.452Gi/7.996Gi]

---

nvtop ~ 3.1 GB + 0.39 overhead = 3.452Gi/7.996Gi]
65536 context
4.531Gi/7.996Gi] - 131072 context

> create a whitelist in solidity with some basic functions to add accounts with a name (short string , type ) and a delete function

[ Prompt: 72.6 t/s | Generation: 17.7 t/s ] (performance)
[ Prompt: 179.0 t/s | Generation: 18.6 t/s ]
[ Prompt: 169.5 t/s | Generation: 18.2 t/s ]
[ Prompt: 167.8 t/s | Generation: 17.1 t/s ]

common_memory_breakdown_print: | memory breakdown [MiB]          | total   free     self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 4588 + ( 2990 =  2038 +     402 +     549) +         230 |
common_memory_breakdown_print: |   - Host                        |                 29914 = 29841 +       0 +      72                |
~llama_context:      CUDA0 compute buffer size of 549.3302 MiB, does not match expectation of 493.0000 MiB


131072 ctx (performance)
[ Prompt: 73.6 t/s | Generation: 19.1 t/s ]
[ Prompt: 177.4 t/s | Generation: 16.8 t/s ]

common_memory_breakdown_print: | memory breakdown [MiB]          | total   free     self   model   context   compute    unaccounted |
common_memory_breakdown_print: |   - CUDA0 (RTX 4070 Laptop GPU) |  7809 = 3542 + ( 4038 =  2038 +    1422 +     577) +         228 |
common_memory_breakdown_print: |   - Host                        |                 30106 = 29841 +       0 +     264                |


## Qwen3.6-35B-A3B-UD-Q8_K_XL

./build/bin/llama-cli \
-m ~/.cache/lm-studio/models/unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
-t 12 \
-ngl all \
--cpu-moe \
-fa on \
-ctk q8_0 \
-ctv q8_0 \
-c 131072 \
--temp 0.1 \
--top-p 0.95 \
--min-p 0.05 \
--jinja \
-cnv \
-p "create a whitelist in solidity with some basic functions to add accounts with a name of type `bytes32`(which we use to represent a short string), and a delete function"





## gemma-4-31b-i1

### balanced power / LMstudio

2.44 token/sec


## Qwen3.6-27B-UD-Q4_K_XL

./build/bin/llama-cli \
-m ~/.cache/lm-studio/models/unsloth/Qwen3.6-27B-GGUF/Qwen3.6-27B-UD-Q4_K_XL.gguf \
-t 12 \
-ngl 18 \
-fa on \
-ctk q8_0 \
-ctv q8_0 \
-c 131072 \
--temp 0.1 \
--top-p 0.95 \
--min-p 0.05 \
--jinja \
-cnv \
-p "create a whitelist in solidity with some basic functions to add accounts with a name of type `bytes32`(which we use to represent a short string), and a delete function"

nvtop : 7.683Gi/7.996Gi

[ Prompt: 9.5 t/s | Generation: 2.3 t/s ] (aborted)


## 2026-07-15 rebuild: CUDA 13.3, sm_89, MTP support

Rebuilt from scratch: git pull (5755a100c -> f955e394b, ~2 months of upstream
commits), reconfigured against CUDA 13.3.73 (was 13.1.80), CMAKE_CUDA_ARCHITECTURES=89,
GGML_CUDA_FA_ALL_QUANTS=ON. ccache installed for faster future rebuilds.
version: 10022 (f955e394b)

/usr/local/bin/llama-server now symlinks here:
  /home/sum/Downloads/AI-Runtime/llama.cpp/build/bin/llama-server

Deleted the redundant checkouts that used to live alongside this one
(llama.cpp_2026-04-20 backup, DEV/AI/inference/llama.cpp, .cache/yay/llama.cpp-cuda-git)
so there is now exactly one canonical llama.cpp checkout: this one.

### Start scripts (no manual flags needed)

  /home/sum/Downloads/AI-Runtime/llama-serve.sh       -> Ornith 1.0 35B
  /home/sum/Downloads/AI-Runtime/llama-serve-mtp.sh    -> Qwen3.6-35B-A3B-MTP (speculative decoding)

Both just set LLAMA_ARG_* env vars (memory profile lifted from LM Studio's own
saved load config for Ornith: --cpu-moe, -ngl all, -ctk/-ctv q8_0, -t 10) and
exec llama-server. Override anything with an env var, e.g.:
  LLAMA_ARG_CTX_SIZE=65536 ./llama-serve.sh
--fit is on by default in this build and auto-sizes anything you leave unset.

### MTP (multi-token prediction) speculative decoding

This build supports `--spec-type draft-mtp` (added upstream since our last
build, wasn't in the May checkout). Uses the MTP head baked into the model's
own GGUF, no separate draft model needed. Confirmed working:

  ./llama-serve-mtp.sh
  # response includes: "draft_n":93,"draft_n_accepted":47  (~50% hit rate)
  # 25.1 tok/s generation on the RTX 4070 Laptop, 35B MoE model

Only Qwen3.6-35B-A3B-MTP-GGUF has a real MTP head (nextnPredictLayers=1,
confirmed via LM Studio's gguf-metadata-cache.json). Ornith's GGUF does NOT
(nextnPredictLayers=null, supportsMtp=false) despite being the same qwen35moe
architecture -- MTP has to be baked into the specific quant/export, it's not
automatic for every model of a supported arch.

Context caveat: Ornith's full 262144 (256k) context fits in ~6GB VRAM, but the
same 262144 on the MTP model OOM'd mid-generation (crashed, verified). That
model is an "UD" unsloth-dynamic quant (keeps attention/output layers at
higher precision) plus one extra layer for the MTP head, so its always-resident
GPU footprint is bigger. 131072 (128k) works with ~2GB headroom -- that's
llama-serve-mtp.sh's default now.

### Does Unsloth Studio use this build?

No, not by default. unsloth_zoo/llama_cpp.py hardcodes its own separate
checkout at ~/.unsloth/llama.cpp (downloads prebuilt binaries from the
unslothai/llama.cpp fork's releases, not upstream ggml-org). To point it at
this build instead:
  UNSLOTH_LLAMA_CPP_PATH=/home/sum/Downloads/AI-Runtime/llama.cpp unsloth export ...

### Can LM Studio use this build?

No. LM Studio manages its own versioned, self-contained backend bundles under
~/.cache/lm-studio/extensions/backends/ (own compiled llama.cpp + proprietary
.node bindings, e.g. llm_engine_cuda12.node -- not just a llama-server binary).
No config found for pointing it at an external backend. Its active backend
(~/.cache/lm-studio/.internal/backend-preferences-v1.json) is independently
auto-updated and was already at llama.cpp-linux-x86_64-nvidia-cuda12-avx2
2.24.0 (dated today) before we touched anything -- decoupled version numbering
from upstream llama.cpp entirely, so "our version" vs "LM Studio's version"
isn't really a comparable question.

2026-07-15: pruned ~/.cache/lm-studio/extensions/backends/ down to the latest
version per backend family (avx2/cuda12/legacy-cuda/vulkan), freed ~6.6GB.
Later narrowed further to just cuda12 + avx2 (only backends that match this
hardware -- no Vulkan needed, have an NVIDIA GPU).

### Bonsai 27B (prism-ml, dense qwen35, Q1_0)

/home/sum/Downloads/AI-Runtime/llama-serve-bonsai.sh -> Bonsai 27B

Dense model, NOT MoE -- --cpu-moe is a no-op here, everything just goes on
GPU (-ngl 999). Model itself is tiny at Q1_0 (~3.8GB) but the 262144 native
context OOM'd anyway: dense model KV cache scales with the full 27B param
attention shape, not a ~3B "active experts" subset like the MoE models.
32768 confirmed working, ~2.3GB VRAM headroom. ~26 tok/s.

### DSpark speculative decoding -- evaluated and rejected, 2026-07-15

Bonsai ships a "DSpark" drafter (prism-ml collection page: "lossless 1.37x
decode speedup"). Downloaded Bonsai-27B-dspark-Q4_1.gguf (1.79GB) to try it.
Failed to load: "unknown model architecture: 'dspark'" -- mainline llama.cpp
doesn't recognize it at all. prism-ml's README confirms it needs a separate
fork, github.com/PrismML-Eng/llama.cpp, not mainline ggml-org/llama.cpp.

Researched whether it's worth building that fork. Found the real DeepSeek/PKU
DSpark method is a still-open, actively-debugged mainline PR (ggml-org/llama.cpp#25173),
NOT the same code as prism-ml's fork but the closest available signal on
whether the technique itself is any good. Author's own benchmark: 1.88x vs
vanilla, beats DFlash by 1.21x -- on Qwen3-8B, datacenter-class hardware.
Independent community test on consumer/prosumer hardware (Ankk98, PR comments):
"No config beat vanilla (~45 t/s). Best geomean was ~0.81x... Even ~93-98%
accept only reached ~0.8-0.9x." Plus greedy-decode correctness mismatches.
A separate contributor (YanissAmz) found a live silent-failure bug days before
we read this: a RoPE-type mismatch that doesn't crash, just quietly collapses
acceptance from ~5-6 tokens to ~2 while still looking like normal output --
easy to miss, would have skewed any benchmark run against it.

Decision: not worth maintaining a 3rd/4th llama.cpp checkout for a technique
whose best independent non-datacenter result is slower than doing nothing,
with an active silent-correctness bug in the shared code path. MTP (already
merged, already measured on our own hardware: 78-82% acceptance, +17-26%
real speedup) is the better bet. Deleted the dspark gguf, reverted
llama-serve-bonsai.sh to plain (no speculative decoding).



## 2026-09-17 rebuild: Qwen3.8-Flash-Next (qwen4exp), build 11011

The July build (b10016) cannot load Qwen3.8-Flash-Next at all. The arch is
`qwen4exp` ("A Preview of the Qwen4 Architecture") and only landed upstream in
ggml-org/llama.cpp#27742, weeks after that checkout. Pulled master 0cea36222 ->
aa39d7a3e (902 commits) and rebuilt from scratch.

  version: 11011 (aa39d7a3e), built with GNU 16.2.1
  full CUDA build: 7m25s wall on 20 threads
  old binaries kept at ../llama.cpp-bin-backup-b10016 (delete once happy)

/usr/local/bin/llama-server still symlinks into build/bin, so it picked this up
with no change needed.

### Build flags and why

  cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES=89-real \
    -DGGML_NATIVE=ON \
    -DGGML_CUDA_FA_QUANTS=all \
    -DGGML_CUDA_GRAPHS=ON \
    -DGGML_CUDA_NCCL=OFF \
    -DGGML_BLAS=OFF \
    -DGGML_CCACHE=ON \
    -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF

Changes vs the July configuration:
  89-real (was 89)      -- "-real" emits SASS only, no PTX. We have exactly one
                           GPU (Ada, sm_89) and never need JIT for a future
                           arch, so the PTX is dead weight in every fatbin.
  GGML_CUDA_NCCL=OFF    -- was ON. NCCL is multi-GPU collectives; single 4070,
                           pure overhead + an extra link dependency.
  GGML_CUDA_FA_QUANTS=all -- same 49 K/V combos as before, but
                           GGML_CUDA_FA_ALL_QUANTS is now deprecated and warns.
                           Kept "all" because we do test mixed -ctk/-ctv.
  GGML_BLAS=OFF         -- explicit. CUDA does prompt processing; a CPU BLAS
                           only adds a dependency.

Toolchain note: system gcc is 16.2.1 but CUDA 13.3's cmake auto-selects the
installed gcc15 (15.3.0) as the nvcc host compiler. That is the supported combo
and it just works -- no need to force -DCMAKE_CUDA_HOST_COMPILER.

### What the model actually is (read from the GGUF, not the model card)

  48 blocks, n_embd 2560, native ctx 262144, 125B total / 6B active
  layout: 12 x (3 x Gated-DeltaNet -> MoE) + 1 x (Qwen Sparse Attention -> MoE)
  full_attention_interval=4, so only 12 of 48 layers hold a real KV cache
  MoE 512 experts, 10 routed + 1 shared, expert FFN 640
  QSA 24 Q heads / 2 KV, head_dim 256; indexer 4 heads x 128, top_k 2048
  PLE 3-gram, 16 heads x ~20M rows x 160 dims
  hyper-connections (count 4, low_rank 320) -- the blk.N.hc_* tensors

Where the 93.7GB of UD-IQ4_XS actually goes:
  *_exps (512 experts x 48 layers)      ~57 GB   IQ3_S gate/up, IQ4_NL down
  per_layer_token_embd (the n-gram LUT) ~28.8 GB IQ4_NL [160, 320001536]
  output.weight Q6_K                     521 MB
  token_embd.weight Q8_0                 676 MB
  everything else (attn/ssm/hc/shexp)    ~3.4 GB  (~71 MB per layer)

### The thing that makes this runnable on 8GB/125GB at all

per_layer_token_embd is 28.8GB but llama.cpp creates it with TENSOR_READ_LAZY
("read rows on demand instead of loading whole tensor; requires mmap",
llama-model-loader.h). It is paged in from SSD per lookup, so only hot rows ever
go resident. Resident RAM is therefore ~57GB of experts + ~5GB, not 93.7GB --
which is why this fits in 125GB with room to spare.

Two consequences, both load-bearing:
  - do NOT pass --no-mmap. It turns the lazy LUT into a real 28.8GB read.
  - do NOT pass --mlock. Same, but worse.
Unsloth's own docs say the same thing in passing ("offload the PLE / Ngram layer
to SSD and use mmap").

### VRAM budget on the 4070 Laptop (7661 MiB free)

  non-expert weights on GPU        ~3.4 GB
  output.weight                     0.52 GB
  token_embd -> pushed to CPU       (-0.68 GB, it is a GET_ROWS lookup;
                                     safe here because output.weight exists
                                     separately and is not tied)
  leaves ~3.0-3.2 GB for KV + compute

KV cost per token: 12 QSA layers x 2 kv heads x 256 x (K+V) @ q8_0 ~= 13 KB,
plus the sparse-attention indexer cache (K only, upstream dropped its V:
"memory : avoid allocating V cache for indexer", #28330) ~= 12 KB.
So ~25 KB/token => ~64k comfortable, ~128k plausible, 262144 native will not fit.
Starting the script at 65536 and pushing up once the download lands.

### Launcher

  /home/sum/Downloads/AI-Runtime/llama-serve-qwen38-flash-next.sh

Same env-var style as the others. Note the sampling defaults are NOT the ones we
use for Qwen3.5/3.6: this model wants temp 1.0 / top-p 0.95 / top-k 20 /
min-p 0.0 for thinking mode (temp 0.7 / top-p 0.80 / presence 1.5 for
non-thinking). Reasoning depth is a chat-template kwarg, not a CLI flag:
  --chat-template-kwargs '{"reasoning_effort":"medium"}'   (xhigh|medium|low|none)

### MTP: needs a second checkout, ggml-org/llama.cpp#28243 is still OPEN

Mainline runs the model but ignores the MTP head entirely -- there is no MTP
graph for qwen4exp upstream, and no cross-model tensor borrowing, so passing -md
to a stock build silently does nothing. Unsloth's MTP README says this outright.

PR #28243 ("models: Qwen3.8-Flash-Next MTP", danielhanchen:qwen4exp/mtp) adds it.
Checked out as a git worktree off the canonical repo rather than a 3rd clone:

  git worktree add ../llama.cpp-mtp pr-28243-mtp     # refs/pull/28243/head
  /home/sum/Downloads/AI-Runtime/llama.cpp-mtp

The PR branches off a master ~220 commits back; built as-is rather than rebasing
someone else's branch. Note this costs a full rebuild -- ccache hit rate was
~0% because the differing base changes the headers every TU sees.

The head we have is mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf (1.9GB). Unsloth
recommends shared-Q8_0 (2.8GB) as fastest, but on 8GB VRAM the smaller one is
the right call -- they quote it at only ~2 points less acceptance.
"shared-" = borrows token_embd + output.weight from the target model
(qwen4exp.nextn_shared_target_tensors=True), saving ~1.3GB over the
self-contained variants.

Structure of the head: one extra block, blk.48 (block_count 49,
nextn_predict_layers 1) -- and it has its own full 512-expert MoE. ~1.8GB of its
1.9GB is *_exps, which means --cpu-moe sends almost all of it to CPU RAM and it
costs only ~100MB of VRAM. Drafting is then one layer's worth of expert compute
against 48 layers for the target, so it should stay cheap even CPU-side.
Caveat to check when benchmarking: the shared head borrows token_embd, which the
launcher currently pushes to CPU -- may need to leave token_embd on GPU when
running MTP, which costs 0.68GB of the KV budget.

TODO once the 93.7GB download finishes (~3.4h at the 6 MiB/s it is pulling):
  - confirm load + memory breakdown at -c 65536, then try 131072
  - benchmark mainline vs the #28243 worktree, check draft_n_accepted ratio
  - decide whether MTP's VRAM cost is worth it at this context size

### MTP worktree build result

  /home/sum/Downloads/AI-Runtime/llama.cpp-mtp
  version: 10802 (d1a92352c), 7m47s, same cmake flags as the main build
  --spec-type accepts: draft-mtp (plus draft-eagle3/dflash/dspark, ngram-*)

  /home/sum/Downloads/AI-Runtime/llama-serve-qwen38-flash-next-mtp.sh
  -> calls the worktree binary directly, NOT /usr/local/bin/llama-server

Both launchers dry-run clean against the partial download: args parse, --fit
engages, and they fail only at the missing shard 2. Nothing left to verify until
the download completes.

### Gotchas found while wiring these up (all cost real debugging time)

1. `--cpu-moe` does NOT apply to the draft model. common_params_speculative has
   its own tensor_buft_overrides vector, separate from common_params. You need
   `--spec-draft-cpu-moe` / `-cmoed` (env LLAMA_ARG_SPEC_DRAFT_CPU_MOE) as well,
   or the MTP head's ~1.8GB of blk.48.ffn_*_exps lands on the 8GB card.
   Same story for -otd / --spec-draft-override-tensor vs -ot.

2. Env var names are not guessable from the flag names. The ones used here:
     -ot   -> LLAMA_ARG_OVERRIDE_TENSOR     (NOT ..._TENSOR_OVERRIDES)
     -md   -> LLAMA_ARG_SPEC_DRAFT_MODEL    (NOT LLAMA_ARG_MODEL_DRAFT)
     -cmoed-> LLAMA_ARG_SPEC_DRAFT_CPU_MOE
   `--spec-draft-n-max` has no env var, pass it on the command line.

3. `-no-cnv` is gone from llama-cli; single-turn is `-st` now.

4. A stock mainline build given `-md <mtp head>` does not warn, does not error,
   and produces no speedup -- it just ignores it. If you ever benchmark MTP and
   see exactly 1.00x, check which binary you ran before anything else.

## 2026-09-18: Unsloth Studio + Qwen3.8-Flash-Next (UD-IQ4_XS)

See llama-qwen38-flash-next-unsloth.md for the setup. Short measured numbers,
patched b11007-mix, 8192 ctx, --cpu-moe, q8_0 KV, 10 threads, balanced:

  mmap lazy:        RSS ~52 GB file-backed, warm TG 8.62 t/s
  full RAM:         --load-mode none --lazy-mode off, RSS ~87.5 GB, TG 8.06 t/s
  MTP n_max=3 digits: TG 12.93 t/s, draft accept 0.982 (112/114)
  MTP n_max=3 prose:  TG  6.51 t/s, draft accept 0.307 (85/277)

Stock mix aborted MTP in build_hc_mix (ggml_can_repeat). One-line fix:
layer.nextn.hc_head_norm { n_embd, hc } | TENSOR_ALLOW_RESHAPE.
Rebuild: ~/.unsloth/llama.cpp/build-hc-fix, copied to build/bin.
Confirmed on unslothai/unsloth#11143.

Do not use llama-bench-ctx-sweep.sh on this model (respawns 90 GB per size).
Occupied probe script: llama-bench-qwen38-unsloth-occupied.sh
  (16384 ctx, CHARS 2000/7000/14000/28000, 128 gen, MTP on).

### Occupied-context Group C — 2026-09-18T00:49 → 00:55 +10

  llama-bench-qwen38-unsloth-occupied.sh
  reload once to 16384 + MTP n_max=3, --cpu-moe --spec-draft-cpu-moe,
  q8_0 KV, --load-mode none --lazy-mode off, --no-mmproj
  llama-server --port 60287, /props n_ctx=16384 (not auto-reduced)
  VRAM at load 6696 MiB / 1142 free; after last probe 7454 MiB / 384 free
  RSS ~97 GiB used / 27 GiB available. profile=unknown (powerprofilesctl empty)
  cache_prompt: false, n_predict=128, temp 0, ignore_eos
  corpus: llama.cpp/src, 65 files

  ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
      574 |     90.8 |   11.84 |      6.3s |    17.1s | 87/119 (73%)
     2029 |    114.1 |    9.60 |     17.8s |    31.0s | 85/124 (69%)
     3910 |    108.4 |   10.76 |     36.1s |    47.9s | 84/127 (66%)
     8389 |    117.3 |   13.04 |     71.5s |    81.3s | 91/106 (86%)

  Short-prompt PP ~12 t/s was not the occupied number. Occupied PP is ~100 t/s
  (~2× slower than Qwen3.6-35B ~230, not 15–20×). TG with MTP did not drop at
  8k occupied; the 8k row is the fastest because accept peaked.
  Raw: llama-bench-qwen38-occupied-20260918.log

### Occupied-context ~16k — 2026-09-18T01:19 → 01:21 +10

  SKIP_RELOAD=1 CTX=16384 CHARS=54000 NPREDICT=128
  llama-bench-qwen38-unsloth-occupied.sh
  live llama-server --port 60287, /props n_ctx=16384, --spec-type draft-mtp
  VRAM 7454 MiB / 384 free before and after. RSS ~97 GiB used / 27 GiB available.
  profile=unknown. GPU 62 °C, P8 idle after the run, no HW slowdown.
  cache_prompt: false, temp 0, ignore_eos, corpus llama.cpp/src

  ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
    15456 |    121.4 |   11.21 |    127.3s |   138.6s | 86/120 (72%)

  CHARS=54000 (not 56000) so prompt + 128 gen fits in 16384. ~15.5k occupied,
  not a full 16k window. TG −14% vs 8k peak (13.04), still above the 2k row.
  VRAM did not grow vs the 8k point. Raw: llama-bench-qwen38-occupied-16k.log

### Occupied-context ~32k — 2026-09-18T01:22 → 01:31 +10

  Reload CTX=32768 MTP n_max=3 (90 GB). llama-server --port 50289,
  /props n_ctx=32768 (not auto-reduced), --spec-type draft-mtp
  VRAM at load 6998 MiB / 840 free; after probe 7078 MiB / 760 free.
  RSS ~97 GiB used / 27 GiB available. profile=unknown.

  First probe CHARS=112000 FAILED HTTP 400:
    request (33178 tokens) exceeds the available context size (32768 tokens)
    log: llama-bench-qwen38-occupied-32k.log

  Retry SKIP_RELOAD=1 CHARS=110000 NPREDICT=128
  log: llama-bench-qwen38-occupied-32k-retry.log

  ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
    32702 |    116.7 |    7.62 |    280.3s |   288.8s | 35/88 (40%)

  Prompt 32702 + n_predict 128 does not fit; generation clipped to ~66 tokens
  (32768-32702). TG 7.62 is still the first real occupied drop (−42% vs 8k
  peak 13.04, −32% vs 15.5k 11.21). Draft accept 40% (was 72% at 15.5k).

### Occupied-context ~64k — 2026-09-18T01:34 → 01:47 +10

  Reload CTX=65536 MTP n_max=3 (90 GB). llama-server --port 44477,
  /props n_ctx=65536 (not auto-reduced), --spec-type draft-mtp
  VRAM at load 7602 MiB / 236 free; after probe 7682 MiB / 156 free.
  RSS ~98 GiB used / 27 GiB available. profile=unknown.
  CHARS=220000 tokenize=64099, +128 gen = 64227 < 65536 (no trim).
  llama-bench-occupied-ctx.py now tokenizes and trims to n_ctx-n_predict.

  ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
    64099 |    105.8 |    7.86 |    606.0s |   622.2s | 83/130 (64%)

  Full 128 gen (not clipped). TG 7.86 ≈ the clipped 32k 7.62, −40% vs 8k peak.
  Draft accept recovered to 64% vs 40% on the clipped 32k row.
  Raw: llama-bench-qwen38-occupied-64k.log

### Occupied 16k/32k at 65536 alloc (unclipped) — 2026-09-18T01:49 → 01:56 +10

  SKIP_RELOAD=1 CTX=65536 CHARS=54000,110000 NPREDICT=128
  llama-server --port 44477, n_ctx=65536, MTP n_max=3
  VRAM 7682–7684 MiB / 154–156 free. Full 128 gen (fit_budget 65408).

  ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
    15456 |    119.8 |    9.70 |    129.0s |   143.1s | 85/126 (67%)
    32702 |    115.6 |    8.00 |    282.9s |   298.9s | 75/153 (49%)

  15.5k @ 65536 alloc is 9.70 vs 11.21 @ 16384 alloc (−13% from reserving 64k).
  32.7k unclipped 8.00 / 49% accept vs clipped 7.62 / 40% — the drop is real,
  the 40% accept was the clip. Raw: llama-bench-qwen38-occupied-64k-alloc-clean.log

### Real-world staking prompt — first try FAILED 2026-09-18T01:57 +10

  POST /v1/chat/completions max_tokens=6144 on the 65536+MTP server after the
  32.7k occupied fill. llama-server CUDA OOM allocating 1705.62 MiB
  (ggml_gallocr_reserve_n_impl), connection dropped, process died.
  VRAM was 7684 MiB / 154 free. Occupied /completion with n_predict=128 at
  the same n_ctx had worked. Retry: reload 65536, native /completion,
  n_predict=2048, erase slot 0 first.

  Second try (CHARS=2000 / ~574 tok as the FIRST request after a fresh 65536
  load) also RemoteDisconnected; llama-server dead again. VRAM at load 7602
  MiB / 236 free. Short prompts at 64k+MTP OOM the decode graph; long occupied
  prefills (15k/32k/64k) worked. Next: one /completion whose prompt is ~15k
  tokens of llama.cpp/src plus the staking task, n_predict=1024.

### Real-world staking @ 65536 — 2026-09-18T02:12 → 02:20 +10  SUCCESS

  Prompt: "write a Solidity staking contract and a test suite in typescript"
  65536 alloc, MTP n_max=3, native /completion (not :8888).
  llama-server --port 33057, n_ctx=65536 verified.
  Short prompts at this alloc CUDA-OOM (~1.7 GiB graph) and kill the process.
  Working shape: ~15k tokens of llama.cpp/src + Qwen chat wrapper + task.

  Pass 1 (empty EOS): raw C++ dump + "Task: ..." → predicted_n=1, stop=eos, 0 chars.
  Pass 2 chat-shaped, n_predict=1024, cache_prompt=false:
    prompt_n=15496  PP=123.1 t/s  TG=10.52 t/s  draft 715/921 (78%)
    wall 223.6s (125.9s prefill + 97.2s gen). stop=limit.
    Solidity started; thinking ate the 1024-token budget.
    log: llama-qwen38-realworld-staking-retry.log

  Pass 3 continuation, n_predict=2048, cache_prompt=true:
    cache_n=16519  prompt_n=1  TG=11.35 t/s  draft 1485/1685 (88%)
    wall 180.8s. stop=limit.
    Combined output 12316 chars: complete StakingContract.sol (OZ Ownable +
    ReentrancyGuard, stake/unstake/claimRewards) + Hardhat/ethers tests
    (Deployment + Staking done; Unstaking cut mid-assert).
    log: llama-qwen38-realworld-staking-cont.log
    artifact: llama-qwen38-realworld-staking-output.md

  Code-shaped generation at 15.5k occupied / 64k alloc is **10.5–11.4 t/s**
  with 78–88% MTP accept — closer to the 8k occupied peak than to C++-fill
  32k (8.00 t/s, 49% accept). VRAM 7646 → 7682 MiB / 156 free.

  llama-bench-occupied-ctx.py now tokenizes and trims so prompt+n_predict
  fits n_ctx (the 32k HTTP 400 / clipped-gen class).

## 2026-09-18 evening: official Unsloth mix-pr220 MTP pin (PR #220)

unslothai/llama.cpp#220 merged. Pin #144 moved f40f64a → ca1426903
(hc_head_norm {n_embd,hc} + shared-head fit borrow). Published
b11027-mix-3e83366 still lists the old pin. Local mix: ggml-org b11027 +
current pr-set.json, house cmake (sm_89-real, GGML_NATIVE=ON).

  source: ~/.unsloth/llama.cpp-mix-pr220
  llama-server --version: 0.4.1-dev (build 11166, commit 10921f3f1)
  installed over ~/.unsloth/llama.cpp/build/bin (RPATH mix-pr220/build/bin)
  previous live bin: ~/.unsloth/llama.cpp/build/bin-pre-pr220
  scripts: llama-unsloth-mix-pr220-build.sh / llama-unsloth-mix-pr220-install.sh
  bench: llama-qwen38-pr220-bench.sh
  log: llama-bench-qwen38-pr220-20260918-214747.log
  profile=unknown (powerprofilesctl empty)

  MTP loaded: --model-draft shared-Q4_K_M --spec-type draft-mtp --spec-draft-n-max 3
  n_ctx verified 8192 then 16384 (not auto-reduced)
  VRAM 6546 MiB at 8192 MTP; 6696 empty / 7454 after occupied at 16384
  RSS ~105 GiB used / 19 GiB available (full RAM none + lazy off)

  Group A 8192 MTP (llama-qwen38-group-a-mtp.py; NOT the morning prompts):
    digits  PP 18.9  TG 11.37  draft 90/111 (81%)  pred 128
    prose   PP 15.3  TG  9.31  draft 171/250 (68%) pred 256

  Occupied Group C 16384, same CHARS as morning (2000,7000,14000,28000):
    ctx_tok |   PP t/s |  TG t/s |   prefill |     wall | draft accept
        574 |     88.9 |    8.94 |      6.5s |    20.7s | 87/119 (73%)
       2029 |    110.5 |   10.58 |     18.4s |    30.4s | 85/124 (69%)
       3910 |    105.9 |    9.43 |     36.9s |    50.4s | 82/132 (62%)
       8389 |    114.9 |    9.25 |     73.0s |    86.8s | 84/126 (67%)

  vs morning patched b11007-mix occupied: PP matched (~89–115 vs ~91–117).
  TG flatter (8.9–10.6 vs 9.6–13.0); 8k peak 13.04 t/s / 86% accept did not
  repeat. Draft counts at 574 and 2029 were identical (87/119, 85/124).

## 2026-09-18/19: Ternary-Bonsai-2-27B on Prism llama.cpp

Fork: github.com/PrismML-Eng/llama.cpp branch prism
worktree: llama.cpp-prism  1a07bfa5f (build 10706)
build: llama-prism-build.sh  (~6.8 min, house CUDA flags, sm_89-real)
models:
  /home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf  (5.53 GiB)
  /home/sum/.cache/lm-studio/models/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PQ2_0.gguf   (6.70 GiB)
harness: llama-bench-ternary-bonsai2.sh
log: llama-bench-ternary-bonsai2.log
# done 2026-09-19T00:20:12+10:00
profile=unknown

llama-cli without --single-turn is a chat REPL; the first smoke hung on `>`
with the model resident and GPU idle. Skipped after that; Group A is the
server smoke.

llama-bench -ngl 99 -fa on -ctk q8_0 -ctv q8_0 -t 10 -p 512 -n 128 -r 3:
  PTQ1_0  pp512 268.30 ± 0.97   tg128 19.89 ± 0.09
  PQ2_0   pp512 421.71 ± 1.72   tg128 18.71 ± 0.08

Load ceiling (--fit off, --no-mmproj, -ngl 99):
  PTQ1_0 q8_0  4096 6048 MiB / 8192 6188 / 16384 6488 / 32768 7112 ; 65536 OOM rs cache
  PTQ1_0 q4_0  32768 6600 / 65536 7336 ; 131072 OOM KV 2304 MiB
  PQ2_0  q8_0  2048 7120 / 4096 7192 / 8192 7332 / 16384 7632 (206 MiB free)
  PQ2_0  q4_0  8192 7204 / 16384 7376 / 32768 7744 (94 MiB free)
  --fit on q8_0: PTQ1_0 n_ctx 21760 (6694 MiB); PQ2_0 n_ctx 4096 (7192 MiB)
  --fit under-sizes vs measured max; always read /props.

Group A short /completion (temp 0, ignore_eos, cache_prompt false):
  PTQ1_0 empty-window TG 19.5–20.7 t/s from 4k to 64k
  PQ2_0  empty-window TG 18.0–18.8 t/s from 2k to 32k

Occupied (llama-bench-occupied-ctx.py, llama.cpp-prism/src, n_predict 128):
  PTQ1_0  8k q8_0   574/3999/8064 tok   PP 251.5/264.3/260.9  TG 19.87/18.95/18.14
  PTQ1_0 32k q8_0   574/15682/32640      PP 247.8/251.0/231.3  TG 19.62/16.47/13.52
  PTQ1_0 64k q4_0   574/33197/65408      PP 237.4/231.1/201.2  TG 19.36/13.17/10.02
  PQ2_0   8k q8_0   574/3999/8064        PP 385.1/404.8/396.2  TG 18.47/17.63/16.65
  PQ2_0  16k q8_0   574/8521/15682       PP 377.6/393.9/368.1  TG 18.50/16.14/14.92
  PQ2_0  32k q4_0   574/15682/32640      PP 380.0/372.9/328.0  TG 18.63/15.33/12.74

Vision mmproj not loaded. DSpark not tested. Flash-Next Unsloth server was
SIGTERM'd for GPU; Studio left running on :8888.

## 2026-09-27: GSQ-RCO Q2_0 evaluation, part 1 — engine choice + UD-IQ4_XS baseline

Handover: handover-gsq-q2_0-evaluation.md. Download of
ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF Q2_0 (66.42 GB) running in the
background (log gsq-q2_0-download.log, ~5.6 MB/s).

MTP sidecar risk (§5), checked on paper from GGUF headers:
  mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf borrows token_embd / output /
  output_norm from the target. Loader checks shape only, not type.
  UD-IQ4_XS: token_embd [2560,248320] Q8_0, output Q6_K
  GSQ Q2_0 : token_embd [2560,248320] Q3_K, output Q5_K   -> shapes equal, attaches.
  Expect slightly lower draft acceptance (lower-precision LM head on GSQ).

Engine update tried: Unsloth mix recipe on ggml-org b11160 + current pr-set.json
+ #26348 (x86 AVX-VNNI Q2_0 vec_dot) + local kernel patch
  llama-unsloth-mix-b11160-build.sh -> build 11305, commit e1204080a
  llama-unsloth-mix-b11160-install.sh (backup of the 11166 bins: bin-pre-b11160)

Occupied 16384 + MTP n_max=3, UD-IQ4_XS, balanced, TG t/s at 574/2029/3910/8389 tok:
  mix-pr220 11166 r1              11.29  11.12  11.10   9.82
  mix-pr220 11166 r2              10.59   9.95   9.74  10.64
  b11160-mix 11305 fusion on r1   10.38   3.91   9.51  11.66   (draft 19/318 at 2k)
  b11160-mix 11305 fusion on r2   10.67   5.84   9.52   9.66
  b11160-mix 11305 FUSION OFF     11.67  10.99  10.49   9.10   (GGML_CUDA_DISABLE_FUSION=1)
  PP ~93–116 on all engines. (11166 A/B bench logs say "engine b11160" in the
  header because BUILD_INFO was not swapped; /props confirmed b11166-10921f3f1.)

Finding: on qwen4exp the newer engine's CUDA fusion changes greedy output
(blank-line loop at the 2k probe, MTP accept collapses to 6–26%).
GGML_CUDA_DISABLE_FUSION=1 restores it. Not the sparse-FA change (#28770,
3cf03257f): reverting it to dense FA did not help. Suspect 1a679828f
"cuda: top-k MoE should always fire". With fusion off, no speed gain over 11166.
Decision: keep the 11166 baseline engine; only add the Q2_0 CPU kernel.

Q2_0 x86 CPU kernel. Upstream Q2_0 vec_dot is scalar generic on x86 until
#26348 (open). Local patch llama-q2_0-avxvnni-transposed.patch on top of it
(in-lane transposed 2-bit unpack + DPBUSD). test-quantize-fns: q2_0 dot err
0.140698, 0 failures. Cycles per 32 values (13700H):
                    in cache   MEM-size
  #26348 as-is        5.86       7.60
  local patch         2.90       5.66
  IQ4_XS (ref)          —        6.10

Chosen engine: llama-unsloth-mix-pr220-q2_0-build.sh
  ~/.unsloth/llama.cpp-mix-pr220-q2_0, build 11170, commit a2fa025fb
  = mix-pr220 10921f3f1 + #26348@915ffcfba + local patch
  (diff vs baseline: arch-fallback.h -2, arch/x86/quants.c +61 only)
  installed with SRC=…/build/bin SRC_TREE=… ./llama-unsloth-mix-pr220-install.sh
  BUILD_INFO: b11027-mix-pr220-ca1426903+q2_0-avxvnni

UD-IQ4_XS on 11170 (same engine the Q2_0 run uses):
  Occupied 16384 + MTP (llama-bench-qwen38-udiq4xs-b11170-occupied-*.log):
    ctx_tok |   PP t/s |  TG t/s | draft
        574 |     93.4 |   11.62 | 87/119
       2029 |    113.6 |   10.87 | 85/124
       3910 |    108.3 |   10.20 | 83/130
       8389 |    116.7 |    9.83 | 82/134
    VRAM 6696 MiB
  Perplexity, wikitext-2 test, -c 512 --chunks 40, --cpu-moe -ngl 999 -fa on
  q8_0 KV -t 10 (llama-ppl-qwen38-udiq4xs-a2fa025fb-c512x40.log):
    PPL = 2.7441 +/- 0.05357   (KLD base saved: eval-data/kld-base-udiq4xs-c512x40.bin)
  House Solidity prompt, chat, temp 0, max_tokens 8192
  (llama-qwen38-quality-probe.py -> llama-qwen38-quality-udiq4xs-b11170.md):
    3853 tok, TG 9.57 t/s, draft 2620/3699 (71%), finish stop.
    Answer correct: mapping + bool, onlyOwner, custom errors, events, no array.
    At 3072 tokens the default xhigh reasoning ran out before the answer.

## 2026-09-27: GSQ-RCO Q2_0 evaluation, part 2 — Q2_0 vs UD-IQ4_XS, same engine

Engine for both: mix-pr220-q2_0, build 11170 / a2fa025fb
(b11027-mix-pr220-ca1426903+q2_0-avxvnni). Profile balanced. 16384 alloc,
MTP n_max=3 + --spec-draft-cpu-moe, --cpu-moe, q8_0 KV, -t 10, full RAM.

Download: 2:56:11, 66,423,878,624 bytes. sha256 shard1 69820c02ec7d0b45…,
shard2 316b46f3a2dbd68c… — both match. Flattened into
~/.cache/lm-studio/models/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/.

MTP attach. First load had NO drafter: argv had --spec-default, no
--model-draft. Studio (llama_cpp.py _pick_mtp) only takes an mtp-*.gguf from
the model's own directory. Fix:
  ln -s …/unsloth/Qwen3.8-Flash-Next-GGUF/mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf \
        …/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/
Second load: --model-draft <sidecar> --spec-type draft-mtp, log
"common_speculative_init_result: loading draft model …". Shared head borrows
Q3_K token_embd / Q5_K output without complaint.
Load 26–33 s (warm page cache). /props n_ctx 16384, build b11170-a2fa025fb.
VRAM 4790 MiB (IQ4_XS: 6696). RSS 61 GiB (IQ4_XS: ~87 GiB).

Occupied 16384 + MTP (llama-bench-qwen38-q2_0-b11170-occupied-20260927-*-r1/r2.log):
  Q2_0 r1  ctx_tok |   PP t/s |  TG t/s | draft
               574 |    144.3 |   20.22 | 80/138
              2029 |    177.1 |   22.15 | 83/128
              3910 |    168.5 |   18.01 | 75/155
              8389 |    180.2 |   21.23 | 84/124
  Q2_0 r2      574 |    158.7 |   20.05 | 81/135
              2029 |    176.8 |   20.93 | 83/128
              3910 |    168.5 |   19.01 | 78/146
              8389 |    180.1 |   21.19 | 85/126
  UD-IQ4_XS same engine (part 1): TG 11.62 / 10.87 / 10.20 / 9.83, PP 93–117
  -> TG ~1.9–2.2x, PP ~1.55x. 8k TG 21.2 vs 9.83. Prefill of 8389 tok 46.6 s vs 71.9 s.

Perplexity wikitext-2 test, -c 512 --chunks 40, same flags
(llama-ppl-qwen38-q2_0-a2fa025fb-c512x40.log):
  Q2_0       PPL = 3.3586 +/- 0.06966
  UD-IQ4_XS  PPL = 2.7441 +/- 0.05357
KLD of Q2_0 vs UD-IQ4_XS logits (NOT vs bf16)
(llama-kld-qwen38-q2_0-vs-udiq4xs-a2fa025fb-c512x40.log):
  PPL ratio 1.2245 +/- 0.0156   Mean KLD 0.4981   Median KLD 0.1133
  99% KLD 4.763   Same top p 77.98 +/- 0.41 %   RMS dp 24.80 %

House Solidity prompt, /v1/chat/completions, max_tokens 8192
(llama-qwen38-quality-probe.py):
  temp 0 (greedy):
    UD-IQ4_XS  3853 tok, 9.57 t/s, draft 2620/3699, stop, answer correct
    Q2_0       8192 tok, 20.02 t/s, draft 5592/7794, LENGTH — wrote a correct
               contract inside reasoning, then looped doubting whether
               bytes32("Alice") compiles; no final answer.
  temp 1.0, min_p 0, seeds 1/2/3 (model's recommended sampling):
    Q2_0       15.75 / 15.24 / 15.47 t/s   6208 / 8079 / 4553 tok   stop / stop / stop
               3/3 correct: mapping(address=>bytes32) + bool (or reverse map),
               onlyOwner, zero-address + empty-name checks, events, no array.
    UD-IQ4_XS   7.60 /  7.66 /  7.19 t/s   4868 / 8192 / 8192 tok   stop / LENGTH / LENGTH
               seed 1, 2 correct (struct Entry mapping); seed 3 ran out after a
               2-line answer. Draft accept at temp 1: Q2_0 48–49%, IQ4_XS 45–51%.
  Files: llama-qwen38-quality-{udiq4xs,q2_0}-b11170[-t1-sN].md

Verdict (handover §9, 8k + MTP): Q2_0 TG 21.2 t/s >= 13 -> Q2_0 WINS on speed.
Quality: measurable on wikitext (PPL +22% vs IQ4_XS, top-1 agreement 78%),
not visible on the house coding prompt at the recommended sampling. Greedy
decoding looped once on Q2_0; do not use temp 0 with it.
Launcher default switched to Q2_0 (QUANT=iq4xs restores UD-IQ4_XS).

# ---------------------------------------------------------------------------
# 2026-10-26  Unsloth 2026.10.5 engine update vs restored 11170 (Qwen3.8)
# Studio replaced ~/.unsloth/llama.cpp with stock b11541-mix-2500203 on 2026-10-14.
# Studio now passes --ubatch-size 2048 (Sept argv: none -> 512).
# 16384 alloc, MTP n_max=3, --cpu-moe, q8_0 KV, 10 threads, profile balanced.
# Probe: llama-bench-qwen38-unsloth-occupied.sh (now sends --api-key-file bearer).
#
# stock b11541, Q2_0, ub 2048       PP / TG t/s
#   r1  574 142.8/3.64  2029 317.3/4.10  3910 332.2/3.32  8389 309.2/3.26
#   r2  574 152.3/3.34  2029 301.1/3.76  3910 314.3/3.06  8389 313.8/3.52
#   -> no x86 Q2_0 vec_dot (generic only). VRAM 6434 MiB.
# stock b11541, UD-IQ4_XS, ub 2048: cudaMalloc 1362.50 MiB OOM creating
#   context; Studio retried and came up WITHOUT --spec-type. Discarded.
#
# restored 11170 (a2fa025fb), Q2_0, ub 2048
#   r1  574 165.2/20.86  2029 344.4/20.65  3910 336.1/20.44  8389 318.7/21.42
#   r2  574 180.4/19.88  2029 302.7/18.97  3910 296.0/18.01  8389 284.8/20.03
#   VRAM 5756 MiB idle. Load 45 s (GGUF in page cache).
# restored 11170, UD-IQ4_XS, --ubatch-size 1024 (fits with MTP, 7000 MiB)
#   r1   574 116.0/11.59  2029 168.9/11.16  3910 164.5/8.66  8389 125.9/6.86
#   r2   574  65.0/6.19   2029  89.1/7.77   3910  88.4/7.35  8389  93.8/6.73
#   r3   574  70.2/10.00  2029 101.9/10.47  3910  95.7/8.45  8389  97.3/9.65
#   r2/r3 thermally throttled: fans 5900 RPM, package 84 -> 99 C.
# Restore: mv build/bin -> build/bin-b11541-stock; cp -af
#   ~/.unsloth/llama.cpp-mix-pr220-q2_0/build/bin/. into build/bin; BUILD_INFO
#   rewritten (stock copy at BUILD_INFO-b11541-stock.txt).

# 2026-10-26  UD-IQ4_XS max-context sweep, engine 11170, llama-serve-qwen38-direct.sh
# (load + n_ctx check + short prompt): MTP on q8_0 ub512 -> 65536 ok (7602 MiB), 81920 OOM 185 MiB
#   MTP off q8_0 ub256 -ot token_embd=CPU -> 131072 ok (7774 MiB), 196608 OOM
#   MTP off q4_0 ub256 -> 196608 ok (7444 MiB), 262144 OOM 1124 MiB;  MTP on q4_0 ub512 131072 OOM 233 MiB
# 131072 breakdown (MTP off, ub512): model 4459 + KV/indexer/RS 1948 + compute 1200 = 7608 > 7547 free
# Full fill 131072 (MTP off, q8_0, ub256): 129263 tok, PP 34.9 t/s, prefill 3699.5 s, TG 2.01 t/s, no OOM.
#   log llama-bench-qwen38-udiq4xs-b11170-128k-fill-20261026-211954.log
# Decision: keep UD-IQ4_XS + MTP + q8_0 KV at 65536 max.

# 2026-10-27  Group H: GSQ IQ3_XXS + GSQ Coder vs Q2_0 (vs UD-IQ4_XS base), engine 11170
# downloads: shard 1 only, sha256 verified; shard 2 (316b46f3...) symlinked from Q2_0 dir
# PPL/KLD wikitext-2 c512x40, --cpu-moe -ngl 999 -fa on q8_0 KV -t 10, base eval-data/kld-base-udiq4xs-c512x40.bin
#   iq4xs PPL 2.7441 (base regenerated, identical to Sept)
#   gsq-iq3xxs PPL 2.8491  KLD 0.2926  top-1 84.20%  99% KLD 3.354
#   q2_0       PPL 3.3586  KLD 0.4981  top-1 77.98%  99% KLD 4.763
#   coder      PPL 5.1097  KLD 0.9380  top-1 68.76%  99% KLD 7.646   (pass 26.8 s vs q2_0 12.7 s)
# occupied probe 16384 MTP n3 ub2048, TG t/s 574/2029/3910/8389:
#   gsq-iq3xxs r1 10.76/12.67/9.48/11.35 PP@8k 261   r2 12.48/12.22/10.15/11.26 PP@8k 259
#   coder      r1  6.07/ 6.04/6.06/5.45  PP@8k 142   r2  5.75/ 6.13/5.19/5.33  PP@8k 131
# agent eval llama-agent-eval.py t1-t8 x seeds 1-3, 65536 ctx ub512 MTP n3 xhigh:
#   q2_0 24/24  avg 5.1 min/task  TG 10.75  accept 68%  bad calls 0
#   coder 24/24 avg 7.6 min/task  TG  8.38  accept 66%  bad calls 0
#   gsq-iq3xxs 24/24 avg 5.8 min/task TG 9.76 accept 67%  bad calls 0
