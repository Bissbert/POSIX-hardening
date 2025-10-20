#!/bin/sh
# Script: 20-integrity-baseline.sh - Create file integrity baseline


SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"
# Load configuration first (before libraries set readonly variables)
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
. "$LIB_DIR/common.sh"

SCRIPT_NAME="20-integrity-baseline"

create_baseline() {
    show_progress "Creating file integrity baseline"

    baseline_file="$STATE_DIR/integrity_baseline.$(date +%Y%m%d-%H%M%S)"

    # Create checksums for critical directories
    for dir in /etc /bin /sbin /usr/bin /usr/sbin; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -exec sha256sum {} \; >> "$baseline_file" 2>/dev/null
            log "INFO" "Baselined: $dir"
        fi
    done

    # Compress baseline
    gzip "$baseline_file"

    # Create symlink to latest
    ln -sf "$(basename "$baseline_file.gz")" "$STATE_DIR/integrity_baseline_latest.gz"

    show_success "Integrity baseline created: $baseline_file.gz"
}

verify_integrity() {
    if [ -f "$STATE_DIR/integrity_baseline_latest.gz" ]; then
        show_progress "Verifying system integrity"

        temp_file="/tmp/integrity_check.$$"
        zcat "$STATE_DIR/integrity_baseline_latest.gz" | while read -r checksum file; do
            if [ -f "$file" ]; then
                current=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
                if [ "$current" != "$checksum" ]; then
                    echo "MODIFIED: $file" >> "$temp_file"
                fi
            else
                echo "MISSING: $file" >> "$temp_file"
            fi
        done

        if [ -f "$temp_file" ]; then
            log "WARN" "Integrity check found changes:"
            cat "$temp_file"
            rm -f "$temp_file"
        else
            show_success "Integrity check passed"
        fi
    fi
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        create_baseline
        # Optionally verify if baseline exists
        [ "$1" = "verify" ] && verify_integrity
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"