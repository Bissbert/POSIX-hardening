#!/bin/sh
# Script: 09-account-lockdown.sh - Lock down user accounts


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

SCRIPT_NAME="09-account-lockdown"

lockdown_accounts() {
    show_progress "Locking down system accounts"

    # Lock unnecessary system accounts
    for user in games news uucp proxy www-data list irc gnats nobody; do
        if id "$user" >/dev/null 2>&1; then
            usermod -L "$user" 2>/dev/null
            usermod -s /usr/sbin/nologin "$user" 2>/dev/null
            log "INFO" "Locked account: $user"
        fi
    done

    # Ensure root has a password set
    if [ "$(passwd -S root | awk '{print $2}')" = "NP" ]; then
        log "WARN" "Root account has no password set!"
    fi

    # Remove empty password accounts
    awk -F: '($2 == "" || $2 == "!" || $2 == "*") {print $1}' /etc/shadow | while read -r user; do
        if [ "$user" != "root" ]; then
            usermod -L "$user" 2>/dev/null
        fi
    done

    show_success "Accounts locked down"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        lockdown_accounts
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"