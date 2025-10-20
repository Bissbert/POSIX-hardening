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
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
. "$LIB_DIR/common.sh"

SCRIPT_NAME="12-tmp-hardening"

harden_tmp() {
    show_progress "Hardening temporary directories"

    # Set secure permissions
    chmod 1777 /tmp 2>/dev/null
    chmod 1777 /var/tmp 2>/dev/null

    # Mount /tmp with noexec,nosuid,nodev if possible
    if mount | grep -q " /tmp "; then
        mount -o remount,noexec,nosuid,nodev /tmp 2>/dev/null && \
            log "INFO" "Remounted /tmp with secure options"
    fi

    # Clean old files
    find /tmp -type f -atime +7 -delete 2>/dev/null
    find /var/tmp -type f -atime +7 -delete 2>/dev/null

    show_success "Temporary directories hardened"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        harden_tmp
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"