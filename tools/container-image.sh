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

docker build -t "$IMAGE" -f "$ROOT/ansible/testing/Dockerfile" \
    "$ROOT/ansible/testing"
echo "built $IMAGE"
