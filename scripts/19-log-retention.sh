#!/bin/sh
# Script: 19-log-retention.sh - Configure log retention

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="19-log-retention"

configure_log_retention() {
    show_progress "Configuring log retention"

    # Configure logrotate
    if [ -f /etc/logrotate.conf ]; then
        backup_file /etc/logrotate.conf

        # Update rotation settings
        sed -i 's/^rotate .*/rotate 90/' /etc/logrotate.conf

        # Add compression
        if ! grep -q "^compress" /etc/logrotate.conf; then
            echo "compress" >> /etc/logrotate.conf
        fi
    fi

    # Create security log rotation
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

    if [ "$DRY_RUN" != "1" ]; then
        configure_log_retention
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"