#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/ssh_safety.sh - SSH preservation and safety mechanisms
# Critical: Prevents lockout on remote servers

# Note: common.sh should be sourced before this file
# Source POSIX compatibility layer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/posix_compat.sh"

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
    _connection_ok=0

    # Check 1: Are we in an SSH session?
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        log "DEBUG" "Currently in SSH session"
        _connection_ok=1
    fi

    # Check 2: Is SSHD running?
    if pgrep -x sshd >/dev/null 2>&1; then
        log "DEBUG" "SSH daemon is active"
    else
        log "ERROR" "SSH daemon is not running!"
        unset _connection_ok
        return 1
    fi

    # Check 3: Can we connect to SSH port?
    if command -v nc >/dev/null 2>&1; then
        if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
            log "DEBUG" "SSH port $SSH_PORT is open"
        else
            log "ERROR" "SSH port $SSH_PORT is not responding"
            unset _connection_ok
            return 1
        fi
    fi

    # Check 4: Test SSH configuration syntax
    if [ -f "$SSHD_CONFIG" ]; then
        if ! /usr/sbin/sshd -t -f "$SSHD_CONFIG" 2>/dev/null; then
            log "ERROR" "Current SSH configuration has syntax errors!"
            unset _connection_ok
            return 1
        fi
    fi

    unset _connection_ok
    return 0
}

# Create a safe test copy of SSH configuration
create_ssh_test_config() {
    _test_config="${1:-${SSHD_CONFIG}.test}"
    _test_port="${2:-$SSHD_TEST_PORT}"

    if [ ! -f "$SSHD_CONFIG" ]; then
        log "ERROR" "SSH config file not found: $SSHD_CONFIG"
        unset _test_config _test_port
        return 1
    fi

    # Create test configuration
    if ! cp "$SSHD_CONFIG" "$_test_config"; then
        unset _test_config _test_port
        return 1
    fi

    # Modify to use test port
    if grep -q "^Port " "$_test_config" 2>/dev/null; then
        posix_sed_inplace "s/^Port .*/Port $_test_port/" "$_test_config"
    else
        echo "Port $_test_port" >> "$_test_config"
    fi

    # Add PID file for test instance
    if grep -q "^PidFile " "$_test_config" 2>/dev/null; then
        posix_sed_inplace "s|^PidFile .*|PidFile /var/run/sshd_test.pid|" "$_test_config"
    else
        echo "PidFile /var/run/sshd_test.pid" >> "$_test_config"
    fi

    log "DEBUG" "Created test SSH config: $_test_config on port $_test_port"
    echo "$_test_config"
    unset _test_port
}

# Test SSH configuration before applying
test_ssh_config() {
    _config_file="${1:-$SSHD_CONFIG}"

    log "INFO" "Testing SSH configuration: $_config_file"

    # Syntax check
    if ! /usr/sbin/sshd -t -f "$_config_file" 2>/dev/null; then
        log "ERROR" "SSH configuration syntax check failed"
        unset _config_file
        return 1
    fi

    log "DEBUG" "SSH configuration syntax is valid"

    # If not in dry run, test with actual daemon (skip if SKIP_SSH_DAEMON_TEST=1)
    if [ "$DRY_RUN" != "1" ] && [ "$SKIP_SSH_DAEMON_TEST" != "1" ]; then
        _test_config_result=$(create_ssh_test_config "$_config_file.test" "$SSHD_TEST_PORT")

        if [ -z "$_test_config_result" ]; then
            unset _config_file _test_config_result
            return 1
        fi

        # Start test SSH daemon
        log "DEBUG" "Starting test SSH daemon on port $SSHD_TEST_PORT"
        if /usr/sbin/sshd -f "$_test_config_result"; then
            sleep 2

            # Test connection to test instance
            if timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSHD_TEST_PORT" 2>/dev/null; then
                log "INFO" "Test SSH daemon is accepting connections"

                # Kill test daemon
                if [ -f /var/run/sshd_test.pid ]; then
                    kill "$(cat /var/run/sshd_test.pid)" 2>/dev/null
                fi

                rm -f "$_test_config_result"
                unset _config_file _test_config_result
                return 0
            else
                log "ERROR" "Test SSH daemon not accepting connections"

                # Kill test daemon
                if [ -f /var/run/sshd_test.pid ]; then
                    kill "$(cat /var/run/sshd_test.pid)" 2>/dev/null
                fi

                rm -f "$_test_config_result"
                unset _config_file _test_config_result
                return 1
            fi
        else
            log "ERROR" "Failed to start test SSH daemon"
            rm -f "$_test_config_result"
            unset _config_file _test_config_result
            return 1
        fi
    fi

    unset _config_file
    return 0
}

# ============================================================================
# SSH Configuration Updates with Rollback
# ============================================================================

# Update SSH configuration with automatic rollback on failure
update_ssh_config_safe() {
    _changes_function="$1"  # Function that makes the changes
    _rollback_pid=""

    if [ -z "$_changes_function" ]; then
        log "ERROR" "No changes function provided"
        unset _changes_function _rollback_pid
        return 1
    fi

    # Verify current SSH connection
    if ! verify_ssh_connection; then
        unset _changes_function _rollback_pid
        die "SSH connection verification failed - aborting"
    fi

    # Backup current configuration
    _backup_file=$(safe_backup_file "$SSHD_CONFIG")

    if [ -z "$_backup_file" ]; then
        unset _changes_function _rollback_pid _backup_file
        die "Failed to backup SSH configuration"
    fi

    log "INFO" "SSH config backed up to: $_backup_file"

    # Create working copy
    _work_config="${SSHD_CONFIG}.work"
    cp "$SSHD_CONFIG" "$_work_config"

    # Apply changes to working copy
    log "INFO" "Applying SSH configuration changes"
    if ! $_changes_function "$_work_config"; then
        log "ERROR" "Failed to apply changes to SSH configuration"
        rm -f "$_work_config"
        unset _changes_function _rollback_pid _backup_file _work_config
        return 1
    fi

    # Test new configuration
    if ! test_ssh_config "$_work_config"; then
        log "ERROR" "New SSH configuration failed testing"
        rm -f "$_work_config"
        unset _changes_function _rollback_pid _backup_file _work_config
        return 1
    fi

    # If in dry run mode, stop here
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would update SSH configuration (changes validated)"
        rm -f "$_work_config"
        unset _changes_function _rollback_pid _backup_file _work_config
        return 0
    fi

    # Set up automatic rollback
    log "INFO" "Setting up automatic rollback (${SSH_ROLLBACK_TIMEOUT}s timeout)"
    (
        sleep "$SSH_ROLLBACK_TIMEOUT"
        if ! timeout "$SSH_TEST_TIMEOUT" nc -z localhost "$SSH_PORT" 2>/dev/null; then
            log "ERROR" "SSH not responding - executing rollback"
            cp "$_backup_file" "$SSHD_CONFIG"
            kill -HUP "$(cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null || \
                /usr/sbin/sshd
            log "INFO" "SSH configuration rolled back"
        fi
    ) &
    _rollback_pid=$!

    # Move new configuration into place
    mv "$_work_config" "$SSHD_CONFIG"

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
        if [ -n "$_rollback_pid" ]; then
            kill "$_rollback_pid" 2>/dev/null
            log "DEBUG" "Cancelled automatic rollback"
        fi

        unset _changes_function _rollback_pid _backup_file _work_config
        show_success "SSH configuration updated successfully"
        return 0
    else
        log "ERROR" "SSH not responding after reload"

        # Rollback will happen automatically
        unset _changes_function _rollback_pid _backup_file _work_config
        show_error "SSH update failed - automatic rollback in progress"
        return 1
    fi
}

# ============================================================================
# SSH Hardening Checks
# ============================================================================

# Check if an SSH setting exists and has expected value
check_ssh_setting() {
    _setting="$1"
    _expected="$2"
    _config="${3:-$SSHD_CONFIG}"

    if [ ! -f "$_config" ]; then
        unset _setting _expected _config
        return 1
    fi

    # Check if setting exists and is not commented
    if grep -q "^$_setting $_expected" "$_config"; then
        unset _setting _expected _config
        return 0  # Setting is correct
    else
        unset _setting _expected _config
        return 1  # Setting needs update
    fi
}

# Update or add SSH setting
update_ssh_setting() {
    _config="$1"
    _setting="$2"
    _value="$3"

    if [ ! -f "$_config" ]; then
        log "ERROR" "Config file not found: $_config"
        unset _config _setting _value
        return 1
    fi

    # Check if setting exists (commented or not)
    if grep -q "^#*$_setting " "$_config"; then
        # Update existing setting (use | as delimiter to handle paths with /)
        posix_sed_inplace "s|^#*$_setting .*|$_setting $_value|" "$_config"
        log "DEBUG" "Updated: $_setting $_value"
    else
        # Add new setting
        echo "$_setting $_value" >> "$_config"
        log "DEBUG" "Added: $_setting $_value"
    fi

    unset _config _setting _value
}

# ============================================================================
# SSH Key Management
# ============================================================================

# Ensure SSH keys have correct permissions
fix_ssh_key_permissions() {
    _ssh_dir="${1:-/root/.ssh}"
    _user="${2:-root}"

    if [ ! -d "$_ssh_dir" ]; then
        log "DEBUG" "SSH directory does not exist: $_ssh_dir"
        unset _ssh_dir _user
        return 0
    fi

    # Fix directory permissions
    chmod 700 "$_ssh_dir"
    chown "$_user:$_user" "$_ssh_dir"

    # Fix authorized_keys if it exists
    if [ -f "$_ssh_dir/authorized_keys" ]; then
        chmod 600 "$_ssh_dir/authorized_keys"
        chown "$_user:$_user" "$_ssh_dir/authorized_keys"
        log "INFO" "Fixed permissions for $_ssh_dir/authorized_keys"
    fi

    # Fix private keys
    for _key in "$_ssh_dir"/id_*; do
        if [ -f "$_key" ] && [ "${_key%.pub}" = "$_key" ]; then
            chmod 600 "$_key"
            chown "$_user:$_user" "$_key"
            log "INFO" "Fixed permissions for private key: $_key"
        fi
    done

    # Fix public keys
    for _key in "$_ssh_dir"/*.pub; do
        if [ -f "$_key" ]; then
            chmod 644 "$_key"
            chown "$_user:$_user" "$_key"
            log "INFO" "Fixed permissions for public key: $_key"
        fi
    done

    unset _ssh_dir _user _key
}

# ============================================================================
# SSH Access Control
# ============================================================================

# Manage SSH allow/deny lists
manage_ssh_access() {
    _action="$1"  # allow or deny
    _type="$2"    # users or groups
    _list="$3"    # space-separated list

    _setting=""
    case "$_action-$_type" in
        allow-users)
            _setting="AllowUsers"
            ;;
        allow-groups)
            _setting="AllowGroups"
            ;;
        deny-users)
            _setting="DenyUsers"
            ;;
        deny-groups)
            _setting="DenyGroups"
            ;;
        *)
            log "ERROR" "Invalid action/type: $_action/$_type"
            unset _action _type _list _setting
            return 1
            ;;
    esac

    # Create function to update config
    update_access() {
        _ua_config="$1"
        update_ssh_setting "$_ua_config" "$_setting" "$_list"
        unset _ua_config
    }

    # Apply with safety
    update_ssh_config_safe update_access
    unset _action _type _list _setting
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
        who | grep pts || true
    fi

    # Method 2: Check established SSH connections
    if command -v ss >/dev/null 2>&1; then
        ss -tn state established '( sport = :22 or dport = :22 )' || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tn | grep ':22 ' | grep ESTABLISHED || true
    fi

    # Method 3: Check SSH daemon status
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null || true
    fi

    # Always return success (this is informational only)
    return 0
}

# ============================================================================
# Emergency SSH Recovery
# ============================================================================

# Create emergency SSH access method
create_emergency_ssh_access() {
    _emergency_port="${1:-2222}"
    _emergency_config="/etc/ssh/sshd_emergency_config"

    log "WARN" "Creating emergency SSH access on port $_emergency_port"

    # Create minimal emergency config
    cat > "$_emergency_config" <<EOF
# Emergency SSH Configuration
Port $_emergency_port
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PidFile /var/run/sshd_emergency.pid
EOF

    # Test emergency config
    if ! /usr/sbin/sshd -t -f "$_emergency_config"; then
        log "ERROR" "Emergency SSH config invalid"
        rm -f "$_emergency_config"
        unset _emergency_port _emergency_config
        return 1
    fi

    # Start emergency SSH daemon
    if /usr/sbin/sshd -f "$_emergency_config"; then
        log "INFO" "Emergency SSH daemon started on port $_emergency_port"

        # Add firewall rule for emergency port
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT 1 -p tcp --dport "$_emergency_port" -j ACCEPT
        fi

        echo "$_emergency_port" > "$STATE_DIR/emergency_ssh_port"
        unset _emergency_port _emergency_config
        return 0
    else
        log "ERROR" "Failed to start emergency SSH daemon"
        rm -f "$_emergency_config"
        unset _emergency_port _emergency_config
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
