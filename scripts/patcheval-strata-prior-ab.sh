#!/usr/bin/env bash
# Routing A/B on one engine: STRATA_ROUTE_PRIOR 0, 0.5 and 1.5 (tail skip off in all), Qwen3.8 IQ3_S,
# PatchEval tasks 1-6, 60 min per task (PI_TIMEOUT=3000 for 50 min), pi output cap 64k. One arm after another (~4.5 h each).
# Question it answers: does the prior cost task quality on our 8 GB card, and is 0.5 a good middle value?
# Usage: setsid -f ./patcheval-strata-prior-ab.sh > patcheval-strata-prior-ab-$(date +%Y%m%d-%H%M).txt 2>&1 < /dev/null
#        PRIORS="0 0.5" ./patcheval-strata-prior-ab.sh   # subset; a finished arm (log has "Saved:") is skipped
#        DRAFTING=dflash2 TAG=-gpuunlock ./patcheval-strata-prior-ab.sh   # pin the drafter; TAG goes into the log label
set -uo pipefail
cd /home/sum/Downloads/AI-Runtime
ENG=$(~/.local/bin/strata --version 2>/dev/null | awk '{print $4}' | tr -d ';')
for p in ${PRIORS:-0 0.5 1.5}; do
    ARMS=iq3s SLICE=patcheval:6 PI_TIMEOUT=${PI_TIMEOUT:-3600} MAX_TOKENS=65536 ROUTE_PRIOR=$p \
        SUFFIX=-prior$p-$ENG-${DRAFTING:-auto}${TAG:-}-64k-t${PI_TIMEOUT:-3600}-first6 ./patcheval-strata-quants.sh
done
