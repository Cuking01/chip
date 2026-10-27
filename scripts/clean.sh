#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if [[ $# -eq 0 ]]; then
  rm -rf "$root/build"/* "$root/runs"/*
  echo "Removed generated build/ and runs/ contents; pdks/ was retained."
else
  design=$1
  rm -rf "$root/build/$design" "$root/runs/$design"
  echo "Removed generated outputs for $design; pdks/ was retained."
fi
