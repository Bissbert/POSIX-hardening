#!/bin/sh
# capture-rollback-coverage.sh - which scripts actually use the rollback API.
#
# Read-only: this greps the repository and runs nothing. Run it through
# tools/host-tools-env.sh so it executes in a Linux container.
#
# lib/rollback.sh offers register_* functions that push undo actions onto the
# transaction stack, and track_* helpers that record the current state and
# register the matching undo action. A transaction that is opened but never
# registers anything rolls back to nothing. This counts both sides per script.
# That the undo actions put the system back is tested separately, in
# tests/regression/rollback-coverage.sh.
#
# Output: media/captures/rollback-coverage.txt
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/media/captures/rollback-coverage.txt"
mkdir -p "$ROOT/media/captures"
cd "$ROOT"

{
    echo "=== 1. the rollback API lib/rollback.sh exports"
    grep -oE '^[a-z_]+\(\)' lib/rollback.sh | tr -d '()' | sed 's/^/      /'

    echo
    echo "=== 2. transaction, register and track calls, per script"
    printf '    %-26s %5s %6s %8s %6s\n' \
        script begin commit register track
    _b=0; _c=0; _g=0; _t=0; _n=0; _opens=0; _none=""
    for s in scripts/*.sh; do
        _sb=$(grep -c '\bbegin_transaction\b' "$s" || true)
        _sc=$(grep -c '\bcommit_transaction\b' "$s" || true)
        _sg=$(grep -cE '\bregister_[a-z_]+_rollback\b' "$s" || true)
        _st=$(grep -cE '\btrack_[a-z_]+ ' "$s" || true)
        printf '    %-26s %5s %6s %8s %6s\n' \
            "$(basename "$s")" "$_sb" "$_sc" "$_sg" "$_st"
        _b=$((_b + _sb)); _c=$((_c + _sc))
        _g=$((_g + _sg)); _t=$((_t + _st)); _n=$((_n + 1))
        [ "$_sb" -gt 0 ] && _opens=$((_opens + 1))
        [ $((_sg + _st)) -eq 0 ] && _none="$_none $(basename "$s")"
    done
    printf '    %-26s %5s %6s %8s %6s\n' "TOTAL over $_n scripts" \
        "$_b" "$_c" "$_g" "$_t"

    echo
    echo "=== 3. summary"
    echo "    scripts in scripts/:                     $_n"
    echo "    scripts that open a transaction:         $_opens"
    echo "    register_* calls in scripts/:            $_g"
    echo "    track_* calls in scripts/:               $_t"
    echo "    scripts that register nothing:          ${_none:- (none)}"

    echo
    echo "=== 4. what lib/ssh_safety.sh registers on its own account"
    grep -n 'register_[a-z_]*_rollback\|track_[a-z_]* ' lib/ssh_safety.sh \
        | sed 's/^/      /' || echo "      (none)"
} > "$OUT" 2>&1

echo "wrote $OUT"
