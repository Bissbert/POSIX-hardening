#!/bin/sh
# host-tools-env.sh - run one of the read-only capture tools inside a
# throwaway Debian container instead of on the workstation.
#
# capture-ansible.sh, capture-team-keys.sh and capture-rollback-coverage.sh
# only parse files and work in a temporary clone, but running them here pins
# the tool versions and keeps every recorded transcript on Linux. Nothing is
# installed on the host.
#
# Usage: sh tools/host-tools-env.sh capture-ansible.sh
#        sh tools/host-tools-env.sh capture-team-keys.sh
#        sh tools/host-tools-env.sh capture-rollback-coverage.sh

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=posix-hardening-hosttools:local
TOOL="${1:?usage: host-tools-env.sh <tool in tools/>}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "building $IMAGE ..." >&2
    docker build -t "$IMAGE" -f - "$ROOT" >&2 <<'DOCKEREOF'
FROM python:3.12-slim-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends git openssh-client \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir ansible-core==2.19.3 ansible-lint==25.9.2
COPY ansible/collections/requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml \
      -p /usr/share/ansible/collections
ENV ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections
WORKDIR /src
DOCKEREOF
fi

# The repository is mounted read-only; only media/captures/ is writable, so
# neither ansible nor ansible-lint can leave files behind in the checkout.
docker run --rm -v "$ROOT:/src:ro" -v "$ROOT/media/captures:/src/media/captures" \
    -e ANSIBLE_LOG_PATH=/tmp/ansible.log "$IMAGE" \
    sh -c "git config --global --add safe.directory /src; sh /src/tools/$TOOL"
