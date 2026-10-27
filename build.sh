#!/usr/bin/env bash
# Build Nima_Abaeian_Thesis.pdf with a tqdm progress bar (one bar per LaTeX pass).
# Usage: ./build.sh [--clean]
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")"

MAIN=Nima_Abaeian_Thesis
LOG="$(mktemp)"
cleanup() {
    rm -f "$LOG"
}
trap cleanup EXIT

if [ "${1:-}" = "--clean" ]; then
    latexmk -C "$MAIN.tex" >/dev/null 2>&1
fi

# Page count of the previous PDF sets the bar length; fall back to a rough guess.
TOTAL=$(pdfinfo "$MAIN.pdf" 2>/dev/null | awk '/^Pages:/ {print $2}')
export TOTAL="${TOTAL:-95}" LOG

latexmk -pdf -interaction=nonstopmode "$MAIN.tex" 2>&1 | python3 -c '
import os, re, sys
from tqdm import tqdm

total = int(os.environ["TOTAL"])
page = re.compile(r"\[(\d+)[ \]<{\s]")
bar, passes = None, 0

with open(os.environ["LOG"], "w") as log:
    for line in sys.stdin:
        log.write(line)
        if "This is pdfTeX" in line or "This is BibTeX" in line:
            if bar:
                bar.n = bar.total
                bar.close()
            passes += 1
            tool = "bibtex" if "BibTeX" in line else "pdflatex"
            bar = tqdm(total=total, unit="page", desc=f"pass {passes} ({tool})",
                       bar_format="{desc:<20} {percentage:3.0f}%|{bar:30}| {n_fmt}/{total_fmt} [{elapsed}]")
        elif bar:
            for m in page.finditer(line):
                n = int(m.group(1))
                if n > bar.n:
                    bar.total = max(bar.total, n)
                    bar.update(n - bar.n)
    if bar:
        bar.n = bar.total
        bar.close()
'
STATUS=${PIPESTATUS[0]}

ERRORS=$(grep -E '^!|^.*Error:|Undefined control|Emergency stop' "$LOG" | head -10)
UNDEF=$(grep -cE 'Reference .* undefined|Citation .* undefined' "$MAIN.log" 2>/dev/null)

if [ "$STATUS" -ne 0 ] || [ -n "$ERRORS" ]; then
    echo "Build FAILED (latexmk exit $STATUS)"
    [ -n "$ERRORS" ] && echo "$ERRORS"
    exit 1
fi

PAGES=$(pdfinfo "$MAIN.pdf" 2>/dev/null | awk '/^Pages:/ {print $2}')
echo "Build OK: $MAIN.pdf ($PAGES pages, ${UNDEF:-0} undefined references)"
