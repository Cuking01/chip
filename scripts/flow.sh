#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/flow.sh DESIGN [OPENLANE_OPTIONS...]}
shift
root=$(cd "$(dirname "$0")/.." && pwd)
config="$root/designs/$design/config/config.json"

[[ -f $config ]] || { echo "Expected OpenLane config: $config" >&2; exit 2; }
tag=$(date +%Y%m%d-%H%M%S)
run_dir="$root/runs/$design/$tag"
out="$root/build/$design"
mkdir -p "$run_dir" "$root/pdks" "$out"

# Resolve the original config in OpenLane, then lower its selected SV sources
# with the upgraded frontend. Keep all other OpenLane settings unchanged.
docker compose -f "$root/compose.yml" run --rm openlane \
  python3 /workspace/scripts/prepare_flow.py \
  "/workspace/designs/$design/config/config.json" "/workspace/build/$design/flow-sources.f"
docker compose -f "$root/compose.yml" run --rm rtl yosys -p \
  "read_slang -f /workspace/build/$design/flow-sources.f; proc; opt; write_verilog /workspace/build/$design/$design.flow.v"

# OpenLane manages PDK acquisition under PDK_ROOT on its first run.
# The exact PDK download can be sizable; it remains in ./pdks and is ignored by Git.
docker compose -f "$root/compose.yml" run --rm openlane \
  openlane "/workspace/designs/$design/config/config.json" \
  --override-config "VERILOG_FILES=/workspace/build/$design/$design.flow.v" \
  --override-config 'SYNTH_PARAMETERS=' \
  --run-tag "$tag" \
  --force-run-dir "/workspace/runs/$design/$tag" \
  "$@"
