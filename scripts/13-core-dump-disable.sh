#!/bin/sh
# Script: 13-core-dump-disable.sh - Disable core dumps

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="13-core-dump-disable"

disable_core_dumps() {
    show_progress "Disabling core dumps"

    # Disable in limits
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "* soft core 0" >> /etc/security/limits.conf

    # Disable via sysctl
    echo "fs.suid_dumpable = 0" >> /etc/sysctl.conf
    sysctl -w fs.suid_dumpable=0 >/dev/null 2>&1

    # Disable in profile
    echo "ulimit -c 0" >> /etc/profile

    show_success "Core dumps disabled"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        disable_core_dumps
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"