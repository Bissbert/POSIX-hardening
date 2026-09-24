#!/bin/sh
# tests/regression/lib.sh - assertions for the regression tests.
# Sourced by each test. Tests run as root inside a throwaway container from
# /opt/posix-hardening, never on a real host.

T_PASS=0
T_FAIL=0
TOOLKIT=/opt/posix-hardening

ok()  { T_PASS=$((T_PASS + 1)); echo "ok - $1"; }
nok() { T_FAIL=$((T_FAIL + 1)); echo "not ok - $1"; }

# check DESCRIPTION COMMAND...: passes when COMMAND exits 0
check() {
    _desc="$1"; shift
    if "$@"; then ok "$_desc"; else nok "$_desc"; fi
}

# check_eq DESCRIPTION EXPECTED ACTUAL
check_eq() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        nok "$1 (expected [$2], got [$3])"
    fi
}

# contains FILE-OR-TEXT PATTERN helpers
has_line() { printf '%s\n' "$1" | grep -q -- "$2"; }
lacks_line() { ! printf '%s\n' "$1" | grep -q -- "$2"; }

mode_of() { stat -c '%a' "$1"; }

finish() {
    echo "# $T_PASS passed, $T_FAIL failed"
    [ "$T_FAIL" -eq 0 ]
}
