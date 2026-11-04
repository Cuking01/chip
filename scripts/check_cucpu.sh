#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/cucpu-check"
mkdir -p "$out"
compose=(docker compose -f "$root/compose.yml" run --rm -T)

# Slang supports the queue's dynamically indexed packed-struct arrays. Lower
# the complete RTL to Verilog, then simulate it using the SV testbench.
if ! "${compose[@]}" rtl python3 /workspace/scripts/prepare_sv.py \
  --output /workspace/build/cucpu-check/preprocessed \
  --filelist /workspace/build/cucpu-check/sources.f \
  /workspace/designs/cucpu/rtl/common.sv \
  /workspace/designs/cucpu/rtl/alu/iadd.sv \
  /workspace/designs/cucpu/rtl/alu/shl.sv \
  /workspace/designs/cucpu/rtl/alu/shr.sv \
  /workspace/designs/cucpu/rtl/executor_alu.sv \
  /workspace/designs/cucpu/rtl/issuer.sv \
  /workspace/designs/cucpu/rtl/regfile.sv \
  /workspace/designs/cucpu/rtl/operand_resolver.sv \
  /workspace/designs/cucpu/rtl/commit_queue.sv \
  /workspace/designs/cucpu/rtl/fetcher.sv \
  /workspace/designs/cucpu/rtl/cucpu.sv > "$out/preprocess.log" 2>&1; then
  cat "$out/preprocess.log"
  exit 1
fi
if ! "${compose[@]}" rtl yosys -Q -T -p \
  'read_slang -f /workspace/build/cucpu-check/sources.f --top cucpu; proc; opt; check -assert; write_verilog /workspace/build/cucpu-check/cucpu.v' \
  > "$out/synthesis.log" 2>&1; then
  cat "$out/synthesis.log"
  exit 1
fi
echo "PASS: cucpu synthesis and structural check"

if ! "${compose[@]}" rtl iverilog -g2012 -Wall -s cucpu_tb \
  -o /workspace/build/cucpu-check/check.vvp \
  /workspace/designs/cucpu/rtl/common.sv \
  /workspace/build/cucpu-check/cucpu.v \
  /workspace/tests/cucpu_tb.sv > "$out/compile.log" 2>&1; then
  cat "$out/compile.log"
  exit 1
fi
"${compose[@]}" rtl vvp /workspace/build/cucpu-check/check.vvp
