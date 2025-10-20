#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 04-network-stack.sh
# Priority: HIGH - Network stack hardening
# Description: Hardens network stack configuration


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

SCRIPT_NAME="04-network-stack"

apply_network_hardening() {
    show_progress "Hardening network stack"

    # Network interface hardening
    for iface in $(ls /proc/sys/net/ipv4/conf/); do
        # Skip if not a real interface
        [ "$iface" = "all" ] || [ "$iface" = "default" ] || [ "$iface" = "lo" ] && continue

        # Disable source routing
        echo 0 > /proc/sys/net/ipv4/conf/$iface/accept_source_route 2>/dev/null
        # Disable redirects
        echo 0 > /proc/sys/net/ipv4/conf/$iface/accept_redirects 2>/dev/null
        echo 0 > /proc/sys/net/ipv4/conf/$iface/send_redirects 2>/dev/null
        # Enable source address verification
        echo 1 > /proc/sys/net/ipv4/conf/$iface/rp_filter 2>/dev/null
    done

    # TCP hardening
    echo 1 > /proc/sys/net/ipv4/tcp_syncookies 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/tcp_timestamps 2>/dev/null
    echo 2 > /proc/sys/net/ipv4/tcp_synack_retries 2>/dev/null

    # ICMP hardening
    echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses 2>/dev/null

    # IPv6 hardening if available
    if [ -d /proc/sys/net/ipv6 ]; then
        echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra 2>/dev/null
        echo 0 > /proc/sys/net/ipv6/conf/default/accept_ra 2>/dev/null
        echo 0 > /proc/sys/net/ipv6/conf/all/accept_redirects 2>/dev/null
    fi

    show_success "Network stack hardened"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "network_stack"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would harden network stack"
    else
        apply_network_hardening
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    show_success "Network stack hardening completed"
    exit 0
}

main "$@"