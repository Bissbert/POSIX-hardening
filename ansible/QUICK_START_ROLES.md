# POSIX Hardening - Quick Start Guide (Role-Based)

**5-Minute Quick Start** for deploying POSIX hardening roles

## 🚀 Fast Track

### 1. Prerequisites (2 minutes)
```bash
# Install dependencies
pip install -r ansible/requirements.txt

# Configure your management IP (CRITICAL!)
vim ansible/group_vars/all.yml
# Set: admin_ip: "YOUR_IP_HERE"

# Add target servers
vim ansible/inventory.ini
```

### 2. Deploy (3 minutes)
```bash
cd ansible/

# Pre-flight check
ansible-playbook preflight.yml

# Deploy all roles
ansible-playbook hardening_master.yml
```

Done! 🎉

---

## 📋 Common Commands

### Full Deployment
```bash
# All 21 roles
ansible-playbook hardening_master.yml

# With check mode (dry run)
ansible-playbook hardening_master.yml --check --diff
```

### By Priority
```bash
# Critical only (SSH + Firewall)
ansible-playbook hardening_master.yml --tags priority1

# Critical + Core (8 roles)
ansible-playbook hardening_master.yml --tags priority1,priority2

# Everything except audit
ansible-playbook hardening_master.yml --skip-tags priority5
```

### Specific Roles
```bash
# Single role (with dependencies)
ansible-playbook hardening_master.yml --tags ssh
ansible-playbook hardening_master.yml --tags firewall
ansible-playbook hardening_master.yml --tags kernel

# Multiple specific roles
ansible-playbook hardening_master.yml --tags "ssh,firewall,kernel"
```

### Target Specific Hosts
```bash
# Single host
ansible-playbook hardening_master.yml -l server01

# Multiple hosts
ansible-playbook hardening_master.yml -l "web01,web02"

# Host group
ansible-playbook hardening_master.yml -l production
```

---

## 🎯 What Gets Deployed

### Priority 1: Critical (5-10 min)
- ✅ SSH hardening (port config, key auth, emergency port)
- ✅ Firewall setup (iptables/ip6tables)

### Priority 2: Core Security (5-7 min)
- ✅ Kernel parameters (40+ sysctl settings)
- ✅ Network stack hardening
- ✅ File permissions (/etc/shadow, SSH configs)
- ✅ Temporary directory security (/tmp with nosuid/nodev/noexec)

### Priority 3: Access Control (5-7 min)
- ✅ Password policies (PAM pwquality)
- ✅ Account lockdown (system accounts)
- ✅ Sudo restrictions (with visudo validation)
- ✅ Process limits & core dump disable

### Priority 4: Services (3-5 min)
- ✅ Disable unnecessary services
- ✅ Cron/at access restrictions

### Priority 5: Audit (5-10 min)
- ✅ Audit logging (auditd)
- ✅ Log retention (90 days)
- ✅ File integrity monitoring (AIDE)

### Priority 6: Final (1-2 min)
- ✅ Security banners (CIS/STIG compliant)

**Total Time:** 25-35 minutes for all roles

---

## 🔧 Configuration

### Critical Settings

Edit `ansible/group_vars/all.yml`:

```yaml
# CRITICAL - Your management IP
admin_ip: "203.0.113.10"

# SSH Configuration
ssh_port: 22
ssh_allow_users: "admin deploy"

# Emergency Access
enable_emergency_ssh: true
emergency_ssh_port: 2222

# Safety
dry_run: 0
force_reharden: false
```

### Per-Role Variables

All roles have extensive configuration options in their `defaults/main.yml`:

```bash
# View role defaults
cat ansible/roles/posix_hardening_ssh/defaults/main.yml
cat ansible/roles/posix_hardening_firewall/defaults/main.yml
```

Override in playbook or command line:
```bash
ansible-playbook hardening_master.yml -e "posix_ssh_port=2022"
```

---

## 🆘 Emergency Procedures

### SSH Access Lost

**Option 1: Emergency Port**
```bash
ssh -p 2222 user@server
```

**Option 2: Rollback Playbook**
```bash
ansible-playbook rollback.yml -l affected_server
```

**Option 3: Console Access**
```bash
# Via IPMI/console
sudo /opt/posix-hardening/emergency-rollback.sh --force
```

### Re-run Specific Role

```bash
# Force re-hardening (ignores marker files)
ansible-playbook hardening_master.yml --tags ssh -e "force_reharden=true"
```

### Check What's Applied

```bash
# View marker files
ansible all -m shell -a "ls -la /var/lib/hardening/"

# View deployment report
ansible all -m shell -a "cat /var/log/hardening/deployment_report_*.txt"
```

---

## 📊 Monitoring

### During Deployment

```bash
# Watch Ansible output
# (Already visible in terminal)

# Check remote logs (another terminal)
ssh user@server 'tail -f /var/log/hardening/*.log'
```

### After Deployment

```bash
# Test connectivity
ansible all -m ping

# Check applied roles
ansible all -m shell -a "ls -1 /var/lib/hardening/*_hardened | wc -l"

# View report
ansible all -m shell -a "cat /var/log/hardening/deployment_report_*.txt"
```

---

## 🧪 Testing

### Dry Run First

```bash
# Check what would change
ansible-playbook hardening_master.yml --check --diff

# Check specific priority
ansible-playbook hardening_master.yml --tags priority1 --check
```

### Molecule Tests (SSH Role)

```bash
cd ansible/roles/posix_hardening_ssh
molecule test
```

---

## 🔄 Idempotency

All roles are idempotent - safe to run multiple times:

```bash
# First run: applies changes
ansible-playbook hardening_master.yml

# Second run: no changes (skipped via marker files)
ansible-playbook hardening_master.yml

# Force re-run
ansible-playbook hardening_master.yml -e "force_reharden=true"
```

**Marker files:** `/var/lib/hardening/<role>_hardened`

---

## 📁 File Locations

### On Control Machine (Ansible)
```
ansible/
├── hardening_master.yml       # NEW: Role-based playbook
├── site.yml                    # OLD: Shell-script-based
├── preflight.yml              # Pre-flight checks
├── rollback.yml               # Emergency rollback
├── inventory.ini              # Target servers
├── group_vars/all.yml         # Global config
└── roles/                     # 21 hardening roles
```

### On Target Server
```
/var/lib/hardening/            # Marker files
/var/backups/hardening/        # Configuration backups
/var/log/hardening/            # Deployment logs + reports
/opt/posix-hardening/          # Old shell scripts (legacy)
```

---

## 🎓 Detailed Documentation

- **Full execution order:** `docs/ROLE_EXECUTION_ORDER.md`
- **Testing guide:** `ansible/TESTING.md`
- **Deployment guide:** `ansible/README.md`
- **Completion report:** `docs/SCRIPT_CONVERSION_COMPLETE.md`

---

## ⚡ Troubleshooting

### Playbook Fails

```bash
# Verbose mode
ansible-playbook hardening_master.yml -vvv

# Start at specific task
ansible-playbook hardening_master.yml --start-at-task="Task Name"

# Skip problematic tag
ansible-playbook hardening_master.yml --skip-tags problematic_role
```

### Dependency Issues

```bash
# List all tasks in order
ansible-playbook hardening_master.yml --list-tasks

# Check role dependencies
cat ansible/roles/*/meta/main.yml | grep -A 3 "dependencies:"
```

### Connection Issues

```bash
# Test connectivity
ansible all -m ping

# Check SSH config
ansible all -m shell -a "grep Port /etc/ssh/sshd_config"
```

---

## 🔒 Security Notes

1. **ALWAYS set `admin_ip`** before deployment
2. **Test in staging first** - never deploy directly to production
3. **Keep emergency SSH enabled** until fully tested
4. **Have console/IPMI access** before hardening SSH
5. **Create backup/snapshot** before deployment
6. **Review deployment report** after completion
7. **Monitor logs** during deployment
8. **Test application functionality** after hardening

---

## 🚀 Advanced Usage

### Custom Playbook

Create `my_hardening.yml`:
```yaml
---
- hosts: webservers
  become: yes
  roles:
    - posix_hardening_ssh
    - posix_hardening_firewall
    - posix_hardening_kernel
```

Run it:
```bash
ansible-playbook my_hardening.yml
```

### Ansible Vault (Secrets)

```bash
# Encrypt sensitive vars
ansible-vault create group_vars/vault.yml

# Run with vault
ansible-playbook hardening_master.yml --ask-vault-pass
```

### CI/CD Integration

```yaml
# .github/workflows/deploy.yml
- name: Deploy hardening
  run: |
    ansible-playbook hardening_master.yml \
      -i inventory.ini \
      --tags priority1,priority2
```

---

## 📞 Support

**Issues:** https://github.com/Bissbert/POSIX-hardening/issues

**Documentation:** All docs in `docs/` directory

**Logs:** Check `/var/log/hardening/` on target servers

---

**Quick Reference Card** - Save this for fast deployment! 🚀
