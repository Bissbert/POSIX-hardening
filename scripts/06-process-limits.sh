#!/bin/sh
# Script: 06-process-limits.sh - Process and resource limits

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="06-process-limits"

apply_limits() {
    show_progress "Configuring process limits"

    backup_file /etc/security/limits.conf

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