#!/bin/sh
# capture-rollback-demo.sh - exercise lib/rollback.sh end to end in a
# throwaway container and record what the rollback actually restores.
#
# The demo does exactly what a hardening script does:
#   begin_transaction -> safe_backup_file -> register_file_rollback ->
#   modify the file -> rollback_transaction
# and then reads the file back. Nothing is simulated; the library does the
# work.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-rollback-demo.sh [outfile]
# Default outfile: media/captures/rollback-demo.log

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/rollback-demo.log}"
CNAME="ph-rollback-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$(dirname "$OUT")"
trap 'capture_stop "$CNAME"' EXIT INT TERM
capture_start "$ROOT" "$CNAME" >/dev/null

docker exec "$CNAME" sh -c 'cat > /tmp/demo.sh <<'"'"'EOS'"'"'
#!/bin/sh
cd /opt/posix-hardening
SCRIPT_DIR=/opt/posix-hardening
LIB_DIR=/opt/posix-hardening/lib
. "$LIB_DIR/../config/defaults.conf"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

TARGET=/etc/demo.conf
printf "ORIGINAL - this must come back after rollback\n" > "$TARGET"
echo "== before =="; cat "$TARGET"

echo
echo "== what safe_backup_file actually returns =="
BK=$(safe_backup_file "$TARGET")
printf "%s\n" "$BK" | cat -n
echo "lines captured: $(printf "%s\n" "$BK" | wc -l | tr -d " ")"
if [ -f "$BK" ]; then
    echo "names an existing file: yes"
else
    echo "names an existing file: NO"
fi

echo
echo "== transaction =="
begin_transaction "demo"
register_file_rollback "$TARGET" "$BK"
printf "HARDENED - this must not survive the rollback\n" > "$TARGET"
echo "after modification:"; cat "$TARGET"
echo
echo "== rollback stack contents =="
cat "$ROLLBACK_STACK" 2>/dev/null | cat -n
echo
echo "== rollback =="
rollback_transaction "demo_failed" || true

echo
echo "== after rollback =="
cat "$TARGET"
echo
if grep -q "^ORIGINAL" "$TARGET"; then
    echo "RESULT: file was restored"
else
    echo "RESULT: file was NOT restored - the hardened content survived"
fi
EOS
sh /tmp/demo.sh 2>&1' > "$OUT" 2>&1 || true

echo "capture written to $OUT"
tail -n 20 "$OUT"
