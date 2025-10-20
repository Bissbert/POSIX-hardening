# POSIX Hardening Scripts Documentation

This document provides comprehensive documentation for all 21 hardening scripts in the toolkit. Each script is designed to be safe for remote execution with multiple rollback mechanisms.

## Table of Contents

### Priority 0 - Pre-Hardening Verification
- [00. SSH Package Verification](#00-ssh-package-verification)

### Priority 1 - Critical (SSH & Network Access)
- [01. SSH Hardening](#01-ssh-hardening)
- [02. Firewall Setup](#02-firewall-setup)

### Priority 2 - Core System Security
- [03. Kernel Parameters](#03-kernel-parameters)
- [04. Network Stack](#04-network-stack)
- [05. File Permissions](#05-file-permissions)

### Priority 3 - Process & Access Control
- [06. Process Limits](#06-process-limits)
- [07. Audit Logging](#07-audit-logging)
- [08. Password Policy](#08-password-policy)
- [09. Account Lockdown](#09-account-lockdown)
- [10. Sudo Restrictions](#10-sudo-restrictions)

### Priority 4 - Service Hardening
- [11. Service Disable](#11-service-disable)
- [12. Tmp Hardening](#12-tmp-hardening)
- [13. Core Dump Disable](#13-core-dump-disable)
- [14. Sysctl Hardening](#14-sysctl-hardening)
- [15. Cron Restrictions](#15-cron-restrictions)

### Priority 5 - Additional Security
- [16. Mount Options](#16-mount-options)
- [17. Shell Timeout](#17-shell-timeout)
- [18. Banner Warnings](#18-banner-warnings)
- [19. Log Retention](#19-log-retention)
- [20. Integrity Baseline](#20-integrity-baseline)

---

## Script Categories

### 🔴 Critical Priority (Must Run First)
Scripts that preserve remote access and establish network security foundations.

### 🟡 High Priority
Core system hardening that affects system-wide security posture.

### 🟢 Standard Priority
Service and access controls that enhance security without affecting core functionality.

### 🔵 Optional Priority
Additional hardening that may require environment-specific configuration.

---

## 00. SSH Package Verification

**Script:** `scripts/00-ssh-verification.sh`
**Priority:** CRITICAL (0) - Runs BEFORE all hardening
**Risk Level:** Low (verification only, safe reinstall)

### Purpose
Verifies the integrity and authenticity of the OpenSSH server package before any hardening is applied. This ensures that the SSH daemon you're about to harden is from an official source and hasn't been compromised.

### What It Does
- Verifies package is from official Debian/Ubuntu repositories
- Checks GPG signatures on package sources
- Verifies binary integrity using debsums
- Automatically reinstalls OpenSSH if integrity check fails
- Creates emergency SSH access during reinstall

### Safety Mechanisms
1. **Package source verification** - Ensures package is from official repos
2. **GPG signature checking** - Verifies repository authenticity
3. **Binary integrity checking** - Compares installed files to package database
4. **Emergency SSH access** - Creates fallback on port 2222 during reinstall
5. **Automatic rollback** - 60-second timeout with automatic restoration
6. **Configuration backup** - Preserves SSH config during reinstall

### Verification Steps
1. **Package Information** - Gathers current OpenSSH version and architecture
2. **Source Verification** - Checks if package is from official Debian/Ubuntu repos
3. **Signature Verification** - Validates GPG keys are present (optional)
4. **Binary Integrity** - Uses debsums to verify all SSH binaries match package checksums
5. **Reinstall if Needed** - If integrity check fails, safely reinstalls package

### Configuration Options
```bash
FORCE_SSH_VERIFICATION=0      # Force reinstall even if verification passes
EMERGENCY_SSH_PORT=2222       # Emergency SSH port during reinstall
DRY_RUN=0                     # Test mode without making changes
```

### Modified Files
- `/etc/ssh/sshd_config` - Backed up during reinstall
- Installs: `debsums` package (if not present)
- OpenSSH package reinstallation (only if integrity fails)

### Prerequisites
- Internet connectivity (for apt operations)
- Root access
- Sufficient disk space for package operations

### When It Runs
- **Automatically** before SSH hardening (01-ssh-hardening.sh)
- Called by Ansible playbook before Priority 1 hardening
- Can be run manually: `sh scripts/00-ssh-verification.sh`

### Output Summary
The script provides a comprehensive summary:
```
=================================
SSH Package Verification Summary
=================================
Package Source: VERIFIED
GPG Signatures: VERIFIED / SKIPPED
Binary Integrity: VERIFIED / REINSTALLED
Reinstall Performed: YES / NO
=================================
```

### Dry-Run Support
```bash
export DRY_RUN=1
sh scripts/00-ssh-verification.sh
```
In dry-run mode:
- Shows what would be checked
- Does not install debsums
- Does not reinstall SSH
- Does not modify any files

### Exit Codes
- `0` - Verification passed or reinstall successful
- `1` - Verification failed and reinstall failed
- `2` - Script error or missing prerequisites

---

## 01. SSH Hardening

**Script:** `scripts/01-ssh-hardening.sh`
**Priority:** CRITICAL
**Risk Level:** High (if misconfigured)

### Purpose
Secures SSH daemon configuration while maintaining remote access. This is the most critical script as it affects your ability to manage the server remotely.

### What It Does
- **Runs SSH package verification first** (00-ssh-verification.sh)
- Disables root login via SSH
- Enforces key-based authentication only
- Disables password authentication
- Configures strong cipher suites
- Sets connection timeouts and limits
- Restricts SSH to specific users/groups (if configured)
- Creates SSH warning banner

### Safety Mechanisms
1. **60-second automatic rollback** if SSH connection is lost
2. **Emergency SSH on port 2222** as fallback
3. **Parallel connection testing** before applying changes
4. **Configuration validation** before reload
5. **Preserves existing connections** during changes

### Configuration Options
```bash
SSH_PORT=22                    # SSH listening port
SSH_ALLOW_USERS=""            # Space-separated list of allowed users
SSH_ALLOW_GROUPS=""           # Space-separated list of allowed groups
ENABLE_EMERGENCY_SSH=1        # Create emergency access on port 2222
EMERGENCY_SSH_PORT=2222       # Emergency SSH port
```

### Modified Files
- `/etc/ssh/sshd_config` - Main SSH configuration
- `/etc/ssh/sshd_config.d/*.conf` - Additional configs
- `/etc/ssh/banner` - Login warning banner
- `/root/.ssh/` - Root SSH directory permissions
- `/home/*/.ssh/` - User SSH directory permissions

### Prerequisites
- SSH key authentication already configured
- Valid SSH keys in authorized_keys
- Network access to server

### Rollback Procedure
```bash
# Automatic rollback after 60 seconds if connection lost
# Manual rollback:
cp /var/backups/hardening/sshd_config.*.bak /etc/ssh/sshd_config
systemctl reload ssh

# Emergency access:
ssh -p 2222 user@server
```

### Common Issues
- **Locked out**: Wait 60 seconds for auto-rollback or use emergency port 2222
- **Keys not working**: Ensure .ssh permissions are correct (700 for dir, 600 for keys)
- **Connection refused**: Check firewall isn't blocking SSH port

---

## 02. Firewall Setup

**Script:** `scripts/02-firewall-setup.sh`
**Priority:** CRITICAL
**Risk Level:** High (if misconfigured)

### Purpose
Configures iptables firewall rules with automatic safety mechanisms to prevent lockout.

### What It Does
- Sets default DROP policy for INPUT
- Allows established connections
- Configures SSH access with rate limiting
- Adds brute-force protection
- Allows configured services
- Enables connection tracking
- Logs dropped packets

### Safety Mechanisms
1. **5-minute auto-reset timer** for testing
2. **SSH explicitly allowed** before DROP rules
3. **Admin IP priority access**
4. **Established connections preserved**
5. **Automatic rule backup**

### Configuration Options

**Basic configuration** (in `config/defaults.conf`):
```bash
ADMIN_IP=""                   # Your management IP (always allowed)
ALLOWED_PORTS="80 443"        # Additional allowed ports
TRUSTED_NETWORKS=""           # Trusted network ranges (CIDR)
FIREWALL_TIMEOUT=300          # Auto-reset timeout in seconds
```

**Advanced configuration** (in `config/firewall.conf`):

Create a custom firewall configuration by copying the example:
```bash
cp config/firewall.conf.example config/firewall.conf
```

All firewall rules are fully customizable via `config/firewall.conf`:

**SSH Protection:**
```bash
SSH_RATE_LIMIT_ENABLED=1      # Enable brute-force protection
SSH_RATE_LIMIT_HITS=4         # Max connection attempts
SSH_RATE_LIMIT_SECONDS=60     # Time window for rate limiting
```

**ICMP Settings:**
```bash
ICMP_ENABLED=1                # Allow ping
ICMP_RATE_LIMIT="1/s"         # Rate limit for ping
ICMP_TYPES="echo-request echo-reply destination-unreachable time-exceeded"
```

**Logging:**
```bash
LOG_DROPPED_PACKETS=1         # Log dropped packets
LOG_RATE_LIMIT="2/min"        # Prevent log flooding
LOG_PREFIX="IPTables-Dropped: "
LOG_LEVEL=4                   # Syslog level
```

**Outbound Traffic:**
```bash
ALLOW_DNS=1                   # Port 53
ALLOW_NTP=1                   # Port 123
ALLOW_HTTP=1                  # Port 80
ALLOW_HTTPS=1                 # Port 443
CUSTOM_OUTBOUND_TCP=""        # Additional TCP ports
CUSTOM_OUTBOUND_UDP=""        # Additional UDP ports
```

**Default Policies:**
```bash
DEFAULT_INPUT_POLICY="DROP"   # Block all incoming by default
DEFAULT_FORWARD_POLICY="DROP" # Block forwarding
DEFAULT_OUTPUT_POLICY="ACCEPT" # Allow all outgoing
```

**Custom Rules:**
```bash
# Define custom iptables rules directly
CUSTOM_RULES_IPV4="
-A INPUT -p tcp --dport 8080 -j ACCEPT
-A INPUT -s 10.0.0.0/8 -j ACCEPT
"

# For IPv6 (if IPV6_MODE=custom)
CUSTOM_RULES_IPV6="
-A INPUT -p tcp --dport 8080 -j ACCEPT
"
```

See `config/firewall.conf.example` for complete documentation and preset configurations.

### Modified Files
- `/etc/iptables/rules.v4` - IPv4 rules
- `/etc/iptables/rules.v6` - IPv6 rules
- `/etc/network/if-pre-up.d/iptables` - Boot restore script

### Rollback Procedure
```bash
# Automatic reset after 5 minutes
# Manual reset:
iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Restore from backup:
iptables-restore < /var/backups/hardening/iptables.rules.*
```

---

## 03. Kernel Parameters

**Script:** `scripts/03-kernel-params.sh`
**Priority:** HIGH
**Risk Level:** Low

### Purpose
Hardens kernel parameters via sysctl for improved security.

### What It Does
- Enables SYN flood protection
- Disables IP forwarding
- Prevents IP source routing
- Disables ICMP redirects
- Enables ASLR (Address Space Layout Randomization)
- Restricts kernel pointer exposure
- Configures network stack security

### Configuration Options
Applied via `/etc/sysctl.conf`:
- `net.ipv4.tcp_syncookies = 1`
- `kernel.randomize_va_space = 2`
- `kernel.kptr_restrict = 2`
- `fs.suid_dumpable = 0`

### Modified Files
- `/etc/sysctl.conf` - Kernel parameters
- `/etc/sysctl.d/*.conf` - Additional configurations

### Rollback Procedure
```bash
# Restore original sysctl settings
cp /var/backups/hardening/sysctl.conf.*.bak /etc/sysctl.conf
sysctl -p
```

---

## 04. Network Stack

**Script:** `scripts/04-network-stack.sh`
**Priority:** HIGH
**Risk Level:** Low

### Purpose
Implements additional network stack hardening beyond kernel parameters.

### What It Does
- Disables IPv6 if not needed
- Configures TCP/IP stack timeouts
- Sets connection limits
- Enables RFC1337 TIME-WAIT protection
- Configures ICMP rate limiting

### Modified Files
- `/etc/sysctl.d/99-network-hardening.conf`
- `/proc/sys/net/ipv4/*` (runtime values)

---

## 05. File Permissions

**Script:** `scripts/05-file-permissions.sh`
**Priority:** HIGH
**Risk Level:** Low

### Purpose
Secures critical system files and directories with proper permissions.

### What It Does
- Sets secure permissions on /etc/passwd, shadow, group
- Secures SSH keys and configurations
- Restricts cron file permissions
- Sets appropriate umask values
- Finds and reports world-writable files

### Modified Files
- `/etc/passwd` (644)
- `/etc/shadow` (000)
- `/etc/group` (644)
- `/etc/ssh/*` (various)
- `/etc/cron*` (600-700)

---

## 06. Process Limits

**Script:** `scripts/06-process-limits.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Sets resource limits to prevent denial of service attacks.

### What It Does
- Configures maximum process limits
- Sets file descriptor limits
- Restricts core dump sizes
- Configures memory limits

### Modified Files
- `/etc/security/limits.conf`
- `/etc/security/limits.d/*.conf`

---

## 07. Audit Logging

**Script:** `scripts/07-audit-logging.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Configures comprehensive system auditing and logging.

### What It Does
- Enables auditd service
- Configures audit rules
- Monitors critical file changes
- Tracks privileged command execution
- Sets log rotation policies

### Modified Files
- `/etc/audit/auditd.conf`
- `/etc/audit/rules.d/hardening.rules`

---

## 08. Password Policy

**Script:** `scripts/08-password-policy.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Enforces strong password policies system-wide.

### What It Does
- Sets minimum password length (12 characters)
- Configures password expiration (90 days)
- Enforces password history (5 passwords)
- Sets password complexity requirements
- Configures account lockout policies

### Modified Files
- `/etc/login.defs`
- `/etc/pam.d/common-password`
- `/etc/security/pwquality.conf`

---

## 09. Account Lockdown

**Script:** `scripts/09-account-lockdown.sh`
**Priority:** MEDIUM
**Risk Level:** Medium

### Purpose
Secures user accounts and removes unnecessary users.

### What It Does
- Locks inactive system accounts
- Removes unnecessary default users
- Sets shell to /sbin/nologin for system accounts
- Configures account expiration policies
- Audits user privileges

### Modified Files
- `/etc/passwd`
- `/etc/shadow`

---

## 10. Sudo Restrictions

**Script:** `scripts/10-sudo-restrictions.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Hardens sudo configuration for better access control.

### What It Does
- Requires password for sudo
- Sets sudo timeout (5 minutes)
- Enables sudo logging
- Restricts sudo to specific groups
- Disables root sudo access

### Modified Files
- `/etc/sudoers`
- `/etc/sudoers.d/99-hardening`

---

## 11. Service Disable

**Script:** `scripts/11-service-disable.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Disables unnecessary services to reduce attack surface.

### What It Does
- Disables Bluetooth
- Disables cups (printing)
- Disables avahi-daemon
- Disables unnecessary network services
- Stops and masks services

### Services Disabled
- bluetooth
- cups
- avahi-daemon
- Other environment-specific services

---

## 12. Tmp Hardening

**Script:** `scripts/12-tmp-hardening.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Secures temporary directories against privilege escalation.

### What It Does
- Mounts /tmp with noexec, nosuid, nodev
- Secures /var/tmp similarly
- Sets sticky bit on temp directories
- Configures tmpfs size limits

### Modified Files
- `/etc/fstab` - Mount options
- `/etc/systemd/system/tmp.mount`

---

## 13. Core Dump Disable

**Script:** `scripts/13-core-dump-disable.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Prevents core dumps which may contain sensitive information.

### What It Does
- Disables core dumps system-wide
- Sets ulimit for core files to 0
- Configures systemd-coredump

### Modified Files
- `/etc/security/limits.conf`
- `/etc/sysctl.conf`
- `/etc/systemd/coredump.conf`

---

## 14. Sysctl Hardening

**Script:** `scripts/14-sysctl-hardening.sh`
**Priority:** MEDIUM
**Risk Level:** Low

### Purpose
Additional sysctl hardening beyond basic kernel parameters.

### What It Does
- Enables additional network protections
- Configures memory security options
- Sets IPC restrictions
- Enables kernel hardening features

### Modified Files
- `/etc/sysctl.d/99-hardening.conf`

---

## 15. Cron Restrictions

**Script:** `scripts/15-cron-restrictions.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Restricts cron and at daemon access to authorized users only.

### What It Does
- Creates cron.allow and at.allow
- Removes cron.deny and at.deny
- Restricts cron to specific users
- Sets secure permissions on cron files

### Modified Files
- `/etc/cron.allow`
- `/etc/at.allow`
- `/etc/cron.d/*`
- `/etc/crontab`

---

## 16. Mount Options

**Script:** `scripts/16-mount-options.sh`
**Priority:** LOW
**Risk Level:** Medium

### Purpose
Adds security options to filesystem mounts.

### What It Does
- Adds nodev to non-root partitions
- Adds nosuid where appropriate
- Adds noexec to temporary partitions
- Configures read-only mounts where possible

### Modified Files
- `/etc/fstab`

### Rollback Procedure
```bash
# Restore original fstab
cp /var/backups/hardening/fstab.*.bak /etc/fstab
mount -a
```

---

## 17. Shell Timeout

**Script:** `scripts/17-shell-timeout.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Sets automatic logout for idle shell sessions.

### What It Does
- Sets TMOUT variable (900 seconds/15 minutes)
- Configures for all users
- Makes timeout readonly
- Applies to bash and sh shells

### Modified Files
- `/etc/profile`
- `/etc/bash.bashrc`

---

## 18. Banner Warnings

**Script:** `scripts/18-banner-warnings.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Configures legal warning banners for system access.

### What It Does
- Creates login warning banner
- Sets motd (message of the day)
- Configures SSH banner
- Removes system information from banners

### Modified Files
- `/etc/issue`
- `/etc/issue.net`
- `/etc/motd`
- `/etc/ssh/banner`

---

## 19. Log Retention

**Script:** `scripts/19-log-retention.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Configures log rotation and retention policies.

### What It Does
- Sets log retention periods
- Configures compression
- Sets maximum log sizes
- Ensures secure permissions on logs

### Modified Files
- `/etc/logrotate.conf`
- `/etc/logrotate.d/*`

---

## 20. Integrity Baseline

**Script:** `scripts/20-integrity-baseline.sh`
**Priority:** LOW
**Risk Level:** Low

### Purpose
Creates filesystem integrity baseline for change detection.

### What It Does
- Creates SHA256 checksums of critical files
- Stores baseline for comparison
- Provides verification capability
- Compresses and timestamps baselines

### Generated Files
- `$STATE_DIR/integrity_baseline.*.gz`
- `$STATE_DIR/integrity_baseline_latest.gz`

### Usage
```bash
# Create baseline
sh scripts/20-integrity-baseline.sh

# Verify integrity
sh scripts/20-integrity-baseline.sh verify
```

---

## Execution Order Recommendations

### Minimal Hardening
1. 01-ssh-hardening.sh
2. 02-firewall-setup.sh
3. 08-password-policy.sh

### Standard Hardening
Run scripts 01-10 in order

### Complete Hardening
Run all 20 scripts via orchestrator:
```bash
sudo sh orchestrator.sh
```

### Testing Order
Always test in this sequence:
1. Dry run mode first
2. Test on non-production
3. Run with emergency SSH enabled
4. Deploy to production
5. Remove emergency access

---

## Global Safety Features

All scripts include:

### Transaction System
- Begin transaction before changes
- Automatic rollback on failure
- Commit only on success

### Backup System
- Timestamped backups before changes
- Easy restoration commands
- Backup retention management

### Logging
- Detailed execution logs
- Error tracking
- Rollback history

### Dry Run Mode
- Test without making changes
- Preview what will be modified
- Validate prerequisites

### Idempotency
- Safe to run multiple times
- Checks if already completed
- Skips unnecessary changes

---

## Emergency Procedures

### Lost SSH Access
1. Wait 60 seconds for auto-rollback
2. Try emergency SSH port 2222
3. Use console access if available
4. Run emergency-rollback.sh

### System Unstable
```bash
# Full rollback
sudo sh emergency-rollback.sh

# Selective rollback
sudo sh lib/rollback.sh restore_checkpoint <checkpoint_name>
```

### View Logs
```bash
# Check execution logs
tail -f /var/log/hardening/hardening-*.log

# Check rollback history
cat /var/log/hardening/rollback.log
```

---

## Best Practices

1. **Always backup** before running scripts
2. **Test in dry-run mode** first
3. **Run one script at a time** initially
4. **Monitor logs** during execution
5. **Keep emergency access** available
6. **Document any customizations**
7. **Review configuration** before running
8. **Verify prerequisites** are met

---

## Support

For issues or questions:
1. Check script logs in `/var/log/hardening/`
2. Review configuration in `config/defaults.conf`
3. Verify prerequisites with `tests/validation_suite.sh`
4. Consult emergency-rollback.sh for recovery