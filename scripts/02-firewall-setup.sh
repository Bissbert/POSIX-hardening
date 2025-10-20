#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 02-firewall-setup.sh
# Priority: CRITICAL - Must preserve remote access
# Description: Configures firewall with safety mechanisms

# Get script directory and toolkit root
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

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/ssh_safety.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Script name for logging
SCRIPT_NAME="02-firewall-setup"

# ============================================================================
# Firewall Configuration
# ============================================================================

# Check for iptables
check_iptables() {
    if ! command -v iptables >/dev/null 2>&1; then
        die "iptables not found - cannot configure firewall"
    fi

    # Check for iptables-save/restore
    if ! command -v iptables-save >/dev/null 2>&1; then
        log "WARN" "iptables-save not found - persistence may not work"
    fi
}

# Save current rules for rollback
save_current_rules() {
    local backup_file="$BACKUP_DIR/iptables.rules.$(date +%Y%m%d-%H%M%S)"

    iptables-save > "$backup_file" 2>/dev/null
    ip6tables-save > "${backup_file}.v6" 2>/dev/null

    register_command_rollback "iptables-restore < $backup_file"

    log "INFO" "Current firewall rules backed up to: $backup_file"
}

# Setup safety timeout
setup_safety_timeout() {
    local timeout="${1:-$FIREWALL_TIMEOUT}"

    log "INFO" "Setting up firewall safety timeout ($timeout seconds)"

    # Create reset script
    cat > /tmp/firewall_reset.sh <<'EOF'
#!/bin/sh
sleep TIMEOUT_VALUE
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
ip6tables -F
ip6tables -X
ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT
echo "$(date): Firewall auto-reset triggered" >> /var/log/hardening/firewall.log
EOF

    sed -i "s/TIMEOUT_VALUE/$timeout/" /tmp/firewall_reset.sh
    chmod +x /tmp/firewall_reset.sh

    # Start timeout in background
    /tmp/firewall_reset.sh &
    FIREWALL_TIMEOUT_PID=$!

    log "DEBUG" "Firewall timeout PID: $FIREWALL_TIMEOUT_PID"
}

# Cancel safety timeout
cancel_safety_timeout() {
    if [ -n "$FIREWALL_TIMEOUT_PID" ]; then
        if kill -0 "$FIREWALL_TIMEOUT_PID" 2>/dev/null; then
            kill "$FIREWALL_TIMEOUT_PID"
            log "INFO" "Firewall safety timeout cancelled"
        fi
    fi
    rm -f /tmp/firewall_reset.sh
}

# Apply firewall rules
apply_firewall_rules() {
    show_progress "Applying firewall rules"

    # === IPv4 Rules ===

    # Flush existing rules
    iptables -F
    iptables -X
    iptables -Z

    # CRITICAL: Preserve established connections first
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # CRITICAL: Allow SSH before any DROP rules
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -j ACCEPT

    # Priority access for admin IP
    if [ -n "$ADMIN_IP" ]; then
        iptables -I INPUT 1 -s "$ADMIN_IP" -j ACCEPT
        log "INFO" "Added priority rule for admin IP: $ADMIN_IP"
    fi

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Drop invalid packets
    iptables -A INPUT -m state --state INVALID -j DROP

    # Allow ICMP (ping) with rate limit
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
    iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT

    # Allow additional configured ports
    if [ -n "$ALLOWED_PORTS" ]; then
        for port in $ALLOWED_PORTS; do
            iptables -A INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT
            log "INFO" "Allowed port: $port"
        done
    fi

    # Allow trusted networks
    if [ -n "$TRUSTED_NETWORKS" ]; then
        for network in $TRUSTED_NETWORKS; do
            iptables -A INPUT -s "$network" -j ACCEPT
            log "INFO" "Allowed network: $network"
        done
    fi

    # DNS (if server)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

    # NTP
    iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

    # HTTP/HTTPS for updates
    iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

    # Log dropped packets
    iptables -N LOGGING
    iptables -A INPUT -j LOGGING
    iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables-Dropped: " --log-level 4
    iptables -A LOGGING -j DROP

    # Default policies (after all rules are set)
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # === IPv6 Rules ===
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F
        ip6tables -X

        # Basic IPv6 protection
        ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        ip6tables -A INPUT -i lo -j ACCEPT
        ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
        ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

        if [ -n "$ADMIN_IP" ]; then
            # Check if admin IP is IPv6
            if echo "$ADMIN_IP" | grep -q ":"; then
                ip6tables -I INPUT 1 -s "$ADMIN_IP" -j ACCEPT
            fi
        fi

        ip6tables -P INPUT DROP
        ip6tables -P FORWARD DROP
        ip6tables -P OUTPUT ACCEPT
    fi

    log "INFO" "Firewall rules applied"
}

# Verify connectivity
verify_connectivity() {
    show_progress "Verifying connectivity after firewall changes"

    # Check SSH
    if ! timeout 5 nc -z localhost "$SSH_PORT" 2>/dev/null; then
        log "ERROR" "SSH port not accessible after firewall setup!"
        return 1
    fi

    # Check if we can still connect externally
    if ! timeout 5 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "WARN" "Cannot reach external networks (this may be intentional)"
    fi

    # Verify SSH is in rules
    if ! iptables -L INPUT -n | grep -q "dpt:$SSH_PORT"; then
        log "ERROR" "SSH port not found in firewall rules!"
        return 1
    fi

    show_success "Connectivity verified"
    return 0
}

# Save rules persistently
save_firewall_rules() {
    show_progress "Saving firewall rules"

    # Debian/Ubuntu method
    if [ -d /etc/iptables ]; then
        iptables-save > /etc/iptables/rules.v4
        ip6tables-save > /etc/iptables/rules.v6
        log "INFO" "Rules saved to /etc/iptables/"
    fi

    # Alternative method
    if [ -d /etc/sysconfig ]; then
        iptables-save > /etc/sysconfig/iptables
        ip6tables-save > /etc/sysconfig/ip6tables
        log "INFO" "Rules saved to /etc/sysconfig/"
    fi

    # Create restore script for boot
    cat > /etc/network/if-pre-up.d/iptables <<'EOF'
#!/bin/sh
[ -f /etc/iptables/rules.v4 ] && iptables-restore < /etc/iptables/rules.v4
[ -f /etc/iptables/rules.v6 ] && ip6tables-restore < /etc/iptables/rules.v6
exit 0
EOF
    chmod +x /etc/network/if-pre-up.d/iptables

    show_success "Firewall rules saved persistently"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    show_progress "Starting firewall setup script"

    # Initialize
    init_hardening_environment "$SCRIPT_NAME"

    # Check requirements
    check_iptables

    # Start transaction
    begin_transaction "firewall_setup"

    # Save current rules
    save_current_rules

    # Critical: Ensure SSH access first
    ensure_ssh_firewall_access

    # Setup safety timeout
    setup_safety_timeout

    # Apply firewall rules
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would configure firewall rules"
    else
        apply_firewall_rules

        # Verify connectivity
        if verify_connectivity; then
            # Cancel timeout - rules are good
            cancel_safety_timeout

            # Save rules
            save_firewall_rules

            show_success "Firewall configured successfully"
        else
            show_error "Connectivity verification failed!"
            # Timeout will auto-reset rules
            rollback_transaction "connectivity_lost"
            exit 1
        fi
    fi

    # Mark complete
    mark_completed "$SCRIPT_NAME"

    # Commit transaction
    commit_transaction

    # Show status
    log "INFO" "="
    log "INFO" "Firewall Status:"
    log "INFO" "- SSH port $SSH_PORT: PROTECTED"
    log "INFO" "- Established connections: ALLOWED"
    log "INFO" "- Default policy: DROP"
    log "INFO" "- Brute force protection: ENABLED"
    log "INFO" "- Logging: ENABLED"
    log "INFO" "="

    exit 0
}

# Run main
main "$@"