#!/bin/sh
# Script: 16-mount-options.sh - Secure mount options

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="16-mount-options"

secure_mounts() {
    show_progress "Securing mount points"

    # Remount /proc with hidepid
    if mount | grep -q " /proc "; then
        mount -o remount,hidepid=2 /proc 2>/dev/null && \
            log "INFO" "Remounted /proc with hidepid=2"
    fi

    # Remount /dev/shm
    if mount | grep -q " /dev/shm "; then
        mount -o remount,noexec,nosuid,nodev /dev/shm 2>/dev/null && \
            log "INFO" "Secured /dev/shm mount"
    fi

    # Add nodev to /home if separate partition
    if mount | grep -q " /home "; then
        mount -o remount,nodev /home 2>/dev/null && \
            log "INFO" "Added nodev to /home"
    fi

    show_success "Mount points secured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        secure_mounts
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"