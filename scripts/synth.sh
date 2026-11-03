#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/synth.sh DESIGN}
root=$(cd "$(dirname "$0")/.." && pwd)
rtl="$root/designs/$design/rtl"
out="$root/build/$design"
top_file="$rtl/$design.sv"

[[ -f $top_file ]] || { echo "Expected top-level file: $top_file" >&2; exit 2; }
mkdir -p "$out"

mapfile -t sources < <(find "$rtl" -type f -name '*.sv' ! -path "$rtl/common.sv" | sort)
if [[ -f "$rtl/common.sv" ]]; then
  sources=("$rtl/common.sv" "${sources[@]}")
fi
docker compose -f "$root/compose.yml" run --rm -T rtl \
  python3 /workspace/scripts/prepare_sv.py \
  --output "/workspace/build/$design/preprocessed/synth" \
  --filelist "/workspace/build/$design/sources.f" \
  "${sources[@]/$root/\/workspace}"

docker compose -f "$root/compose.yml" run --rm rtl yosys -p \
  "read_slang -f /workspace/build/$design/sources.f --top $design; hierarchy -check -top $design; proc; opt; stat; write_json /workspace/build/$design/$design.json; write_verilog /workspace/build/$design/$design.v"
