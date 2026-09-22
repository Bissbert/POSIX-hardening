#!/bin/sh
# capture-rollback-coverage.sh - which scripts actually use the rollback API.
#
# Host-only, read-only: this greps the repository and runs nothing.
#
# lib/rollback.sh offers five register_* functions that push undo actions onto
# the transaction stack. A transaction that is opened but never registers
# anything rolls back to nothing. This counts both sides per script.
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
    echo "=== 2. transaction and register calls, per script"
    printf '    %-26s %5s %6s %8s %8s\n' \
        script begin commit rollback register
    _b=0; _c=0; _r=0; _g=0; _n=0; _opens=0
    for s in scripts/*.sh; do
        _sb=$(grep -c '\bbegin_transaction\b' "$s" || true)
        _sc=$(grep -c '\bcommit_transaction\b' "$s" || true)
        _sr=$(grep -c '\brollback_transaction\b' "$s" || true)
        _sg=$(grep -cE '\bregister_[a-z_]+_rollback\b' "$s" || true)
        printf '    %-26s %5s %6s %8s %8s\n' \
            "$(basename "$s")" "$_sb" "$_sc" "$_sr" "$_sg"
        _b=$((_b + _sb)); _c=$((_c + _sc))
        _r=$((_r + _sr)); _g=$((_g + _sg)); _n=$((_n + 1))
        [ "$_sb" -gt 0 ] && _opens=$((_opens + 1))
    done
    printf '    %-26s %5s %6s %8s %8s\n' "TOTAL over $_n scripts" \
        "$_b" "$_c" "$_r" "$_g"

    echo
    echo "=== 3. summary"
    echo "    scripts in scripts/:                     $_n"
    echo "    scripts that open a transaction:         $_opens"
    echo "    register_* calls in all of scripts/:     $_g"
    echo "    the one script that registers anything, and what:"
    grep -rn 'register_[a-z_]*_rollback' scripts/ | sed 's/^/      /'

    echo
    echo "=== 4. the other way a script could give rollback something to do"
    echo "    safe_backup_file calls in scripts/:"
    grep -rn 'safe_backup_file' scripts/ | sed 's/^/      /' \
        || echo "      (none)"
    echo "    register_* callers anywhere outside lib/:"
    grep -rn 'register_[a-z_]*_rollback' scripts/ orchestrator.sh \
        quick-start.sh emergency-rollback.sh tests/ 2>/dev/null \
        | sed 's/^/      /' || echo "      (none)"

    echo
    echo "=== 5. what lib/ssh_safety.sh registers on its own account"
    grep -n 'register_[a-z_]*_rollback\|safe_backup_file' lib/ssh_safety.sh \
        | sed 's/^/      /' || echo "      (none)"
} > "$OUT" 2>&1

echo "wrote $OUT"
