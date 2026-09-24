#!/bin/sh
# tests/docker.sh - run the regression tests in throwaway Linux containers.
#
# Each file in tests/regression/ runs in its own fresh posix-hardening-target
# container (tools/capture-lib.sh), so one test's changes cannot leak into
# another. Nothing runs on the host except docker.
#
# Usage:
#   sh tests/docker.sh              run every test
#   sh tests/docker.sh rollback     run tests whose file name contains "rollback"
#
# TARGET_ROOT=<checkout> runs these tests against another checkout of the
# toolkit, for example one with a fix reverted, to show that a test fails
# without its fix.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_ROOT="${TARGET_ROOT:-$ROOT}"
. "$ROOT/tools/capture-lib.sh"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required" >&2
    exit 1
fi

files=""
for f in "$ROOT"/tests/regression/*.sh; do
    name=$(basename "$f" .sh)
    [ "$name" = "lib" ] && continue
    if [ $# -gt 0 ]; then
        match=0
        for pat in "$@"; do
            case "$name" in *"$pat"*) match=1 ;; esac
        done
        [ $match -eq 1 ] || continue
    fi
    files="$files $name"
done

total_pass=0
total_fail=0
failed_files=""
for name in $files; do
    c="ph-regression-$$-$name"
    capture_start "$TARGET_ROOT" "$c"
    # Always run the tests from this checkout, whatever TARGET_ROOT is.
    docker exec "$c" rm -rf /opt/posix-hardening/tests
    docker cp "$ROOT/tests" "$c:/opt/posix-hardening/tests" >/dev/null
    echo "=== $name"
    set +e
    out=$(docker exec -w /opt/posix-hardening "$c" sh "tests/regression/$name.sh" 2>&1)
    rc=$?
    set -e
    capture_stop "$c"
    printf '%s\n' "$out" | sed 's/^/    /'
    p=$(printf '%s\n' "$out" | grep -c '^ok - ' || true)
    n=$(printf '%s\n' "$out" | grep -c '^not ok - ' || true)
    total_pass=$((total_pass + p))
    total_fail=$((total_fail + n))
    if [ $rc -ne 0 ] || [ "$n" -gt 0 ]; then
        failed_files="$failed_files $name"
        [ "$n" -gt 0 ] || total_fail=$((total_fail + 1))
    fi
done

echo "=== summary: $total_pass passed, $total_fail failed"
if [ -n "$failed_files" ]; then
    echo "failed:$failed_files"
    exit 1
fi
