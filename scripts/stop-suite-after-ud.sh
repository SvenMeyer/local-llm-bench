#!/usr/bin/env bash
# 2026-10-29 02:50: end the suite after arm D (UD-IQ4_XS) so arm E (IQ3_S on Strata defaults) does not run;
# queue 3 runs IQ3_S with the tail skip off instead (the setting that won for IQ3_XXS). Saves ~1.5-2 h.
cd /home/sum/Downloads/AI-Runtime
F=$(ls -t llama-strata-suite-*.txt | head -1)
NAME="llama-strata-over""night.sh"   # split so this script's own command line does not match
until grep -q '=== strata-ud-iq4xs: eval done' "$F"; do sleep 15; done
sleep 3
pkill -f "$NAME"
sleep 2
echo "[$(date +%H:%M:%S)] === suite stopped after arm D on purpose (arm E skipped; queue 3 runs IQ3_S noskip)" >> "$F"
~/.local/bin/strata launch --stop 2>&1 | tail -1 >> "$F"
