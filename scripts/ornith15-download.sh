#!/usr/bin/env bash
# Download unsloth/Ornith-1.5-122B-GGUF UD-Q4_K_XL (3 shards, ~80 GB), resumable, sha256-verified per shard.
# Usage: nohup ./ornith15-download.sh > ornith15-download.log 2>&1 &
set -euo pipefail
REPO=unsloth/Ornith-1.5-122B-GGUF; Q=UD-Q4_K_XL
DIR=/home/sum/.cache/lm-studio/models/unsloth/Ornith-1.5-122B-GGUF
mkdir -p "$DIR"
curl -s "https://huggingface.co/api/models/$REPO/tree/main/$Q" |
  python3 -c 'import json,sys; [print(x["path"].split("/")[-1], x["lfs"]["oid"]) for x in json.load(sys.stdin)]' |
while read -r F OID; do
  if [[ -f "$DIR/$F" ]]; then echo "# $F already present, skipped"; continue; fi
  echo "# $(date -Iseconds) start $F expect sha256 $OID"
  curl -fL --retry 20 --retry-delay 10 --retry-all-errors -C - -o "$DIR/$F.part" -sS \
       "https://huggingface.co/$REPO/resolve/main/$Q/$F"
  GOT=$(sha256sum "$DIR/$F.part" | cut -d' ' -f1)
  [[ "$GOT" == "$OID" ]] || { echo "FAILED: $F sha256 $GOT != $OID"; exit 1; }
  mv "$DIR/$F.part" "$DIR/$F"; echo "# $(date -Iseconds) OK $F"
done
echo "# $(date -Iseconds) all shards done"
