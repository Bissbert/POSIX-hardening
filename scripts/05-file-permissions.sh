#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 05-file-permissions.sh
# Priority: HIGH - Critical file permissions
# Description: Secures permissions on sensitive files and directories


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

SCRIPT_NAME="05-file-permissions"

# set_mode MODE PATH: chmod an existing PATH, recording its mode for rollback
set_mode() {
    [ -e "$2" ] || return 0
    track_mode "$2"
    chmod "$1" "$2"
}

secure_system_files() {
    show_progress "Securing system file permissions"

    # Secure sensitive files
    set_mode 644 /etc/passwd
    set_mode 640 /etc/shadow
    set_mode 644 /etc/group
    set_mode 640 /etc/gshadow
    set_mode 600 /etc/ssh/sshd_config

    # Secure cron files
    set_mode 600 /etc/crontab
    set_mode 700 /etc/cron.d
    set_mode 700 /etc/cron.daily
    set_mode 700 /etc/cron.hourly
    set_mode 700 /etc/cron.monthly
    set_mode 700 /etc/cron.weekly

    # Secure log files
    set_mode 755 /var/log
    find /var/log -type f 2>/dev/null | while IFS= read -r f; do
        set_mode 640 "$f"
    done

    # Remove world-writable permissions
    find / -xdev -type f -perm -002 2>/dev/null | while IFS= read -r f; do
        set_mode o-w "$f"
    done

    show_success "File permissions secured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "file_permissions"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would secure file permissions"
    else
        secure_system_files
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    show_success "File permissions hardening completed"
    exit 0
}

main "$@"