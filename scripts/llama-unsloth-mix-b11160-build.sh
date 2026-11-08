#!/usr/bin/env bash
# Reproduce Unsloth's mix tree for ggml-org b11160 (= published
# b11160-mix-a6922cc, latest 2026-09-25) with the current pr-set.json, plus
# ggml-org#26348 (x86 AVX-VNNI Q2_0 vec_dot; without it every Q2_0 expert
# runs the scalar generic path on x86). Compile with the house CUDA flags.
# Does NOT install: run llama-unsloth-mix-b11160-install.sh afterwards.
#
# Mix procedure matches .github/workflows/unsloth-prebuilt.yml `resolve`.
set -euo pipefail

BASE="${BASE:-b11160}"
SRC_DIR="${SRC_DIR:-$HOME/.unsloth/llama.cpp-mix-b11160}"
REF_GIT="${REF_GIT:-$HOME/.unsloth/llama.cpp-mix-pr220}"
UNSLOTH_SCRIPTS="${UNSLOTH_SCRIPTS:-$HOME/.unsloth/mix-scripts}"
LOG="${LOG:-/home/sum/Downloads/AI-Runtime/llama-unsloth-mix-b11160-build.log}"
JOBS="${JOBS:-20}"
# Extra pins on top of Unsloth's set. Same URL shape as pr-set.json.
EXTRA_PINS=(
  "https://github.com/ggml-org/llama.cpp/pull/26348/commits/915ffcfbaae38def21aeb10b36e00b5df3620c27"
)

exec > >(tee -a "$LOG") 2>&1
echo "# $LOG"
echo "# start $(date -Iseconds)"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  echo "# clone ggml-org/llama.cpp -> $SRC_DIR"
  git clone --reference "$REF_GIT" --dissociate \
    https://github.com/ggml-org/llama.cpp.git "$SRC_DIR"
fi

cd "$SRC_DIR"
git remote get-url unslothai >/dev/null 2>&1 \
  || git remote add unslothai https://github.com/unslothai/llama.cpp.git
git fetch --no-tags origin "refs/tags/${BASE}:refs/tags/${BASE}"
git fetch --no-tags unslothai

# pr-set.json and additive_merge.py from the fork's master, via git (not raw URLs).
mkdir -p "$UNSLOTH_SCRIPTS"
git show unslothai/master:scripts/unsloth/pr-set.json > "$UNSLOTH_SCRIPTS/pr-set.json"
git show unslothai/master:scripts/unsloth/additive_merge.py > "$UNSLOTH_SCRIPTS/additive_merge.py"

PIN144=$(jq -r '.prs[] | select(test("/pull/144/commits/"))' "$UNSLOTH_SCRIPTS/pr-set.json")
echo "# pin #144 = $PIN144"
[[ "$PIN144" == *ca1426903fabe9af26cd10c42034cb4bbd2e0e11 ]] \
  || { echo "FAILED: pr-set.json #144 is not ca1426903"; exit 1; }

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
done < <(jq -r '.prs[] | if type == "string" then . else .url end' "$UNSLOTH_SCRIPTS/pr-set.json"; printf '%s\n' "${EXTRA_PINS[@]}")

# Local kernel on top of #26348: same math, in-lane transposed unpack
# (2x in cache, +26% at MEM size vs the PR on the 13700H; test-quantize-fns clean).
LOCAL_PATCH=/home/sum/Downloads/AI-Runtime/llama-q2_0-avxvnni-transposed.patch
git apply "$LOCAL_PATCH"
git -c user.name='mix-build' -c user.email='mix@local' commit -q -am "local: Q2_0 AVX-VNNI transposed unpack"
echo "# applied $LOCAL_PATCH"

COMMIT=$(git rev-parse --short HEAD)
echo "# mixed HEAD $COMMIT"
if ! rg -n 'layer.nextn.hc_head_norm = create_tensor\(.*\{ n_embd, hc \}' src/models/qwen4exp.cpp; then
  echo "FAILED: hc_head_norm is not { n_embd, hc }"
  exit 1
fi
if ! rg -n '^void ggml_vec_dot_q2_0_q8_0\(' ggml/src/ggml-cpu/arch/x86/quants.c; then
  echo "FAILED: no x86 Q2_0 vec_dot (ggml-org#26348 missing)"
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
  -DLLAMA_BUILD_TESTS=ON \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON

echo "# ninja -j $JOBS"
cmake --build build -j "$JOBS"
./build/bin/llama-server --version
strings ./build/bin/libllama.so | grep -x qwen4exp
# __AVXVNNI__ must be on for the #26348 path; -march=native on 13700H sets it.
echo | gcc -march=native -dM -E - | grep -q __AVXVNNI__ \
  && echo "# AVXVNNI: on" || echo "WARNING: __AVXVNNI__ not defined, Q2_0 falls back to generic"
echo "# compile done $(date -Iseconds) HEAD=$COMMIT"
