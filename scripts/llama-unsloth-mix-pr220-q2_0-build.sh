#!/usr/bin/env bash
# The baseline engine (mix-pr220, 11166 / 10921f3f1) plus ONLY the x86 Q2_0
# CPU kernel: ggml-org#26348 (AVX-VNNI vec_dot) + llama-q2_0-avxvnni-transposed.patch.
# Without it Q2_0 experts run the scalar generic path on x86.
#
# Why not the newer b11160 mix: measured 2026-09-27, it is no faster on
# UD-IQ4_XS with CUDA fusion off, and with fusion on it changes greedy output
# on qwen4exp (blank-line loop at the 2k probe, MTP accept 6-26%). Keeping the
# baseline engine leaves the quant as the only variable.
# Install: SRC=$HOME/.unsloth/llama.cpp-mix-pr220-q2_0/build/bin
#          SRC_TREE=$HOME/.unsloth/llama.cpp-mix-pr220-q2_0 ./llama-unsloth-mix-pr220-install.sh
set -euo pipefail

BASE_TREE="${BASE_TREE:-$HOME/.unsloth/llama.cpp-mix-pr220}"
SRC_DIR="${SRC_DIR:-$HOME/.unsloth/llama.cpp-mix-pr220-q2_0}"
LOG="${LOG:-/home/sum/Downloads/AI-Runtime/llama-unsloth-mix-pr220-q2_0-build.log}"
JOBS="${JOBS:-20}"
PIN="https://github.com/ggml-org/llama.cpp.git 915ffcfbaae38def21aeb10b36e00b5df3620c27"
LOCAL_PATCH=/home/sum/Downloads/AI-Runtime/llama-q2_0-avxvnni-transposed.patch

exec > >(tee -a "$LOG") 2>&1
echo "# $LOG"
echo "# start $(date -Iseconds)"

BASE_HEAD=$(git -C "$BASE_TREE" rev-parse HEAD)
if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone --reference "$BASE_TREE" --dissociate --no-checkout "$BASE_TREE" "$SRC_DIR"
fi
cd "$SRC_DIR"
git checkout -q --detach "$BASE_HEAD"
git reset -q --hard "$BASE_HEAD"
git clean -fdx -e build -e .ccache >/dev/null

echo "# merge ggml-org/llama.cpp#26348 onto $(git rev-parse --short HEAD)"
git fetch -q --no-tags $PIN
git -c user.name='mix-build' -c user.email='mix@local' \
  merge --no-ff --no-edit -m "Merge ggml-org/llama.cpp#26348 @ 915ffcfba" FETCH_HEAD
git apply "$LOCAL_PATCH"
git -c user.name='mix-build' -c user.email='mix@local' commit -q -am "local: Q2_0 AVX-VNNI transposed unpack"
echo "# applied $LOCAL_PATCH"
COMMIT=$(git rev-parse --short HEAD)
echo "# HEAD $COMMIT"
git diff --stat "$BASE_HEAD" HEAD

sed -i "s/^set(BUILD_NUMBER 0)$/set(BUILD_NUMBER 11027)/" cmake/build-info.cmake || true
sed -i "s/^set(BUILD_COMMIT \"unknown\")$/set(BUILD_COMMIT \"${COMMIT}\")/" cmake/build-info.cmake || true
grep -q 'Compiled by the Unsloth team' cmake/build-info.cmake \
  || printf '\n# Unsloth fingerprint\nset(BUILD_TARGET "${BUILD_TARGET} (Compiled by the Unsloth team)")\n' \
       >> cmake/build-info.cmake

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
  -DLLAMA_BUILD_TESTS=ON \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON
cmake --build build -j "$JOBS"
./build/bin/llama-server --version
./build/bin/test-quantize-fns | tail -1
echo "# compile done $(date -Iseconds) HEAD=$COMMIT"
