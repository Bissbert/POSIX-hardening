#!/bin/sh
# Script: 11-service-disable.sh - Disable unnecessary services


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

SCRIPT_NAME="11-service-disable"

disable_services() {
    show_progress "Disabling unnecessary services"

    # Common services to disable
    services="bluetooth cups avahi-daemon rpcbind nfs-server snmpd"

    for service in $services; do
        if systemctl list-unit-files | grep -q "^$service"; then
            systemctl stop "$service" 2>/dev/null
            systemctl disable "$service" 2>/dev/null
            log "INFO" "Disabled: $service"
        elif service "$service" status >/dev/null 2>&1; then
            service "$service" stop 2>/dev/null
            update-rc.d "$service" disable 2>/dev/null
            log "INFO" "Disabled: $service"
        fi
    done

    show_success "Unnecessary services disabled"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        disable_services
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"