#!/bin/sh
# capture-hardening-run.sh - run real hardening scripts in a throwaway
# container and capture the output verbatim.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-hardening-run.sh [outdir]
# Default outdir: media/captures
#
# Writes, per script: <name>.log (stdout+stderr, unedited) and <name>.exit.
# Plus summary.txt, effects.txt and pristine.txt (the same entry points run
# WITHOUT the bug workarounds, which is how the repository behaves as shipped).

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures}"
CNAME="ph-capture-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$OUT"
trap 'capture_stop "$CNAME"' EXIT INT TERM

# ---------------------------------------------------------------------------
# 1. The repository exactly as shipped, before any workaround.
# ---------------------------------------------------------------------------
capture_ensure_image "$ROOT"
docker run -d --name "$CNAME" --privileged --entrypoint /bin/sh \
    "$CAPTURE_IMAGE" -c 'mkdir -p /run/sshd && /usr/sbin/sshd && sleep 3600' \
    >/dev/null
sleep 2
docker cp "$ROOT/." "$CNAME:/opt/posix-hardening" >/dev/null
docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening
    cp config/defaults.conf.template config/defaults.conf
    echo "# Repository as shipped, no workarounds. /bin/sh is dash."
    for e in "scripts/01-ssh-hardening.sh" "scripts/03-kernel-params.sh" \
             "scripts/05-file-permissions.sh" "orchestrator.sh --status" \
             "orchestrator.sh --dry-run --all" "emergency-rollback.sh --help"; do
        out=$(sh $e 2>&1); rc=$?
        printf "%-34s exit=%-3s %s\n" "$e" "$rc" \
            "$(printf "%s" "$out" | head -n1)"
    done
    echo
    echo "# Same entry points under bash, which names the failing library."
    for e in "scripts/01-ssh-hardening.sh" "orchestrator.sh --status" \
             "emergency-rollback.sh --help"; do
        out=$(bash $e 2>&1); rc=$?
        printf "%-34s exit=%-3s %s\n" "$e" "$rc" \
            "$(printf "%s" "$out" | head -n1)"
    done
' > "$OUT/pristine.txt" 2>&1
capture_stop "$CNAME"

# ---------------------------------------------------------------------------
# 2. With the workarounds applied, so there is something to capture.
# ---------------------------------------------------------------------------
capture_start "$ROOT" "$CNAME"

: > "$OUT/summary.txt"
for s in 01-ssh-hardening 03-kernel-params 05-file-permissions; do
    echo "running scripts/$s.sh ..." >&2
    set +e
    docker exec "$CNAME" sh -c "cd /opt/posix-hardening && sh scripts/$s.sh" \
        > "$OUT/$s.log" 2>&1
    rc=$?
    set -e
    echo "$rc" > "$OUT/$s.exit"
    printf '%-22s exit=%s  lines=%s\n' "$s" "$rc" \
        "$(wc -l < "$OUT/$s.log" | tr -d ' ')" >> "$OUT/summary.txt"
done

# Effects read back from the system, not from the script's own claims.
docker exec "$CNAME" sh -c '
    echo "--- sshd -T, settings the toolkit claims to set ---"
    /usr/sbin/sshd -T 2>/dev/null | grep -E \
"^(permitrootlogin|passwordauthentication|pubkeyauthentication|permitemptypasswords|x11forwarding|maxauthtries|clientaliveinterval|clientalivecountmax|logingracetime|allowusers|port) "
    echo "--- is sshd still reachable on port 22? ---"
    nc -z localhost 22 && echo "yes" || echo "no"
    echo "--- backups written ---"
    ls -1 /var/backups/hardening/ 2>/dev/null
    echo "--- completion markers ---"
    cat /var/lib/hardening/completed 2>/dev/null
    echo "--- 03-kernel-params rolled back; is its block still in sysctl.conf? ---"
    grep -c "POSIX Hardening Toolkit - Kernel Parameters" /etc/sysctl.conf \
        || echo 0
    echo "--- which sysctl key does sysctl -p reject here? ---"
    sysctl -p /etc/sysctl.conf 2>&1 >/dev/null | head -5
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    echo "sysctl -p exit: $?"
' > "$OUT/effects.txt" 2>&1

# Two questions about DRY_RUN: does config/defaults.conf override the
# environment, and does a dry run leave a completion marker behind?
docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening

    echo "=== A. DRY_RUN=1 with config/defaults.conf present"
    grep "^DRY_RUN" config/defaults.conf
    DRY_RUN=1 sh scripts/05-file-permissions.sh 2>&1 | grep -c "DRY-RUN" \
        | sed "s/^/    lines containing DRY-RUN: /"

    echo
    echo "=== B. DRY_RUN=1 with config/defaults.conf removed"
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening
    mv config/defaults.conf /tmp/defaults.conf
    DRY_RUN=1 sh scripts/05-file-permissions.sh 2>&1 \
        | grep -E "DRY-RUN|Marked as completed"
    echo "    completion markers after the DRY RUN:"
    sed "s/^/      /" /var/lib/hardening/completed 2>/dev/null || echo "      (none)"

    echo
    echo "=== C. running the same script directly afterwards"
    echo "    (a script invoked directly never consults the markers)"
    sh scripts/05-file-permissions.sh 2>&1 | tail -3

    echo
    echo "=== D. what the orchestrator does with a marker a dry run wrote"
    echo "    A dry run of 05-file-permissions is not enough to show this:"
    echo "    FAIL_FAST abandons the rest of priority 2 before reaching it"
    echo "    (BUG-16). Seed the marker for the first script instead, which"
    echo "    a dry run of 01-ssh-hardening would have written the same way."
    rm -rf /var/lib/hardening /var/log/hardening /var/backups/hardening
    mkdir -p /var/lib/hardening
    echo "01-ssh-hardening" > /var/lib/hardening/completed
    echo "    marker present before the run:"
    sed "s/^/      /" /var/lib/hardening/completed
    echo "    orchestrator.sh --all, lines naming that script:"
    sh orchestrator.sh --all </dev/null 2>&1 \
        | sed "s/\x1b\[[0-9;]*m//g" \
        | grep -i "01-ssh-hardening" \
        | sed "s/^/      /"
    echo "    note the marker has no \".sh\" suffix and the dependency"
    echo "    lines do, which is why they read as unmet (BUG-9d)"
    mv /tmp/defaults.conf config/defaults.conf
' > "$OUT/dry-run.txt" 2>&1

echo "--- summary ---"
cat "$OUT/summary.txt"
echo "captures written to $OUT"
