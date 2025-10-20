#!/bin/sh
# Script: 17-shell-timeout.sh - Configure shell timeout


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

SCRIPT_NAME="17-shell-timeout"

configure_timeout() {
    show_progress "Configuring shell timeout (${SHELL_TIMEOUT}s)"

    # Set timeout in profile (only if not already set)
    if ! grep -q "^TMOUT=" /etc/profile 2>/dev/null; then
        echo "" >> /etc/profile
        echo "# Shell timeout configured by POSIX hardening toolkit" >> /etc/profile
        echo "TMOUT=${SHELL_TIMEOUT}" >> /etc/profile
        echo "readonly TMOUT" >> /etc/profile
        echo "export TMOUT" >> /etc/profile
        log "INFO" "Added TMOUT to /etc/profile"
    else
        log "INFO" "TMOUT already configured in /etc/profile"
    fi

    # Set in bash profile if exists (only if not already set)
    if [ -f /etc/bash.bashrc ]; then
        if ! grep -q "^TMOUT=" /etc/bash.bashrc 2>/dev/null; then
            echo "" >> /etc/bash.bashrc
            echo "# Shell timeout configured by POSIX hardening toolkit" >> /etc/bash.bashrc
            echo "TMOUT=${SHELL_TIMEOUT}" >> /etc/bash.bashrc
            echo "readonly TMOUT" >> /etc/bash.bashrc
            echo "export TMOUT" >> /etc/bash.bashrc
            log "INFO" "Added TMOUT to /etc/bash.bashrc"
        else
            log "INFO" "TMOUT already configured in /etc/bash.bashrc"
        fi
    fi

    show_success "Shell timeout configured (${SHELL_TIMEOUT}s)"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        configure_timeout
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"