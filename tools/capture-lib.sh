#!/bin/sh
# capture-lib.sh - shared helpers for the capture tools in this directory.
# Sourced, not executed.
#
# WARNING: everything here targets a throwaway Docker container. Never point
# these tools at a real host: the hardening scripts rewrite sshd_config,
# sysctl settings, PAM configuration and firewall rules in place.

CAPTURE_IMAGE="${IMAGE:-posix-hardening-target:local}"

# Build the target image if it is not already present.
capture_ensure_image() {
    docker image inspect "$CAPTURE_IMAGE" >/dev/null 2>&1 && return 0
    sh "$1/tools/container-image.sh"
}

# capture_start <repo-root> <container-name>
#
# Starts a container with sshd running, copies the repository into it and
# creates config/defaults.conf from the shipped template. The source is run
# as committed; the repository itself is never modified.
capture_start() {
    _root="$1"
    _name="$2"

    capture_ensure_image "$_root"

    docker run -d --name "$_name" --privileged --entrypoint /bin/sh \
        "$CAPTURE_IMAGE" -c 'mkdir -p /run/sshd && /usr/sbin/sshd && sleep 3600' \
        >/dev/null
    sleep 2
    docker cp "$_root/." "$_name:/opt/posix-hardening" >/dev/null

    docker exec "$_name" sh -c '
        cd /opt/posix-hardening
        cp config/defaults.conf.template config/defaults.conf
        # SSH_ALLOW_USERS must name a user that exists or the run locks the
        # container out of its own account.
        sed -i "s/^SSH_ALLOW_USERS=.*/SSH_ALLOW_USERS=\"ansible\"/" \
            config/defaults.conf
    '
    unset _root _name
}

capture_stop() {
    docker rm -f "$1" >/dev/null 2>&1 || true
}
