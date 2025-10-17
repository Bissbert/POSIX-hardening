# POSIX Shell Hardening Toolkit - Quick Reference Guide

## ⚠️ CRITICAL SAFETY RULES
1. **NEVER** run on production without testing
2. **ALWAYS** maintain console/OOB access during changes
3. **ALWAYS** backup configurations before starting
4. **NEVER** disable SSH without alternate access
5. **ALWAYS** test new SSH connections before closing current session

## Script Priority and Risk Matrix

| Priority | Script | Lock-out Risk | Reversible | Critical |
|----------|--------|--------------|------------|----------|
| 1 | 01_ssh_config_hardening.sh | LOW | ✓ | ✓✓✓ |
| 2 | 02_ssh_key_management.sh | MEDIUM | ✓ | ✓✓✓ |
| 3 | 03_firewall_ssh_protection.sh | MEDIUM | ✓ | ✓✓✓ |
| 4 | 04_user_account_hardening.sh | LOW | ✓ | ✓✓ |
| 5 | 05_sudo_configuration.sh | MEDIUM | ✓ | ✓✓ |
| 6-20 | Remaining scripts | LOW-NONE | ✓ | ✓ |

## Pre-Flight Checklist

```sh
# Before starting any hardening:
□ Backup system configurations
□ Document current SSH access methods
□ Verify console/OOB access works
□ Note current admin SSH keys
□ Record service dependencies
□ Check disk space (need 1GB free minimum)
□ Schedule maintenance window
□ Notify team of changes
```

## Emergency SSH Recovery Commands

```sh
# If SSH config is broken (via console):
cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
/usr/sbin/sshd -t  # Test config
service ssh restart

# If firewall blocks you:
iptables -F INPUT  # Flush INPUT chain
iptables -P INPUT ACCEPT  # Set policy to ACCEPT
iptables -I INPUT -p tcp --dport 22 -j ACCEPT

# If SSH key is rejected:
# Via console, temporarily enable password auth:
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
service ssh restart
# Fix keys, then disable password auth again

# If all else fails - boot to single user mode:
# At GRUB, add 'single' or '1' to kernel line
# Mount / as read-write: mount -o remount,rw /
# Fix configurations
# Reboot
```

## Safe Deployment Order

### Stage 1: Low Risk (Do First)
```sh
# These have minimal risk of lockout
./15_login_banner.sh
./14_core_dump_disable.sh
./09_audit_logging.sh
./20_log_rotation_hardening.sh
./18_shared_memory_security.sh
```

### Stage 2: System Hardening (Do Second)
```sh
# These affect system behavior but not access
./07_kernel_parameters.sh
./08_process_limits.sh
./06_file_permissions.sh
./13_mount_hardening.sh
./17_password_aging.sh
```

### Stage 3: Access Controls (Do Third, Carefully)
```sh
# These can affect access - test thoroughly
./04_user_account_hardening.sh
./05_sudo_configuration.sh
./12_cron_hardening.sh
./16_session_timeout.sh
```

### Stage 4: Network Security (Do Last, Most Risk)
```sh
# These have highest risk of lockout
./01_ssh_config_hardening.sh
./02_ssh_key_management.sh
./03_firewall_ssh_protection.sh
./11_tcp_wrappers.sh
./10_network_services.sh
```

## Configuration Verification Commands

```sh
# Verify SSH configuration
/usr/sbin/sshd -t

# Check current SSH settings
sshd -T | grep -E "permitrootlogin|passwordauth|maxauthtries"

# Test firewall rules
iptables -L -n -v

# Check kernel parameters
sysctl -a | grep -E "ip_forward|tcp_syncookies|randomize_va_space"

# Verify file permissions
ls -la /etc/passwd /etc/shadow /etc/ssh/sshd_config

# Check listening services
netstat -tlnp
ss -tlnp

# Review user accounts
awk -F: '$3 >= 1000 {print $1}' /etc/passwd

# Check sudo configuration
visudo -c

# Verify cron restrictions
ls -la /etc/cron.allow /etc/cron.deny

# Check audit logging
tail -f /var/log/auth.log
```

## Monitoring After Deployment

```sh
# Monitor SSH attacks
grep "Failed password" /var/log/auth.log | tail -20

# Check for permission denied errors
grep "Permission denied" /var/log/syslog | tail -20

# Monitor system resources
vmstat 1 5
iostat -x 1 5

# Check for service failures
systemctl list-units --failed

# Review sudo usage
grep sudo /var/log/auth.log | tail -20

# Check firewall hit counts
iptables -L -n -v | grep DROP
```

## Rollback Procedures

### Individual Script Rollback
```sh
# Each script creates timestamped backups
ls -la /etc/ssh/*.backup.*
ls -la /root/*.backup.*

# Restore specific configuration
cp /etc/ssh/sshd_config.backup.20240315_120000 /etc/ssh/sshd_config
service ssh restart
```

### Full System Rollback
```sh
# If full rollback needed
cd /root
tar xzf pre-hardening-backup-20240315_120000.tar.gz -C /
service ssh restart
sysctl -p /etc/sysctl.conf
iptables-restore < /root/iptables.backup
```

## Common Issues and Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| SSH Connection Refused | Cannot connect via SSH | Check sshd_config syntax, ensure service running |
| SSH Key Rejected | "Permission denied (publickey)" | Check .ssh permissions (700), authorized_keys (600) |
| Firewall Blocking | Connection timeout | Check iptables rules, ensure port 22 open |
| Sudo Not Working | "user is not in sudoers" | Check /etc/sudoers and /etc/sudoers.d/ |
| Services Failing | Services won't start | Check file permissions, SELinux contexts |
| Slow SSH Login | Long delay before prompt | Check DNS resolution, UseDNS no in sshd_config |

## Testing Commands

```sh
# Test SSH key authentication
ssh -o PasswordAuthentication=no -o PubkeyAuthentication=yes user@server

# Test SSH password authentication (if enabled)
ssh -o PreferredAuthentications=password user@server

# Test sudo access
sudo -l
sudo -v

# Test firewall rules
nmap -p22 server_ip

# Check for open ports
netstat -an | grep LISTEN

# Verify hardening effectiveness
# Using Lynis (if installed)
lynis audit system --quick

# Manual checks
find / -type f -perm -4000 2>/dev/null  # SUID files
find / -type f -perm -002 2>/dev/null   # World-writable files
```

## Compliance Quick Checks

```sh
# CIS Benchmark Key Items
grep "^Protocol 2" /etc/ssh/sshd_config || echo "FAIL: SSH Protocol"
grep "^PermitRootLogin no" /etc/ssh/sshd_config || echo "WARN: Root login"
grep "^PermitEmptyPasswords no" /etc/ssh/sshd_config || echo "FAIL: Empty passwords"
sysctl net.ipv4.ip_forward | grep "= 0" || echo "FAIL: IP forwarding"
sysctl net.ipv4.tcp_syncookies | grep "= 1" || echo "FAIL: SYN cookies"
```

## Post-Deployment Actions

1. **Document Changes**
   - Record all applied scripts
   - Note any custom modifications
   - Update system documentation

2. **Set Up Monitoring**
   - Configure alerts for failed SSH attempts
   - Monitor disk usage for logs
   - Watch for permission denied errors

3. **Schedule Reviews**
   - Weekly: Check logs for issues
   - Monthly: Verify hardening still applied
   - Quarterly: Review and update scripts

4. **Create Automation**
   - Add to configuration management
   - Create periodic compliance checks
   - Automate log analysis

## Support Resources

- **Logs to Check**: /var/log/auth.log, /var/log/syslog, /var/log/hardening_*.log
- **Backup Locations**: /root/*backup*, /etc/ssh/*.backup.*
- **Config Files**: /etc/ssh/sshd_config, /etc/sysctl.d/99-hardening.conf
- **Documentation**: CIS Debian Benchmark, NIST Guidelines, OWASP

## Important Notes

1. These scripts are templates - customize for your environment
2. Always test in non-production first
3. Some hardening may break specific applications
4. Maintain exemptions list for special requirements
5. Regular updates needed as threats evolve

## Final Safety Reminder

**The Golden Rule**: If you're not 100% sure a change is safe, test it with automatic rollback:

```sh
# Safe testing with automatic rollback after 5 minutes
(sleep 300; cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config; service ssh restart) &
# Make your changes
# If successful, kill the background job: kill %1
```