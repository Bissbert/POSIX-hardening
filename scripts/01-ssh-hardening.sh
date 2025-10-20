#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 01-ssh-hardening.sh
# Priority: CRITICAL - Must preserve remote access
# Description: Hardens SSH configuration while maintaining remote access

# Get script directory and toolkit root
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/ssh_safety.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Load configuration
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Script name for logging
SCRIPT_NAME="01-ssh-hardening"

# ============================================================================
# SSH Hardening Configuration
# ============================================================================

# SSH settings to apply
SSH_SETTINGS="
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
Compression delayed
ClientAliveInterval 300
ClientAliveCountMax 2
UseDNS no
MaxAuthTries 3
MaxSessions 10
MaxStartups 10:30:60
LoginGraceTime 60
StrictModes yes
IgnoreRhosts yes
HostbasedAuthentication no
Protocol 2
LogLevel VERBOSE
SyslogFacility AUTH
AuthorizedKeysFile .ssh/authorized_keys
AllowAgentForwarding no
AllowTcpForwarding no
PermitUserEnvironment no
"

# Ciphers and algorithms (strong only)
SSH_CRYPTO="
Ciphers aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-256,hmac-sha2-512,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
"

# ============================================================================
# Pre-flight Checks
# ============================================================================

pre_flight_checks() {
    show_progress "Running pre-flight checks for SSH hardening"

    # Initialize environment
    init_hardening_environment "$SCRIPT_NAME"

    # Critical: Verify SSH connection
    if ! verify_ssh_connection; then
        die "SSH connection verification failed - cannot proceed"
    fi

    # Check if we're in an SSH session
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ]; then
        show_warning "Currently in SSH session - extra safety measures enabled"

        # Create emergency SSH access as fallback
        if [ "$ENABLE_EMERGENCY_ACCESS" = "1" ]; then
            create_emergency_ssh_access "$EMERGENCY_SSH_PORT" || \
                log "WARN" "Could not create emergency SSH access"
        fi
    fi

    # Ensure SSH config exists
    if [ ! -f "$SSHD_CONFIG" ]; then
        die "SSH configuration file not found: $SSHD_CONFIG"
    fi

    # Check for SSH keys (warn if none found)
    if [ ! -f /root/.ssh/authorized_keys ] && [ ! -f "$HOME/.ssh/authorized_keys" ]; then
        show_warning "No SSH authorized_keys found - ensure you have alternate access!"
        printf "Continue anyway? (y/N): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log "WARN" "Continuing without authorized_keys at user request"
                ;;
            *)
                die "Aborting: No SSH keys configured"
                ;;
        esac
    fi

    # Ensure firewall won't block SSH
    ensure_ssh_firewall_access

    show_success "Pre-flight checks completed"
}

# ============================================================================
# SSH Configuration Hardening
# ============================================================================

apply_ssh_hardening() {
    local config_file="$1"

    show_progress "Applying SSH hardening to: $config_file"

    # Apply each setting
    echo "$SSH_SETTINGS" | while read -r setting; do
        [ -z "$setting" ] && continue

        param=$(echo "$setting" | awk '{print $1}')
        value=$(echo "$setting" | cut -d' ' -f2-)

        if [ -n "$param" ] && [ -n "$value" ]; then
            update_ssh_setting "$config_file" "$param" "$value"
        fi
    done

    # Apply crypto settings (only if SSH version supports them)
    if /usr/sbin/sshd -T 2>/dev/null | grep -q "ciphers"; then
        echo "$SSH_CRYPTO" | while read -r setting; do
            [ -z "$setting" ] && continue

            param=$(echo "$setting" | awk '{print $1}')
            value=$(echo "$setting" | cut -d' ' -f2-)

            if [ -n "$param" ] && [ -n "$value" ]; then
                update_ssh_setting "$config_file" "$param" "$value"
            fi
        done
    else
        log "WARN" "SSH version does not support crypto restrictions"
    fi

    # Apply user/group restrictions if configured
    if [ -n "$SSH_ALLOW_USERS" ]; then
        update_ssh_setting "$config_file" "AllowUsers" "$SSH_ALLOW_USERS"
        log "INFO" "Restricted SSH to users: $SSH_ALLOW_USERS"
    fi

    if [ -n "$SSH_ALLOW_GROUPS" ]; then
        update_ssh_setting "$config_file" "AllowGroups" "$SSH_ALLOW_GROUPS"
        log "INFO" "Restricted SSH to groups: $SSH_ALLOW_GROUPS"
    fi

    # Ensure listening on correct port
    if [ "$SSH_PORT" != "22" ]; then
        update_ssh_setting "$config_file" "Port" "$SSH_PORT"
        log "INFO" "SSH configured on port: $SSH_PORT"
    fi

    return 0
}

# ============================================================================
# SSH Key Permissions
# ============================================================================

fix_ssh_permissions() {
    show_progress "Fixing SSH file permissions"

    # Fix SSH daemon files
    if [ -d /etc/ssh ]; then
        chmod 755 /etc/ssh
        chmod 644 /etc/ssh/*.pub 2>/dev/null || true
        chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
        chmod 644 /etc/ssh/ssh_config 2>/dev/null || true
        chmod 600 /etc/ssh/sshd_config

        log "INFO" "Fixed /etc/ssh permissions"
    fi

    # Fix user SSH directories
    for home_dir in /root /home/*; do
        if [ -d "$home_dir" ] && [ -d "$home_dir/.ssh" ]; then
            user=$(basename "$home_dir")

            # Get actual user if not root
            if [ "$user" != "root" ]; then
                if id "$user" >/dev/null 2>&1; then
                    fix_ssh_key_permissions "$home_dir/.ssh" "$user"
                fi
            else
                fix_ssh_key_permissions "$home_dir/.ssh" "root"
            fi
        fi
    done

    show_success "SSH permissions fixed"
}

# ============================================================================
# SSH Banner Configuration
# ============================================================================

configure_ssh_banner() {
    local banner_file="/etc/ssh/banner"

    show_progress "Configuring SSH banner"

    # Create warning banner
    cat > "$banner_file" <<'EOF'
###############################################################
#                      SECURITY WARNING                      #
###############################################################
# Unauthorized access to this system is strictly prohibited. #
# All access attempts are logged and monitored.             #
# Violators will be prosecuted to the full extent of law.   #
###############################################################
EOF

    chmod 644 "$banner_file"

    # Update SSH config to use banner
    update_ssh_setting "$SSHD_CONFIG" "Banner" "$banner_file"

    log "INFO" "SSH banner configured: $banner_file"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    show_progress "Starting SSH hardening script"

    # Start transaction for rollback capability
    begin_transaction "ssh_hardening"

    # Run pre-flight checks
    pre_flight_checks

    # Check if already completed
    if is_completed "$SCRIPT_NAME"; then
        show_warning "SSH hardening already completed, checking configuration..."

        # Verify settings are still in place
        if check_ssh_setting "PermitRootLogin" "no" && \
           check_ssh_setting "PasswordAuthentication" "no"; then
            show_success "SSH hardening already in place and verified"
            commit_transaction
            exit 0
        else
            log "WARN" "SSH hardening was completed but settings have changed, reapplying..."
        fi
    fi

    # Create system snapshot before changes
    snapshot_id=$(create_system_snapshot "pre_ssh_hardening")
    log "INFO" "Created snapshot: $snapshot_id"

    # Apply SSH hardening with automatic rollback protection
    if update_ssh_config_safe apply_ssh_hardening; then
        show_success "SSH configuration hardened successfully"
    else
        show_error "Failed to harden SSH configuration"
        rollback_transaction "ssh_config_failed"
        exit 1
    fi

    # Fix permissions
    fix_ssh_permissions

    # Configure banner
    configure_ssh_banner

    # Additional safety check
    if ! verify_ssh_connection; then
        show_error "Lost SSH connectivity after hardening!"
        rollback_transaction "lost_connectivity"
        exit 1
    fi

    # Run validation tests
    if [ "$RUN_VALIDATION" = "1" ]; then
        show_progress "Running validation tests"

        # Test that we can still connect
        if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
            show_success "SSH port is still accessible"
        else
            show_error "SSH port is not accessible!"
            rollback_transaction "validation_failed"
            exit 1
        fi

        # Verify hardening settings
        if check_ssh_setting "PermitRootLogin" "no" && \
           check_ssh_setting "PasswordAuthentication" "no" && \
           check_ssh_setting "PubkeyAuthentication" "yes"; then
            show_success "SSH hardening settings verified"
        else
            show_error "SSH hardening verification failed"
            rollback_transaction "verification_failed"
            exit 1
        fi
    fi

    # Mark as completed
    mark_completed "$SCRIPT_NAME"

    # Commit transaction
    commit_transaction

    # Final status
    show_success "SSH hardening completed successfully"
    log "INFO" "="
    log "INFO" "SSH Security Status:"
    log "INFO" "- Root login: DISABLED"
    log "INFO" "- Password authentication: DISABLED"
    log "INFO" "- Public key authentication: ENABLED"
    log "INFO" "- Empty passwords: DISABLED"
    log "INFO" "- Strong ciphers: CONFIGURED"
    log "INFO" "- Connection limits: APPLIED"
    log "INFO" "- Warning banner: CONFIGURED"

    if [ -n "$SSH_ALLOW_USERS" ] || [ -n "$SSH_ALLOW_GROUPS" ]; then
        log "INFO" "- Access restrictions: APPLIED"
    fi

    log "INFO" "="

    # Show current connections
    monitor_ssh_connections

    # Cleanup emergency access if it was created
    if [ -f "$STATE_DIR/emergency_ssh_port" ]; then
        show_warning "Emergency SSH access is still active on port $(cat "$STATE_DIR/emergency_ssh_port")"
        printf "Remove emergency access? (y/N): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                kill_emergency_ssh
                show_success "Emergency SSH access removed"
                ;;
            *)
                show_warning "Emergency SSH access retained for safety"
                ;;
        esac
    fi

    exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

# Run main function
main "$@"