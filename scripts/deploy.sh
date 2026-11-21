#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

usage() {
    echo 'Usage: bash scripts/deploy.sh [--build | --load IMAGE.tar | --pull]'
}
mode=${1:---build}
case "$mode" in
    --build|--pull) [[ $# -le 1 ]] || { usage >&2; exit 2; } ;;
    --load) [[ $# -eq 2 && -f $2 ]] || { usage >&2; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
command -v docker >/dev/null || { echo 'Install Docker with scripts/install-docker.sh first.' >&2; exit 1; }
docker compose version >/dev/null
docker info >/dev/null
if [[ ! -f .env ]]; then
    (umask 077; cp .env.example .env)
fi
docker compose config --quiet
case "$mode" in
    --build) docker compose build qwen ;;
    --load) docker load --input "$2" ;;
    --pull) docker compose pull qwen ;;
esac
if ! docker compose up -d --no-build --pull never --wait --wait-timeout 600; then
    docker compose ps >&2
    docker compose logs --tail 100 >&2
    echo 'Deployment did not become healthy. Inspect the logs above.' >&2
    exit 1
fi
docker compose ps
echo 'Qwen is ready. Run: bash scripts/smoke-test.sh'
