# POSIX Hardening Troubleshooting Guide

> **Quick Links:** [SSH Issues](#ssh-access-issues) | [Firewall](#firewall-issues) | [Emergency Recovery](#emergency-recovery-procedures) | [Ansible](#ansible-issues) | [Getting Help](#getting-help)

## Table of Contents

1. [Quick Diagnostics](#1-quick-diagnostics)
2. [Common Issues and Solutions](#2-common-issues-and-solutions)
   - [SSH Access Issues](#ssh-access-issues)
   - [Firewall Issues](#firewall-issues)
   - [Script Execution Errors](#script-execution-errors)
   - [Rollback Issues](#rollback-issues)
   - [Service Issues](#service-issues)
   - [Ansible Issues](#ansible-issues)
3. [Emergency Recovery Procedures](#3-emergency-recovery-procedures)
4. [Log Analysis](#4-log-analysis)
5. [Validation Failures](#5-validation-failures)
6. [Performance Issues](#6-performance-issues)
7. [Environment-Specific Issues](#7-environment-specific-issues)
8. [Getting Help](#8-getting-help)

---

## 1. Quick Diagnostics

### Where to Find Logs

```bash
# Main hardening logs (timestamped)
ls -la /var/log/hardening/

# Current session log
tail -f /var/log/hardening/hardening-*.log

# Rollback history
cat /var/log/hardening/rollback.log

# Ansible logs
cat /opt/posix-hardening/ansible/ansible.log

# System logs
journalctl -xe
tail -f /var/log/syslog
```

### Check System State

```bash
# Check hardening state
ls -la /var/lib/hardening/
cat /var/lib/hardening/completed 2>/dev/null

# Check current transaction
cat /var/lib/hardening/current_transaction

# View rollback stack
cat /var/lib/hardening/rollback_stack

# Check for emergency flags
ls /var/lib/hardening/emergency_*
```

### Key Files to Examine

| File | Purpose |
|------|---------|
| `/etc/ssh/sshd_config` | SSH configuration |
| `/var/backups/hardening/` | All backup files |
| `/var/lib/hardening/completed` | Completed hardening steps |
| `/etc/iptables/rules.v4` | IPv4 firewall rules |
| `/etc/sudoers.d/hardening` | Sudo restrictions |
| `/var/log/hardening/*.log` | Hardening operation logs |

### Diagnostic Commands

```bash
# Quick system health check
/opt/posix-hardening/tests/validation_suite.sh

# Check SSH status
systemctl status ssh
ss -tln | grep :22

# Check firewall status
iptables -L -n -v
ip6tables -L -n -v

# Check failed services
systemctl --failed

# Check disk space
df -h /var/backups/hardening/

# View recent hardening activity
tail -50 /var/log/hardening/rollback.log
```

---

## 2. Common Issues and Solutions

### SSH Access Issues

#### **Issue: Locked out of SSH**
- **Severity:** 🔴 CRITICAL
- **Symptoms:**
  - Cannot connect via SSH
  - "Connection refused" error
  - "Permission denied" after hardening

**Diagnosis:**
```bash
# From console/IPMI:
systemctl status ssh
grep "PermitRootLogin\|PasswordAuthentication" /etc/ssh/sshd_config
tail -20 /var/log/auth.log
```

**Solutions:**
1. **Use emergency SSH on port 2222:**
   ```bash
   # From console:
   /opt/posix-hardening/emergency-rollback.sh
   # Select option 5: Create emergency SSH

   # Then connect:
   ssh -p 2222 user@server
   ```

2. **Restore SSH from backup:**
   ```bash
   # From console:
   ls -t /var/backups/hardening/sshd_config.*.bak | head -1
   cp /var/backups/hardening/sshd_config.*.bak /etc/ssh/sshd_config
   systemctl restart ssh
   ```

**Prevention:**
- Always maintain console/IPMI access during hardening
- Test SSH configuration changes before applying
- Keep emergency access credentials ready

**Related logs:**
```bash
grep "SSH" /var/log/hardening/*.log
grep "sshd" /var/log/auth.log
```

---

#### **Issue: Port 2222 not responding**
- **Severity:** 🟡 MEDIUM
- **Symptoms:** Emergency SSH port not accessible

**Diagnosis:**
```bash
ss -tln | grep 2222
ps aux | grep "sshd.*2222"
iptables -L INPUT -n -v | grep 2222
```

**Solution:**
```bash
# Check if emergency SSH is running
cat /var/run/sshd_emergency.pid

# Manually start emergency SSH
cat > /tmp/sshd_emergency <<EOF
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
PidFile /var/run/sshd_emergency.pid
EOF

/usr/sbin/sshd -f /tmp/sshd_emergency

# Open firewall
iptables -I INPUT 1 -p tcp --dport 2222 -j ACCEPT
```

---

#### **Issue: "Too many authentication failures"**
- **Severity:** 🟡 MEDIUM
- **Symptoms:** SSH disconnects after multiple key attempts

**Diagnosis:**
```bash
grep MaxAuthTries /etc/ssh/sshd_config
ssh -vvv user@server  # Check authentication methods
```

**Solution:**
```bash
# Specify exact key to use
ssh -i ~/.ssh/specific_key -o IdentitiesOnly=yes user@server

# Or temporarily increase MaxAuthTries
sed -i 's/MaxAuthTries.*/MaxAuthTries 10/' /etc/ssh/sshd_config
systemctl reload ssh
```

---

### Firewall Issues

#### **Issue: Can't connect after firewall setup**
- **Severity:** 🔴 CRITICAL
- **Symptoms:** All network connections blocked

**Diagnosis:**
```bash
iptables -L INPUT -n -v | head -20
iptables -L OUTPUT -n -v | head -20
```

**Solution:**
```bash
# Emergency firewall reset
/opt/posix-hardening/emergency-rollback.sh
# Select option 2: Reset firewall

# Or manually:
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
```

**Prevention:**
- Always test firewall rules with automatic rollback
- Ensure SSH port is explicitly allowed before other rules

---

#### **Issue: Firewall auto-rollback not working**
- **Severity:** 🟡 MEDIUM
- **Symptoms:** Firewall changes persist despite connection loss

**Diagnosis:**
```bash
ps aux | grep "sleep.*rollback"
cat /var/lib/hardening/rollback_stack
```

**Solution:**
```bash
# Manually trigger rollback
cd /opt/posix-hardening
. lib/rollback.sh
rollback_transaction "manual_firewall_fix"

# Or restore from backup
iptables-restore < /var/backups/hardening/iptables.rules.*.bak
```

---

### Script Execution Errors

#### **Issue: "local: not found" errors**
- **Severity:** 🟢 LOW
- **Symptoms:** Scripts fail with "local: not found"

**Diagnosis:**
```bash
ls -la /bin/sh
echo $SHELL
```

**Solution:**
```bash
# Ensure using POSIX sh, not dash/bash specific features
# Scripts should use:
#!/bin/sh
# NOT #!/bin/bash

# For variables, use:
var="value"  # Not: local var="value"
```

---

#### **Issue: Permission denied errors**
- **Severity:** 🟡 MEDIUM
- **Symptoms:** Cannot execute hardening scripts

**Diagnosis:**
```bash
ls -la /opt/posix-hardening/*.sh
id
```

**Solution:**
```bash
# Fix permissions
chmod +x /opt/posix-hardening/*.sh
chmod +x /opt/posix-hardening/scripts/*.sh

# Ensure running as root
sudo -i
# or
su -
```

---

### Rollback Issues

#### **Issue: Automatic rollback not triggering**
- **Severity:** 🔴 CRITICAL
- **Symptoms:** System remains broken after failed operation

**Diagnosis:**
```bash
cat /var/lib/hardening/current_transaction
cat /var/lib/hardening/rollback_stack
grep ROLLBACK_ENABLED /opt/posix-hardening/config/defaults.conf
```

**Solution:**
```bash
# Manually trigger rollback
cd /opt/posix-hardening
. lib/common.sh
. lib/rollback.sh
rollback_transaction "manual_recovery"

# Or use emergency script
/opt/posix-hardening/emergency-rollback.sh --force
```

**Prevention:**
- Ensure ROLLBACK_ENABLED=1 in config
- Test rollback mechanism before production use

---

#### **Issue: Backup files missing**
- **Severity:** 🔴 CRITICAL
- **Symptoms:** Cannot restore original configurations

**Diagnosis:**
```bash
ls -la /var/backups/hardening/
df -h /var/backups/
```

**Solution:**
```bash
# Check for alternative backup locations
find / -name "*.bak" -mtime -7 2>/dev/null

# Restore from snapshots if available
ls -la /var/backups/hardening/snapshots/
cd /opt/posix-hardening
. lib/backup.sh
restore_system_snapshot "$(ls -t /var/backups/hardening/snapshots/ | head -1)"
```

---

### Service Issues

#### **Issue: Services not starting after hardening**
- **Severity:** 🟡 MEDIUM
- **Symptoms:** Critical services fail to start

**Diagnosis:**
```bash
systemctl --failed
journalctl -xe
systemctl status [service-name]
```

**Solution:**
```bash
# Re-enable service
systemctl unmask [service-name]
systemctl enable [service-name]
systemctl start [service-name]

# Check for permission issues
ls -la /etc/systemd/system/
restorecon -Rv /etc/systemd/  # If SELinux enabled
```

---

### Ansible Issues

#### **Issue: Ansible connection failures**
- **Severity:** 🟡 MEDIUM
- **Symptoms:**
  - "Host unreachable"
  - "Permission denied"
  - "sudo: sorry, you must have a tty to run sudo"

**Diagnosis:**
```bash
ansible all -m ping -i inventory.ini
ansible all -m shell -a "whoami" --become
grep requiretty /etc/sudoers.d/hardening
```

**Solution:**

1. **Fix sudo requiretty:**
   ```bash
   # On target host:
   /opt/posix-hardening/scripts/recovery/fix-sudo-requiretty.sh

   # Or manually:
   sed -i 's/^Defaults requiretty/Defaults !requiretty/' /etc/sudoers.d/hardening
   visudo -c
   ```

2. **Fix SSH for Ansible:**
   ```bash
   # Add Ansible control node to AllowUsers
   echo "AllowUsers ansible_user" >> /etc/ssh/sshd_config
   systemctl reload ssh
   ```

3. **Test connectivity:**
   ```bash
   ansible-playbook -i inventory.ini preflight.yml
   ```

**Prevention:**
- Use preflight.yml before main playbook
- Configure ansible_ssh_common_args in inventory
- Test with --check mode first

---

#### **Issue: Task timeouts**
- **Severity:** 🟢 LOW
- **Symptoms:** Playbook hangs on specific tasks

**Diagnosis:**
```bash
# Add -vvv for verbose output
ansible-playbook -i inventory.ini site.yml -vvv

# Check system resources on target
top
df -h
```

**Solution:**
```bash
# Increase timeout in ansible.cfg
[defaults]
timeout = 60

# Or per task in playbook:
- name: Long running task
  command: /opt/scripts/heavy-task.sh
  async: 300
  poll: 10
```

---

## 3. Emergency Recovery Procedures

### Console Access Recovery

**When to use:** No network access, SSH completely broken

```bash
# Step 1: Access via console/IPMI/KVM

# Step 2: Run emergency recovery
/opt/posix-hardening/emergency-rollback.sh

# Step 3: Select appropriate option:
# 1) Restore SSH access
# 2) Reset firewall
# 3) Restore from snapshot
# 7) FULL EMERGENCY RESET

# Step 4: Verify access
systemctl status ssh
iptables -L INPUT -n | head -10
```

### Single-User Mode Recovery

**When to use:** System won't boot normally

1. **Boot into single-user mode:**
   - Interrupt boot at GRUB
   - Add `single` or `1` to kernel parameters
   - Boot system

2. **Mount filesystems:**
   ```bash
   mount -o remount,rw /
   mount -a
   ```

3. **Restore configurations:**
   ```bash
   # Restore SSH
   cp /var/backups/hardening/sshd_config.*.bak /etc/ssh/sshd_config

   # Clear firewall
   iptables -F
   iptables -P INPUT ACCEPT

   # Fix permissions
   chmod 640 /etc/shadow
   chmod 644 /etc/ssh/sshd_config
   ```

4. **Reboot:**
   ```bash
   sync
   reboot -f
   ```

### Manual Rollback from Backups

```bash
# List all backups
ls -la /var/backups/hardening/

# Restore specific service config
cp /var/backups/hardening/[service].*.bak /etc/[service]/

# Restore from snapshot
cd /opt/posix-hardening
. lib/backup.sh
list_snapshots
restore_system_snapshot "snapshot_id"

# Restore multiple files
for backup in /var/backups/hardening/*.bak; do
    original="${backup%.*.bak}"
    cp "$backup" "$original"
done
```

### Fixing sudo requiretty lockout

**Symptoms:** Ansible fails with "sorry, you must have a tty to run sudo"

**Quick fix:**
```bash
# Via SSH with terminal
ssh -t user@host

# Run recovery script
sudo /opt/posix-hardening/scripts/recovery/fix-sudo-requiretty.sh

# Or manually
sudo visudo -f /etc/sudoers.d/hardening
# Change: Defaults requiretty
# To: Defaults !requiretty
```

---

## 4. Log Analysis

### How to Read Hardening Logs

**Log format:**
```
[TIMESTAMP] [LEVEL] Message
[2024-01-15 10:30:45] [INFO] Starting hardening script: 01-ssh-hardening
[2024-01-15 10:30:46] [ERROR] SSH configuration syntax check failed
```

**Log levels:**
- `ERROR` - Critical failures requiring attention
- `WARN` - Issues that may need review
- `INFO` - Normal operations
- `DEBUG` - Detailed troubleshooting info (when VERBOSE=1)
- `DRY_RUN` - What would be changed (when DRY_RUN=1)

### Understanding Error Messages

**Common patterns:**

| Error Pattern | Meaning | Action |
|--------------|---------|--------|
| `Failed to backup file` | Disk space or permission issue | Check `/var/backups/` space |
| `Transaction failed with exit code` | Script error triggering rollback | Check rollback.log |
| `SSH not responding` | SSH daemon issue | Use emergency access |
| `Operation would break SSH` | Safety check prevented damage | Review SSH settings |
| `Rollback command failed` | Restoration issue | Manual intervention needed |

### Identifying Failed Operations

```bash
# Find all errors
grep ERROR /var/log/hardening/*.log

# Find specific script failures
grep "Script failed:" /var/log/hardening/*.log

# Find rollback triggers
grep "ROLLBACK" /var/log/hardening/rollback.log

# Find by timestamp
grep "2024-01-15 10:" /var/log/hardening/*.log
```

### Tracking Root Cause

1. **Identify failing script:**
   ```bash
   tail -100 /var/log/hardening/*.log | grep -B5 ERROR
   ```

2. **Check transaction state:**
   ```bash
   cat /var/lib/hardening/current_transaction
   cat /var/lib/hardening/rollback_stack
   ```

3. **Review system logs:**
   ```bash
   journalctl -xe --since "10 minutes ago"
   dmesg | tail -50
   ```

4. **Check resource constraints:**
   ```bash
   df -h
   free -h
   uptime
   ```

---

## 5. Validation Failures

### How to Interpret Validation Results

Run validation: `/opt/posix-hardening/tests/validation_suite.sh`

**Output format:**
```
Testing: SSH daemon running                        [PASS]
Testing: Firewall rules applied                    [FAIL]
Testing: Audit logging enabled                     [WARN] auditd not installed
```

### What to Do When Validation Fails

1. **Critical failures (SSH, network):**
   ```bash
   # Immediate action required
   /opt/posix-hardening/emergency-rollback.sh
   ```

2. **Security failures (permissions, configs):**
   ```bash
   # Re-run specific hardening script
   cd /opt/posix-hardening
   ./scripts/05-file-permissions.sh
   ```

3. **Warning conditions:**
   ```bash
   # Review and decide
   grep WARN /var/log/hardening/*.log
   # May be acceptable in your environment
   ```

### Manual Verification Steps

```bash
# Verify SSH hardening
grep -E "^(PermitRoot|Password|Pubkey)" /etc/ssh/sshd_config

# Verify firewall
iptables -L INPUT -n | grep -E "(ACCEPT|DROP|REJECT)"

# Verify file permissions
ls -la /etc/shadow /etc/gshadow /etc/passwd

# Verify services disabled
systemctl list-unit-files | grep -E "(telnet|rsh|rlogin)"

# Verify audit logging
auditctl -l
```

---

## 6. Performance Issues

### Hardening Taking Too Long

**Symptoms:** Scripts run for hours without completing

**Diagnosis:**
```bash
# Check current operation
ps aux | grep hardening
tail -f /var/log/hardening/*.log

# Check system resources
top
iostat -x 1
```

**Solutions:**
1. **Skip intensive operations:**
   ```bash
   export SKIP_INTEGRITY_BASELINE=1
   export SKIP_AIDE_INIT=1
   ```

2. **Run in parallel:**
   ```bash
   # Use Ansible with higher forks
   ansible-playbook -f 10 site.yml
   ```

### System Slowdown After Hardening

**Symptoms:** High CPU/memory usage, slow response

**Diagnosis:**
```bash
# Check audit logging overhead
auditctl -s
ausearch -m ALL --start today | wc -l

# Check firewall rule count
iptables -L -n | wc -l
```

**Solutions:**
```bash
# Reduce audit logging
auditctl -e 0  # Temporarily disable
vim /etc/audit/rules.d/hardening.rules  # Remove verbose rules

# Optimize firewall rules
iptables -F LOGGING  # Clear logging chain
```

---

## 7. Environment-Specific Issues

### Cloud Provider Quirks

#### **AWS EC2:**
- Security Groups override iptables for external traffic
- Use EC2 Instance Connect for emergency access
- IMDSv2 may affect some scripts

```bash
# Allow IMDS access
iptables -I OUTPUT -d 169.254.169.254 -j ACCEPT
```

#### **Google Cloud:**
- OS Login may conflict with SSH hardening
- Serial console available for recovery
- Firewall rules in VPC take precedence

```bash
# Check metadata access
curl -H "Metadata-Flavor: Google" http://metadata.google.internal/
```

#### **Azure:**
- Serial console requires boot diagnostics
- Reset password feature may not work after hardening
- Network Security Groups are primary firewall

### Container/Docker Issues

**Symptoms:** Hardening fails in containers

**Solutions:**
```bash
# Skip unsupported features
export SKIP_KERNEL_PARAMS=1
export SKIP_GRUB_CONFIG=1
export SKIP_SYSCTL=1

# Use container-specific config
cp config/container.conf config/defaults.conf
```

### VM-Specific Problems

**VMware/VirtualBox:**
- Console access through hypervisor
- Snapshots before hardening recommended
- Guest additions may need reinstall after kernel hardening

---

## 8. Getting Help

### What Information to Collect

Before requesting help, gather:

```bash
# Create diagnostic bundle
mkdir /tmp/hardening-diag
cd /tmp/hardening-diag

# System info
uname -a > system.txt
cat /etc/os-release >> system.txt
df -h >> system.txt
free -h >> system.txt

# Hardening state
cp -r /var/lib/hardening/ state/
cp -r /var/log/hardening/ logs/

# Current configs
cp /etc/ssh/sshd_config ssh_config.txt
iptables-save > firewall_rules.txt
systemctl --failed > failed_services.txt

# Recent errors
journalctl -xe --since "1 hour ago" > journal.txt
dmesg | tail -100 > dmesg.txt

# Create archive
tar czf hardening-diag-$(date +%Y%m%d-%H%M%S).tar.gz *
```

### How to File a Bug Report

Include in your report:

1. **Environment:**
   - OS version
   - Cloud/VM/Physical
   - Network configuration

2. **Steps to reproduce:**
   - Exact commands run
   - Configuration files used
   - Point of failure

3. **Error messages:**
   - Complete error output
   - Log excerpts
   - Screenshots if applicable

4. **Attempted solutions:**
   - What you've tried
   - Results of attempts

### Where to Ask Questions

- **GitHub Issues:** https://github.com/your-org/POSIX-hardening/issues
- **Email Support:** security-team@your-org.com
- **Emergency Hotline:** (If critical production issue)

### Quick Reference Card

```bash
# Emergency Commands
/opt/posix-hardening/emergency-rollback.sh --force  # Full reset
systemctl restart ssh                               # Restart SSH
iptables -F && iptables -P INPUT ACCEPT            # Clear firewall

# Diagnostic Commands
/opt/posix-hardening/tests/validation_suite.sh     # Run tests
tail -f /var/log/hardening/*.log                   # Watch logs
grep ERROR /var/log/hardening/*.log                # Find errors

# Recovery Paths
/var/backups/hardening/                            # All backups
/var/lib/hardening/                                # State files
/opt/posix-hardening/scripts/recovery/             # Recovery scripts
```

---

## Severity Indicators

- 🔴 **CRITICAL** - System access lost, immediate action required
- 🟡 **MEDIUM** - Functionality impaired, should be addressed
- 🟢 **LOW** - Minor issue, can be addressed during maintenance

## Related Documentation

- [Installation Guide](../installation.md)
- [Configuration Reference](../configuration.md)
- [Security Best Practices](../security-best-practices.md)
- [Emergency Recovery](../emergency-recovery.md)

---

*Last Updated: 2024*
*Version: 1.0.0*