#!/bin/sh
# analysis-env.sh - run tools/static-analysis.sh inside a throwaway container.
#
# Nothing is installed on the host. The container is a plain debian:12-slim
# with the five analysers the CI uses, and it is removed when the run ends.
#
# Usage: sh tools/analysis-env.sh

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=posix-hardening-analysis:local

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required" >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "building $IMAGE ..." >&2
    docker build -t "$IMAGE" -f - "$ROOT" >&2 <<'DOCKEREOF'
FROM debian:12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      dash bash busybox shellcheck devscripts git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
DOCKEREOF
fi

docker run --rm -v "$ROOT:/src:ro" "$IMAGE" \
    sh -c 'git config --global --add safe.directory /src; sh /src/tools/static-analysis.sh /src'
