# llama.cpp compile guide — i7-13700H + RTX 4070 Laptop 8GB, Manjaro KDE

Everything needed to rebuild from scratch on this machine. Written 2026-09-17.

Start at [README.md](lab-notebook.md). Companion docs:
[llama-run-guide.md](llama-run-guide.md) (how to run models),
[llama-benchmark-and-tuning-guide.md](llama-benchmark-and-tuning-guide.md)
(how to measure), [llama-todo.md](llama-todo.md) (open work). Historical run
logs and per-model benchmark numbers live in `llama.cpp-test.sh`.

---

## 1. The machine

| | |
|---|---|
| CPU | Intel i7-13700H — 14 cores (6 P + 8 E), 20 threads, 5.0 GHz max |
| CPU ISA | AVX2, AVX-VNNI, F16C, BMI2, SHA-NI, VAES. **No AVX-512** (Raptor Lake) |
| Cache | L2 11.5 MiB, L3 24 MiB |
| GPU | RTX 4070 Laptop — Ada, **sm_89**, 8188 MiB total / **7836 MiB usable, ~7661 MiB free** |
| GPU power | 35 W cap on this chassis — matters for benchmark comparability |
| RAM | 125 GiB, no swap |
| Disk | `/home` on LUKS, 1.9 T total |
| OS | Manjaro, kernel 6.12.108-1-MANJARO |
| NVIDIA driver | 610.57.04, CUDA UMD 13.3 |
| CUDA toolkit | 13.3.73 at `/opt/cuda` |
| System gcc | 16.2.1 |
| nvcc host gcc | **15.3.0** (`gcc15` package) — chosen automatically, see §4 |

Note the GPU has only **7836 MiB usable**, not 8192. Budget against 7661 MiB
free, and remember KDE/kwin_wayland holds ~40 MiB.

## 2. Checkout layout

There is exactly **one canonical clone**, plus worktrees off it. This is
deliberate — a previous cleanup (2026-07-15) deleted several redundant
checkouts. Do not add a fresh clone; use `git worktree`.

```
/home/sum/Downloads/AI-Runtime/
├── llama.cpp/                      # canonical, branch master
├── llama.cpp-mtp/                  # git worktree, PR #28243 (MTP)
├── llama.cpp-prism/                # git worktree, remote prism/prism (Ternary-Bonsai-2)
├── llama.cpp-poolside/             # unrelated fork (branch: laguna)
└── llama.cpp-bin-backup-b10016/    # previous build's bin/, delete when happy
```

`llama.cpp-prism` is the PrismML-Eng fork (`git remote add prism` on the
canonical clone, then `git worktree add -b prism ../llama.cpp-prism prism/prism`).
House CUDA flags, script `llama-prism-build.sh`. **Do not** copy its
`llama-server` over `/usr/local/bin` — mainline cannot load `PTQ1_0`/`PQ2_0`.

`/usr/local/bin/llama-server` is a **root-owned symlink** to
`llama.cpp/build/bin/llama-server`. It therefore updates itself whenever you
rebuild in place — but it also means a failed in-place rebuild leaves you with
a dangling symlink. Back up `build/bin` before wiping `build/`.

## 3. The build command

```bash
cd /home/sum/Downloads/AI-Runtime/llama.cpp
git pull --ff-only

cp -a build/bin ../llama.cpp-bin-backup-$(git describe --tags)   # safety net
rm -rf build

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
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON

cmake --build build -j 20
```

**~7.5 minutes** wall on 20 threads from a cold ccache (1122 ninja edges,
~6800 s of CPU time at ~1570 % utilisation).

### Why each flag

| flag | reason |
|---|---|
| `CMAKE_CUDA_ARCHITECTURES=89-real` | `-real` emits SASS only and skips PTX. We have exactly one GPU and will never JIT for a future arch, so PTX is dead weight in every fatbin. Was plain `89` in the July build. |
| `GGML_NATIVE=ON` | `-march=native`. Gets AVX2 + AVX-VNNI on Raptor Lake. Do **not** hand-set `GGML_AVX512*` — this CPU has no AVX-512 and enabling it produces a binary that SIGILLs. |
| `GGML_CUDA_FA_QUANTS=all` | All 49 flash-attention K/V quant combinations. Costs build time; buys the freedom to test mixed `-ctk`/`-ctv`. The old spelling `GGML_CUDA_FA_ALL_QUANTS` still works but now prints a deprecation warning. |
| `GGML_CUDA_GRAPHS=ON` | Default on. Needed for the CUDA-graph MTP draft path (#28549). |
| `GGML_CUDA_NCCL=OFF` | Was **ON** in the July build, which was wrong — NCCL is multi-GPU collectives. Single 4070: pure overhead plus a link dependency. |
| `GGML_BLAS=OFF` | Explicit. CUDA handles prompt processing; a CPU BLAS only adds a dependency. |
| `GGML_CCACHE=ON` | ccache is installed; limit raised to 15 G (`ccache -M 15G`). |
| `LLAMA_BUILD_TESTS/EXAMPLES=OFF` | Cuts build time. Tools (server, cli, bench, quantize, gguf-split, mtmd) are under `LLAMA_BUILD_TOOLS`. |

### Flags deliberately **not** used

- **`GGML_LTO`** — marginal on ggml, whose hot loops are already hand-written
  SIMD intrinsics; adds long link times and occasionally breaks CUDA links.
- **`GGML_CUDA_F16`** — forces f16 intermediates in some kernels. Small,
  unreliable gain; precision risk. Left at default OFF.
- **`GGML_CUDA_FORCE_MMQ` / `FORCE_CUBLAS`** — the runtime heuristic picks
  better than a blanket override.
- **`LLAMA_CURL`** — now deprecated and ignored; it warns if you pass it.
- **`BUILD_SHARED_LIBS=OFF`** — Unsloth's docs use it. Not needed; the default
  shared build is fine and links faster.

## 4. Toolchain gotcha: gcc 16 vs CUDA 13.3

System gcc is **16.2.1**, which CUDA 13.3 does not officially support as an
nvcc host compiler. This resolves itself: `gcc15` (15.3.0) is installed, and
CUDA's cmake integration picks it automatically. Configure output confirms it:

```
-- CUDA compiler identification NVIDIA 13.3.73 host compiler GNU 15.3.0
```

So **do not** set `-DCMAKE_CUDA_HOST_COMPILER`. The C/C++ (non-CUDA) side still
builds with gcc 16.2.1, which is what `llama-server --version` reports:

```
version: 0.4.1-dev (build 11011, commit aa39d7a3e)
built with GNU 16.2.1 for Linux x86_64
```

If `gcc15` is ever uninstalled, nvcc will fail with an unsupported-GNU-version
error. Fix by reinstalling `gcc15`, not by forcing the host compiler to 16.

Sanity check nvcc independently of llama.cpp:

```bash
cat > /tmp/t.cu <<'EOF'
#include <cstdio>
__global__ void k(){}
int main(){ k<<<1,1>>>(); cudaDeviceSynchronize(); printf("cuda ok\n"); return 0; }
EOF
/opt/cuda/bin/nvcc -arch=sm_89 -o /tmp/t /tmp/t.cu && /tmp/t
```

## 5. Post-build verification

```bash
cd /home/sum/Downloads/AI-Runtime/llama.cpp

./build/bin/llama-server --version          # expect build number + commit
./build/bin/llama-server --list-devices     # expect CUDA0 with ~7661 MiB free
llama-server --version                      # confirms /usr/local/bin symlink

# arch actually compiled in?
strings build/bin/libllama-server-impl.so | grep -x qwen4exp

# end-to-end, small fully-GPU model
./build/bin/llama-cli \
  -m /home/sum/.cache/lm-studio/models/prism-ml/Bonsai-27B-gguf/Bonsai-27B-Q1_0.gguf \
  -ngl 999 -fa on -ctk q8_0 -ctv q8_0 -c 4096 -t 6 -n 48 --no-warmup -st \
  -p "Reply with exactly: build smoke test passed."
```

Bonsai reference: **~26 t/s** idle, **21.2 t/s** measured while a second build
was saturating all 20 threads. Use the idle figure for comparison.

## 6. Building a pull request as a worktree

For unmerged upstream work, add a worktree rather than a second clone:

```bash
cd /home/sum/Downloads/AI-Runtime/llama.cpp
git fetch origin refs/pull/<PR>/head:pr-<PR>-<slug>
git worktree add ../llama.cpp-<slug> pr-<PR>-<slug>
# then the same cmake + build command as §3, inside that directory
```

Done for MTP (#28243) → `llama.cpp-mtp`, built in **7m47s**, reporting
`version: 0.3.0-dev (build 10802, commit d1a92352c)`.

**ccache will not help across branches.** The MTP PR branches off a master
~220 commits old, and the differing headers change nearly every translation
unit's preprocessed output: hit rate was **2 / 1505**. Budget a full rebuild.

Worktree housekeeping: `git worktree list`, `git worktree remove ../llama.cpp-mtp`.
Never use bare `git stash` in a worktree — the stash stack is shared with the
main checkout.

## 7. Build-time facts worth remembering

- Ninja edge count for this configuration: **1122** (mainline), 586 shown at the
  tail for the MTP build because `LLAMA_BUILD_EXAMPLES=OFF` prunes differently
  on the older base.
- Progress is pollable at `build/.ninja_log` (one line per completed edge) —
  but **do not** pipe `cmake --build` through `tail`, it buffers and you see
  nothing until the end. Redirect to a log file instead.
- The CUDA flash-attention kernels dominate the first ~2/3 of the build; the
  final few hundred edges are fast C++ and links.
- Peak is ~60 concurrent `nvcc`/`cicc`/`cc1plus` processes at `-j 20`. RAM is
  not a constraint at 125 GiB.

## 8. Upstream history that matters for this hardware

`qwen4exp` (Qwen3.8-Flash-Next) support and its follow-up fixes:

| PR | what |
|---|---|
| #27742 | `model: add Qwen3.8-Flash-Next (qwen4exp)` — the initial support |
| #27880 | reduce number of graph splits |
| #27941 | fix seq_cp, block position keying, mtmd input, **cuda abort**, add tests |
| #28023 | sum the indexer heads by slices |
| #28123 | support recurrent state rollback |
| #28330 | avoid allocating V cache for the indexer (it is unused) — saves VRAM |
| #28896 | enable rms_norm + mul fusion |
| #28901 | add hyper-connection (hc) ops |
| **#28243** | **MTP for Qwen3.8-Flash-Next — still OPEN as of 2026-09-17** |

There are **no open issues** against `qwen4exp` upstream, which is a good
stability signal.

The July checkout was at `b10016` (0cea36222), i.e. **902 commits** behind and
predating #27742 entirely — it cannot load this model at all.
