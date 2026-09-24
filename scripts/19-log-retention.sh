#!/bin/sh
# Script: 19-log-retention.sh - Configure log retention


SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"
# Load configuration first (before libraries set readonly variables)
# Environment values win over the file (see lib/config.sh)
. "$LIB_DIR/config.sh"
load_config "$CONFIG_FILE"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

SCRIPT_NAME="19-log-retention"

configure_log_retention() {
    show_progress "Configuring log retention"

    # Configure logrotate
    if [ -f /etc/logrotate.conf ]; then
        backup_file /etc/logrotate.conf
        track_file /etc/logrotate.conf

        # Update rotation settings
        sed -i 's/^rotate .*/rotate 90/' /etc/logrotate.conf

        # Add compression
        if ! grep -q "^compress" /etc/logrotate.conf; then
            echo "compress" >> /etc/logrotate.conf
        fi
    fi

    # Create security log rotation
    track_file /etc/logrotate.d/security
    cat > /etc/logrotate.d/security <<'EOF'
/var/log/auth.log
/var/log/secure
/var/log/audit/audit.log
{
    rotate 90
    daily
    compress
    delaycompress
    missingok
    notifempty
    create 600 root root
}
EOF

    show_success "Log retention configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "log_retention"

    if [ "$DRY_RUN" != "1" ]; then
        configure_log_retention
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"