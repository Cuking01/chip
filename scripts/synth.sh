#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/synth.sh DESIGN}
root=$(cd "$(dirname "$0")/.." && pwd)
rtl="$root/designs/$design/rtl"
out="$root/build/$design"
top_file="$rtl/$design.sv"

[[ -f $top_file ]] || { echo "Expected top-level file: $top_file" >&2; exit 2; }
mkdir -p "$out"

docker compose -f "$root/compose.yml" run --rm rtl yosys -p \
  "read_verilog -sv /workspace/designs/$design/rtl/*.sv; hierarchy -check -top $design; proc; opt; stat; write_json /workspace/build/$design/$design.json"
