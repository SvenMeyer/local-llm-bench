#!/usr/bin/env bash
# Download one ISTA-DASLab GSQ-RCO shard 1, verify its sha256 against the HF LFS oid, and
# symlink the shared shard 2 (n-gram table, identical in every tier) plus the MTP drafter.
# Usage: ./llama-gsq-download.sh coder | iq3xxs | iq3s
set -euo pipefail
M=/home/sum/.cache/lm-studio/models
SHARED2=$M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-GGUF/Qwen3.8-Flash-Next-GSQ-RCO-Q2_0-00002-of-00002.gguf
MTP=$M/unsloth/Qwen3.8-Flash-Next-GGUF/mtp-Qwen3.8-Flash-Next-shared-Q4_K_M.gguf
case "$1" in
  coder)  REPO=Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF; Q=IQ1_M;   DIR=$M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF ;;
  iq3xxs) REPO=Qwen3.8-Flash-Next-GSQ-RCO-GGUF;       Q=IQ3_XXS; DIR=$M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-GGUF ;;
  iq3s)   REPO=Qwen3.8-Flash-Next-GSQ-RCO-GGUF;       Q=IQ3_S;   DIR=$M/ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-GGUF ;;
  *) echo "usage: $0 coder|iq3xxs|iq3s" >&2; exit 1 ;;
esac
F=Qwen3.8-Flash-Next-GSQ-RCO-$Q-00001-of-00002.gguf
F2=Qwen3.8-Flash-Next-GSQ-RCO-$Q-00002-of-00002.gguf
mkdir -p "$DIR"
OID=$(curl -s "https://huggingface.co/api/models/ISTA-DASLab/$REPO/tree/main?recursive=true" |
      python3 -c "import json,sys; print([x['lfs']['oid'] for x in json.load(sys.stdin) if x['path'].endswith('$F')][0])")
echo "# $(date -Iseconds) start $F expect sha256 $OID"
curl -fL --retry 20 --retry-delay 10 --retry-all-errors -C - -o "$DIR/$F.part" \
     "https://huggingface.co/ISTA-DASLab/$REPO/resolve/main/$Q/$F" -sS
echo "# $(date -Iseconds) downloaded $(stat -c %s "$DIR/$F.part") bytes, verifying"
GOT=$(sha256sum "$DIR/$F.part" | cut -d' ' -f1)
[[ "$GOT" == "$OID" ]] || { echo "FAILED: sha256 $GOT != $OID"; exit 1; }
mv "$DIR/$F.part" "$DIR/$F"
ln -sfn "$SHARED2" "$DIR/$F2"
ln -sfn "$MTP" "$DIR/$(basename "$MTP")"
echo "# $(date -Iseconds) OK $DIR/$F (sha256 verified), shard 2 + MTP symlinked"
