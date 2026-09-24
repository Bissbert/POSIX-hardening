#!/bin/sh
# Script: 12-tmp-hardening.sh - Harden temporary directories


SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"
# Load configuration first (before libraries set readonly variables)
# Environment values win over the file (see lib/config.sh)
. "$LIB_DIR/config.sh"
load_config "$CONFIG_FILE"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/rollback.sh"

SCRIPT_NAME="12-tmp-hardening"

harden_tmp() {
    show_progress "Hardening temporary directories"

    # Set secure permissions
    track_mode /tmp
    chmod 1777 /tmp 2>/dev/null
    track_mode /var/tmp
    chmod 1777 /var/tmp 2>/dev/null

    # Mount /tmp with noexec,nosuid,nodev if possible
    if mount | grep -q " /tmp "; then
        track_mount /tmp
        mount -o remount,noexec,nosuid,nodev /tmp 2>/dev/null && \
            log "INFO" "Remounted /tmp with secure options"
    fi

    # Clean old files. This is the one change rollback cannot undo: deleted
    # files are not copied first (see docs/rollback.md).
    find /tmp -type f -atime +7 -delete 2>/dev/null
    find /var/tmp -type f -atime +7 -delete 2>/dev/null

    show_success "Temporary directories hardened"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "tmp_hardening"

    if [ "$DRY_RUN" != "1" ]; then
        harden_tmp
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"