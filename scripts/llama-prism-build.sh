#!/usr/bin/env bash
# Build PrismML-Eng/llama.cpp (branch prism) with house CUDA flags.
# Worktree: llama.cpp-prism. Does NOT overwrite /usr/local/bin/llama-server.
set -euo pipefail

SRC="${SRC:-/home/sum/Downloads/AI-Runtime/llama.cpp-prism}"
LOG="${LOG:-/home/sum/Downloads/AI-Runtime/llama-prism-build.log}"
JOBS="${JOBS:-20}"

exec > >(tee -a "$LOG") 2>&1
echo "# $LOG"
echo "# start $(date -Iseconds)"

cd "$SRC"
COMMIT=$(git rev-parse --short HEAD)
echo "# HEAD $COMMIT $(git log -1 --oneline)"

export PATH="/opt/cuda/bin:$PATH"
export CUDACXX="/opt/cuda/bin/nvcc"

echo "# cmake"
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

echo "# ninja -j $JOBS"
cmake --build build -j "$JOBS"

./build/bin/llama-server --version
./build/bin/llama-cli --version || true
echo "# types:"
strings ./build/bin/libggml-base.so | grep -E '^(PTQ1_0|PQ2_0|TQ1_0)$' || true
echo "# compile done $(date -Iseconds) HEAD=$COMMIT"
