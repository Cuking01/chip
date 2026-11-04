#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  '') variant=cucpu-check ;;
  --small-queue) variant=cucpu-check-small-queue ;;
  *) echo "usage: $0 [--small-queue]" >&2; exit 2 ;;
esac
out="$root/build/$variant"
container_out="/workspace/build/$variant"
mkdir -p "$out"
compose=(docker compose -f "$root/compose.yml" run --rm -T)
common=/workspace/designs/cucpu/rtl/common.sv

if [[ $variant == cucpu-check-small-queue ]]; then
  # Exercise full-queue backpressure without changing the real package.
  "${compose[@]}" rtl python3 -c '
import re, sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
for name, value in (("COMMIT_SLOT_NUM", 4), ("COMMIT_SLOT_ADDR_W", 2)):
    source, count = re.subn(r"(" + name + r"\s*=\s*)\d+", lambda m: m[1] + str(value), source)
    assert count == 1, name
Path(sys.argv[2]).write_text(source)
' "$common" "$container_out/common.sv"
  common="$container_out/common.sv"
fi

# Slang supports the queue's dynamically indexed packed-struct arrays. Lower
# the complete RTL to Verilog, then simulate it using the SV testbench.
if ! "${compose[@]}" rtl python3 /workspace/scripts/prepare_sv.py \
  --output "$container_out/preprocessed" \
  --filelist "$container_out/sources.f" \
  "$common" \
  /workspace/designs/cucpu/rtl/alu/iadd.sv \
  /workspace/designs/cucpu/rtl/alu/imul.sv \
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
  "read_slang -f $container_out/sources.f --top cucpu; proc; opt; check -assert; write_verilog $container_out/cucpu.v" \
  > "$out/synthesis.log" 2>&1; then
  cat "$out/synthesis.log"
  exit 1
fi
echo "PASS: cucpu synthesis and structural check"

if ! "${compose[@]}" rtl iverilog -g2012 -Wall -s cucpu_tb \
  -o "$container_out/check.vvp" \
  "$common" \
  "$container_out/cucpu.v" \
  /workspace/tests/cucpu_tb.sv > "$out/compile.log" 2>&1; then
  cat "$out/compile.log"
  exit 1
fi
"${compose[@]}" rtl vvp "$container_out/check.vvp" "+WAVE_PATH=$container_out/cucpu.vcd"
