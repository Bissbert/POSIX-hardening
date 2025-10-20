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

    # Set timeout in profile
    echo "TMOUT=${SHELL_TIMEOUT}" >> /etc/profile
    echo "readonly TMOUT" >> /etc/profile
    echo "export TMOUT" >> /etc/profile

    # Set in bash profile if exists
    if [ -f /etc/bash.bashrc ]; then
        echo "TMOUT=${SHELL_TIMEOUT}" >> /etc/bash.bashrc
        echo "readonly TMOUT" >> /etc/bash.bashrc
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