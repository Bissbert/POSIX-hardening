#!/bin/sh
# Script: 08-password-policy.sh - Password policy enforcement


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

SCRIPT_NAME="08-password-policy"

configure_password_policy() {
    show_progress "Configuring password policy"

    # Backup PAM files
    [ -f /etc/pam.d/common-password ] && backup_file /etc/pam.d/common-password
    [ -f /etc/login.defs ] && backup_file /etc/login.defs

    # Update login.defs
    if [ -f /etc/login.defs ]; then
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
        sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
        sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
        sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    12/' /etc/login.defs
    fi

    # Configure PAM if available
    if [ -f /etc/pam.d/common-password ]; then
        if ! grep -q "remember=" /etc/pam.d/common-password; then
            echo "password required pam_pwhistory.so remember=5" >> /etc/pam.d/common-password
        fi
    fi

    show_success "Password policy configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "password_policy"

    if [ "$DRY_RUN" != "1" ]; then
        configure_password_policy
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"