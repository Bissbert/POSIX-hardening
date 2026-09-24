#!/bin/sh
# container-image.sh - build the throwaway target image used by the capture
# tools in this directory.
#
# The image is ansible/testing/Dockerfile with the systemd entrypoint left
# unused: the capture tools start sshd directly, because systemd inside a
# container is not needed to exercise the hardening scripts and makes the
# capture harder to read.
#
# Never point these tools at a real host. They modify /etc/ssh, /etc/sysctl.d,
# firewall rules and PAM configuration in place.
#
# Usage: sh tools/container-image.sh

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-posix-hardening-target:local}"

# The Dockerfile copies an authorized_keys file that is not tracked in git.
# Build from a temporary context with an empty one: the capture tools never
# log in over SSH, they use docker exec.
CTX="$(mktemp -d)"
trap 'rm -rf "$CTX"' EXIT INT TERM
cp "$ROOT/ansible/testing/Dockerfile" "$CTX/"
: > "$CTX/authorized_keys"
docker build -t "$IMAGE" "$CTX"
echo "built $IMAGE"
