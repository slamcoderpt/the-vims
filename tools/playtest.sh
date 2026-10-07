#!/usr/bin/env bash
# Automated end-to-end playtest of the game loop (software GL under Xvfb).
# usage: tools/playtest.sh [test=playtest] [extra user args...]
#   tools/playtest.sh                      -> scripts/sim/tests/playtest.gd, prints PASS/FAIL per step,
#                                             saves shots/playtest_*.png
#   tools/playtest.sh navdump --location=market   -> nav grid images in shots/
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST="${1:-playtest}"; shift || true
mkdir -p "$ROOT/shots"
[ "$TEST" = "playtest" ] && rm -f "$ROOT/shots"/playtest_*.png
LOG="$(mktemp)"
VIMS_PLAYTEST=1 timeout 3600 xvfb-run -a -s "-screen 0 1672x941x24" godot --path "$ROOT" --rendering-driver opengl3 \
  --resolution 1672x941 --audio-driver Dummy -- --playtest="$TEST" --shots="$ROOT/shots" "$@" 2>&1 \
  | grep --line-buffered -vE "ALSA|alsa|set_use_vsync|^\s*at:|^$" | tee "$LOG"
if grep -qE "SCRIPT ERROR|Parse Error" "$LOG"; then
  echo "PLAYTEST: script errors found"; rm -f "$LOG"; exit 2
fi
if grep -q "^RESULT FAIL" "$LOG"; then rm -f "$LOG"; exit 1; fi
rm -f "$LOG"
