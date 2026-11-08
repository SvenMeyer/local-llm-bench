#!/usr/bin/env bash
# Copy the PR #220 mix binaries into Unsloth's live llama.cpp tree.
# Uses /usr/bin/cp -af (shell cp is interactive on this box).
set -euo pipefail
SRC="${SRC:-$HOME/.unsloth/llama.cpp-mix-pr220/build/bin}"
LIVE="${LIVE:-$HOME/.unsloth/llama.cpp}"
DST="$LIVE/build/bin"
BAK="$LIVE/build/bin-pre-pr220"

[[ -x "$SRC/llama-server" ]] || { echo "FAILED: no $SRC/llama-server"; exit 1; }
mkdir -p "$BAK" "$DST"
if [[ ! -e "$BAK/llama-server" ]]; then
  /usr/bin/cp -af "$DST/." "$BAK/"
fi
/usr/bin/cp -af "$SRC/." "$DST/"
# Keep Unsloth's root symlink pointing at build/bin.
ln -sfn build/bin/llama-server "$LIVE/llama-server"
ln -sfn build/bin/llama-quantize "$LIVE/llama-quantize" 2>/dev/null || true

SRC_TREE="${SRC_TREE:-$HOME/.unsloth/llama.cpp-mix-pr220}"
COMMIT=$(git -C "$SRC_TREE" rev-parse --short HEAD)
{
  echo "llama.cpp version: b11027-mix-pr220-ca1426903"
  echo "requested source ref: unslothai/llama.cpp#220 pin #144@ca1426903 on ggml-org b11027"
  echo "resolved source ref: mixed HEAD $COMMIT"
  echo "variant: local-native-sm89"
  echo "runtime line: cuda13"
  echo "coverage class: older"
  echo "backend: CUDA"
  echo "toolkit version: 13.3"
  echo "supported sms: 89-real"
  echo "os: linux"
  echo "arch: x64"
  echo "source commit: $COMMIT"
  echo "built at (local): $(date -Iseconds)"
  echo "notes: house cmake GGML_NATIVE=ON CMAKE_CUDA_ARCHITECTURES=89-real. Official MTP hc_head_norm + shared-head fit borrow. tree: $SRC_TREE"
} > "$LIVE/BUILD_INFO.txt"

echo "# installed HEAD $COMMIT"
"$DST/llama-server" --version
readelf -d "$DST/llama-server" | awk '/RPATH|RUNPATH/'
echo "# install done"
