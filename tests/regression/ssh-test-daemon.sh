#!/bin/sh
# Issue #17: test_ssh_config must only pass when the daemon it started is the
# one answering on the test port, and must fail closed when the port is taken.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1
LIB_DIR="$TOOLKIT/lib"; export LIB_DIR
rm -f config/defaults.conf

run_test_ssh_config() {
    sh -c '
        . lib/common.sh; . lib/backup.sh; . lib/rollback.sh; . lib/ssh_safety.sh
        test_ssh_config "$1"
    ' _ "$1" >/tmp/tsc.out 2>&1
    echo $?
}

# The emergency daemon, on its default port 2222.
sh -c '. lib/common.sh; . lib/ssh_safety.sh; create_emergency_ssh_access' >/dev/null 2>&1
check "emergency sshd listens on 2222" sh -c 'ss -ltn | grep -q ":2222 "'

port=$(sh -c '. lib/common.sh; . lib/ssh_safety.sh; echo "$SSHD_TEST_PORT"' 2>/dev/null)
check "default test port differs from the emergency port" [ "$port" != "2222" ]

# A candidate that parses but cannot serve: it listens on an address this
# host does not have, so the test daemon exits right after forking.
cp /etc/ssh/sshd_config /tmp/candidate-bad
echo "ListenAddress 192.0.2.1" >> /tmp/candidate-bad
check "candidate passes the syntax check" /usr/sbin/sshd -t -f /tmp/candidate-bad
check_eq "a candidate whose daemon cannot start is rejected" \
    "1" "$(run_test_ssh_config /tmp/candidate-bad)"

# A good candidate still passes, with the emergency daemon running, and the
# test daemon is gone afterwards.
cp /etc/ssh/sshd_config /tmp/candidate-good
check_eq "a working candidate is accepted" "0" "$(run_test_ssh_config /tmp/candidate-good)"
check "the test daemon was stopped" sh -c "! ss -ltn | grep -q \":$port \""
check "the emergency daemon is untouched" sh -c 'ss -ltn | grep -q ":2222 "'

# Something unrelated already holds the test port: fail closed.
nc -l 127.0.0.1 2299 >/dev/null 2>&1 &
nc_pid=$!
sleep 1
out=$(SSHD_TEST_PORT=2299; export SSHD_TEST_PORT; run_test_ssh_config /tmp/candidate-good)
check_eq "a busy test port makes the check fail" "1" "$out"
check "the reason is logged" grep -q "already in use" /tmp/tsc.out
kill "$nc_pid" 2>/dev/null

finish
