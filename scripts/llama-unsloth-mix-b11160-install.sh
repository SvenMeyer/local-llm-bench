#!/usr/bin/env bash
# Copy the b11160 mix (+ ggml-org#26348) binaries into Unsloth's live llama.cpp tree.
# Uses /usr/bin/cp -af (shell cp is interactive on this box).
# Rollback: SRC=$HOME/.unsloth/llama.cpp/build/bin-pre-b11160 is the previous
# (mix-pr220 11166) bin dir; copy it back with the same cp -af.
set -euo pipefail
SRC="${SRC:-$HOME/.unsloth/llama.cpp-mix-b11160/build/bin}"
LIVE="${LIVE:-$HOME/.unsloth/llama.cpp}"
DST="$LIVE/build/bin"
BAK="$LIVE/build/bin-pre-b11160"

[[ -x "$SRC/llama-server" ]] || { echo "FAILED: no $SRC/llama-server"; exit 1; }
mkdir -p "$BAK" "$DST"
if [[ ! -e "$BAK/llama-server" ]]; then
  /usr/bin/cp -af "$DST/." "$BAK/"
  /usr/bin/cp -af "$LIVE/BUILD_INFO.txt" "$BAK/BUILD_INFO.txt"
fi
/usr/bin/cp -af "$SRC/." "$DST/"
# Keep Unsloth's root symlink pointing at build/bin.
ln -sfn build/bin/llama-server "$LIVE/llama-server"
ln -sfn build/bin/llama-quantize "$LIVE/llama-quantize" 2>/dev/null || true

COMMIT=$(git -C "$HOME/.unsloth/llama.cpp-mix-b11160" rev-parse --short HEAD)
{
  echo "llama.cpp version: b11160-mix-a6922cc+26348"
  echo "requested source ref: unslothai/llama.cpp pr-set (master 88e42eec2) on ggml-org b11160 + ggml-org#26348@915ffcfba"
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
  echo "notes: house cmake GGML_NATIVE=ON CMAKE_CUDA_ARCHITECTURES=89-real. Official MTP pin #144@ca1426903. x86 AVX-VNNI Q2_0 vec_dot (#26348)."
} > "$LIVE/BUILD_INFO.txt"

echo "# installed HEAD $COMMIT"
"$DST/llama-server" --version
readelf -d "$DST/llama-server" | awk '/RPATH|RUNPATH/'
echo "# install done"
