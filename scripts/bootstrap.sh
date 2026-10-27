#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "Docker Engine and the Docker Compose plugin are required on the host." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^LOCAL_UID=.*/LOCAL_UID=$(id -u)/" .env
  sed -i "s/^LOCAL_GID=.*/LOCAL_GID=$(id -g)/" .env
  echo "Created .env for UID:GID $(id -u):$(id -g)."
fi

mkdir -p build runs reports pdks
chmod u+rwx,g+rwx build runs reports pdks

echo "Environment prepared. Build tools with: make images"
