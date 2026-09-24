#!/bin/sh
# capture-emergency-ssh.sh - exercise the emergency SSH fallback in
# lib/ssh_safety.sh and record how test_ssh_config behaves next to it: on
# its own default port, and when both are pointed at the same port.
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
    echo "=== 2. which setting starts the emergency sshd"
    grep -n "ENABLE_EMERGENCY_SSH\|ENABLE_EMERGENCY_ACCESS" config/defaults.conf \
        | sed "s/^/    /" || echo "    neither is in config/defaults.conf"
    echo "    the gate in scripts/01-ssh-hardening.sh:"
    grep -n "ENABLE_EMERGENCY_SSH:-0" scripts/01-ssh-hardening.sh \
        | sed "s/^/      /"
    echo "    value seen by a script after sourcing the config:"
    ( . ./config/defaults.conf
      echo "      ENABLE_EMERGENCY_SSH=[${ENABLE_EMERGENCY_SSH:-}]" )

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
    echo "=== 4. test_ssh_config on its default port while the emergency daemon holds 2222"
    cp /etc/ssh/sshd_config /tmp/candidate
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        echo \"    test port: \$SSHD_TEST_PORT\"
        # common.sh sets -e; keep the shell alive to print the status
        test_ssh_config /tmp/candidate && rc=0 || rc=\$?
        echo \"    test_ssh_config returned: \$rc\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"

    echo
    echo "=== 4b. the same test pointed at 2222, the port the emergency daemon holds"
    echo "    listeners before the test:"
    ss -ltnp 2>/dev/null | grep ":2222" | sed "s/^/      /"
    LIB_DIR=/opt/posix-hardening/lib SSHD_TEST_PORT=2222 sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        # common.sh sets -e; keep the shell alive to print the status
        test_ssh_config /tmp/candidate && rc=0 || rc=\$?
        echo \"    test_ssh_config returned: \$rc\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"

    echo
    echo "=== 5. why the test also checks the pid file: a test sshd started by"
    echo "===    hand on the taken port"
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
    echo "=== 6. the test on 2222 once the port is free"
    kill "$(cat /var/run/sshd_emergency.pid 2>/dev/null)" 2>/dev/null || true
    sleep 1
    ss -ltn 2>/dev/null | grep -q ":2222" \
        && echo "    2222 still held" || echo "    2222 is free"
    LIB_DIR=/opt/posix-hardening/lib SSHD_TEST_PORT=2222 sh -c "
        . ./config/defaults.conf
        . lib/common.sh
        . lib/ssh_safety.sh
        # common.sh sets -e; keep the shell alive to print the status
        test_ssh_config /tmp/candidate && rc=0 || rc=\$?
        echo \"    test_ssh_config returned: \$rc\"
    " 2>&1 | sed "s/\x1b\[[0-9;]*m//g" | sed "s/^/    /"
' > "$OUT" 2>&1 || true

echo "capture written to $OUT"
cat "$OUT"
