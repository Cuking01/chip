#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/toolchain"
mkdir -p "$out"
compose=(docker compose -f "$root/compose.yml" run --rm)

"${compose[@]}" rtl python3 /workspace/tests/test_prepare_sv.py

"${compose[@]}" rtl iverilog -g2012 -Wall -s toolchain_tb \
  -o /workspace/build/toolchain/check.vvp \
  /workspace/designs/cucpu/rtl/common.sv /workspace/tests/toolchain.sv
"${compose[@]}" rtl vvp /workspace/build/toolchain/check.vvp

if ! "${compose[@]}" rtl yosys -Q -T -p \
  'read_slang /workspace/designs/cucpu/rtl/common.sv /workspace/tests/toolchain.sv --top toolchain_probe; proc; opt; check -assert; write_verilog /workspace/build/toolchain/probe.v' \
  > "$out/synthesis.log" 2>&1; then
  cat "$out/synthesis.log"
  exit 1
fi

# Run the same behavioral checks on Verilog emitted by the new frontend.
"${compose[@]}" rtl iverilog -g2012 -Wall -DTOOLCHAIN_LOWERED_TEST \
  -s toolchain_tb -o /workspace/build/toolchain/lowered.vvp \
  /workspace/designs/cucpu/rtl/common.sv \
  /workspace/build/toolchain/probe.v /workspace/tests/toolchain.sv
"${compose[@]}" rtl vvp /workspace/build/toolchain/lowered.vvp

# Check that the existing OpenLane Yosys can consume the lowered design.
if ! "${compose[@]}" openlane yosys -Q -T -p \
  'read_verilog /workspace/build/toolchain/probe.v; hierarchy -check -top toolchain_probe; proc; opt; check -assert' \
  > "$out/openlane-reader.log" 2>&1; then
  cat "$out/openlane-reader.log"
  exit 1
fi
echo "PASS: slang synthesis and OpenLane Verilog reader"

"$root/scripts/sim.sh" hello_rtl
if ! "$root/scripts/synth.sh" hello_rtl > "$out/hello-synthesis.log" 2>&1; then
  cat "$out/hello-synthesis.log"
  exit 1
fi
echo "PASS: hello_rtl simulation and synthesis"
