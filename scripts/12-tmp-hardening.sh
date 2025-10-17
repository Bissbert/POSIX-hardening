#!/bin/sh
# Script: 12-tmp-hardening.sh - Harden temporary directories

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

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