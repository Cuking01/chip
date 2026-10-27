#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/sim.sh DESIGN}
root=$(cd "$(dirname "$0")/.." && pwd)
rtl="$root/designs/$design/rtl"
tb="$root/designs/$design/tb"
out="$root/build/$design"

[[ -d $rtl && -d $tb ]] || { echo "Unknown design: $design" >&2; exit 2; }
mkdir -p "$out"

mapfile -t sources < <(find "$rtl" "$tb" -maxdepth 1 -type f \( -name '*.v' -o -name '*.sv' \) | sort)
(( ${#sources[@]} )) || { echo "No Verilog sources for $design" >&2; exit 2; }

docker compose -f "$root/compose.yml" run --rm rtl \
  iverilog -g2012 -Wall -s "${design}_tb" -o "/workspace/build/$design/$design.vvp" \
  "${sources[@]/$root/\/workspace}"
docker compose -f "$root/compose.yml" run --rm rtl \
  vvp "/workspace/build/$design/$design.vvp"
