# POSIX Hardening Ansible Deployment Guide

Automated deployment of the POSIX Shell Server Hardening Toolkit using Ansible.

## 🚀 Quick Start

### Testing with Docker (Recommended)

Test the playbooks in a safe, isolated environment:

```bash
cd ansible/testing
./test-runner.sh full
```

See [testing/README.md](testing/README.md) for complete Docker testing documentation.

### Prerequisites for Production

1. **Ansible installed on control machine**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install ansible

# macOS
brew install ansible

# Python pip
pip install ansible
```

2. **SSH access to target servers** with sudo privileges
3. **SSH key authentication configured** (password auth will be disabled!)

### Step 1: Configure Inventory

Edit `inventory.ini` to add your target servers:

```ini
[production]
server1.example.com ansible_host=192.168.1.10 ansible_user=admin

[production:vars]
admin_ip=YOUR_MANAGEMENT_IP_HERE  # CRITICAL - Set your IP!
```

### Step 2: Set Critical Variables

Edit `group_vars/all.yml`:

```yaml
# CRITICAL - Set your management IP for emergency access
admin_ip: "YOUR_IP_HERE"

# SSH settings
ssh_port: 22
ssh_allow_users: "admin deploy"  # Users who can SSH

# Emergency access
enable_emergency_ssh: true
emergency_ssh_port: 2222
```

### Step 3: Run Pre-flight Checks

```bash
cd ansible/
ansible-playbook preflight.yml
```

### Step 4: Deploy Hardening

```bash
# Test mode (dry run)
ansible-playbook site.yml -e "dry_run=1"

# Deploy to staging
ansible-playbook site.yml -l staging

# Deploy to production
ansible-playbook site.yml -l production
```

## 📋 Detailed Usage

### Pre-flight Checks

Always run pre-flight checks first:

```bash
ansible-playbook preflight.yml

# Check specific hosts
ansible-playbook preflight.yml -l server1.example.com
```

This verifies:
- ✓ Debian-based OS
- ✓ SSH connectivity
- ✓ SSH keys present
- ✓ Sufficient disk space
- ✓ Required commands available

### Deployment Options

#### Full Deployment (All Scripts)
```bash
ansible-playbook site.yml
```

#### Priority-Based Deployment

Deploy only critical scripts (SSH + Firewall):
```bash
ansible-playbook site.yml --tags priority1
```

Deploy by priority level:
```bash
# Priority 1: SSH and Firewall (Critical)
ansible-playbook site.yml --tags priority1

# Priority 2: Core hardening
ansible-playbook site.yml --tags priority2

# Priority 3: Standard hardening
ansible-playbook site.yml --tags priority3

# Priority 4: Additional hardening
ansible-playbook site.yml --tags priority4
```

#### Component-Specific Deployment

```bash
# Deploy toolkit only
ansible-playbook site.yml --tags deploy

# Run hardening only (toolkit must be deployed)
ansible-playbook site.yml --tags harden

# Run validation only
ansible-playbook site.yml --tags validate
```

### Dry Run Mode

Test without making changes:

```bash
# Via command line
ansible-playbook site.yml -e "dry_run=1"

# Via inventory
# Set in group_vars or host_vars:
# dry_run: 1
```

### Limit to Specific Hosts

```bash
# Single host
ansible-playbook site.yml -l server1.example.com

# Multiple hosts
ansible-playbook site.yml -l "server1.example.com,server2.example.com"

# Host group
ansible-playbook site.yml -l production
```

## 🔧 Configuration

### Inventory Structure

```ini
[production]
server1.example.com ansible_host=10.0.1.10 ansible_user=admin

[staging]
staging.example.com ansible_host=10.0.2.10 ansible_user=admin

[test]
test.example.com ansible_host=10.0.3.10 ansible_user=testuser

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### Important Variables

#### Critical Settings (group_vars/all.yml)

```yaml
# Your management IP - NEVER lose access!
admin_ip: "203.0.113.10"

# SSH configuration
ssh_port: 22
ssh_allow_users: "admin deploy"
ssh_allow_groups: "ssh-users"

# Emergency SSH backdoor
enable_emergency_ssh: true
emergency_ssh_port: 2222
remove_emergency_ssh: false  # Set true after testing

# Safety settings
dry_run: 0  # Set to 1 for simulation
safety_mode: 1  # NEVER disable in production
rollback_enabled: 1
```

#### Per-Environment Settings

Create `group_vars/production.yml`:
```yaml
dry_run: 0
run_full_hardening: true
enable_emergency_ssh: true
```

Create `group_vars/staging.yml`:
```yaml
dry_run: 0
run_full_hardening: true
enable_emergency_ssh: true
```

Create `group_vars/test.yml`:
```yaml
dry_run: 1
run_full_hardening: false
enable_emergency_ssh: true
```

### Using Ansible Vault for Secrets

Encrypt sensitive variables:

```bash
# Create encrypted variables file
ansible-vault create group_vars/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/vault.yml

# Content example:
vault_sudo_pass: "your_sudo_password"
vault_admin_ip: "203.0.113.10"
```

Run playbook with vault:
```bash
ansible-playbook site.yml --ask-vault-pass
```

## 🆘 Emergency Procedures

### If SSH Access is Lost

1. **Wait 60 seconds** - Automatic rollback will trigger
2. **Use emergency SSH port**:
   ```bash
   ssh -p 2222 user@server
   ```
3. **Run emergency rollback**:
   ```bash
   ansible-playbook rollback.yml -l affected_server
   ```

### Emergency Rollback

Restore systems to pre-hardening state:

```bash
# Interactive rollback
ansible-playbook rollback.yml

# Force rollback without confirmation
ansible-playbook rollback.yml -e "force_rollback=true"

# Rollback specific host
ansible-playbook rollback.yml -l server1.example.com
```

### Manual Recovery

If Ansible fails, SSH to server and run:

```bash
# Full emergency reset
sudo /opt/posix-hardening/emergency-rollback.sh --force

# Or restore from snapshot
sudo /opt/posix-hardening/emergency-rollback.sh
# Select option 3 (restore from snapshot)
```

## 📊 Monitoring Deployment

### Check Deployment Status

```bash
# View deployment logs
tail -f ansible.log

# Check specific host
ansible all -m shell -a "ls -la /opt/posix-hardening"

# Run validation
ansible all -m shell -a "cd /opt/posix-hardening && sh tests/validation_suite.sh"
```

### Verify Hardening

```bash
# Check completed scripts
ansible all -m shell -a "cat /var/lib/hardening/completed"

# Check SSH config
ansible all -m shell -a "grep PermitRootLogin /etc/ssh/sshd_config"

# Check firewall rules
ansible all -m shell -a "iptables -L -n"
```

## 🔒 Security Best Practices

1. **ALWAYS set admin_ip** to your management IP
2. **Test on non-production first**
3. **Keep emergency SSH enabled initially**
4. **Run pre-flight checks**
5. **Use dry_run mode for testing**
6. **Deploy incrementally by priority**
7. **Monitor logs during deployment**
8. **Have console access ready**

## 📝 Deployment Checklist

- [ ] Configured inventory with target servers
- [ ] Set admin_ip in variables
- [ ] Configured SSH key authentication
- [ ] Run pre-flight checks successfully
- [ ] Tested with dry_run=1
- [ ] Have console/IPMI access ready
- [ ] Documented current SSH port and credentials
- [ ] Created manual backup/snapshot
- [ ] Scheduled maintenance window
- [ ] Prepared rollback plan

## 🚨 Troubleshooting

### Connection Issues

```bash
# Test SSH connectivity
ansible all -m ping

# Verbose mode
ansible-playbook site.yml -vvv

# Check SSH config
ansible all -m shell -a "cat /etc/ssh/sshd_config | grep -E 'Port|PermitRoot|PasswordAuth'"
```

### Deployment Failures

```bash
# Resume from failure
ansible-playbook site.yml --start-at-task="Execute kernel parameters hardening"

# Skip failing task
ansible-playbook site.yml --skip-tags=priority3

# Use step mode
ansible-playbook site.yml --step
```

### Validation Failures

```bash
# Run validation manually
ansible all -m shell -a "cd /opt/posix-hardening && sh tests/validation_suite.sh"

# Check specific test
ansible all -m shell -a "cd /opt/posix-hardening && ./lib/common.sh && verify_ssh_connection"
```

## 📁 File Structure

```
ansible/
├── site.yml              # Main deployment playbook
├── preflight.yml         # Pre-deployment checks
├── rollback.yml          # Emergency rollback
├── inventory.ini         # Server inventory
├── ansible.cfg           # Ansible configuration
├── group_vars/
│   └── all.yml          # Global variables
├── host_vars/           # Host-specific variables
├── templates/
│   └── defaults.conf.j2 # Configuration template
├── testing/             # Docker-based testing
│   ├── Dockerfile       # Target system image
│   ├── docker-compose.yml # Multi-container setup
│   ├── inventory-docker.ini # Docker inventory
│   ├── test-runner.sh   # Automated testing script
│   └── README.md        # Testing documentation
└── README.md            # This file
```

## 🔄 Workflow Examples

### Production Deployment

```bash
# 1. Pre-flight
ansible-playbook preflight.yml -l production

# 2. Dry run
ansible-playbook site.yml -l production -e "dry_run=1"

# 3. Deploy critical (SSH + Firewall)
ansible-playbook site.yml -l production --tags priority1

# 4. Verify connectivity
ansible production -m ping

# 5. Deploy remaining
ansible-playbook site.yml -l production --tags priority2,priority3,priority4

# 6. Validate
ansible-playbook site.yml -l production --tags validate
```

### Staging Test

```bash
# Full deployment with all checks
ansible-playbook preflight.yml -l staging
ansible-playbook site.yml -l staging
```

### Single Server Update

```bash
# Update one server
ansible-playbook site.yml -l server1.example.com --tags harden
```

## 📊 Reporting

Deployment creates reports in:
- `/opt/posix-hardening/deployment_report_*.txt` on each server
- `/tmp/preflight_report_*.txt` on Ansible controller
- `ansible.log` in the ansible/ directory

## 🤝 Support

For issues:
1. Check `ansible.log` for errors
2. Run pre-flight checks
3. Verify variables in group_vars/all.yml
4. Test with dry_run=1
5. Use emergency rollback if needed

Remember: **Safety first!** This toolkit prioritizes maintaining access over security. Always have a backup plan.