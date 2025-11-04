# POSIX Hardening - Role Execution Order & Dependencies

**Date:** November 4, 2025
**Status:** Production Ready

## Overview

This document details the execution order and dependencies for all 21 POSIX hardening Ansible roles. The order is critical for maintaining system access, preventing lockouts, and ensuring proper configuration sequencing.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Dependency Hierarchy](#dependency-hierarchy)
- [Execution Priorities](#execution-priorities)
- [Role Dependencies](#role-dependencies)
- [Usage Examples](#usage-examples)
- [Safety Considerations](#safety-considerations)

## Quick Reference

### Execution Order Summary

```
Pre-flight → SSH → Firewall → Core System → Access Control → Services → Audit → Banner
```

### Total Execution Time
- **Minimal (Priority 1 only)**: ~5-10 minutes
- **Standard (Priorities 1-3)**: ~15-20 minutes
- **Full (All priorities)**: ~25-35 minutes

## Dependency Hierarchy

The roles are organized in a strict dependency hierarchy to ensure proper execution order:

```
posix_hardening_validation (foundation)
    └── posix_hardening_ssh
        └── posix_hardening_firewall
            ├── posix_hardening_kernel
            │   ├── posix_hardening_network
            │   ├── posix_hardening_sysctl
            │   └── posix_hardening_limits
            │       └── posix_hardening_coredump
            ├── posix_hardening_files
            │   ├── posix_hardening_tmp
            │   ├── posix_hardening_mount
            │   ├── posix_hardening_password
            │   │   └── posix_hardening_accounts
            │   │       ├── posix_hardening_sudo
            │   │       ├── posix_hardening_shell
            │   │       └── posix_hardening_cron
            │   ├── posix_hardening_audit
            │   ├── posix_hardening_logs
            │   ├── posix_hardening_integrity
            │   └── posix_hardening_banner
            └── posix_hardening_services
```

## Execution Priorities

### Priority 0: Pre-flight Validation
**Role:** `posix_hardening_validation`

**Purpose:** Verify system compatibility and readiness before any hardening

**Checks:**
- Debian-based system verification
- SSH connectivity validation
- SSH key presence confirmation
- Disk space availability
- Required commands present
- Admin IP configuration

**Why First:**
- Prevents deployment on incompatible systems
- Catches configuration errors early
- Validates prerequisites before changes

**Critical:** This role MUST succeed or deployment stops

---

### Priority 1: Critical Access & Protection
**Roles:**
1. `posix_hardening_ssh`
2. `posix_hardening_firewall`

**Purpose:** Secure remote access and establish network protection before any other changes

**Why This Order:**

1. **SSH First:**
   - Hardens SSH configuration while maintaining access
   - Creates emergency SSH port (2222) as backup
   - Disables root login and password authentication
   - **Must succeed**: If SSH breaks, everything else is pointless

2. **Firewall Second:**
   - Protects the system after SSH is secured
   - Allows SSH traffic (both main and emergency ports)
   - Establishes baseline network security
   - **Depends on SSH**: Needs SSH ports configured first

**Safety Features:**
- Emergency SSH port on 2222
- Automatic rollback after 60 seconds if connectivity lost
- Multiple SSH connectivity checks
- Drift detection and recovery

**Time:** ~5-10 minutes
**Risk:** Medium (SSH reconfiguration)
**Reversible:** Yes (emergency port + rollback)

---

### Priority 2: Core System Security
**Roles:**
1. `posix_hardening_kernel`
2. `posix_hardening_network`
3. `posix_hardening_sysctl`
4. `posix_hardening_files`
5. `posix_hardening_tmp`
6. `posix_hardening_mount`

**Purpose:** Harden kernel, network stack, and filesystem foundations

**Execution Flow:**

```
Kernel Parameters (03-kernel-params.sh)
    ↓
Network Interfaces (04-network-stack.sh)
    ↓
Sysctl Tuning (14-sysctl-hardening.sh)
    ↓
File Permissions (05-file-permissions.sh)
    ↓
Tmp Hardening (12-tmp-hardening.sh)
    ↓
Mount Options (16-mount-options.sh)
```

**Why This Order:**

1. **Kernel Parameters:** Foundation for memory and process security (ASLR, KASLR)
2. **Network Interfaces:** Per-interface security settings (IP forwarding, source routing)
3. **Sysctl Tuning:** Advanced TCP/network optimization
4. **File Permissions:** Secure critical system files (/etc/passwd, /etc/shadow, SSH configs)
5. **Tmp Hardening:** Mount /tmp with nosuid/nodev/noexec
6. **Mount Options:** Apply security options to /proc, /home, /var

**Key Settings:**
- 40+ kernel sysctl parameters
- Network interface hardening (per-interface)
- Critical file permissions (0000 for /etc/shadow)
- Filesystem mount options (hidepid=2 for /proc)

**Time:** ~5-7 minutes
**Risk:** Low (no service disruption)
**Reversible:** Yes (backups in /var/backups/hardening/)

---

### Priority 3: Access Control & User Security
**Roles:**
1. `posix_hardening_password`
2. `posix_hardening_accounts`
3. `posix_hardening_sudo`
4. `posix_hardening_limits`
5. `posix_hardening_coredump`
6. `posix_hardening_shell`

**Purpose:** Enforce password policies, lock accounts, restrict privileges

**Execution Flow:**

```
Password Policies (08-password-policy.sh)
    ↓
Account Lockdown (09-account-lockdown.sh)
    ↓
Sudo Restrictions (10-sudo-restrictions.sh)
    ↓
Process Limits (06-process-limits.sh)
    ↓
Core Dump Disable (13-core-dump-disable.sh)
    ↓
Shell Timeout (17-shell-timeout.sh)
```

**Why This Order:**

1. **Password Policies:** Configure PAM pwquality before user operations
2. **Account Lockdown:** Lock unused accounts, set nologin shell
3. **Sudo Restrictions:** Configure sudo logging and restrictions (visudo validation!)
4. **Process Limits:** Set ulimits for processes and files
5. **Core Dump Disable:** Multi-layer core dump prevention
6. **Shell Timeout:** TMOUT and shell history hardening

**Critical Safety:**
- **Sudo role uses `visudo -cf` validation** - NEVER allows invalid sudoers file
- Password policies won't affect existing users immediately
- Account lockdown only affects system accounts (UID < 1000)

**Time:** ~5-7 minutes
**Risk:** Medium (sudo configuration)
**Reversible:** Yes (sudoers backups + validation)

---

### Priority 4: Service Management
**Roles:**
1. `posix_hardening_services`
2. `posix_hardening_cron`

**Purpose:** Disable unnecessary services, restrict scheduling

**Execution Flow:**

```
Service Disable (11-service-disable.sh)
    ↓
Cron Restrictions (15-cron-restrictions.sh)
```

**Why This Order:**

1. **Services:** Disable/mask unnecessary services (never disables critical ones)
2. **Cron:** Restrict cron/at access via allow/deny files

**Safe Defaults:**
- Never disables SSH, networking, or critical system services
- Only disables commonly unnecessary services (Bluetooth, cups, avahi)
- Cron restrictions use whitelist approach (cron.allow)

**Time:** ~3-5 minutes
**Risk:** Low (safe defaults)
**Reversible:** Yes (services can be re-enabled)

---

### Priority 5: Audit & Monitoring
**Roles:**
1. `posix_hardening_audit`
2. `posix_hardening_logs`
3. `posix_hardening_integrity`

**Purpose:** Enable security monitoring and logging

**Execution Flow:**

```
Audit Logging (07-audit-logging.sh)
    ↓
Log Retention (19-log-retention.sh)
    ↓
Integrity Baseline (20-integrity-baseline.sh)
```

**Why This Order:**

1. **Audit Logging:** Configure auditd with comprehensive rules
2. **Log Retention:** Set up logrotate for 90-day retention
3. **Integrity Monitoring:** AIDE baseline and daily checks

**Key Features:**
- Monitors critical files and syscalls
- 90-day compressed log retention
- Daily AIDE integrity checks
- Audit log rotation

**Time:** ~5-10 minutes (AIDE baseline can take time)
**Risk:** Low (monitoring only)
**Reversible:** Yes

---

### Priority 6: Final Configuration
**Role:** `posix_hardening_banner`

**Purpose:** Legal disclaimers and warning banners

**Execution Flow:**

```
Banner Warnings (18-banner-warnings.sh)
```

**Why Last:**
- Non-critical cosmetic configuration
- Applies to /etc/issue, /etc/issue.net, /etc/motd
- CIS/STIG compliant warning text

**Time:** ~1-2 minutes
**Risk:** None
**Reversible:** Yes

---

## Role Dependencies

Each role declares its dependencies in `meta/main.yml`. Ansible automatically ensures dependencies are executed first.

### Dependency Table

| Role | Depends On | Reason |
|------|-----------|--------|
| **posix_hardening_validation** | (none) | Foundation |
| **posix_hardening_ssh** | validation | Needs pre-flight checks |
| **posix_hardening_firewall** | ssh | Needs SSH ports configured |
| **posix_hardening_kernel** | firewall | Needs network protection first |
| **posix_hardening_network** | kernel | Needs kernel params set |
| **posix_hardening_sysctl** | kernel | Needs kernel params set |
| **posix_hardening_files** | firewall | Needs baseline security |
| **posix_hardening_tmp** | files | Needs file permission baseline |
| **posix_hardening_mount** | files | Needs file permission baseline |
| **posix_hardening_password** | files | Needs PAM files secured |
| **posix_hardening_accounts** | password | Needs password policies first |
| **posix_hardening_sudo** | accounts | Needs accounts configured |
| **posix_hardening_limits** | kernel | Needs kernel limits |
| **posix_hardening_coredump** | limits | Needs limit configs |
| **posix_hardening_shell** | accounts | Needs user accounts |
| **posix_hardening_services** | firewall | Needs network security |
| **posix_hardening_cron** | accounts | Needs user accounts |
| **posix_hardening_audit** | files | Needs audit files secured |
| **posix_hardening_logs** | files | Needs log files secured |
| **posix_hardening_integrity** | files | Needs baseline files |
| **posix_hardening_banner** | files | Needs file permissions |

### Dependency Chains

**Longest Chain (12 levels):**
```
validation → ssh → firewall → files → password → accounts → sudo
```

**Alternative Chains:**
```
validation → ssh → firewall → kernel → network
validation → ssh → firewall → kernel → limits → coredump
validation → ssh → firewall → files → tmp
```

## Usage Examples

### Full Deployment (All Priorities)

```bash
cd ansible/
ansible-playbook hardening_master.yml
```

Executes all 21 roles in dependency order:
- Pre-flight validation
- All 6 priorities
- Final validation and reporting

**Time:** ~25-35 minutes
**Use Case:** Initial hardening deployment

---

### Critical Only (Priority 1)

```bash
ansible-playbook hardening_master.yml --tags priority1
```

Executes only:
- posix_hardening_validation
- posix_hardening_ssh
- posix_hardening_firewall

**Time:** ~5-10 minutes
**Use Case:** Emergency hardening, quick security baseline

---

### Priority 1 + 2 (Critical + Core)

```bash
ansible-playbook hardening_master.yml --tags priority1,priority2
```

Executes:
- Priority 1 (SSH + Firewall)
- Priority 2 (Kernel + Filesystem)

**Time:** ~10-15 minutes
**Use Case:** Strong security foundation without user restrictions

---

### Specific Role (With Dependencies)

```bash
ansible-playbook hardening_master.yml --tags sudo
```

Automatically executes dependency chain:
1. validation
2. ssh
3. firewall
4. files
5. password
6. accounts
7. sudo ← Target role

**Time:** Varies by dependency depth
**Use Case:** Update specific configuration

---

### Dry Run (Check Mode)

```bash
ansible-playbook hardening_master.yml --check --diff
```

Shows what would change without applying:
- Safe to run in production
- No actual modifications
- Preview of changes

**Time:** ~5-10 minutes
**Use Case:** Preview before deployment, compliance check

---

### Specific Hosts

```bash
# Single host
ansible-playbook hardening_master.yml -l webserver01

# Host group
ansible-playbook hardening_master.yml -l production

# Multiple hosts
ansible-playbook hardening_master.yml -l "web01,web02,db01"
```

---

## Safety Considerations

### Pre-Deployment Checklist

- [ ] Run pre-flight validation: `ansible-playbook preflight.yml`
- [ ] Configure `admin_ip` in `group_vars/all.yml`
- [ ] Test with `--check` mode first
- [ ] Have console/IPMI access ready
- [ ] Create manual backup/snapshot
- [ ] Document current SSH port and credentials
- [ ] Schedule maintenance window
- [ ] Prepare rollback plan

### During Deployment

**Monitor Progress:**
```bash
# Watch log file
tail -f /var/log/hardening/*.log

# Check deployment status
ansible all -m shell -a "ls -la /var/lib/hardening/"
```

**Verify Connectivity:**
```bash
# Test SSH access periodically
ansible all -m ping
```

### Post-Deployment

**Verify Applied Roles:**
```bash
ssh user@server
ls -1 /var/lib/hardening/
```

**Check Deployment Report:**
```bash
cat /var/log/hardening/deployment_report_*.txt
```

**Test System Functionality:**
- SSH access (both normal and emergency port)
- Application services
- Network connectivity
- User authentication

### Emergency Recovery

**If SSH access is lost:**

1. Wait 60 seconds (automatic rollback triggers)
2. Try emergency SSH port:
   ```bash
   ssh -p 2222 user@server
   ```
3. Run rollback playbook:
   ```bash
   ansible-playbook rollback.yml -l affected_server
   ```

**Manual recovery via console:**
```bash
# Emergency rollback script
sudo /opt/posix-hardening/emergency-rollback.sh --force

# Restore specific role
sudo cp /var/backups/hardening/sshd_config.* /etc/ssh/sshd_config
sudo systemctl restart ssh
```

### Idempotency

All roles are idempotent and safe to re-run:
- Marker files track completion: `/var/lib/hardening/<role>_hardened`
- Skip execution if marker exists (unless `force_reharden=true`)
- Changes only when necessary
- Proper `changed_when` conditions

**Re-run specific role:**
```bash
ansible-playbook hardening_master.yml --tags ssh -e "force_reharden=true"
```

## Customization

### Modify Execution Order

Edit `ansible/hardening_master.yml` and adjust:
- Play order
- Role inclusion
- Priority groupings
- Tags

### Change Dependencies

Edit `ansible/roles/*/meta/main.yml`:
```yaml
dependencies:
  - role: posix_hardening_validation
  - role: posix_hardening_ssh
```

### Skip Specific Roles

```bash
# Skip specific role
ansible-playbook hardening_master.yml --skip-tags audit

# Skip multiple roles
ansible-playbook hardening_master.yml --skip-tags "audit,integrity,logs"
```

### Override Variables

```bash
# Command line
ansible-playbook hardening_master.yml -e "posix_ssh_port=2022"

# Variables file
ansible-playbook hardening_master.yml -e @custom_vars.yml
```

## Troubleshooting

### Role Fails to Execute

**Check dependencies:**
```bash
ansible-playbook hardening_master.yml --list-tasks
```

**Run dependency manually:**
```bash
ansible-playbook hardening_master.yml --tags validation
```

### Execution Takes Too Long

**Expected times by priority:**
- Priority 0 (validation): 1-2 min
- Priority 1 (SSH/firewall): 5-10 min
- Priority 2 (core): 5-7 min
- Priority 3 (access): 5-7 min
- Priority 4 (services): 3-5 min
- Priority 5 (audit): 5-10 min
- Priority 6 (banner): 1-2 min

**Bottlenecks:**
- AIDE baseline creation (Priority 5) - can take 5-10 minutes
- Package installations (if missing auditd, aide, etc.)
- Network latency

### Marker Files Not Created

Check for errors:
```bash
ansible all -m shell -a "tail -50 /var/log/hardening/*.log"
```

Verify role succeeded:
```bash
ansible all -m shell -a "cat /var/lib/hardening/completed"
```

## Best Practices

1. **Always run validation first**
2. **Test in non-production environment**
3. **Deploy incrementally by priority**
4. **Keep emergency SSH enabled until fully tested**
5. **Monitor logs during deployment**
6. **Create backups/snapshots before hardening**
7. **Document any custom changes**
8. **Review deployment reports**

## References

- Main playbook: `ansible/hardening_master.yml`
- Old playbook (shell-based): `ansible/site.yml`
- Pre-flight checks: `ansible/preflight.yml`
- Rollback: `ansible/rollback.yml`
- Testing guide: `ansible/TESTING.md`
- Completion report: `docs/SCRIPT_CONVERSION_COMPLETE.md`

---

**Version:** 1.0
**Last Updated:** November 4, 2025
**Maintainer:** POSIX Hardening Team
**Repository:** https://github.com/Bissbert/POSIX-hardening
