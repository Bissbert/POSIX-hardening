#!/bin/sh
# capture-orchestrator.sh - record how orchestrator.sh behaves in a throwaway
# container: with a config file present, without one, with --dry-run, with
# --script whose declared dependency has not run, with --priority, and --all
# with FAIL_FAST on and off.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-orchestrator.sh [outfile]
# Default outfile: media/captures/orchestrator.log

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/orchestrator.log}"
CNAME="ph-orchestrator-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$(dirname "$OUT")"
trap 'capture_stop "$CNAME"' EXIT INT TERM
capture_start "$ROOT" "$CNAME" >/dev/null

docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening

    # run COMMAND, then print the exit status of the orchestrator itself
    # (not of the tail/head it would otherwise be piped into).
    run() {
        _filter="$1"; shift
        "$@" >/tmp/o.txt 2>&1; _rc=$?
        eval "$_filter" </tmp/o.txt
        echo "exit=$_rc"
    }

    echo "=== 1. with config/defaults.conf present, as quick-start.sh creates it"
    run "head -3" sh orchestrator.sh --status

    echo
    echo "=== 2. same command with config/defaults.conf removed"
    rm -f config/defaults.conf
    run "tail -4" sh orchestrator.sh --status

    echo
    echo "=== 3. --dry-run"
    run "tail -2" sh orchestrator.sh --dry-run --all

    echo
    echo "=== 4. --script 02-firewall-setup.sh"
    echo "    SCRIPT_ORDER declares: 1:02-firewall-setup.sh:01-ssh-hardening.sh"
    echo "    01-ssh-hardening has NOT run:"
    grep -c . /var/lib/hardening/completed 2>/dev/null \
        || echo "    (no completion markers yet)"
    run "tail -5" sh orchestrator.sh --script 02-firewall-setup.sh

    echo
    echo "=== 5. --priority 2"
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening
    echo "    priority-2 entries in SCRIPT_ORDER:"
    grep "^2:" orchestrator.sh | sed "s/^/      /"
    echo "    no completion markers exist, so all of them are due to run:"
    run "tail -4" sh orchestrator.sh --priority 2

    echo
    echo "=== 6. --all, and what it actually ran"
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening
    sh orchestrator.sh --all </dev/null >/tmp/all.txt 2>&1
    echo "exit=$?"
    sed -i "s/\x1b\[[0-9;]*m//g" /tmp/all.txt
    echo "    where FAIL_FAST stops the run:"
    grep -A2 "Stopping execution due to failure" /tmp/all.txt \
        | sed "s/^/      /"
    echo "    scripts in SCRIPT_ORDER that were never executed:"
    sed -n "/^SCRIPT_ORDER=\"/,/^\"/p" orchestrator.sh | grep "^[0-9]:" \
        | cut -d: -f2 | sort > /tmp/declared.txt
    grep "==> Executing:" /tmp/all.txt | sed "s/.*Executing: //" | sort \
        > /tmp/ran.txt
    comm -23 /tmp/declared.txt /tmp/ran.txt | sed "s/^/      /"
    echo "    declared / executed:"
    echo "      $(wc -l </tmp/declared.txt | tr -d " ") / $(wc -l </tmp/ran.txt | tr -d " ")"
    echo "    unmet-dependency warnings during the run:"
    grep -c "Dependency not met" /tmp/all.txt | sed "s/^/      /"
    echo "    completion markers written:"
    head -2 /var/lib/hardening/completed | sed "s/^/      /"
    echo "    final summary:"
    tail -7 /tmp/all.txt | sed "s/^/      /"

    echo
    echo "=== 7. --all with FAIL_FAST=0, so one failure does not end the run"
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening
    FAIL_FAST=0 sh orchestrator.sh --all </dev/null >/tmp/all.txt 2>&1
    echo "exit=$?"
    sed -i "s/\x1b\[[0-9;]*m//g" /tmp/all.txt
    echo "    per-script result, in execution order:"
    grep -E "^(✓ Completed|✗ Failed): |^\[WARN\] Skipping " /tmp/all.txt \
        | sed "s/^/      /"
    echo "    the errors behind the two failures:"
    grep -E "^sysctl: setting key|^chmod: cannot access" /tmp/all.txt \
        | sed "s/^/      /"
    echo "    final summary:"
    tail -7 /tmp/all.txt | sed "s/^/      /"
' > "$OUT" 2>&1 || true

echo "capture written to $OUT"
cat "$OUT"
