#!/bin/sh
# Script: 18-banner-warnings.sh - Configure login banners


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
. "$LIB_DIR/rollback.sh"

SCRIPT_NAME="18-banner-warnings"

create_banners() {
    show_progress "Creating warning banners"

    track_file /etc/issue
    track_file /etc/issue.net
    track_file /etc/motd

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
    begin_transaction "banner_warnings"

    if [ "$DRY_RUN" != "1" ]; then
        create_banners
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"