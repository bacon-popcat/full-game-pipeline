#!/usr/bin/env bash
# usage: agy_grade.sh <sheet dir> [NNNN ...]
# Grades each p_NNNN.jpg with agy.exe directly (no MCP hop, so no MCP request timeout),
# one at a time, writing agy_NNNN.txt next to the sheets. Retries a failed or empty answer once.
# Set AGY_QUESTION to replace the default question (written for LavaEruption sheets); keep
# "Start your answer with 'SCORE: x/10'" in it so the retry check works.
# Set AGY_MODEL to grade with another model (id or name from `agy models`).
D="$1"; shift
AGY=/c/Users/oscar/AppData/Local/agy/bin/agy.exe
MODEL="${AGY_MODEL:-gemini-4-argon-high}"
DEFAULT_Q="You are a strict but calibrated VFX grader. This image is one timestamp of a Roblox lava-eruption effect: left = REFERENCE video frame, right = OUR recreation; top row = front camera, bottom row = angled camera (cameras matched; cyan grid posts every 5 studs, ticks every 2). Ignore background/sky/ground colour, the mouse cursor and the moon; the thin dark branching lines on the ground are an intentional crack decal the reference also has. Score out of 10 (9-10 hard to tell apart, 7-8 same effect with clear differences, 5-6 recognisably similar but off in major ways, 3-4 different). Start your answer with 'SCORE: x/10'. Say whether ours has any ring/sticker artifact. List the top 3 concrete differences with approximate stud sizes. Answer directly, concisely."
Q="${AGY_QUESTION:-$DEFAULT_Q}"
ids="$*"
[ -z "$ids" ] && ids=$(ls "$D" | sed -n 's/^p_\([0-9]*\)\.jpg$/\1/p')
for n in $ids; do
  out="$D/agy_$n.txt"
  for try in 1 2; do
    start=$(date +%s)
    "$AGY" --add-dir "$D" --print-timeout 300s --model "$MODEL" -p "Read and analyze these files:
- $D/p_$n.jpg

Question: $Q" > "$out" 2>/dev/null
    code=$?
    if [ $code -eq 0 ] && grep -q "SCORE" "$out"; then break; fi
  done
  echo "$n: exit $code, $(( $(date +%s) - start ))s, $(grep -m1 -o 'SCORE: *[0-9.]*/10' "$out")"
done
