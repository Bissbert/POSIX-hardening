# Getting Started with POSIX Hardening

5-minute guide to hardening your Linux servers

## What is POSIX Hardening?

A comprehensive security hardening toolkit for Debian-based systems with **two deployment methods:**

1. **Ansible Roles** (recommended) - Automated, idempotent, role-based deployment
2. **Shell Scripts** - Standalone scripts for systems without Ansible

Covers: SSH, firewall, kernel, filesystem, access control, audit logging, and more (23 roles / 22 scripts).

---

## Quick Start: Ansible Deployment (Recommended)

### 1. Install Prerequisites (1 minute)

```shell
# Install Ansible
pip install -r ansible/requirements.txt

# OR with system package manager
apt install ansible  # Debian/Ubuntu
brew install ansible # macOS
```

### 2. Configure (2 minutes)

**Edit `ansible/inventory.ini`:**

```ini
[production]
server1.example.com ansible_host=192.168.1.10 ansible_user=admin
```

**Edit `ansible/group_vars/all.yml`:**

```yaml
admin_ip: "YOUR_IP_HERE"        # CRITICAL - your management IP
ssh_allow_users: "admin deploy" # Users who can SSH
enable_emergency_ssh: true      # Safety port 2222
```

### 3. Deploy (2 minutes)

```shell
cd ansible/

# Pre-flight check
ansible-playbook preflight.yml

# Deploy all hardening
ansible-playbook hardening_master.yml
```

**Done!** Your servers are hardened in ~25-35 minutes.

---

## Quick Start: Shell Scripts (Alternative)

For systems without Ansible or for manual execution:

```shell
# 1. Clone repository
git clone https://github.com/Bissbert/POSIX-hardening
cd POSIX-hardening

# 2. Set your admin IP
export ADMIN_IP="YOUR_IP_HERE"

# 3. Run orchestrator
sudo sh orchestrator.sh --full
```

See [`docs/SCRIPTS.md`](SCRIPTS.md) for detailed script usage.

---

## Common Operations

### Deploy by Priority

```shell
# Critical only (SSH + Firewall) - 5-10 min
ansible-playbook hardening_master.yml --tags priority1

# Critical + Core (8 roles) - 15-20 min
ansible-playbook hardening_master.yml --tags priority1,priority2

# Full deployment (21 roles) - 25-35 min
ansible-playbook hardening_master.yml
```

### Test Before Deploying

```shell
# Dry run - see what would change
ansible-playbook hardening_master.yml --check --diff

# Single host first
ansible-playbook hardening_master.yml -l staging-server
```

### Emergency Recovery

If you lose SSH access:

```shell
# Option 1: Emergency SSH port
ssh -p 2222 user@server

# Option 2: Rollback playbook
ansible-playbook rollback.yml -l affected_server

# Option 3: Manual recovery (requires console)
sudo /opt/posix-hardening/emergency-rollback.sh --force
```

---

## What Gets Hardened?

### Priority 1: Critical (5-10 min)

- **SSH:** Key-only auth, no root login, emergency port 2222
- **Firewall:** iptables/ip6tables, stateful filtering

### Priority 2: Core System (5-7 min)

- **Kernel:** 40+ sysctl parameters (ASLR, TCP hardening)
- **Network:** Interface-level security
- **Filesystem:** Permissions, /tmp nosuid/noexec, mount options

### Priority 3: Access Control (5-7 min)

- **Password Policies:** PAM pwquality, aging, history
- **Account Security:** Lock system accounts, sudo restrictions
- **Limits:** Process/file limits, core dump disable

### Priority 4-6: Additional (10-15 min)

- Services, cron restrictions, audit logging, log retention, integrity monitoring, banners

---

## Configuration

All settings have sane defaults. Key variables to customize:

| Variable | Purpose | Default |
|----------|---------|---------|
| `admin_ip` | **Your management IP (CRITICAL)** | Must set |
| `ssh_port` | Main SSH port | 22 |
| `ssh_allow_users` | Who can SSH | Must set |
| `enable_emergency_ssh` | Safety backup port 2222 | true |
| `posix_ssh_permit_root_login` | Allow root login | no |
| `posix_kernel_tcp_syncookies` | SYN flood protection | 1 |

**Full reference:** [`ansible/group_vars/all.yml`](../ansible/group_vars/all.yml) or [`docs/reference/configuration.md`](reference/configuration.md)

---

## Documentation Map

### New Users

- **This file** - Quick start
- [`ansible/QUICK_START_ROLES.md`](../ansible/QUICK_START_ROLES.md) - Quick command reference
- [`ansible/README.md`](../ansible/README.md) - Ansible deployment guide

### Reference

- [`SCRIPTS.md`](SCRIPTS.md) - Shell script documentation (22 scripts)
- [`reference/configuration.md`](reference/configuration.md) - Configuration options
- [`ROLE_EXECUTION_ORDER.md`](ROLE_EXECUTION_ORDER.md) - Role dependencies & order

### Advanced

- [`architecture/overview.md`](architecture/overview.md) - System architecture
- [`guides/IMPLEMENTATION_GUIDE.md`](guides/IMPLEMENTATION_GUIDE.md) - Detailed implementation
- [`ansible/TESTING.md`](../ansible/TESTING.md) - Testing with Molecule
- [`FUTURE_IMPROVEMENTS.md`](FUTURE_IMPROVEMENTS.md) - Roadmap

---

## Safety First

### Pre-Deployment Checklist

- [ ] Set `admin_ip` in `group_vars/all.yml`
- [ ] Configure `ssh_allow_users`
- [ ] Test with `--check` mode first
- [ ] Have console/IPMI access ready
- [ ] Create backup/snapshot
- [ ] Schedule maintenance window
- [ ] Test in non-production first

### Built-in Safety Features

- **Emergency SSH port 2222** - Backup access
- **Auto-rollback** - 60-second timeout
- **Pre-flight validation** - Catches issues before changes
- **Idempotent** - Safe to run multiple times
- **Comprehensive backups** - All configs backed up to `/var/backups/hardening/`
- **visudo validation** - sudo configs tested before applying

---

## Troubleshooting

### Deployment Issues

```shell
# Verbose output
ansible-playbook hardening_master.yml -vvv

# Skip problematic role
ansible-playbook hardening_master.yml --skip-tags audit

# Check logs on target
ssh user@server 'cat /var/log/hardening/*.log'
```

### Connection Issues

```shell
# Test connectivity
ansible all -m ping

# Check SSH config
ansible all -m shell -a "grep Port /etc/ssh/sshd_config"

# Try emergency port
ssh -p 2222 user@server
```

**More:** [`ansible/README.md` Troubleshooting](../ansible/README.md#-troubleshooting)

---

## Support & Contributing

- **Issues:** <https://github.com/Bissbert/POSIX-hardening/issues>
- **Documentation:** This `docs/` directory
- **Repository:** <https://github.com/Bissbert/POSIX-hardening>

---

## Project Structure

```text
POSIX-hardening/
├── ansible/                    # Ansible deployment (recommended)
│   ├── hardening_master.yml   # Main playbook - all 21 roles
│   ├── preflight.yml          # Pre-flight validation
│   ├── rollback.yml           # Emergency recovery
│   ├── roles/                 # 23 hardening roles
│   └── group_vars/all.yml     # Configuration
├── scripts/                   # Standalone shell scripts (alternative)
│   ├── 01-ssh-hardening.sh    # 22 hardening scripts
│   └── ...
├── lib/                       # Shared library functions
├── docs/                      # Documentation (you are here)
└── README.md                  # Project overview
```

---

## Next Steps

1. **Deploy to test environment:**

   ```shell
   ansible-playbook hardening_master.yml -l test-server
   ```

2. **Review deployment report:**

   ```shell
   ssh user@server 'cat /var/log/hardening/deployment_report_*.txt'
   ```

3. **Verify hardening:**

   ```shell
   # Check applied roles
   ansible all -m shell -a "ls -1 /var/lib/hardening/*_hardened"

   # Run validation
   ansible all -m shell -a "cd /opt/posix-hardening && sh tests/validation_suite.sh"
   ```

4. **Deploy to production** (after testing!)

---

**Welcome to POSIX Hardening!** 🔒

Start with the Quick Start above, then explore the documentation as needed.
