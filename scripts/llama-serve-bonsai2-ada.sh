#!/usr/bin/env bash
# Ternary-Bonsai-2-27B on Cary Palmer's patched Prism runtime (github.com/professorpalmer/bonsai-ada-surgery),
# Linux port of the 8 GB preset in its start-server.ps1 (bundle d6c977f, 2026-10-26):
#   262k window, q3_0 K/V, tiered KV (cells 0..N in VRAM, the rest in pinned RAM), MTP draft 1 (2 past the VRAM
#   line) + lookup drafting, replay rollback, shared CUDA pool, packed KQ mask, f16/chunked prefill, sparse host-tail
#   reads in auto mode, medium reasoning with a 20k budget.
#
# Usage:
#   ./llama-serve-bonsai2-ada.sh                     # 262k, thinking medium
#   THINK=0 ./llama-serve-bonsai2-ada.sh             # agent harnesses: enable_thinking=false (runtime's advice)
#   CTX=65536 KV=q4_0 ./llama-serve-bonsai2-ada.sh   # other window / K/V type
#   SPEC=0 ./llama-serve-bonsai2-ada.sh              # no drafting (plain PTQ1_0 file, no tiered sizing for MTP)
#   KV_VRAM_CELLS=80000 ./...                        # pin the VRAM line instead of sizing it
#   DRY=1 ./...                                      # print env + command, do not start
# Build: bonsai-ada-surgery/build/build_linux.sh (see llama-compile-guide.md). Does NOT touch /usr/local/bin.
set -euo pipefail

ROOT=/home/sum/Downloads/AI-Runtime
BIN="${BIN:-$(cat $ROOT/bonsai-ada-surgery/tooling/linux-server-path 2>/dev/null || true)}"
MDIR=/home/sum/.cache/lm-studio/models
HEAD="${HEAD:-q4}"   # q4 = Q4_0 draft head (8 GB default, -214 MiB), q8 = original ProCreations Q8_0 head
case "$HEAD" in
  q4) MTP_MODEL=$MDIR/CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations-q4head.gguf ;;
  q8) MTP_MODEL=$MDIR/CaryPalmer/Ternary-Bonsai-2-27B-262k-GGUF/Ternary-Bonsai-2-27B-PTQ1_0-mtp-procreations.gguf ;;
  *) echo "HEAD must be q4 or q8" >&2; exit 2 ;;
esac
PLAIN_MODEL=$MDIR/prism-ml/Ternary-Bonsai-2-27B-gguf/Ternary-Bonsai-2-27B-PTQ1_0.gguf

SPEC="${SPEC:-1}"            # MTP draft size below the VRAM line (8 GB preset: 1)
REPLAY="${REPLAY:-0}"        # replay rollback (LLAMA_RS_REPLAY). Off: on Linux it crashed (illegal memory access in
                             # launch_gated_delta_net replay path) on a 4k code prompt with lookup drafting, 2026-10-27
SPEC_DEEP="${SPEC_DEEP:-$([[ $REPLAY == 1 ]] && echo 2 || echo 1)}"  # draft past the VRAM line (preset: 2 with replay, 1 without)
MODEL="${MODEL:-$([[ $SPEC -gt 0 ]] && echo "$MTP_MODEL" || echo "$PLAIN_MODEL")}"
CTX="${CTX:-262144}"
KV="${KV:-q3_0}"
UB="${UB:-$([[ $SPEC -gt 0 ]] && echo 512 || echo 1024)}"
PORT="${PORT:-8099}"
THINK="${THINK:-1}"
EFFORT="${EFFORT:-medium}"
THINK_BUDGET="${THINK_BUDGET:-20480}"
MARGIN="${MARGIN:-225}"      # free VRAM the preset keeps (drafting mode, measured on Windows; Linux needs no more)
STAGE_CELLS="${STAGE_CELLS:-81920}"
SPARSE="${SPARSE:-auto}"     # auto | 1 | 0
LOOKUP="${LOOKUP:-1}"        # 1: ngram lookup drafting in front of MTP (runtime default); 0: MTP only
SCHED="${SCHED:-}"           # GGML_CUDA_SCHEDULE (local patch llama-cuda-schedule-env.patch): blocking|yield|spin|auto
[[ -n $SCHED ]] && export GGML_CUDA_SCHEDULE=$SCHED
[[ $SCHED == blocking ]] && export GGML_CUDA_BLOCKING_SYNC=1   # upstream PR #26487 name, same effect

[[ -x "$BIN" ]] || { echo "missing engine $BIN (run bonsai-ada-surgery/build/build_linux.sh)" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "missing model $MODEL" >&2; exit 1; }
LIBDIR=$(dirname "$BIN")

MiB=1048576
case "$KV" in q8_0) CELL=34816 ;; q4_0) CELL=18432 ;; q3_0) CELL=14336 ;; f16) CELL=65536 ;; *) CELL=34816 ;; esac
POOL_MIB=0
TIER_ARGS=(); SPEC_ARGS=()

# ---- drafting (MTP head + lookup), replay rollback, shared pool, 8 GB engine switches ----
if [[ $SPEC -gt 0 ]]; then
  export GGML_CUDA_BATCH_INVARIANT=1
  [[ $REPLAY == 1 ]] && export LLAMA_RS_REPLAY=1
  export GGML_CUDA_SHARED_POOL=${GGML_CUDA_SHARED_POOL:-1}
  export LLAMA_MTP_DRAFT_UBATCH=${LLAMA_MTP_DRAFT_UBATCH:-256}
  export LLAMA_ARG_KQ_MASK_PACKED=${LLAMA_ARG_KQ_MASK_PACKED:-1}
  POOL_MIB=48
  if [[ $LOOKUP == 1 ]]; then SPEC_ARGS=(--spec-type ngram-mod,draft-mtp --spec-lookup-n-max 32)
  else SPEC_ARGS=(--spec-type draft-mtp); fi
  SPEC_ARGS+=(--spec-draft-n-max "$SPEC" -ctkd "$KV" -ctvd "$KV" --spec-draft-window 16384)
  DRAFT_PREFILL=32768
else
  DRAFT_PREFILL=65536
fi
export GGML_CUDA_FA_PREFILL_F16=${GGML_CUDA_FA_PREFILL_F16:-$DRAFT_PREFILL}
export GGML_CUDA_FA_CHUNK=${GGML_CUDA_FA_CHUNK:-32768}
export LLAMA_ARG_CHECKPOINT_EVERY_NT=${LLAMA_ARG_CHECKPOINT_EVERY_NT:-8192}

# ---- sparse host-tail reads (auto: the engine times dense vs sparse per 16k band and keeps the faster) ----
SPARSE_CELL=0
if [[ $SPARSE != 0 ]]; then
  export GGML_CUDA_FA_SPARSE=${GGML_CUDA_FA_SPARSE:-12288,64,1024}
  export GGML_CUDA_FA_SPARSE_FAST=${GGML_CUDA_FA_SPARSE_FAST:-1}
  export GGML_CUDA_KV_TIER_STAGE_MIN_Q=${GGML_CUDA_KV_TIER_STAGE_MIN_Q:-9}
  if [[ $SPARSE == auto ]]; then export GGML_CUDA_FA_SPARSE_MIN_HOST=${GGML_CUDA_FA_SPARSE_MIN_HOST:-16384}; export GGML_CUDA_FA_SPARSE_AUTO=1
  else export GGML_CUDA_FA_SPARSE_MIN_HOST=${GGML_CUDA_FA_SPARSE_MIN_HOST:-32768}; fi
  [[ $KV == q3_0 ]] && export GGML_CUDA_FA_SPARSE_FRAC=${GGML_CUDA_FA_SPARSE_FRAC:-0.25} || export GGML_CUDA_FA_SPARSE_FRAC=${GGML_CUDA_FA_SPARSE_FRAC:-0.125}
  SPARSE_CELL=$(( 16 * 4 * (2 * 256 + 2) / 64 ))   # int8 page bounds, page 64: 514 B per host cell
fi

# ---- tiered KV sizing (same formula as start-server.ps1, 8 GB branch) ----
FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1 | tr -d ' ')
if [[ $SPEC -gt 0 ]]; then FIXED=6531; else [[ $UB -ge 1024 ]] && FIXED=6218 || FIXED=5955; fi
[[ $SPEC -gt 0 && $REPLAY == 1 ]] && FIXED=$(( FIXED - 142 + 7 * ( (SPEC > SPEC_DEEP ? SPEC : SPEC_DEEP) - 1 ) ))   # replay rollback
[[ $HEAD == q8 && $SPEC -gt 0 ]] && FIXED=$(( FIXED + 214 ))
if [[ ${LLAMA_ARG_KQ_MASK_PACKED:-0} == 1 ]]; then MASK=$(( CTX * UB / 8 / MiB )); else MASK=$(( CTX * UB * 2 / MiB )); fi
FIXED=$(( FIXED + MASK - 131072 * UB * 2 / MiB - POOL_MIB ))
[[ $SPARSE_CELL -gt 0 ]] && FIXED=$(( FIXED + 64 ))
if [[ -n ${KV_VRAM_CELLS:-} ]]; then
  CELLS=$KV_VRAM_CELLS; DENSE=$CELLS
else
  BUDGET=$(( (FREE - MARGIN - FIXED) * MiB - STAGE_CELLS * CELL / 16 - CTX * SPARSE_CELL ))
  CELLS=$(( BUDGET / (CELL - SPARSE_CELL) / 256 * 256 ))
  DENSE=$(( ((FREE - MARGIN - FIXED + 64) * MiB - STAGE_CELLS * CELL / 16) / CELL / 256 * 256 ))
  [[ $SPARSE_CELL -gt 0 ]] || DENSE=$CELLS
fi
if (( CTX - CELLS > STAGE_CELLS )); then
  export GGML_CUDA_KV_TIER_STAGING_FRAC=$(python3 -c "print(f'{$STAGE_CELLS/$CTX:.6f}')")
fi
if [[ $SPARSE_CELL -gt 0 && $DENSE -gt $CELLS ]]; then   # late reserve: keep the dense line until sparse engages
  export GGML_CUDA_KV_TIER_DEMOTE_FRAC=$(python3 -c "print(f'{($DENSE-$CELLS)/$CTX:.6f}')")
  if [[ $SPARSE == auto ]]; then
    export GGML_CUDA_FA_SPARSE_CALIB=$ROOT/bonsai-ada-surgery/artifacts/sparse-calib.txt
    export GGML_CUDA_FA_SPARSE_CALIB_KEY="RTX4070Laptop|$(nvidia-smi --query-gpu=driver_version --format=csv,noheader|head -1)|$(stat -c %s-%Y $LIBDIR/libggml-cuda.so 2>/dev/null)|line_~$(( (DENSE+2048)/4096*4096 ))/$(( (CELLS+2048)/4096*4096 ))|$KV|ctx_$CTX|$GGML_CUDA_FA_SPARSE|frac_$GGML_CUDA_FA_SPARSE_FRAC"
  fi
  CELLS=$DENSE
fi
if (( CELLS < CTX )); then
  (( CELLS >= 16384 )) || { echo "only $CELLS cells fit in VRAM ($FREE MiB free): free VRAM or lower CTX" >&2; exit 1; }
  TIER_ARGS=(--kv-vram-cells "$CELLS")
  [[ $SPEC -gt 0 ]] && SPEC_ARGS+=(--spec-draft-n-max-tail "$SPEC_DEEP")
fi

# ---- reasoning (medium effort, 20k budget, harness-proofing) ----
if [[ $THINK == 0 ]]; then export LLAMA_ARG_CHAT_TEMPLATE_KWARGS='{"reasoning_effort":"'$EFFORT'","enable_thinking":false}'
else export LLAMA_ARG_CHAT_TEMPLATE_KWARGS='{"reasoning_effort":"'$EFFORT'"}'; fi
NPRED=$(( THINK_BUDGET + 4096 > 24576 ? THINK_BUDGET + 4096 : 24576 ))

echo "# engine  $BIN"
echo "# model   $(basename "$MODEL")  head=$HEAD spec=$SPEC/$SPEC_DEEP replay=$REPLAY lookup=$LOOKUP sched=${SCHED:-driver-default}"
echo "# window  $CTX / $KV  ub $UB  vram free $FREE MiB  fixed $FIXED MiB  margin $MARGIN"
echo "# kv      vram cells ${CELLS} (dense line $DENSE)  staging_frac ${GGML_CUDA_KV_TIER_STAGING_FRAC:-none}  demote_frac ${GGML_CUDA_KV_TIER_DEMOTE_FRAC:-none}"
echo "# think   $THINK effort=$EFFORT budget=$THINK_BUDGET"
env | grep -E '^(GGML_CUDA_|LLAMA_RS_|LLAMA_MTP_|LLAMA_ARG_)' | sort | sed 's/^/# env     /'

CMD=("$BIN" "${TIER_ARGS[@]}" "${SPEC_ARGS[@]}" --backend-sampling
  --reasoning-budget-message "Now produce the complete answer."
  --reasoning-effort-allow "$EFFORT" --reasoning-effort-fallback medium --reasoning-max-tokens-floor $(( THINK_BUDGET + 4096 ))
  --fit off --reasoning-budget "$THINK_BUDGET" -n "$NPRED"
  -m "$MODEL" -ngl 99 -fa on -c "$CTX" -np 1 -b 2048 -ub "$UB" -ctk "$KV" -ctv "$KV"
  --host "${HOST:-127.0.0.1}" --port "$PORT" --alias bonsai-2-27b --jinja --prio 2 --poll 100 --metrics
  -t "${THREADS:-6}" --temp 1.0 --top-p 0.95 --top-k 20 "$@")
echo "# cmd     ${CMD[*]}"
[[ ${DRY:-0} == 1 ]] && exit 0
exec "${CMD[@]}"
