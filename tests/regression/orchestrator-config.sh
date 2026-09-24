#!/bin/sh
# Issue #13: orchestrator.sh must start when config/defaults.conf exists.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1
check "config/defaults.conf exists (as quick-start.sh leaves it)" \
    test -f config/defaults.conf

out=$(sh orchestrator.sh --status 2>&1); rc=$?
check_eq "orchestrator.sh --status exits 0 with a config file" "0" "$rc"
check "no read-only error" lacks_line "$out" "read only"
check "status table is printed" has_line "$out" "20-integrity-baseline.sh"

# The config file is really loaded: a value only the file sets reaches the
# orchestrator.
sed -i 's|^LOG_DIR=.*|LOG_DIR="/var/log/hardening-from-config"|' config/defaults.conf
sh orchestrator.sh --status >/dev/null 2>&1
check "LOG_DIR from the config file is used" \
    sh -c 'ls /var/log/hardening-from-config/hardening-*.log >/dev/null 2>&1'

finish
