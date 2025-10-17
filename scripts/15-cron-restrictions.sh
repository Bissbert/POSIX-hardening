#!/bin/sh
# Script: 15-cron-restrictions.sh - Restrict cron access

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="15-cron-restrictions"

restrict_cron() {
    show_progress "Restricting cron access"

    # Create cron.allow with only root
    echo "root" > /etc/cron.allow
    chmod 600 /etc/cron.allow

    # Remove cron.deny
    rm -f /etc/cron.deny

    # Secure cron files
    chmod 600 /etc/crontab
    chmod 700 /etc/cron.d
    chmod 700 /etc/cron.daily
    chmod 700 /etc/cron.hourly
    chmod 700 /etc/cron.monthly
    chmod 700 /etc/cron.weekly

    # Create at.allow
    echo "root" > /etc/at.allow
    chmod 600 /etc/at.allow
    rm -f /etc/at.deny

    show_success "Cron access restricted"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        restrict_cron
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"