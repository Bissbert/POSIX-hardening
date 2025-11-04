# POSIX Hardening - Role Execution Order & Dependencies

## Quick Reference

**Order:** Pre-flight → SSH → Firewall → Core System → Access Control → Services → Audit → Banner

**Timing:**
- Priority 1 only: ~5-10 min
- Priorities 1-3: ~15-20 min
- Full (all): ~25-35 min

## Dependency Hierarchy

```
validation → ssh → firewall → {kernel, files, services}
kernel → {network, sysctl, limits → coredump}
files → {tmp, mount, password → accounts → {sudo, shell, cron}, audit, logs, integrity, banner}
```

## Execution Priorities

### Priority 0: Pre-flight Validation
- **Role:** `posix_hardening_validation`
- **Checks:** OS compatibility, SSH connectivity, disk space, admin IP
- **Critical:** Must succeed or deployment stops

### Priority 1: Critical Access
- **Roles:** `ssh`, `firewall`
- **Order:** SSH first (secure access) → Firewall (protect network)
- **Safety:** Emergency port 2222, 60s auto-rollback, connectivity checks
- **Time:** ~5-10 min

### Priority 2: Core System
- **Roles:** `kernel`, `network`, `sysctl`, `files`, `tmp`, `mount`
- **Flow:** Kernel → Network → Sysctl → Files → Tmp → Mount
- **Key:** 40+ sysctl params, file permissions, mount options (noexec/nosuid)
- **Time:** ~5-7 min

### Priority 3: Access Control
- **Roles:** `password`, `accounts`, `sudo`, `limits`, `coredump`, `shell`
- **Flow:** Passwords → Accounts → Sudo → Limits → Core dumps → Shell
- **Safety:** visudo validation, only system accounts locked (UID<1000)
- **Time:** ~5-7 min

### Priority 4: Services
- **Roles:** `services`, `cron`
- **Safety:** Never disables SSH/networking, whitelist approach
- **Time:** ~3-5 min

### Priority 5: Monitoring
- **Roles:** `audit`, `logs`, `integrity`
- **Key:** auditd rules, 90-day retention, AIDE baseline
- **Time:** ~5-10 min (AIDE slow)

### Priority 6: Final
- **Role:** `banner`
- **Purpose:** Legal disclaimers
- **Time:** ~1-2 min

## Role Dependencies

Dependencies declared in `meta/main.yml`, enforced automatically by Ansible.

**Key chains:**
- Longest: validation → ssh → firewall → files → password → accounts → sudo
- Kernel: firewall → kernel → {network, sysctl, limits→coredump}
- Files: firewall → files → {tmp, mount, audit, logs, integrity}

## Usage Examples

```bash
# Full deployment (all 21 roles)
ansible-playbook hardening_master.yml

# Priority 1 only (SSH + firewall)
ansible-playbook hardening_master.yml --tags priority1

# Specific role (runs dependencies)
ansible-playbook hardening_master.yml --tags sudo

# Dry run
ansible-playbook hardening_master.yml --check --diff

# Specific hosts
ansible-playbook hardening_master.yml -l webserver01
```

## Safety & Operations

### Pre-Deployment
✓ Run `ansible-playbook preflight.yml`
✓ Set `admin_ip` in `group_vars/all.yml`
✓ Test with `--check` first
✓ Have console access ready
✓ Create snapshots

### Emergency Recovery
```bash
# If locked out:
ssh -p 2222 user@server                      # Emergency port
ansible-playbook rollback.yml -l server      # Auto rollback
/opt/posix-hardening/emergency-rollback.sh   # Manual recovery
```

### Monitoring
- Logs: `/var/log/hardening/`
- State: `/var/lib/hardening/`
- Marker files: `<role>_hardened`

### Customization
```bash
# Skip roles
ansible-playbook hardening_master.yml --skip-tags audit,logs

# Override variables
ansible-playbook hardening_master.yml -e "posix_ssh_port=2022"

# Force re-run
ansible-playbook hardening_master.yml --tags ssh -e "force_reharden=true"
```

## Quick Reference

**Playbooks:** `hardening_master.yml`, `preflight.yml`, `rollback.yml`
**Bottlenecks:** AIDE baseline (5-10min), package installs
**Best Practice:** Test non-prod → Deploy by priority → Keep emergency SSH

---

*POSIX Hardening Role Execution Order v1.0*
