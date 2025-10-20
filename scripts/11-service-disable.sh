#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 11-service-disable.sh
# Priority: STANDARD
# Description: Disable unnecessary services to reduce attack surface

# Get script directory and toolkit root
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

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Script name for logging
SCRIPT_NAME="11-service-disable"

disable_services() {
    show_progress "Disabling unnecessary services"

    # Use configured list if available, otherwise use defaults
    local services_to_disable="${DISABLE_SERVICES:-bluetooth cups avahi-daemon rpcbind nfs-server snmpd}"

    # Skip if no services to disable
    if [ -z "$services_to_disable" ]; then
        log "INFO" "No services configured for disabling (DISABLE_SERVICES is empty)"
        show_success "Service disable skipped (no services configured)"
        return 0
    fi

    local disabled_count=0
    local skipped_count=0

    for service in $services_to_disable; do
        # Check if service exists using systemctl
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl list-unit-files 2>/dev/null | grep -q "^${service}\.service"; then
                log "INFO" "Found service: $service (systemd)"

                if [ "$DRY_RUN" = "1" ]; then
                    log "DRY_RUN" "Would stop and disable service: $service"
                    disabled_count=$((disabled_count + 1))
                else
                    # Stop the service
                    if systemctl stop "$service" 2>/dev/null; then
                        log "INFO" "Stopped service: $service"
                    else
                        log "WARN" "Could not stop service: $service (may already be stopped)"
                    fi

                    # Disable the service
                    if systemctl disable "$service" 2>/dev/null; then
                        log "INFO" "Disabled service: $service"
                        disabled_count=$((disabled_count + 1))
                    else
                        log "WARN" "Could not disable service: $service"
                    fi
                fi
            else
                log "INFO" "Service not found: $service (not installed)"
                skipped_count=$((skipped_count + 1))
            fi
        # Fallback to sysvinit service command
        elif command -v service >/dev/null 2>&1; then
            if service "$service" status >/dev/null 2>&1; then
                log "INFO" "Found service: $service (sysvinit)"

                if [ "$DRY_RUN" = "1" ]; then
                    log "DRY_RUN" "Would stop and disable service: $service"
                    disabled_count=$((disabled_count + 1))
                else
                    service "$service" stop 2>/dev/null
                    if command -v update-rc.d >/dev/null 2>&1; then
                        update-rc.d "$service" disable 2>/dev/null
                    elif command -v chkconfig >/dev/null 2>&1; then
                        chkconfig "$service" off 2>/dev/null
                    fi
                    log "INFO" "Disabled service: $service"
                    disabled_count=$((disabled_count + 1))
                fi
            else
                log "INFO" "Service not found: $service (not installed)"
                skipped_count=$((skipped_count + 1))
            fi
        else
            log "WARN" "No service management tool found (systemctl or service)"
            show_warning "Cannot disable services - no service manager found"
            return 0
        fi
    done

    log "INFO" "Services disabled: $disabled_count"
    log "INFO" "Services skipped (not installed): $skipped_count"
    show_success "Service hardening completed"

    return 0
}

main() {
    show_progress "Starting service disable script"

    # Initialize environment
    init_hardening_environment "$SCRIPT_NAME"

    # Check if already completed
    if is_completed "$SCRIPT_NAME"; then
        show_warning "Service disable already completed"
        log "INFO" "Skipping service disable (already done)"
        exit 0
    fi

    # Start transaction
    begin_transaction "service_disable"

    # Disable services
    if disable_services; then
        show_success "Service disable completed successfully"
    else
        show_error "Service disable failed"
        rollback_transaction "service_disable_failed"
        exit 1
    fi

    # Mark as completed
    mark_completed "$SCRIPT_NAME"

    # Commit transaction
    commit_transaction

    # Final status
    log "INFO" "Service hardening complete"
    exit 0
}

main "$@"