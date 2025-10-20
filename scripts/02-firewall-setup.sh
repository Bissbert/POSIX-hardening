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
# Load Firewall-Specific Configuration
# ============================================================================

# Load firewall.conf if it exists (overrides defaults.conf)
FIREWALL_CONFIG_FILE="$TOOLKIT_ROOT/config/firewall.conf"
if [ -f "$FIREWALL_CONFIG_FILE" ]; then
    . "$FIREWALL_CONFIG_FILE"
    log "INFO" "Loaded firewall configuration from: $FIREWALL_CONFIG_FILE"
else
    log "INFO" "No firewall.conf found, using default configuration"
fi

# Set defaults for firewall-specific variables (if not set in firewall.conf)
: "${SSH_RATE_LIMIT_ENABLED:=1}"
: "${SSH_RATE_LIMIT_HITS:=4}"
: "${SSH_RATE_LIMIT_SECONDS:=60}"
: "${ICMP_ENABLED:=1}"
: "${ICMP_RATE_LIMIT:=1/s}"
: "${ICMP_TYPES:=echo-request echo-reply destination-unreachable time-exceeded}"
: "${LOG_DROPPED_PACKETS:=1}"
: "${LOG_RATE_LIMIT:=2/min}"
: "${LOG_PREFIX:=IPTables-Dropped: }"
: "${LOG_LEVEL:=4}"
: "${ALLOW_DNS:=1}"
: "${ALLOW_NTP:=1}"
: "${ALLOW_HTTP:=1}"
: "${ALLOW_HTTPS:=1}"
: "${CUSTOM_OUTBOUND_TCP:=}"
: "${CUSTOM_OUTBOUND_UDP:=}"
: "${DEFAULT_INPUT_POLICY:=DROP}"
: "${DEFAULT_FORWARD_POLICY:=DROP}"
: "${DEFAULT_OUTPUT_POLICY:=ACCEPT}"
: "${IPV6_ENABLED:=1}"
: "${IPV6_MODE:=same}"
: "${CUSTOM_RULES_IPV4:=}"
: "${CUSTOM_RULES_IPV6:=}"
: "${CUSTOM_CHAINS:=}"

# ============================================================================
# Firewall Configuration
# ============================================================================

# Check for iptables
check_iptables() {
    if ! command -v iptables >/dev/null 2>&1; then
        log "WARN" "iptables not found - skipping firewall configuration"
        return 1
    fi

    # Check for iptables-save/restore
    if ! command -v iptables-save >/dev/null 2>&1; then
        log "WARN" "iptables-save not found - persistence may not work"
    fi

    return 0
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
    if [ "$SSH_RATE_LIMIT_ENABLED" = "1" ]; then
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --set
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m state --state NEW -m recent --update --seconds "$SSH_RATE_LIMIT_SECONDS" --hitcount "$SSH_RATE_LIMIT_HITS" -j DROP
        log "INFO" "SSH rate limiting: $SSH_RATE_LIMIT_HITS attempts per $SSH_RATE_LIMIT_SECONDS seconds"
    fi
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
    if [ "$ICMP_ENABLED" = "1" ]; then
        for icmp_type in $ICMP_TYPES; do
            if [ "$icmp_type" = "echo-request" ]; then
                # Rate-limit echo-request (ping)
                iptables -A INPUT -p icmp --icmp-type "$icmp_type" -m limit --limit "$ICMP_RATE_LIMIT" -j ACCEPT
            else
                # Other ICMP types without rate limit
                iptables -A INPUT -p icmp --icmp-type "$icmp_type" -j ACCEPT
            fi
        done
        log "INFO" "ICMP enabled: $ICMP_TYPES (rate limit: $ICMP_RATE_LIMIT)"
    else
        log "INFO" "ICMP disabled"
    fi

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

    # DNS (if enabled)
    if [ "$ALLOW_DNS" = "1" ]; then
        iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
        log "INFO" "Outbound DNS allowed"
    fi

    # NTP (if enabled)
    if [ "$ALLOW_NTP" = "1" ]; then
        iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
        log "INFO" "Outbound NTP allowed"
    fi

    # HTTP (if enabled)
    if [ "$ALLOW_HTTP" = "1" ]; then
        iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
        log "INFO" "Outbound HTTP allowed"
    fi

    # HTTPS (if enabled)
    if [ "$ALLOW_HTTPS" = "1" ]; then
        iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
        log "INFO" "Outbound HTTPS allowed"
    fi

    # Custom outbound TCP ports
    if [ -n "$CUSTOM_OUTBOUND_TCP" ]; then
        for port in $CUSTOM_OUTBOUND_TCP; do
            iptables -A OUTPUT -p tcp --dport "$port" -j ACCEPT
            log "INFO" "Outbound TCP port allowed: $port"
        done
    fi

    # Custom outbound UDP ports
    if [ -n "$CUSTOM_OUTBOUND_UDP" ]; then
        for port in $CUSTOM_OUTBOUND_UDP; do
            iptables -A OUTPUT -p udp --dport "$port" -j ACCEPT
            log "INFO" "Outbound UDP port allowed: $port"
        done
    fi

    # === CUSTOM CHAINS ===
    # Create custom chains if defined
    if [ -n "$CUSTOM_CHAINS" ]; then
        echo "$CUSTOM_CHAINS" | while IFS=: read -r chain_name description; do
            # Skip empty lines
            [ -z "$chain_name" ] && continue

            # Trim whitespace
            chain_name=$(echo "$chain_name" | tr -d ' \t')

            if [ -n "$chain_name" ]; then
                iptables -N "$chain_name" 2>/dev/null || log "WARN" "Chain $chain_name already exists"
                log "INFO" "Created custom chain: $chain_name ($description)"
            fi
        done
    fi

    # === CUSTOM IPv4 RULES ===
    # Apply custom iptables rules (if defined)
    if [ -n "$CUSTOM_RULES_IPV4" ]; then
        log "INFO" "Applying custom IPv4 firewall rules"
        echo "$CUSTOM_RULES_IPV4" | while IFS= read -r rule; do
            # Skip empty lines and comments
            [ -z "$rule" ] && continue
            echo "$rule" | grep -q "^#" && continue

            # Validate rule starts with -A, -I, or other valid flags
            if echo "$rule" | grep -qE "^-[AID]"; then
                # Apply rule (without 'iptables' prefix)
                if iptables $rule 2>/dev/null; then
                    log "INFO" "Applied custom rule: iptables $rule"
                else
                    log "WARN" "Failed to apply custom rule: iptables $rule"
                fi
            else
                log "WARN" "Skipping invalid rule (must start with -A, -I, or -D): $rule"
            fi
        done
    fi

    # === LOGGING ===
    # Log dropped packets (if enabled)
    if [ "$LOG_DROPPED_PACKETS" = "1" ]; then
        iptables -N LOGGING 2>/dev/null || true
        iptables -A INPUT -j LOGGING
        iptables -A LOGGING -m limit --limit "$LOG_RATE_LIMIT" -j LOG --log-prefix "$LOG_PREFIX" --log-level "$LOG_LEVEL"
        iptables -A LOGGING -j DROP
        log "INFO" "Firewall logging enabled (rate: $LOG_RATE_LIMIT, level: $LOG_LEVEL)"
    else
        # No logging, just drop
        iptables -A INPUT -j DROP
    fi

    # === DEFAULT POLICIES ===
    # Set default policies (after all rules are set)
    iptables -P INPUT "$DEFAULT_INPUT_POLICY"
    iptables -P FORWARD "$DEFAULT_FORWARD_POLICY"
    iptables -P OUTPUT "$DEFAULT_OUTPUT_POLICY"
    log "INFO" "Default policies: INPUT=$DEFAULT_INPUT_POLICY FORWARD=$DEFAULT_FORWARD_POLICY OUTPUT=$DEFAULT_OUTPUT_POLICY"

    # === IPv6 Rules ===
    if [ "$IPV6_ENABLED" = "1" ] && command -v ip6tables >/dev/null 2>&1; then
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
                log "INFO" "IPv6: Admin IP priority access: $ADMIN_IP"
            fi
        fi

        # Apply custom IPv6 rules if IPV6_MODE is custom
        if [ "$IPV6_MODE" = "custom" ] && [ -n "$CUSTOM_RULES_IPV6" ]; then
            log "INFO" "Applying custom IPv6 firewall rules"
            echo "$CUSTOM_RULES_IPV6" | while IFS= read -r rule; do
                # Skip empty lines and comments
                [ -z "$rule" ] && continue
                echo "$rule" | grep -q "^#" && continue

                # Validate rule
                if echo "$rule" | grep -qE "^-[AID]"; then
                    if ip6tables $rule 2>/dev/null; then
                        log "INFO" "Applied custom IPv6 rule: ip6tables $rule"
                    else
                        log "WARN" "Failed to apply IPv6 rule: ip6tables $rule"
                    fi
                else
                    log "WARN" "Skipping invalid IPv6 rule: $rule"
                fi
            done
        elif [ "$IPV6_MODE" = "block" ]; then
            # Block all IPv6 except SSH
            log "INFO" "IPv6 mode: block (only SSH allowed)"
        else
            # Mode "same" - apply same rules as IPv4 (already done above)
            log "INFO" "IPv6 mode: same as IPv4"
        fi

        ip6tables -P INPUT "$DEFAULT_INPUT_POLICY"
        ip6tables -P FORWARD "$DEFAULT_FORWARD_POLICY"
        ip6tables -P OUTPUT "$DEFAULT_OUTPUT_POLICY"
        log "INFO" "IPv6 firewall enabled"
    else
        if [ "$IPV6_ENABLED" = "0" ]; then
            log "INFO" "IPv6 firewall disabled by configuration"
        else
            log "INFO" "IPv6 not available (ip6tables not found)"
        fi
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
    if ! check_iptables; then
        show_warning "iptables not available - skipping firewall configuration"
        log "INFO" "Firewall setup skipped (iptables not found)"
        log "INFO" "This system may be using nftables, firewalld, or ufw instead"
        log "INFO" "Please configure firewall manually if needed"

        # Mark as completed even though skipped (don't block other scripts)
        mark_completed "$SCRIPT_NAME"

        # Exit successfully (not a failure, just skipped)
        exit 0
    fi

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