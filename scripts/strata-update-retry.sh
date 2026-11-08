#!/usr/bin/env bash
# Retry `strata update` (it resumes its partial download) until engine 0.1.55 is installed; max 20 tries.
for i in $(seq 1 20); do
  ls ~/.local/share/strata/components/engine/ | grep -q 0.1.55 && { echo "# $(date -Iseconds) engine 0.1.55 installed"; ~/.local/bin/strata --version; exit 0; }
  echo "# $(date -Iseconds) try $i"; ~/.local/bin/strata update 2>&1 | grep -v "downloading engine" ; sleep 15
done
echo "# gave up"
