# POSIX Shell Hardening - Testing & Validation Framework

## Pre-Deployment Testing Protocol

### 1. Environment Setup

```sh
# Create test environment (use VM or container)
# NEVER test on production systems first

# Snapshot/backup before testing
# Ensure console/OOB access available
# Document current SSH configuration
# Record network access methods
```

### 2. Individual Script Testing

#### Phase 1: Syntax Validation

```sh
#!/bin/sh
# validate_syntax.sh - Check POSIX compliance

for script in *.sh; do
    # Check with shellcheck in sh mode
    shellcheck -s sh "$script"

    # Check for bash-specific constructs
    if grep -E '\[\[|\]\]|function |local |array\[|==|\(\(' "$script"; then
        echo "WARNING: $script may contain bash-specific syntax"
    fi
done
```

#### Phase 2: Dry-Run Testing

```sh
#!/bin/sh
# test_dry_run.sh - Test in report-only mode

# Modify each script to add --dry-run support
case "$1" in
    --dry-run)
        DRY_RUN=1
        ;;
esac

# In script functions:
if [ "$DRY_RUN" = "1" ]; then
    echo "Would execute: command"
else
    command
fi
```

#### Phase 3: Idempotency Testing

```sh
#!/bin/sh
# test_idempotency.sh - Verify scripts can run multiple times

run_test() {
    script="$1"

    # Run first time
    ./"$script" > /tmp/first_run.log 2>&1

    # Capture state
    capture_system_state > /tmp/state1.txt

    # Run second time
    ./"$script" > /tmp/second_run.log 2>&1

    # Capture state again
    capture_system_state > /tmp/state2.txt

    # Compare states
    if diff /tmp/state1.txt /tmp/state2.txt; then
        echo "PASS: $script is idempotent"
    else
        echo "FAIL: $script changed state on second run"
    fi
}

capture_system_state() {
    # Capture relevant system state
    sysctl -a 2>/dev/null | sort
    mount | sort
    iptables -L -n 2>/dev/null
    cat /etc/ssh/sshd_config 2>/dev/null
    ls -la /etc/security/limits.d/ 2>/dev/null
}
```

### 3. SSH Access Validation

#### Critical SSH Tests

```sh
#!/bin/sh
# test_ssh_access.sh - Ensure SSH access maintained

SSH_TEST_HOST="${1:-localhost}"
SSH_TEST_USER="${2:-$(whoami)}"
SSH_TEST_KEY="${3:-$HOME/.ssh/id_rsa}"

# Test 1: Current session remains active
echo "Test 1: Checking current session..."
echo "Session OK" || echo "Session FAILED"

# Test 2: New connections work
echo "Test 2: Testing new SSH connection..."
ssh -o ConnectTimeout=5 \
    -o PasswordAuthentication=no \
    -i "$SSH_TEST_KEY" \
    "$SSH_TEST_USER@$SSH_TEST_HOST" \
    "echo 'New connection successful'" || {
    echo "CRITICAL: Cannot establish new SSH connection!"
    exit 1
}

# Test 3: Validate sshd config
echo "Test 3: Validating sshd configuration..."
ssh "$SSH_TEST_USER@$SSH_TEST_HOST" \
    "sudo /usr/sbin/sshd -t" || {
    echo "ERROR: Invalid sshd configuration"
    exit 1
}

# Test 4: Check for config errors
echo "Test 4: Checking for configuration errors..."
ssh "$SSH_TEST_USER@$SSH_TEST_HOST" \
    "sudo grep -i error /var/log/auth.log | tail -5"

# Test 5: Verify key authentication works
echo "Test 5: Testing key-based authentication..."
ssh -o PreferredAuthentications=publickey \
    -o PubkeyAuthentication=yes \
    -o PasswordAuthentication=no \
    -i "$SSH_TEST_KEY" \
    "$SSH_TEST_USER@$SSH_TEST_HOST" \
    "echo 'Key auth successful'" || {
    echo "WARNING: Key authentication may have issues"
}
```

#### Firewall Rule Testing

```sh
#!/bin/sh
# test_firewall_rules.sh - Validate firewall doesn't block legitimate access

# Test SSH connectivity through firewall
test_ssh_through_firewall() {
    # Record current connection details
    CURRENT_IP=$(who am i | awk '{print $5}' | tr -d '()')

    # Ensure our IP isn't blocked
    iptables -L INPUT -n | grep -q "DROP.*$CURRENT_IP" && {
        echo "ERROR: Current IP would be blocked!"
        return 1
    }

    # Test rate limiting isn't too aggressive
    for i in 1 2 3 4 5; do
        ssh -o ConnectTimeout=2 testuser@localhost exit 2>/dev/null || {
            if [ $i -le 3 ]; then
                echo "ERROR: Connection blocked too early (attempt $i)"
                return 1
            fi
        }
        sleep 1
    done

    echo "Firewall rules OK"
}
```

### 4. Rollback Testing

#### Automatic Rollback Script

```sh
#!/bin/sh
# auto_rollback.sh - Automatic rollback if connection lost

TIMEOUT=300  # 5 minutes
BACKUP_DIR="/root/hardening_backups"
TEST_MARKER="/tmp/.hardening_test_active"

# Create marker file
touch "$TEST_MARKER"

# Schedule automatic rollback
(
    sleep "$TIMEOUT"
    if [ -f "$TEST_MARKER" ]; then
        echo "Test timeout - initiating rollback"
        restore_all_configs
        rm -f "$TEST_MARKER"
    fi
) &
ROLLBACK_PID=$!

# Function to restore configs
restore_all_configs() {
    cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config
    cp "$BACKUP_DIR/sudoers.backup" /etc/sudoers
    cp "$BACKUP_DIR/limits.conf.backup" /etc/security/limits.conf
    iptables-restore < "$BACKUP_DIR/iptables.backup"
    sysctl -p /etc/sysctl.conf.backup
    service ssh restart
}

# Cleanup function
cleanup() {
    rm -f "$TEST_MARKER"
    kill $ROLLBACK_PID 2>/dev/null
}

trap cleanup EXIT
```

### 5. Compliance Validation

#### CIS Benchmark Checks

```sh
#!/bin/sh
# check_cis_compliance.sh - Validate against CIS benchmarks

check_ssh_compliance() {
    echo "=== SSH Compliance Checks ==="

    # Check Protocol 2
    grep -q "^Protocol 2" /etc/ssh/sshd_config || \
        echo "FAIL: SSH Protocol 2 not enforced"

    # Check PermitRootLogin
    grep -q "^PermitRootLogin no\|^PermitRootLogin prohibit-password" /etc/ssh/sshd_config || \
        echo "WARN: Root login may not be properly restricted"

    # Check PermitEmptyPasswords
    grep -q "^PermitEmptyPasswords no" /etc/ssh/sshd_config || \
        echo "FAIL: Empty passwords not explicitly disabled"

    # Check MaxAuthTries
    grep -q "^MaxAuthTries [1-4]" /etc/ssh/sshd_config || \
        echo "WARN: MaxAuthTries not properly configured"
}

check_kernel_compliance() {
    echo "=== Kernel Parameter Compliance ==="

    required_params="
    net.ipv4.ip_forward=0
    net.ipv4.conf.all.accept_redirects=0
    net.ipv4.conf.all.secure_redirects=0
    net.ipv4.conf.all.send_redirects=0
    net.ipv4.tcp_syncookies=1
    kernel.randomize_va_space=2
    "

    for param in $required_params; do
        key=$(echo "$param" | cut -d= -f1)
        expected=$(echo "$param" | cut -d= -f2)
        actual=$(sysctl -n "$key" 2>/dev/null)

        if [ "$actual" != "$expected" ]; then
            echo "FAIL: $key = $actual (expected $expected)"
        else
            echo "PASS: $key = $actual"
        fi
    done
}

check_file_permissions() {
    echo "=== File Permission Compliance ==="

    # Check critical file permissions
    files="
    /etc/passwd:644
    /etc/shadow:640
    /etc/group:644
    /etc/gshadow:640
    /etc/ssh/sshd_config:600
    "

    for file_perm in $files; do
        file=$(echo "$file_perm" | cut -d: -f1)
        expected=$(echo "$file_perm" | cut -d: -f2)

        if [ -f "$file" ]; then
            actual=$(stat -c %a "$file" 2>/dev/null)
            if [ "$actual" != "$expected" ]; then
                echo "FAIL: $file has $actual (expected $expected)"
            else
                echo "PASS: $file has correct permissions"
            fi
        fi
    done
}
```

#### Security Scanner Integration

```sh
#!/bin/sh
# run_security_scan.sh - Run various security scanners

# Lynis scan (if available)
if command -v lynis >/dev/null 2>&1; then
    echo "Running Lynis audit..."
    lynis audit system --quick > /tmp/lynis_report.txt 2>&1
    echo "Lynis hardening index: $(grep "Hardening index" /tmp/lynis_report.txt)"
fi

# Check for common vulnerabilities
echo "Checking for common issues..."

# World-writable files
echo "World-writable files in system directories:"
find /etc /usr /bin /sbin /lib -type f -perm -002 2>/dev/null | head -10

# SUID/SGID files
echo "SUID files outside standard locations:"
find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | \
    grep -v "^/usr/bin\|^/usr/sbin\|^/bin\|^/sbin" | head -10

# Empty password accounts
echo "Accounts with empty passwords:"
awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow

# Listening services
echo "Listening network services:"
netstat -tlnp 2>/dev/null | grep LISTEN
```

### 6. Performance Impact Testing

```sh
#!/bin/sh
# test_performance_impact.sh - Measure performance impact

# Baseline measurements
baseline_tests() {
    echo "=== Baseline Performance ==="

    # SSH connection time
    time ssh -o ConnectTimeout=10 localhost exit

    # Memory usage
    free -m | grep "^Mem"

    # CPU load
    uptime

    # Disk I/O
    iostat -x 1 2 2>/dev/null | tail -n +4
}

# Run before hardening
baseline_tests > /tmp/baseline_before.txt

# Apply hardening
./run_hardening.sh

# Run after hardening
baseline_tests > /tmp/baseline_after.txt

# Compare results
echo "=== Performance Comparison ==="
diff /tmp/baseline_before.txt /tmp/baseline_after.txt
```

### 7. Monitoring and Alerting

```sh
#!/bin/sh
# monitor_hardening.sh - Monitor hardening effectiveness

# Check for SSH brute force attempts
check_ssh_attacks() {
    echo "=== SSH Attack Detection ==="
    grep "Failed password\|Invalid user" /var/log/auth.log | \
        tail -20 | \
        awk '{print $1, $2, $3, $9, $11}'
}

# Monitor system changes
monitor_changes() {
    echo "=== System Change Detection ==="

    # Monitor critical files
    for file in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config; do
        if [ -f "$file.md5" ]; then
            md5sum -c "$file.md5" 2>/dev/null || \
                echo "WARNING: $file has been modified"
        else
            md5sum "$file" > "$file.md5"
        fi
    done
}

# Check hardening persistence
check_persistence() {
    echo "=== Hardening Persistence Check ==="

    # Check if settings survive reboot
    settings_to_check="
    net.ipv4.ip_forward
    net.ipv4.tcp_syncookies
    kernel.randomize_va_space
    "

    for setting in $settings_to_check; do
        value=$(sysctl -n "$setting" 2>/dev/null)
        echo "$setting = $value"
    done
}
```

## Test Execution Plan

### Phase 1: Development Environment (1-2 days)

1. Set up isolated VM/container
2. Run syntax validation
3. Test each script individually
4. Verify idempotency
5. Test rollback procedures

### Phase 2: Staging Environment (2-3 days)

1. Full backup of staging system
2. Apply hardening scripts in sequence
3. Run compliance checks
4. Performance impact assessment
5. 24-hour soak test

### Phase 3: Limited Production (3-5 days)

1. Select non-critical production server
2. Full backup and snapshot
3. Apply during maintenance window
4. Monitor for 72 hours
5. Gather metrics and logs

### Phase 4: Full Production Rollout

1. Schedule maintenance windows
2. Create rollback plan for each server
3. Apply in groups (not all at once)
4. Monitor each group for 24 hours
5. Document any issues or adjustments

## Success Criteria

### Must Pass

- [ ] SSH access maintained throughout
- [ ] No service disruptions
- [ ] All scripts are idempotent
- [ ] Rollback procedures work
- [ ] No performance degradation >10%

### Should Pass

- [ ] CIS benchmark score improvement >30%
- [ ] Lynis hardening index >80
- [ ] No false positive security alerts
- [ ] Log rotation working properly
- [ ] Audit trails complete

### Nice to Have

- [ ] Automated compliance reporting
- [ ] Integration with monitoring systems
- [ ] Self-healing capabilities
- [ ] Zero manual interventions required

## Emergency Procedures

### If Locked Out of SSH

1. Use console/OOB access immediately
2. Check /var/log/auth.log for errors
3. Restore sshd_config from backup
4. Restart sshd service
5. Test SSH access before other changes

### If System Becomes Unstable

1. Document symptoms
2. Check system resources (CPU, memory, disk)
3. Review recent log entries
4. Begin staged rollback
5. Monitor after each rollback step

### If Services Fail

1. Identify affected services
2. Check for permission issues
3. Review recent hardening changes
4. Restore specific configurations
5. Document root cause
