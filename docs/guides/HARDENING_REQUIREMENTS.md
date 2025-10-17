# POSIX Shell Server Hardening Toolkit - Requirements Analysis

## Critical Constraints
- **POSIX Shell Only**: No bash-specific features (arrays, [[ ]], etc.)
- **Remote Access Only**: MUST NOT lock out SSH administrators
- **No Package Manager**: Work with default Debian packages only
- **Idempotent**: Scripts must be safe to run multiple times
- **State Checking**: Always verify current state before changes

## 20 Critical Hardening Steps (Priority Order)

### 1. SSH Configuration Hardening (Priority: 1)
**Security Benefit**: Prevents brute force, weak crypto, and unauthorized access
**Remote Access Risk**: LOW - Changes applied gracefully with config validation
**Pre-checks Required**:
- Verify sshd_config syntax before reload
- Ensure at least one admin user can still login
- Check current SSH session won't be terminated
**Expected Impact**: Stronger authentication, disabled root login, key-only auth

### 2. SSH Key Management (Priority: 2)
**Security Benefit**: Ensures only strong, authorized keys are accepted
**Remote Access Risk**: MEDIUM - Must preserve existing authorized keys
**Pre-checks Required**:
- Backup existing authorized_keys
- Verify key strength (RSA ≥ 2048, ED25519 preferred)
- Ensure admin keys are preserved
**Expected Impact**: Removal of weak keys, proper permissions on .ssh directories

### 3. Firewall Rules - SSH Protection (Priority: 3)
**Security Benefit**: Rate limiting, connection throttling for SSH
**Remote Access Risk**: MEDIUM - Incorrect rules could block legitimate access
**Pre-checks Required**:
- Check if iptables/nftables is available
- Verify current SSH connection source IP
- Test rules in permissive mode first
**Expected Impact**: Protection against SSH brute force attacks

### 4. User Account Hardening (Priority: 4)
**Security Benefit**: Removes unnecessary accounts, enforces password policies
**Remote Access Risk**: LOW - Only affects local accounts, not SSH keys
**Pre-checks Required**:
- List all user accounts with shell access
- Identify service accounts vs. human users
- Check for UID 0 accounts besides root
**Expected Impact**: Reduced attack surface, stronger password requirements

### 5. Sudo Configuration Hardening (Priority: 5)
**Security Benefit**: Limits privilege escalation, enforces least privilege
**Remote Access Risk**: MEDIUM - Must preserve admin sudo access
**Pre-checks Required**:
- Backup sudoers file
- Verify visudo syntax checking
- Ensure admin group has appropriate access
**Expected Impact**: Restricted sudo usage, command logging, no NOPASSWD entries

### 6. File Permission Hardening (Priority: 6)
**Security Benefit**: Prevents unauthorized file access and modifications
**Remote Access Risk**: LOW - Only affects file permissions, not access methods
**Pre-checks Required**:
- Find world-writable files and directories
- Check SUID/SGID binaries
- Verify critical system file permissions
**Expected Impact**: Proper permissions on /etc/passwd, /etc/shadow, etc.

### 7. Kernel Parameter Hardening (Priority: 7)
**Security Benefit**: Network stack hardening, memory protection
**Remote Access Risk**: LOW - Network parameters tested before permanent changes
**Pre-checks Required**:
- Current sysctl settings
- Network connectivity requirements
- Available kernel modules
**Expected Impact**: IP spoofing protection, SYN flood protection, ASLR enabled

### 8. Process Limits Configuration (Priority: 8)
**Security Benefit**: Prevents resource exhaustion attacks
**Remote Access Risk**: VERY LOW - Only affects resource limits
**Pre-checks Required**:
- Current limits.conf settings
- System resource availability
- Critical service requirements
**Expected Impact**: Fork bomb protection, memory limits per user

### 9. Audit Logging Configuration (Priority: 9)
**Security Benefit**: Comprehensive security event logging
**Remote Access Risk**: VERY LOW - Only adds logging, doesn't restrict access
**Pre-checks Required**:
- Available disk space for logs
- Current syslog configuration
- Auditd availability
**Expected Impact**: Enhanced logging of authentication, sudo, file access

### 10. Network Service Hardening (Priority: 10)
**Security Benefit**: Reduces network attack surface
**Remote Access Risk**: LOW - SSH explicitly preserved
**Pre-checks Required**:
- List all listening services
- Identify required services
- Check service dependencies
**Expected Impact**: Disabled unnecessary network services

### 11. TCP Wrapper Configuration (Priority: 11)
**Security Benefit**: Additional layer of access control
**Remote Access Risk**: MEDIUM - Must whitelist admin IPs carefully
**Pre-checks Required**:
- Check if tcpwrappers is compiled in sshd
- Current hosts.allow/deny settings
- Admin IP ranges
**Expected Impact**: Service-level access restrictions

### 12. Cron Job Hardening (Priority: 12)
**Security Benefit**: Prevents unauthorized scheduled task execution
**Remote Access Risk**: VERY LOW - Doesn't affect SSH access
**Pre-checks Required**:
- Current cron.allow/deny settings
- User crontabs inventory
- System cron jobs review
**Expected Impact**: Restricted cron access to authorized users only

### 13. Mount Point Hardening (Priority: 13)
**Security Benefit**: Prevents execution from temporary locations
**Remote Access Risk**: VERY LOW - Doesn't affect SSH
**Pre-checks Required**:
- Current mount options
- Separate partitions availability
- Service dependencies on /tmp, /var
**Expected Impact**: noexec, nosuid on /tmp, /var/tmp, /dev/shm

### 14. Core Dump Restrictions (Priority: 14)
**Security Benefit**: Prevents information disclosure via core dumps
**Remote Access Risk**: NONE - No impact on remote access
**Pre-checks Required**:
- Current core dump settings
- Debugging requirements
- Disk space considerations
**Expected Impact**: Core dumps disabled for regular users

### 15. Login Banner Configuration (Priority: 15)
**Security Benefit**: Legal protection, unauthorized access deterrent
**Remote Access Risk**: NONE - Only adds warning messages
**Pre-checks Required**:
- Current banner settings
- Legal requirements
- File locations
**Expected Impact**: Warning banners on SSH login

### 16. Session Timeout Configuration (Priority: 16)
**Security Benefit**: Prevents abandoned session hijacking
**Remote Access Risk**: LOW - Long timeouts for admin work
**Pre-checks Required**:
- Current timeout settings
- Admin workflow requirements
- Service account needs
**Expected Impact**: Automatic logout after inactivity

### 17. Password Aging Policies (Priority: 17)
**Security Benefit**: Ensures regular password rotation
**Remote Access Risk**: VERY LOW - Doesn't affect key-based auth
**Pre-checks Required**:
- Current password policies
- Service account requirements
- Key-based authentication usage
**Expected Impact**: Password expiration, minimum age, history

### 18. Secure Shared Memory (Priority: 18)
**Security Benefit**: Prevents shared memory attacks
**Remote Access Risk**: NONE - No impact on SSH
**Pre-checks Required**:
- Current shared memory configuration
- Application requirements
- Available mount options
**Expected Impact**: Secured /run/shm mount point

### 19. Disable Unnecessary Kernel Modules (Priority: 19)
**Security Benefit**: Reduces kernel attack surface
**Remote Access Risk**: LOW - Network modules preserved
**Pre-checks Required**:
- Currently loaded modules
- Hardware requirements
- Network driver dependencies
**Expected Impact**: Blacklisted rare/dangerous modules

### 20. Log Rotation Hardening (Priority: 20)
**Security Benefit**: Prevents log tampering and ensures availability
**Remote Access Risk**: NONE - No impact on access
**Pre-checks Required**:
- Current logrotate configuration
- Disk space availability
- Retention requirements
**Expected Impact**: Compressed, protected historical logs

## Implementation Guidelines

### Script Structure Template
```sh
#!/bin/sh
# POSIX-compliant hardening script
set -e

# State checking function
check_current_state() {
    # Return 0 if already hardened, 1 if changes needed
}

# Backup function
create_backup() {
    # Backup configuration before changes
}

# Validation function
validate_changes() {
    # Test changes won't break system
}

# Apply hardening
apply_hardening() {
    # Make actual changes
}

# Rollback function
rollback_on_error() {
    # Restore from backup if needed
}

# Main execution
if check_current_state; then
    echo "System already hardened"
    exit 0
fi

create_backup
if apply_hardening && validate_changes; then
    echo "Hardening applied successfully"
else
    rollback_on_error
    exit 1
fi
```

### Critical Safety Measures

1. **SSH Access Protection**:
   - Never modify SSH config without syntax validation
   - Always test with non-breaking changes first
   - Maintain failsafe SSH access on alternate port during testing
   - Keep session alive during changes

2. **Firewall Safety**:
   - Default ACCEPT policy during rule creation
   - Explicit SSH allow rules before any DROP rules
   - Time-based automatic rollback for testing

3. **Testing Protocol**:
   - Test on non-production first
   - Maintain console/OOB access during initial deployment
   - Gradual rollout with monitoring

4. **Rollback Capability**:
   - Every script must support --undo flag
   - Automatic backups with timestamps
   - State verification before and after

## Risk Matrix

| Script | Remote Access Risk | Reversibility | Testing Required |
|--------|-------------------|---------------|------------------|
| SSH Config | LOW | Easy | Critical |
| SSH Keys | MEDIUM | Easy | Critical |
| Firewall | MEDIUM | Moderate | Critical |
| User Accounts | LOW | Easy | Important |
| Sudo Config | MEDIUM | Easy | Critical |
| File Perms | LOW | Easy | Standard |
| Kernel Params | LOW | Easy | Important |
| Process Limits | VERY LOW | Easy | Standard |
| Audit Logs | VERY LOW | Easy | Minimal |
| Network Services | LOW | Easy | Important |
| TCP Wrappers | MEDIUM | Easy | Critical |
| Cron | VERY LOW | Easy | Minimal |
| Mount Options | VERY LOW | Moderate | Standard |
| Core Dumps | NONE | Easy | Minimal |
| Login Banners | NONE | Easy | Minimal |
| Session Timeout | LOW | Easy | Standard |
| Password Aging | VERY LOW | Easy | Minimal |
| Shared Memory | NONE | Easy | Standard |
| Kernel Modules | LOW | Easy | Important |
| Log Rotation | NONE | Easy | Minimal |

## Validation Checklist

Before deploying any script:
- [ ] POSIX compliance verified (shellcheck with sh mode)
- [ ] Idempotency tested (run twice, check results)
- [ ] State checking works correctly
- [ ] Backup mechanism functional
- [ ] Rollback tested
- [ ] No SSH lockout scenarios identified
- [ ] Error handling comprehensive
- [ ] Logging adequate for troubleshooting

## Dependencies Matrix

Minimum required Debian commands/files:
- Core: sh, grep, sed, awk, cut, test, echo, cat
- Files: /etc/ssh/sshd_config, /etc/sysctl.conf, /etc/security/limits.conf
- Services: sshd, syslog/rsyslog
- Optional but recommended: iptables/nftables, auditd, sudo

## Success Metrics

After implementation:
1. SSH access maintained for authorized admins
2. Lynis/CIS benchmark score improvement >30%
3. No service disruptions
4. All changes logged and reversible
5. Reduced attack surface measurable via port scans
6. Compliance with major frameworks (CIS, NIST)