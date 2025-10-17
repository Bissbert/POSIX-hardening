#!/bin/sh
# Script: 11-service-disable.sh - Disable unnecessary services

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

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