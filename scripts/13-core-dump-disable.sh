#!/bin/sh
# Script: 13-core-dump-disable.sh - Disable core dumps


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