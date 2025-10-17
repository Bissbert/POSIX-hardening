#!/bin/sh
# Script: 18-banner-warnings.sh - Configure login banners

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"
. "$LIB_DIR/common.sh"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SCRIPT_NAME="18-banner-warnings"

create_banners() {
    show_progress "Creating warning banners"

    # Create issue banner
    cat > /etc/issue <<'EOF'
###############################################################
#                    AUTHORIZED ACCESS ONLY                  #
# Unauthorized access to this system is strictly prohibited. #
# All activities are monitored and logged.                   #
###############################################################
EOF

    # Create issue.net banner
    cp /etc/issue /etc/issue.net

    # Create motd
    cat > /etc/motd <<'EOF'
WARNING: This system is for authorized use only.
All activities are subject to monitoring and logging.
Disconnect immediately if you are not an authorized user.
EOF

    chmod 644 /etc/issue /etc/issue.net /etc/motd
    show_success "Warning banners configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"

    if [ "$DRY_RUN" != "1" ]; then
        create_banners
    fi

    mark_completed "$SCRIPT_NAME"
    exit 0
}

main "$@"