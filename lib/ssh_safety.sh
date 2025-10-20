#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/ssh_safety.sh - SSH preservation and safety mechanisms
# Critical: Prevents lockout on remote servers

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

# SSH-specific configuration
readonly SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
readonly SSHD_TEST_PORT="${SSHD_TEST_PORT:-2222}"
readonly SSH_ROLLBACK_TIMEOUT="${SSH_ROLLBACK_TIMEOUT:-60}"
readonly SSH_TEST_TIMEOUT="${SSH_TEST_TIMEOUT:-10}"

# ============================================================================
# SSH Connection Preservation
# ============================================================================

# Enhanced SSH connection verification
verify_ssh_connection() {
    local connection_ok=0

    # Check 1: Are we in an SSH session?
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        log "DEBUG" "Currently in SSH session"
        connection_ok=1
    fi

    # Check 2: Is SSHD running?
    if pgrep -x sshd >/dev/null 2>&1; then
        log "DEBUG" "SSH daemon is active"
    else
        log "ERROR" "SSH daemon is not running!"
        return 1
    fi

    # Check 3: Can we connect to SSH port?
    if command -v nc >/dev/null 2>&1; then
        if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
            log "DEBUG" "SSH port $SSH_PORT is open"
        else
            log "ERROR" "SSH port $SSH_PORT is not responding"
            return 1
        fi
    fi

    # Check 4: Test SSH configuration syntax
    if [ -f "$SSHD_CONFIG" ]; then
        if ! /usr/sbin/sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
            log "ERROR" "Current SSH configuration has syntax errors!"
            return 1
        fi
    fi

    return 0
}

# Create a safe test copy of SSH configuration
create_ssh_test_config() {
    local test_config="${1:-${SSHD_CONFIG}.test}"
    local test_port="${2:-$SSHD_TEST_PORT}"

    if [ ! -f "$SSHD_CONFIG" ]; then
        log "ERROR" "SSH config file not found: $SSHD_CONFIG"
        return 1
    fi

    # Create test configuration
    cp "$SSHD_CONFIG" "$test_config"

    # Modify to use test port
    if grep -q "^Port " "$test_config"; then
        sed -i "s/^Port .*/Port $test_port/" "$test_config"
    else
        echo "Port $test_port" >> "$test_config"
    fi

    # Add PID file for test instance
    if grep -q "^PidFile " "$test_config"; then
        sed -i "s|^PidFile .*|PidFile /var/run/sshd_test.pid|" "$test_config"
    else
        echo "PidFile /var/run/sshd_test.pid" >> "$test_config"
    fi

    log "DEBUG" "Created test SSH config: $test_config on port $test_port"
    echo "$test_config"
}

# Test SSH configuration before applying
test_ssh_config() {
    local config_file="${1:-$SSHD_CONFIG}"

    log "INFO" "Testing SSH configuration: $config_file"

    # Syntax check
    if ! /usr/sbin/sshd -t -f "$config_file" 2>/dev/null; then
        log "ERROR" "SSH configuration syntax check failed"
        return 1
    fi

    log "DEBUG" "SSH configuration syntax is valid"

    # If not in dry run, test with actual daemon
    if [ "$DRY_RUN" != "1" ]; then
        local test_config
        test_config=$(create_ssh_test_config "$config_file.test" "$SSHD_TEST_PORT")

        if [ -z "$test_config" ]; then
            return 1
        fi

        # Start test SSH daemon
        log "DEBUG" "Starting test SSH daemon on port $SSHD_TEST_PORT"
        if /usr/sbin/sshd -f "$test_config"; then
            sleep 2

            # Test connection to test instance
            if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSHD_TEST_PORT" 2>/dev/null; then
                log "INFO" "Test SSH daemon is accepting connections"

                # Kill test daemon
                if [ -f /var/run/sshd_test.pid ]; then
                    kill "$(cat /var/run/sshd_test.pid)" 2>/dev/null
                fi

                rm -f "$test_config"
                return 0
            else
                log "ERROR" "Test SSH daemon not accepting connections"

                # Kill test daemon
                if [ -f /var/run/sshd_test.pid ]; then
                    kill "$(cat /var/run/sshd_test.pid)" 2>/dev/null
                fi

                rm -f "$test_config"
                return 1
            fi
        else
            log "ERROR" "Failed to start test SSH daemon"
            rm -f "$test_config"
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# SSH Configuration Updates with Rollback
# ============================================================================

# Update SSH configuration with automatic rollback on failure
update_ssh_config_safe() {
    local changes_function="$1"  # Function that makes the changes
    local rollback_pid=""

    if [ -z "$changes_function" ]; then
        log "ERROR" "No changes function provided"
        return 1
    fi

    # Verify current SSH connection
    if ! verify_ssh_connection; then
        die "SSH connection verification failed - aborting"
    fi

    # Backup current configuration
    local backup_file
    backup_file=$(safe_backup_file "$SSHD_CONFIG")

    if [ -z "$backup_file" ]; then
        die "Failed to backup SSH configuration"
    fi

    log "INFO" "SSH config backed up to: $backup_file"

    # Create working copy
    local work_config="${SSHD_CONFIG}.work"
    cp "$SSHD_CONFIG" "$work_config"

    # Apply changes to working copy
    log "INFO" "Applying SSH configuration changes"
    if ! $changes_function "$work_config"; then
        log "ERROR" "Failed to apply changes to SSH configuration"
        rm -f "$work_config"
        return 1
    fi

    # Test new configuration
    if ! test_ssh_config "$work_config"; then
        log "ERROR" "New SSH configuration failed testing"
        rm -f "$work_config"
        return 1
    fi

    # If in dry run mode, stop here
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would update SSH configuration (changes validated)"
        rm -f "$work_config"
        return 0
    fi

    # Set up automatic rollback
    log "INFO" "Setting up automatic rollback (${SSH_ROLLBACK_TIMEOUT}s timeout)"
    (
        sleep "$SSH_ROLLBACK_TIMEOUT"
        if ! timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
            log "ERROR" "SSH not responding - executing rollback"
            cp "$backup_file" "$SSHD_CONFIG"
            kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null || \
                /usr/sbin/sshd
            log "INFO" "SSH configuration rolled back"
        fi
    ) &
    rollback_pid=$!

    # Move new configuration into place
    mv "$work_config" "$SSHD_CONFIG"

    # Reload SSH daemon
    log "INFO" "Reloading SSH daemon"
    if [ -f /var/run/sshd.pid ]; then
        kill -HUP "$(cat /var/run/sshd.pid)"
    else
        log "WARN" "SSH PID file not found, trying service reload"
        safe_service_reload "ssh" || safe_service_reload "sshd"
    fi

    # Wait a moment for SSH to reload
    sleep 3

    # Verify SSH is still accessible
    if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
        log "INFO" "SSH is responding after reload"

        # Cancel rollback
        if [ -n "$rollback_pid" ]; then
            kill "$rollback_pid" 2>/dev/null
            log "DEBUG" "Cancelled automatic rollback"
        fi

        show_success "SSH configuration updated successfully"
        return 0
    else
        log "ERROR" "SSH not responding after reload"

        # Rollback will happen automatically
        show_error "SSH update failed - automatic rollback in progress"
        return 1
    fi
}

# ============================================================================
# SSH Hardening Checks
# ============================================================================

# Check if an SSH setting exists and has expected value
check_ssh_setting() {
    local setting="$1"
    local expected="$2"
    local config="${3:-$SSHD_CONFIG}"

    if [ ! -f "$config" ]; then
        return 1
    fi

    # Check if setting exists and is not commented
    if grep -q "^$setting $expected" "$config"; then
        return 0  # Setting is correct
    else
        return 1  # Setting needs update
    fi
}

# Update or add SSH setting
update_ssh_setting() {
    local config="$1"
    local setting="$2"
    local value="$3"

    if [ ! -f "$config" ]; then
        log "ERROR" "Config file not found: $config"
        return 1
    fi

    # Check if setting exists (commented or not)
    if grep -q "^#*$setting " "$config"; then
        # Update existing setting
        sed -i "s/^#*$setting .*/$setting $value/" "$config"
        log "DEBUG" "Updated: $setting $value"
    else
        # Add new setting
        echo "$setting $value" >> "$config"
        log "DEBUG" "Added: $setting $value"
    fi
}

# ============================================================================
# SSH Key Management
# ============================================================================

# Ensure SSH keys have correct permissions
fix_ssh_key_permissions() {
    local ssh_dir="${1:-/root/.ssh}"
    local user="${2:-root}"

    if [ ! -d "$ssh_dir" ]; then
        log "DEBUG" "SSH directory does not exist: $ssh_dir"
        return 0
    fi

    # Fix directory permissions
    chmod 700 "$ssh_dir"
    chown "$user:$user" "$ssh_dir"

    # Fix authorized_keys if it exists
    if [ -f "$ssh_dir/authorized_keys" ]; then
        chmod 600 "$ssh_dir/authorized_keys"
        chown "$user:$user" "$ssh_dir/authorized_keys"
        log "INFO" "Fixed permissions for $ssh_dir/authorized_keys"
    fi

    # Fix private keys
    for key in "$ssh_dir"/id_*; do
        if [ -f "$key" ] && [ "${key%.pub}" = "$key" ]; then
            chmod 600 "$key"
            chown "$user:$user" "$key"
            log "INFO" "Fixed permissions for private key: $key"
        fi
    done

    # Fix public keys
    for key in "$ssh_dir"/*.pub; do
        if [ -f "$key" ]; then
            chmod 644 "$key"
            chown "$user:$user" "$key"
            log "INFO" "Fixed permissions for public key: $key"
        fi
    done
}

# ============================================================================
# SSH Access Control
# ============================================================================

# Manage SSH allow/deny lists
manage_ssh_access() {
    local action="$1"  # allow or deny
    local type="$2"    # users or groups
    local list="$3"    # space-separated list

    local setting=""
    case "$action-$type" in
        allow-users)
            setting="AllowUsers"
            ;;
        allow-groups)
            setting="AllowGroups"
            ;;
        deny-users)
            setting="DenyUsers"
            ;;
        deny-groups)
            setting="DenyGroups"
            ;;
        *)
            log "ERROR" "Invalid action/type: $action/$type"
            return 1
            ;;
    esac

    # Create function to update config
    update_access() {
        local config="$1"
        update_ssh_setting "$config" "$setting" "$list"
    }

    # Apply with safety
    update_ssh_config_safe update_access
}

# ============================================================================
# Firewall Rules for SSH
# ============================================================================

# Ensure firewall allows SSH before applying rules
ensure_ssh_firewall_access() {
    if ! command -v iptables >/dev/null 2>&1; then
        log "DEBUG" "iptables not available"
        return 0
    fi

    # Check if SSH port rule exists
    if iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null; then
        log "DEBUG" "SSH port $SSH_PORT already allowed in firewall"
        return 0
    fi

    log "INFO" "Adding firewall rule for SSH port $SSH_PORT"

    # Add rule to allow SSH (at the beginning to ensure it's evaluated first)
    iptables -I INPUT 1 -p tcp --dport "$SSH_PORT" -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -I OUTPUT 1 -p tcp --sport "$SSH_PORT" -m state --state ESTABLISHED -j ACCEPT

    # If admin IP is set, add specific rule for it
    if [ -n "$ADMIN_IP" ]; then
        iptables -I INPUT 1 -s "$ADMIN_IP" -p tcp --dport "$SSH_PORT" -j ACCEPT
        log "INFO" "Added priority firewall rule for admin IP: $ADMIN_IP"
    fi

    return 0
}

# ============================================================================
# SSH Connection Monitoring
# ============================================================================

# Monitor active SSH connections
monitor_ssh_connections() {
    log "INFO" "Current SSH connections:"

    # Method 1: Check who is logged in via SSH
    if command -v who >/dev/null 2>&1; then
        who | grep pts
    fi

    # Method 2: Check established SSH connections
    if command -v ss >/dev/null 2>&1; then
        ss -tn state established '( sport = :22 or dport = :22 )'
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tn | grep ':22 ' | grep ESTABLISHED
    fi

    # Method 3: Check SSH daemon status
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null
    fi
}

# ============================================================================
# Emergency SSH Recovery
# ============================================================================

# Create emergency SSH access method
create_emergency_ssh_access() {
    local emergency_port="${1:-2222}"
    local emergency_config="/etc/ssh/sshd_emergency_config"

    log "WARN" "Creating emergency SSH access on port $emergency_port"

    # Create minimal emergency config
    cat > "$emergency_config" <<EOF
# Emergency SSH Configuration
Port $emergency_port
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PidFile /var/run/sshd_emergency.pid
EOF

    # Test emergency config
    if ! /usr/sbin/sshd -t -f "$emergency_config"; then
        log "ERROR" "Emergency SSH config invalid"
        rm -f "$emergency_config"
        return 1
    fi

    # Start emergency SSH daemon
    if /usr/sbin/sshd -f "$emergency_config"; then
        log "INFO" "Emergency SSH daemon started on port $emergency_port"

        # Add firewall rule for emergency port
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT 1 -p tcp --dport "$emergency_port" -j ACCEPT
        fi

        echo "$emergency_port" > "$STATE_DIR/emergency_ssh_port"
        return 0
    else
        log "ERROR" "Failed to start emergency SSH daemon"
        rm -f "$emergency_config"
        return 1
    fi
}

# Kill emergency SSH daemon
kill_emergency_ssh() {
    if [ -f /var/run/sshd_emergency.pid ]; then
        kill "$(cat /var/run/sshd_emergency.pid)" 2>/dev/null
        rm -f /var/run/sshd_emergency.pid
        rm -f /etc/ssh/sshd_emergency_config
        rm -f "$STATE_DIR/emergency_ssh_port"
        log "INFO" "Emergency SSH daemon stopped"
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

#export -f verify_ssh_connection create_ssh_test_config test_ssh_config
#export -f update_ssh_config_safe check_ssh_setting update_ssh_setting
#export -f fix_ssh_key_permissions manage_ssh_access ensure_ssh_firewall_access
#export -f monitor_ssh_connections create_emergency_ssh_access kill_emergency_ssh