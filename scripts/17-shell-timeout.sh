#!/bin/sh
# Script: 17-shell-timeout.sh - Configure shell timeout

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="17-shell-timeout"

configure_timeout() {
    show_progress "Configuring shell timeout"

    # Set timeout in profile
    echo "TMOUT=${SHELL_TIMEOUT:-900}" >> /etc/profile
    echo "readonly TMOUT" >> /etc/profile
    echo "export TMOUT" >> /etc/profile

    # Set in bash profile if exists
    if [ -f /etc/bash.bashrc ]; then
        echo "TMOUT=${SHELL_TIMEOUT:-900}" >> /etc/bash.bashrc
        echo "readonly TMOUT" >> /etc/bash.bashrc
    fi

    show_success "Shell timeout configured"
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