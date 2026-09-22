#!/bin/sh
# capture-ssh-watchdog.sh - make the SSH lockout watchdog in
# lib/ssh_safety.sh fire for real, and record what it does.
#
# update_ssh_config_safe() arms a background watchdog before it moves the new
# sshd_config into place. If SSH is not answering after the timeout, the
# watchdog is supposed to copy the backup back and restart sshd. This tool
# creates exactly that situation by killing sshd immediately after the script
# reloads it, then reads /etc/ssh/sshd_config back afterwards.
#
# The timeout is lowered from the shipped 60s to 15s so the capture finishes in
# reasonable time; nothing else about the code path is changed.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-ssh-watchdog.sh [outfile]
# Default outfile: media/captures/ssh-watchdog.log

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/ssh-watchdog.log}"
CNAME="ph-watchdog-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$(dirname "$OUT")"
trap 'capture_stop "$CNAME"' EXIT INT TERM
capture_start "$ROOT" "$CNAME" >/dev/null

docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening
    sed -i "s/^SSH_ROLLBACK_TIMEOUT=.*/SSH_ROLLBACK_TIMEOUT=15/" \
        config/defaults.conf
    grep "^SSH_ROLLBACK_TIMEOUT" config/defaults.conf
'

docker exec "$CNAME" sh -c 'cat > /tmp/watchdog.sh <<'"'"'EOS'"'"'
#!/bin/sh
cd /opt/posix-hardening
: > /tmp/run.out
BEFORE=$(sha256sum /etc/ssh/sshd_config | cut -d" " -f1)

# Kill sshd one second after the script reloads it. This is the failure the
# watchdog exists for: the new configuration takes the daemon down.
(
    i=0
    while [ $i -lt 600 ]; do
        if grep -q "Reloading SSH daemon" /tmp/run.out 2>/dev/null; then
            sleep 1
            pkill -9 -x sshd
            echo "harness: sshd killed after reload"
            exit 0
        fi
        sleep 0.2
        i=$((i + 1))
    done
    echo "harness: the script never reached the reload step"
) &
KILLER=$!

sh scripts/01-ssh-hardening.sh > /tmp/run.out 2>&1
echo "script exit: $?"
wait $KILLER
pgrep -x sshd >/dev/null && echo "sshd running: yes" || echo "sshd running: no"

echo "waiting 30s for the 15s watchdog to fire"
sleep 30

AFTER=$(sha256sum /etc/ssh/sshd_config | cut -d" " -f1)
echo
echo "sshd_config sha256 before : $BEFORE"
echo "sshd_config sha256 after  : $AFTER"
if [ "$BEFORE" = "$AFTER" ]; then
    echo "RESULT: sshd_config was restored"
else
    echo "RESULT: sshd_config was NOT restored"
fi
pgrep -x sshd >/dev/null && echo "sshd back up: yes" || echo "sshd back up: no"

echo
echo "== the lines that matter, from the run =="
grep -n "backed up to\|Setting up automatic\|Reloading SSH\|not responding\|executing rollback\|rolled back\|cannot stat" /tmp/run.out
EOS
sh /tmp/watchdog.sh 2>&1' > "$OUT" 2>&1 || true

echo "capture written to $OUT"
cat "$OUT"
