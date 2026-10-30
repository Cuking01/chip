#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/sim.sh DESIGN}
root=$(cd "$(dirname "$0")/.." && pwd)
rtl="$root/designs/$design/rtl"
tb="$root/designs/$design/tb"
out="$root/build/$design"

[[ -d $rtl && -d $tb ]] || { echo "Unknown design: $design" >&2; exit 2; }
mkdir -p "$out"

mapfile -t sources < <(find "$rtl" "$tb" -maxdepth 1 -type f \( -name '*.v' -o -name '*.sv' \) ! -path "$rtl/common.sv" | sort)

# Read the shared package before modules and testbenches that use its types.
if [[ -f "$rtl/common.sv" ]]; then
  sources=("$rtl/common.sv" "${sources[@]}")
fi
(( ${#sources[@]} )) || { echo "No Verilog sources for $design" >&2; exit 2; }

docker compose -f "$root/compose.yml" run --rm -T rtl \
  python3 /workspace/scripts/prepare_sv.py \
  --output "/workspace/build/$design/preprocessed/sim" \
  --filelist "/workspace/build/$design/sim-sources.f" \
  --iverilog-top "${design}_tb" \
  --iverilog-output "/workspace/build/$design/$design.vvp" \
  "${sources[@]/$root/\/workspace}"

docker compose -f "$root/compose.yml" run --rm rtl \
  vvp "/workspace/build/$design/$design.vvp"
