#!/usr/bin/env bash
set -euo pipefail

design=${1:?usage: scripts/flow.sh DESIGN}
root=$(cd "$(dirname "$0")/.." && pwd)
config="$root/designs/$design/config/config.json"

[[ -f $config ]] || { echo "Expected OpenLane config: $config" >&2; exit 2; }
tag=$(date +%Y%m%d-%H%M%S)
run_dir="$root/runs/$design/$tag"
mkdir -p "$run_dir" "$root/pdks"

# OpenLane manages PDK acquisition under PDK_ROOT on its first run.
# The exact PDK download can be sizable; it remains in ./pdks and is ignored by Git.
docker compose -f "$root/compose.yml" run --rm openlane \
  openlane "/workspace/designs/$design/config/config.json" \
  --run-tag "$tag" \
  --force-run-dir "/workspace/runs/$design/$tag"
