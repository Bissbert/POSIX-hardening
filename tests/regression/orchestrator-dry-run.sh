#!/bin/sh
# Issue #14: orchestrator.sh --dry-run must work and must reach the scripts it
# runs, even though config/defaults.conf says DRY_RUN=0.
. "$(dirname "$0")/lib.sh"
cd "$TOOLKIT" || exit 1
check "config file says DRY_RUN=0" grep -q '^DRY_RUN=0' config/defaults.conf

chmod 644 /etc/shadow
out=$(sh orchestrator.sh --dry-run --script 05-file-permissions.sh 2>&1); rc=$?
check_eq "orchestrator.sh --dry-run --script exits 0" "0" "$rc"
check "no read-only error" lacks_line "$out" "read only"
check "the script ran in simulation mode" has_line "$out" "DRY-RUN\] Would secure file permissions"
check_eq "/etc/shadow was not changed" "644" "$(mode_of /etc/shadow)"

out=$(sh orchestrator.sh -n --status 2>&1); rc=$?
check_eq "orchestrator.sh -n --status exits 0" "0" "$rc"

# Menu option 8 switches to dry-run mode instead of dying.
out=$(printf '8\n7\n\n0\n' | sh orchestrator.sh 2>&1); rc=$?
check_eq "interactive option 8 then exit returns 0" "0" "$rc"
check "option 8 does not hit the read-only error" lacks_line "$out" "read only"
check "option 8 announces dry-run mode" has_line "$out" "DRY-RUN mode"

finish
