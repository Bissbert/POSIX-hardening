#!/bin/sh
# Script: 06-process-limits.sh - Process and resource limits


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
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

SCRIPT_NAME="06-process-limits"

apply_limits() {
    show_progress "Configuring process limits"

    backup_file /etc/security/limits.conf

    # Remove old POSIX hardening section if it exists (for idempotency)
    if [ -f /etc/security/limits.conf ]; then
        if grep -q "# POSIX Hardening - Process Limits" /etc/security/limits.conf; then
            log "INFO" "Removing old process limits section for update"
            sed -i '/# POSIX Hardening - Process Limits/,/^$/d' /etc/security/limits.conf
        fi
    fi

    cat >> /etc/security/limits.conf <<EOF

# POSIX Hardening - Process Limits
* soft core 0
* hard core 0
* soft nproc 1024
* hard nproc 1024
* soft nofile 1024
* hard nofile 65535
* soft memlock unlimited
* hard memlock unlimited
EOF

    show_success "Process limits configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "process_limits"

    if [ "$DRY_RUN" != "1" ]; then
        apply_limits
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"