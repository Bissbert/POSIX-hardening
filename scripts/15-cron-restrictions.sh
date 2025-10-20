#!/bin/sh
# Script: 15-cron-restrictions.sh - Restrict cron access


SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"
. "$LIB_DIR/common.sh"
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