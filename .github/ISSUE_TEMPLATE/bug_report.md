---
name: Bug Report
about: Report a bug in the POSIX hardening scripts
title: '[BUG] '
labels: bug
assignees: ''
---

## Bug Description

<!-- A clear and concise description of what the bug is -->

## Environment

**Operating System:**
- [ ] Debian 11
- [ ] Debian 12
- [ ] Ubuntu 20.04
- [ ] Ubuntu 22.04
- [ ] Other: <!-- specify -->

**Shell:**
- [ ] `/bin/sh`
- [ ] `dash`
- [ ] `bash`
- [ ] `ash` (BusyBox)
- [ ] Other: <!-- specify -->

**Deployment Method:**
- [ ] Standalone shell scripts (orchestrator.sh)
- [ ] Ansible automation
- [ ] Manual script execution

**Version:**
<!-- Check VERSION file or git commit hash -->
```
Version:
```

## Steps to Reproduce

1. <!-- First step -->
2. <!-- Second step -->
3. <!-- Third step -->
4. <!-- And so on... -->

**Command executed:**
```bash
# Paste the exact command you ran

```

## Expected Behavior

<!-- A clear description of what you expected to happen -->

## Actual Behavior

<!-- A clear description of what actually happened -->

## Logs

**Hardening Log:**
<!-- Contents of /var/log/hardening/hardening-*.log -->
```
# Paste relevant log entries

```

**Error Output:**
```
# Paste any error messages from terminal

```

**System Logs:**
<!-- If relevant, include /var/log/syslog or journalctl output -->
```
# Paste relevant system logs

```

## Impact

<!-- Select all that apply -->
- [ ] SSH lockout (cannot connect to server)
- [ ] Service disruption (services stopped working)
- [ ] Data loss or corruption
- [ ] Security vulnerability
- [ ] Performance degradation
- [ ] Incorrect configuration
- [ ] Other: <!-- specify -->

**Severity:**
- [ ] Critical (system unusable, locked out)
- [ ] High (major feature broken)
- [ ] Medium (feature partially broken)
- [ ] Low (minor issue, workaround available)

## System State

**Before hardening:**
```bash
# Output of: uname -a

# Output of: systemctl status sshd

```

**After hardening:**
```bash
# Current SSH configuration (if accessible)
# cat /etc/ssh/sshd_config | grep -v '^#' | grep -v '^$'

# Current firewall rules (if accessible)
# iptables -L -n -v

```

## Configuration

**Config file used:**
<!-- Contents of config/defaults.conf if using standalone, or relevant ansible/group_vars/all.yml if using Ansible -->
```bash
# Paste your configuration (redact sensitive IPs/usernames if needed)

```

## Rollback Status

- [ ] Automatic rollback triggered
- [ ] Manual rollback attempted
- [ ] Rollback succeeded
- [ ] Rollback failed
- [ ] No rollback attempted

**Rollback log:**
```
# Contents of /var/log/hardening/rollback.log if available

```

## Workaround

<!-- If you found a workaround, describe it here -->

## Additional Context

<!-- Any other context about the problem -->

## Recovery Method Used

<!-- If you regained access to the system, how did you do it? -->
- [ ] Emergency SSH port (2222)
- [ ] Console access (physical/IPMI/KVM)
- [ ] Single-user mode
- [ ] Automatic rollback after timeout
- [ ] Manual rollback script
- [ ] Other: <!-- specify -->

## Files for Debugging

<!-- Attach or link to any relevant files -->
- [ ] Complete log from /var/log/hardening/
- [ ] Backup files from /var/backups/hardening/
- [ ] Configuration file used
- [ ] Screenshot of error
- [ ] Network diagram (for firewall issues)

---

**Checklist before submitting:**
- [ ] I have checked existing issues for duplicates
- [ ] I have included all relevant logs
- [ ] I have redacted sensitive information (IPs, usernames, keys)
- [ ] I have described the impact accurately
- [ ] I have provided steps to reproduce
