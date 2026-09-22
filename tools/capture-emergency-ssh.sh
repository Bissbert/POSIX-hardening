#!/bin/sh
# capture-emergency-ssh.sh - exercise the emergency SSH fallback in
# lib/ssh_safety.sh and record what it does to the test daemon that
# test_ssh_config wants to start on the same port.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-emergency-ssh.sh [outfile]
# Default outfile: media/captures/emergency-ssh.txt

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/emergency-ssh.txt}"
CNAME="ph-emergency-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$(dirname "$OUT")"
trap 'capture_stop "$CNAME"' EXIT INT TERM
capture_start "$ROOT" "$CNAME" >/dev/null

docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening

    echo "=== 1. the two ports the toolkit defaults to"
    grep -n "SSHD_TEST_PORT:-" lib/ssh_safety.sh | sed "s/^/    /"
    grep -n "^EMERGENCY_SSH_PORT" config/defaults.conf | sed "s/^/    /"
    grep -n "ssh_test_port:\|emergency_ssh_port:" ansible/group_vars/all.yml \
        | sed "s/^/    /"

    echo
    echo "=== 2. is ENABLE_EMERGENCY_ACCESS set by config/defaults.conf"
    if grep -q "ENABLE_EMERGENCY_ACCESS" config/defaults.conf; then
        grep -n "ENABLE_EMERGENCY_ACCESS" config/defaults.conf | sed "s/^/    /"
    else
        echo "    not present in config/defaults.conf"
    fi
    echo "    the gate in scripts/01-ssh-hardening.sh:"
    grep -n "ENABLE_EMERGENCY_ACCESS" scripts/01-ssh-hardening.sh \
        | sed "s/^/      /"
    echo "    value seen by a script after sourcing the config:"
    ( . ./config/defaults.conf
      echo "      ENABLE_EMERGENCY_ACCESS=[${ENABLE_EMERGENCY_ACCESS:-}]" )

    echo
    echo "=== 3. create_emergency_ssh_access 2222"
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        create_emergency_ssh_access 2222
        echo \"    returned: \$?\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"
    echo "    listening on 2222:"
    ss -ltn 2>/dev/null | grep ":2222" | sed "s/^/      /" \
        || echo "      nothing"

    echo
    echo "=== 4. what test_ssh_config does while the emergency daemon holds 2222"
    echo "    listeners before the test:"
    ss -ltnp 2>/dev/null | grep ":2222" | sed "s/^/      /"
    cp /etc/ssh/sshd_config /tmp/candidate
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        test_ssh_config /tmp/candidate
        echo \"    test_ssh_config returned: \$?\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"
    echo "    listeners after the test:"
    ss -ltnp 2>/dev/null | grep ":2222" | sed "s/^/      /"
    echo "    /var/run/sshd_test.pid:"
    ls -l /var/run/sshd_test.pid 2>&1 | sed "s/^/      /"

    echo
    echo "=== 5. the same start, run by hand, so its exit status is visible"
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        create_ssh_test_config /tmp/candidate.test 2222 >/dev/null
    " 2>/dev/null
    echo "    the port and pid file the test config asks for:"
    tail -2 /tmp/candidate.test | sed "s/^/      /"
    /usr/sbin/sshd -f /tmp/candidate.test
    echo "    /usr/sbin/sshd -f exit status: $?"
    sleep 1
    echo "    listeners on 2222 afterwards:"
    ss -ltnp 2>/dev/null | grep ":2222" | sed "s/^/      /"
    echo "    /var/run/sshd_test.pid:"
    ls -l /var/run/sshd_test.pid 2>&1 | sed "s/^/      /"
    rm -f /tmp/candidate.test

    echo
    echo "=== 6. the same test with port 2222 free"
    kill "$(cat /var/run/sshd_emergency.pid 2>/dev/null)" 2>/dev/null || true
    sleep 1
    ss -ltn 2>/dev/null | grep -q ":2222" \
        && echo "    2222 still held" || echo "    2222 is free"
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        test_ssh_config /tmp/candidate
        echo \"    test_ssh_config returned: \$?\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"
' > "$OUT" 2>&1 || true

echo "capture written to $OUT"
cat "$OUT"
