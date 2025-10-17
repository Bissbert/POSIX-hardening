#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 05-file-permissions.sh
# Priority: HIGH - Critical file permissions
# Description: Secures permissions on sensitive files and directories

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="05-file-permissions"

secure_system_files() {
    show_progress "Securing system file permissions"

    # Secure sensitive files
    [ -f /etc/passwd ] && chmod 644 /etc/passwd
    [ -f /etc/shadow ] && chmod 000 /etc/shadow
    [ -f /etc/group ] && chmod 644 /etc/group
    [ -f /etc/gshadow ] && chmod 000 /etc/gshadow
    [ -f /etc/ssh/sshd_config ] && chmod 600 /etc/ssh/sshd_config

    # Secure cron files
    [ -f /etc/crontab ] && chmod 600 /etc/crontab
    [ -d /etc/cron.d ] && chmod 700 /etc/cron.d
    [ -d /etc/cron.daily ] && chmod 700 /etc/cron.daily
    [ -d /etc/cron.hourly ] && chmod 700 /etc/cron.hourly
    [ -d /etc/cron.monthly ] && chmod 700 /etc/cron.monthly
    [ -d /etc/cron.weekly ] && chmod 700 /etc/cron.weekly

    # Secure log files
    [ -d /var/log ] && chmod 755 /var/log
    find /var/log -type f -exec chmod 640 {} \; 2>/dev/null

    # Remove world-writable permissions
    find / -xdev -type f -perm -002 -exec chmod o-w {} \; 2>/dev/null

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