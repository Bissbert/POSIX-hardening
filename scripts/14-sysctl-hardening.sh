#!/bin/sh
# Script: 14-sysctl-hardening.sh - Additional sysctl hardening


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

SCRIPT_NAME="14-sysctl-hardening"

apply_sysctl_hardening() {
    show_progress "Applying additional sysctl hardening"

    backup_file /etc/sysctl.conf

    cat >> /etc/sysctl.conf <<'EOF'

# Additional POSIX Hardening
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_congestion_control = htcp
vm.swappiness = 10
kernel.panic = 60
kernel.panic_on_oops = 1
EOF

    sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    show_success "Sysctl hardening applied"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "sysctl_hardening"

    if [ "$DRY_RUN" != "1" ]; then
        apply_sysctl_hardening
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"