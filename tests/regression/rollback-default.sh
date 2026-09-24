#!/bin/sh
# Issue #12: without config/defaults.conf, ROLLBACK_ENABLED must default to 1
# so a failing transaction is rolled back.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1
rm -f config/defaults.conf
unset ROLLBACK_ENABLED
LIB_DIR="$TOOLKIT/lib"; export LIB_DIR

val=$(sh -c '. lib/common.sh; . lib/backup.sh; . lib/rollback.sh; echo "$ROLLBACK_ENABLED"' 2>/dev/null)
check_eq "ROLLBACK_ENABLED defaults to 1 without a config file" "1" "$val"

# A transaction that changes a file and then fails must restore the file.
failing_transaction() {
    echo original > /tmp/rb-target
    sh -c '
        . lib/common.sh; . lib/backup.sh; . lib/rollback.sh
        begin_transaction rb_test
        cp -p /tmp/rb-target /tmp/rb-target.bak
        register_file_rollback /tmp/rb-target /tmp/rb-target.bak
        echo changed > /tmp/rb-target
        exit 1
    ' >/tmp/rb-out 2>&1
    cat /tmp/rb-target
}

check_eq "failing transaction restores the file with no config" \
    "original" "$(failing_transaction)"
check "rollback is logged" grep -q "initiating rollback" /tmp/rb-out

# Switching it off explicitly still works.
check_eq "ROLLBACK_ENABLED=0 still disables rollback" \
    "changed" "$(ROLLBACK_ENABLED=0; export ROLLBACK_ENABLED; failing_transaction)"

finish
