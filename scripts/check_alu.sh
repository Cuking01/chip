#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/alu-check"
mkdir -p "$out"
compose=(docker compose -f "$root/compose.yml" run --rm -T)

if ! "${compose[@]}" rtl python3 /workspace/scripts/prepare_sv.py \
  --output /workspace/build/alu-check/preprocessed \
  --filelist /workspace/build/alu-check/sources.f \
  --iverilog-top executor_alu_tb \
  --iverilog-output /workspace/build/alu-check/check.vvp \
  /workspace/designs/cucpu/rtl/common.sv \
  /workspace/designs/cucpu/rtl/alu/iadd.sv \
  /workspace/designs/cucpu/rtl/alu/imul.sv \
  /workspace/designs/cucpu/rtl/alu/shl.sv \
  /workspace/designs/cucpu/rtl/alu/shr.sv \
  /workspace/designs/cucpu/rtl/executor_alu.sv \
  /workspace/tests/executor_alu_tb.sv > "$out/compile.log" 2>&1; then
  cat "$out/compile.log"
  exit 1
fi
"${compose[@]}" rtl vvp /workspace/build/alu-check/check.vvp

if ! "${compose[@]}" rtl yosys -Q -T -p \
  'read_slang -f /workspace/build/alu-check/sources.f --top executor_alu; check -assert' \
  > "$out/synthesis.log" 2>&1; then
  cat "$out/synthesis.log"
  exit 1
fi
echo "PASS: executor_alu synthesis"
