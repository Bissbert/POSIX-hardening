#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# validation_suite.sh - Comprehensive validation tests
# Verifies hardening has been applied correctly without breaking system

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Source libraries
. "$LIB_DIR/common.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# ============================================================================
# Test Framework
# ============================================================================

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected="${3:-0}"

    printf "Testing: %-50s " "$test_name"

    if eval "$test_command"; then
        if [ "$expected" -eq 0 ]; then
            printf "[PASS]\n"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            printf "[FAIL] (expected failure)\n"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if [ "$expected" -ne 0 ]; then
            printf "[PASS] (correctly failed)\n"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            printf "[FAIL]\n"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi
}

warn_test() {
    local test_name="$1"
    local message="$2"

    printf "Testing: %-50s [WARN] %s\n" "$test_name" "$message"
    TESTS_WARNED=$((TESTS_WARNED + 1))
}

# ============================================================================
# SSH Tests
# ============================================================================

test_ssh() {
    echo ""
    echo "=== SSH Configuration Tests ==="

    # Check SSH daemon is running
    run_test "SSH daemon running" "pgrep -x sshd >/dev/null 2>&1"

    # Check SSH port is listening
    run_test "SSH port listening" "netstat -tln | grep -q ':${SSH_PORT:-22} ' 2>/dev/null || ss -tln | grep -q ':${SSH_PORT:-22} ' 2>/dev/null"

    # Check SSH config exists
    run_test "SSH config exists" "[ -f /etc/ssh/sshd_config ]"

    # Check critical SSH settings
    if [ -f /etc/ssh/sshd_config ]; then
        run_test "PermitRootLogin disabled" "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"
        run_test "PasswordAuthentication disabled" "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"
        run_test "PubkeyAuthentication enabled" "grep -q '^PubkeyAuthentication yes' /etc/ssh/sshd_config"
        run_test "PermitEmptyPasswords disabled" "grep -q '^PermitEmptyPasswords no' /etc/ssh/sshd_config"
    fi

    # Check SSH key permissions
    if [ -d /root/.ssh ]; then
        run_test "Root .ssh directory permissions" "[ $(stat -c %a /root/.ssh 2>/dev/null || stat -f %Lp /root/.ssh 2>/dev/null) = '700' ]"
    fi
}

# ============================================================================
# Firewall Tests
# ============================================================================

test_firewall() {
    echo ""
    echo "=== Firewall Tests ==="

    if ! command -v iptables >/dev/null 2>&1; then
        warn_test "Firewall" "iptables not found"
        return
    fi

    # Check default policies
    run_test "INPUT policy set" "iptables -L INPUT -n | head -1 | grep -q 'policy DROP\|policy REJECT'"

    # Check SSH rule exists
    run_test "SSH port allowed" "iptables -L INPUT -n | grep -q 'dpt:${SSH_PORT:-22}'"

    # Check established connections allowed
    run_test "Established connections allowed" "iptables -L INPUT -n | grep -q 'state RELATED,ESTABLISHED'"

    # Check if rules are saved
    run_test "Firewall rules saved" "[ -f /etc/iptables/rules.v4 ] || [ -f /etc/sysconfig/iptables ]"
}

# ============================================================================
# Kernel Parameter Tests
# ============================================================================

test_kernel() {
    echo ""
    echo "=== Kernel Parameter Tests ==="

    # Check critical kernel parameters
    run_test "TCP SYN cookies enabled" "[ $(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null) = '1' ]"
    run_test "IP forwarding disabled" "[ $(sysctl -n net.ipv4.ip_forward 2>/dev/null) = '0' ]"
    run_test "Source route disabled" "[ $(sysctl -n net.ipv4.conf.all.accept_source_route 2>/dev/null) = '0' ]"
    run_test "ICMP redirects disabled" "[ $(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null) = '0' ]"
    run_test "Secure redirects disabled" "[ $(sysctl -n net.ipv4.conf.all.secure_redirects 2>/dev/null) = '0' ]"
    run_test "Martians logging enabled" "[ $(sysctl -n net.ipv4.conf.all.log_martians 2>/dev/null) = '1' ]"
    run_test "RP filter enabled" "[ $(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null) = '1' ]"
}

# ============================================================================
# File Permission Tests
# ============================================================================

test_permissions() {
    echo ""
    echo "=== File Permission Tests ==="

    # Check critical file permissions
    run_test "/etc/passwd permissions" "[ -f /etc/passwd ] && [ $(stat -c %a /etc/passwd 2>/dev/null || stat -f %Lp /etc/passwd 2>/dev/null) = '644' ]"
    run_test "/etc/shadow permissions" "[ -f /etc/shadow ] && [ $(stat -c %a /etc/shadow 2>/dev/null || stat -f %Lp /etc/shadow 2>/dev/null) = '640' ]"
    run_test "/etc/ssh/sshd_config permissions" "[ -f /etc/ssh/sshd_config ] && [ $(stat -c %a /etc/ssh/sshd_config 2>/dev/null || stat -f %Lp /etc/ssh/sshd_config 2>/dev/null) = '600' ]"

    # Check for world-writable files
    run_test "No world-writable files in /etc" "! find /etc -xdev -type f -perm -002 2>/dev/null | grep -q ."
}

# ============================================================================
# Service Tests
# ============================================================================

test_services() {
    echo ""
    echo "=== Service Tests ==="

    # Check unnecessary services are disabled
    for service in bluetooth cups avahi-daemon; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^$service"; then
            run_test "$service disabled" "! systemctl is-enabled $service 2>/dev/null | grep -q enabled"
        fi
    done
}

# ============================================================================
# Account Tests
# ============================================================================

test_accounts() {
    echo ""
    echo "=== Account Security Tests ==="

    # Check for accounts with empty passwords
    run_test "No empty password accounts" "! awk -F: '(\$2 == \"\" || \$2 == \"!\") {print \$1}' /etc/shadow 2>/dev/null | grep -v '^root$' | grep -q ."

    # Check password policy
    if [ -f /etc/login.defs ]; then
        run_test "Password max age set" "grep -q '^PASS_MAX_DAYS[[:space:]]*90' /etc/login.defs"
        run_test "Password min length set" "grep -q '^PASS_MIN_LEN[[:space:]]*12' /etc/login.defs"
    fi
}

# ============================================================================
# Audit Tests
# ============================================================================

test_audit() {
    echo ""
    echo "=== Audit and Logging Tests ==="

    # Check if audit logging is configured
    if [ -f /etc/rsyslog.conf ]; then
        run_test "Auth logging configured" "grep -q 'auth,authpriv.*' /etc/rsyslog.conf"
    fi

    # Check log file permissions
    run_test "Auth log exists" "[ -f /var/log/auth.log ] || [ -f /var/log/secure ]"
}

# ============================================================================
# Network Tests
# ============================================================================

test_network() {
    echo ""
    echo "=== Network Security Tests ==="

    # Test network connectivity
    run_test "Loopback interface working" "ping -c 1 127.0.0.1 >/dev/null 2>&1"

    # Check listening ports
    open_ports=$(netstat -tln 2>/dev/null | grep LISTEN | wc -l || ss -tln 2>/dev/null | grep LISTEN | wc -l)
    if [ "$open_ports" -lt 10 ]; then
        printf "Testing: %-50s [PASS] (%s listening ports)\n" "Minimal open ports" "$open_ports"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "Testing: %-50s [WARN] (%s listening ports)\n" "Check open ports" "$open_ports"
        TESTS_WARNED=$((TESTS_WARNED + 1))
    fi
}

# ============================================================================
# Compliance Check
# ============================================================================

test_compliance() {
    echo ""
    echo "=== Compliance Checks ==="

    # Check if all hardening scripts completed
    if [ -f "$STATE_DIR/completed" ]; then
        completed_count=$(wc -l < "$STATE_DIR/completed")
        if [ "$completed_count" -ge 15 ]; then
            printf "Testing: %-50s [PASS] (%s/20 completed)\n" "Hardening scripts executed" "$completed_count"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            printf "Testing: %-50s [WARN] (%s/20 completed)\n" "Partial hardening" "$completed_count"
            TESTS_WARNED=$((TESTS_WARNED + 1))
        fi
    else
        warn_test "Hardening status" "No completion records found"
    fi
}

# ============================================================================
# Performance Tests
# ============================================================================

test_performance() {
    echo ""
    echo "=== System Performance Tests ==="

    # Check system load
    load=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
    if [ "$(echo "$load < 2" | bc 2>/dev/null || echo 1)" -eq 1 ]; then
        printf "Testing: %-50s [PASS] (load: %s)\n" "System load acceptable" "$load"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "Testing: %-50s [WARN] (load: %s)\n" "System load high" "$load"
        TESTS_WARNED=$((TESTS_WARNED + 1))
    fi

    # Check disk space
    root_usage=$(df / | awk 'NR==2 {print int($5)}')
    if [ "$root_usage" -lt 90 ]; then
        printf "Testing: %-50s [PASS] (%s%% used)\n" "Disk space available" "$root_usage"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        printf "Testing: %-50s [WARN] (%s%% used)\n" "Low disk space" "$root_usage"
        TESTS_WARNED=$((TESTS_WARNED + 1))
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

print_summary() {
    echo ""
    echo "========================================="
    echo "Validation Summary"
    echo "========================================="
    echo "Tests Passed:  $TESTS_PASSED"
    echo "Tests Failed:  $TESTS_FAILED"
    echo "Tests Warning: $TESTS_WARNED"
    echo "========================================="

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo "Status: ALL CRITICAL TESTS PASSED"
        return 0
    else
        echo "Status: SOME TESTS FAILED - REVIEW NEEDED"
        return 1
    fi
}

main() {
    echo "========================================="
    echo "POSIX Hardening Validation Suite"
    echo "========================================="
    echo "Running comprehensive validation tests..."

    # Run all test categories
    test_ssh
    test_firewall
    test_kernel
    test_permissions
    test_services
    test_accounts
    test_audit
    test_network
    test_compliance
    test_performance

    # Print summary
    print_summary

    exit $?
}

# Run main
main "$@"