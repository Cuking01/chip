#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/imul-check"
mkdir -p "$out"
compose=(docker compose -f "$root/compose.yml" run --rm -T)

if ! "${compose[@]}" rtl python3 /workspace/scripts/prepare_sv.py \
  --output /workspace/build/imul-check/preprocessed \
  --filelist /workspace/build/imul-check/sources.f \
  --iverilog-top imul_partial_tb \
  --iverilog-output /workspace/build/imul-check/check.vvp \
  /workspace/designs/cucpu/rtl/common.sv \
  /workspace/designs/cucpu/rtl/alu/imul.sv \
  /workspace/tests/imul_partial_tb.sv > "$out/compile.log" 2>&1; then
  cat "$out/compile.log"
  exit 1
fi
"${compose[@]}" rtl vvp /workspace/build/imul-check/check.vvp

# Check the hand-written carry-select adder and the complete multiplier.
if ! "${compose[@]}" rtl yosys -Q -T -p \
  'read_slang -f /workspace/build/imul-check/sources.f --top imul_add_helper; proc; opt; check -assert' \
  > "$out/adder-synthesis.log" 2>&1; then
  cat "$out/adder-synthesis.log"
  exit 1
fi
echo "PASS: carry-select adder synthesis and structural check"
if ! "${compose[@]}" rtl yosys -Q -T -p \
  'read_slang -f /workspace/build/imul-check/sources.f --top imul; proc; opt; check -assert' \
  > "$out/synthesis.log" 2>&1; then
  cat "$out/synthesis.log"
  exit 1
fi
echo "PASS: imul synthesis and structural check"
