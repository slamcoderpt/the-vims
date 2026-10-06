#!/usr/bin/env bash
# Render one screenshot preset headlessly (software GL under Xvfb).
# usage: tools/shot.sh <preset> [out.png]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESET="$1"; OUT="${2:-$ROOT/shots/$PRESET.png}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
timeout 300 xvfb-run -a -s "-screen 0 1672x941x24" godot --path "$ROOT" --rendering-driver opengl3 \
  --resolution 1672x941 --audio-driver Dummy -- --shot="$PRESET" --out="$OUT" 2>&1 \
  | grep -vE "ALSA|alsa|set_use_vsync|^\s*at:|^$" || true
test -f "$OUT" && echo "OK $OUT"
