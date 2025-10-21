#!/bin/sh
# Script: 10-sudo-restrictions.sh - Sudo configuration hardening


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

SCRIPT_NAME="10-sudo-restrictions"

configure_sudo() {
    show_progress "Configuring sudo restrictions"

    [ -f /etc/sudoers ] && backup_file /etc/sudoers

    # Create sudoers.d directory if needed
    [ ! -d /etc/sudoers.d ] && mkdir -p /etc/sudoers.d

    # Detect current user (typically the Ansible remote user)
    local current_user="${SUDO_USER:-${USER}}"

    # Add hardening rules
    cat > /etc/sudoers.d/hardening <<EOF
# POSIX Hardening Sudo Configuration
# Note: requiretty is disabled for automation tools like Ansible
# If you need requiretty for security, enable it only for specific users
Defaults !requiretty
Defaults !visiblepw
Defaults always_set_home
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults timestamp_timeout=15
Defaults lecture=always
Defaults logfile="/var/log/sudo.log"

# Allow automation user to run sudo without TTY (required for Ansible)
# If you want to restrict this, uncomment and set specific user:
# Defaults:${current_user} !requiretty
EOF

    chmod 440 /etc/sudoers.d/hardening

    # Validate sudoers configuration
    if ! visudo -c -f /etc/sudoers.d/hardening >/dev/null 2>&1; then
        log "ERROR" "Sudoers configuration validation failed!"
        rm -f /etc/sudoers.d/hardening
        restore_file /etc/sudoers
        return 1
    fi

    show_success "Sudo configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "sudo_config"

    if [ "$DRY_RUN" != "1" ]; then
        configure_sudo
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"