#!/usr/bin/env bash
# Reproduce Unsloth's mix tree for ggml-org b11027 with pr-set.json after
# unslothai/llama.cpp#220 (Qwen3.8 MTP pin moved to ca1426903), then compile
# with the house CUDA flags and install into ~/.unsloth/llama.cpp/build/bin.
#
# Mix procedure matches .github/workflows/unsloth-prebuilt.yml `resolve`.
set -euo pipefail

BASE="${BASE:-b11027}"
SRC_DIR="${SRC_DIR:-$HOME/.unsloth/llama.cpp-mix-pr220}"
LIVE="${LIVE:-$HOME/.unsloth/llama.cpp}"
REF_GIT="${REF_GIT:-/home/sum/Downloads/AI-Runtime/llama.cpp}"
UNSLOTH_SCRIPTS="${UNSLOTH_SCRIPTS:-$HOME/.unsloth/mix-scripts}"
LOG="${LOG:-/home/sum/Downloads/AI-Runtime/llama-unsloth-mix-pr220-build.log}"
JOBS="${JOBS:-20}"

exec > >(tee -a "$LOG") 2>&1
echo "# $LOG"
echo "# start $(date -Iseconds)"

mkdir -p "$UNSLOTH_SCRIPTS"
curl -fsSL -o "$UNSLOTH_SCRIPTS/pr-set.json" \
  https://raw.githubusercontent.com/unslothai/llama.cpp/master/scripts/unsloth/pr-set.json
curl -fsSL -o "$UNSLOTH_SCRIPTS/additive_merge.py" \
  https://raw.githubusercontent.com/unslothai/llama.cpp/master/scripts/unsloth/additive_merge.py

PIN144=$(jq -r '.prs[] | select(test("/pull/144/commits/"))' "$UNSLOTH_SCRIPTS/pr-set.json")
echo "# pin #144 = $PIN144"
[[ "$PIN144" == *ca1426903fabe9af26cd10c42034cb4bbd2e0e11 ]] \
  || { echo "FAILED: pr-set.json #144 is not ca1426903"; exit 1; }

if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "# clone ggml-org/llama.cpp -> $SRC_DIR"
  git clone --reference "$REF_GIT" --dissociate \
    https://github.com/ggml-org/llama.cpp.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git remote get-url unslothai >/dev/null 2>&1 \
  || git remote add unslothai https://github.com/unslothai/llama.cpp.git
git fetch --no-tags origin "refs/tags/${BASE}:refs/tags/${BASE}"
git fetch --no-tags unslothai || true
git checkout -q --detach "refs/tags/${BASE}"
git reset --hard "refs/tags/${BASE}"
git clean -fdx -e build -e .ccache >/dev/null

echo "# merging pins onto $BASE"
while read -r url; do
  [[ -z "$url" ]] && continue
  repo=$(sed -nE 's#https://github.com/([^/]+)/llama.cpp/pull/([0-9]+)/commits/([0-9a-f]{40}).*#\1/llama.cpp#p' <<<"$url")
  num=$(sed -nE 's#https://github.com/([^/]+)/llama.cpp/pull/([0-9]+)/commits/([0-9a-f]{40}).*#\2#p' <<<"$url")
  sha=$(sed -nE 's#https://github.com/([^/]+)/llama.cpp/pull/([0-9]+)/commits/([0-9a-f]{40}).*#\3#p' <<<"$url")
  echo "# merge ${repo}#${num} @ ${sha}"
  git fetch -q --no-tags "https://github.com/${repo}.git" "$sha"
  if ! git -c user.name='mix-build' -c user.email='mix@local' \
         -c merge.conflictStyle=diff3 \
         merge --no-ff --no-edit -m "Merge ${repo}#${num} @ ${sha}" "$sha"; then
    if python3 "$UNSLOTH_SCRIPTS/additive_merge.py" --repo "$SRC_DIR" \
         && [[ -z "$(git diff --name-only --diff-filter=U)" ]]; then
      git -c user.name='mix-build' -c user.email='mix@local' commit --no-edit
      echo "# additive merge kept both sides for ${repo}#${num}"
    else
      git merge --abort 2>/dev/null || true
      echo "FAILED: ${repo}#${num} does not merge cleanly"
      exit 1
    fi
  fi
done < <(jq -r '.prs[] | if type == "string" then . else .url end' "$UNSLOTH_SCRIPTS/pr-set.json")

COMMIT=$(git rev-parse --short HEAD)
echo "# mixed HEAD $COMMIT"
rg -n 'nextn.hc_head_norm = create_tensor' src/models/qwen4exp.cpp
rg -n 'TENSOR_ALLOW_RESHAPE' src/models/qwen4exp.cpp | head
if ! rg -n 'layer.nextn.hc_head_norm = create_tensor\(.*\{ n_embd, hc \}' src/models/qwen4exp.cpp; then
  echo "FAILED: hc_head_norm is not { n_embd, hc }"
  exit 1
fi

# Bake build number like Unsloth CI so --version is not b0.
COUNT="${BASE#b}"
sed -i "s/^set(BUILD_NUMBER 0)$/set(BUILD_NUMBER ${COUNT})/" cmake/build-info.cmake || true
sed -i "s/^set(BUILD_COMMIT \"unknown\")$/set(BUILD_COMMIT \"${COMMIT}\")/" cmake/build-info.cmake || true
grep -q 'Compiled by the Unsloth team' cmake/build-info.cmake \
  || printf '\n# Unsloth fingerprint\nset(BUILD_TARGET "${BUILD_TARGET} (Compiled by the Unsloth team)")\n' \
       >> cmake/build-info.cmake

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
strings ./build/bin/libllama.so | grep -x qwen4exp
echo "# compile done $(date -Iseconds) HEAD=$COMMIT"
