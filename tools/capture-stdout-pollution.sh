#!/bin/sh
# capture-stdout-pollution.sh - every library function that returns a value by
# echoing it also logs to stdout first, so callers using $(...) capture both.
# This records the three affected functions, and shows that VERBOSE=1 widens
# the problem to a fourth.
#
# WARNING: container only. See tools/capture-lib.sh.
#
# Usage: sh tools/capture-stdout-pollution.sh [outfile]
# Default outfile: media/captures/stdout-pollution.txt

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/media/captures/stdout-pollution.txt}"
CNAME="ph-pollution-$$"
. "$ROOT/tools/capture-lib.sh"

mkdir -p "$(dirname "$OUT")"
trap 'capture_stop "$CNAME"' EXIT INT TERM
capture_start "$ROOT" "$CNAME" >/dev/null

docker exec "$CNAME" sh -c '
    cd /opt/posix-hardening
    rm -f config/defaults.conf
    echo "hello" > /etc/pollution-demo.conf

    for VERBOSE in 0 1; do
        echo "=== VERBOSE=$VERBOSE"
        export VERBOSE
        LIB_DIR=/opt/posix-hardening/lib sh -c "
            . ./lib/common.sh
            . ./lib/backup.sh
            . ./lib/ssh_safety.sh

            report() {
                printf \"  %-26s lines=%s  names an existing file: %s\n\" \
                    \"\$1\" \
                    \"\$(printf %s\\\\n \"\$2\" | wc -l | tr -d \" \")\" \
                    \"\$([ -f \"\$2\" ] && echo YES || echo NO)\"
            }

            v=\$(safe_backup_file /etc/pollution-demo.conf)
            report \"safe_backup_file\" \"\$v\"

            v=\$(backup_file /etc/pollution-demo.conf)
            report \"backup_file\" \"\$v\"

            v=\$(create_ssh_test_config /tmp/sshd.test 2222)
            report \"create_ssh_test_config\" \"\$v\"
        "
        echo
    done

    echo "=== what the caller receives from safe_backup_file, in full"
    LIB_DIR=/opt/posix-hardening/lib sh -c "
        . ./lib/common.sh
        . ./lib/backup.sh
        v=\$(safe_backup_file /etc/pollution-demo.conf)
        printf %s\\\\n \"\$v\" | cat -n
    "
' > "$OUT" 2>&1

echo "capture written to $OUT"
cat "$OUT"
