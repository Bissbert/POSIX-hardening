# Configuration Variable Reference

## Quick Start

> **📍 Full variable reference:** See `ansible/group_vars/all.yml` for complete list with defaults **🔧 Override:** Use
> `ansible/inventory.ini` or environment variables **📚 Examples:** Jump to
> [Common Scenarios](#common-configuration-scenarios)

## Configuration Overview

### Three Configuration Methods

1. **Ansible** (Production): `group_vars/all.yml` → `inventory.ini` → auto-generates `defaults.conf`
2. **Standalone** (Single server): Copy `defaults.conf.template` → edit `defaults.conf`
3. **Runtime** (Testing): Environment variables override all settings

### Precedence (Highest → Lowest)

1. Runtime environment variables
2. Ansible inventory variables
3. Ansible group variables
4. Local config file
5. Built-in defaults

### Key Files

- **Runtime config:** `/opt/posix-hardening/config/defaults.conf`
- **Ansible defaults:** `ansible/group_vars/all.yml` (⚠️ Master reference - 100+ variables)
- **Environment overrides:** `ansible/inventory.ini`

---

## Critical Variables Only

### Must-Set Variables ⚠️

| Variable              | Purpose                                   | Example                        | Without It                           |
| --------------------- | ----------------------------------------- | ------------------------------ | ------------------------------------ |
| **`ADMIN_IP`**        | Your management IP for firewall whitelist | `203.0.113.10` or `10.0.0.0/8` | **DEPLOYMENT FAILS** - Locked out    |
| **`SSH_ALLOW_USERS`** | Users allowed SSH access                  | `"admin john deploy"`          | **NO SSH ACCESS** - Complete lockout |

### Critical Safety Controls

| Variable                   | Default | Purpose                  | Warning                         |
| -------------------------- | ------- | ------------------------ | ------------------------------- |
| **`SAFETY_MODE`**          | `1`     | Master safety switch     | ⚠️ NEVER set to 0 in production |
| **`ROLLBACK_ENABLED`**     | `1`     | Auto-rollback on failure | Prevents permanent lockout      |
| **`SSH_ROLLBACK_TIMEOUT`** | `60`    | Seconds before rollback  | Time to verify changes work     |
| **`ENABLE_EMERGENCY_SSH`** | `1`     | Backup SSH on port 2222  | Keep during initial setup       |

### Key Configuration Variables

| Category      | Variable             | Default                  | Purpose                      |
| ------------- | -------------------- | ------------------------ | ---------------------------- |
| **SSH**       | `SSH_PORT`           | `22`                     | Primary SSH port             |
|               | `EMERGENCY_SSH_PORT` | `2222`                   | Backup access port           |
|               | `SSH_TEST_PORT`      | `2222`                   | Temporary test port          |
| **Firewall**  | `ENABLE_FIREWALL`    | `1`                      | Activate iptables            |
|               | `FIREWALL_TIMEOUT`   | `300`                    | Auto-rollback timer          |
|               | `ALLOWED_PORTS`      | `""`                     | Additional open ports        |
| **Execution** | `DRY_RUN`            | `0`                      | Simulation mode              |
|               | `VERBOSE`            | `0`                      | Debug output                 |
|               | `RUN_FULL_HARDENING` | `1`                      | All scripts vs priority only |
| **Paths**     | `TOOLKIT_PATH`       | `/opt/posix-hardening`   | Install location             |
|               | `BACKUP_DIR`         | `/var/backups/hardening` | Backup storage               |

---

## Common Configuration Scenarios

### Development/Test Environment

Minimal security for isolated development servers:

```bash
# config/defaults.conf or inventory.ini
DRY_RUN=1                    # Test mode first
VERBOSE=1                    # See what happens
ADMIN_IP="10.0.0.0/8"        # Internal network
SSH_PORT=22                  # Standard port OK
ENABLE_EMERGENCY_SSH=1       # Keep backdoor
ENABLE_FIREWALL=0            # May interfere with dev
RUN_FULL_HARDENING=0         # Quick setup
```

### Production Single Server

Maximum security for internet-facing server:

```bash
# Production settings
SAFETY_MODE=1                # Never disable
DRY_RUN=0                    # Apply changes
ADMIN_IP="203.0.113.10"      # Your static IP only
SSH_PORT=2222                # Non-standard port
SSH_ALLOW_USERS="admin"      # Specific user only
ENABLE_EMERGENCY_SSH=0       # No backdoor
ENABLE_FIREWALL=1            # Full firewall
ALLOWED_PORTS="443"          # HTTPS only
RUN_FULL_HARDENING=1         # All hardening
PASSWORD_MIN_LENGTH=16       # Strong passwords
ACCOUNT_LOCKOUT_THRESHOLD=3  # Strict lockout
```

### Production Multi-Server (Ansible)

```yaml
# ansible/inventory.ini
[production:vars]
admin_ip=203.0.113.0/24
ssh_port=2222
enable_emergency_ssh=false
allowed_ports=[443]
trusted_networks=["10.0.0.0/8"]
run_full_hardening=true
```

### High-Security Environment

Government/financial compliance:

```bash
# Maximum security
SAFETY_MODE=1
ADMIN_IP="203.0.113.10"      # Single admin IP
SSH_PORT=22222               # Very non-standard
SSH_ALLOW_USERS="secadmin"   # One admin only
ENABLE_EMERGENCY_SSH=0
ENABLE_FIREWALL=1
ALLOWED_PORTS=""             # No services
PASSWORD_MIN_LENGTH=20
PASSWORD_MAX_AGE=30          # Monthly rotation
ACCOUNT_LOCKOUT_THRESHOLD=2  # Two strikes
ACCOUNT_LOCKOUT_DURATION=1440 # 24-hour lockout
LOG_RETENTION_DAYS=2555      # 7 years
ENABLE_AUDIT_LOGGING=1
SHELL_TIMEOUT=300            # 5-minute timeout
ICMP_ENABLED=0               # No ping
```

### Cloud Deployments (AWS/Azure/GCP)

```bash
# Cloud-optimized
ADMIN_IP="0.0.0.0/0"         # Use security groups instead
SSH_PORT=22                  # Standard for automation
TRUSTED_NETWORKS="10.0.0.0/8" # VPC CIDR
ENABLE_EMERGENCY_SSH=0       # Use cloud console
ENABLE_FIREWALL=0            # Use cloud firewall
# Rely on cloud provider's security groups/firewall rules
```

---

## Configuration Validation

### Required Variables

These MUST be set or deployment fails:

1. **ADMIN_IP** - Your management IP for SSH access
2. **SSH_ALLOW_USERS** - At least one valid username

### Pre-flight Checks

The toolkit validates configuration before applying:

```bash
# Manual validation
./scripts/validate-config.sh

# Ansible validation
ansible-playbook preflight.yml
```

### Validation Checks

- ADMIN_IP is valid IP/CIDR
- SSH_ALLOW_USERS contains existing users
- SSH_PORT != EMERGENCY_SSH_PORT
- Backup directory is writable
- Required commands exist (iptables, sshd, etc.)
- At least 100MB free space

### What Happens if Variables Are Not Set

| Variable         | If Not Set | Result                                             |
| ---------------- | ---------- | -------------------------------------------------- |
| ADMIN_IP         | Empty      | **DEPLOYMENT FAILS** - Firewall would lock you out |
| SSH_ALLOW_USERS  | Empty      | **CRITICAL FAILURE** - No SSH access               |
| SSH_PORT         | Not set    | Defaults to 22                                     |
| ALLOWED_PORTS    | Empty      | Only SSH allowed                                   |
| DISABLE_SERVICES | Empty      | No services disabled                               |
| Most others      | Not set    | Safe defaults applied                              |

---

## Troubleshooting Configuration Issues

### Common Misconfigurations

#### Problem: Locked out after hardening

**Cause**: ADMIN_IP not set or incorrect **Solution**:

1. Use emergency SSH port: `ssh -p 2222 user@server`
2. Fix ADMIN_IP in config
3. Re-run hardening

#### Problem: SSH connection refused

**Cause**: User not in SSH_ALLOW_USERS **Solution**:

1. Use emergency access
2. Add user to SSH_ALLOW_USERS
3. Restart SSH: `systemctl restart sshd`

#### Problem: Firewall blocks legitimate traffic

**Cause**: Port not in ALLOWED_PORTS **Solution**:

```bash
# Temporarily disable firewall
iptables -F
# Add port to ALLOWED_PORTS
ALLOWED_PORTS="80 443 3306"
# Re-run firewall script
```

#### Problem: Services needed but disabled

**Cause**: Service in DISABLE_SERVICES list **Solution**:

1. Remove from DISABLE_SERVICES
2. Start service: `systemctl start service-name`
3. Enable service: `systemctl enable service-name`

#### Problem: Can't write to /tmp

**Cause**: noexec mount option **Solution**:

```bash
# Temporarily remount
mount -o remount,exec /tmp
# Or disable mount hardening
ENABLE_MOUNT_HARDENING=0
```

### Debug Mode

Enable maximum verbosity for troubleshooting:

```bash
VERBOSE=1 DRY_RUN=1 ./hardening.sh 2>&1 | tee debug.log
```

### Configuration Precedence Issues

To verify which value is being used:

```bash
# Check runtime value
grep ADMIN_IP /opt/posix-hardening/config/defaults.conf

# Check Ansible value
ansible -i inventory.ini all -m debug -a "var=admin_ip"

# Override test
ADMIN_IP="10.0.0.1" VERBOSE=1 ./scripts/00-ssh-verification.sh
```

### Emergency Recovery

If completely locked out:

1. **Boot to single-user mode** (physical/console access)
2. **Restore backups**:

   ```bash
   cp /var/backups/hardening/sshd_config.* /etc/ssh/sshd_config
   cp /var/backups/hardening/iptables.* /etc/iptables/rules.v4
   ```

3. **Disable hardening**:

   ```bash
   systemctl stop iptables
   systemctl disable iptables
   ```

4. **Reset SSH**:

   ```bash
   sed -i 's/^AllowUsers.*/# AllowUsers/' /etc/ssh/sshd_config
   systemctl restart sshd
   ```

---

## Best Practices

1. **Always test in non-production first** - Use DRY_RUN=1
2. **Set ADMIN_IP correctly** - Most common cause of lockout
3. **Keep emergency access during initial setup** - ENABLE_EMERGENCY_SSH=1
4. **Document your configuration** - Track changes in version control
5. **Use Ansible for multiple servers** - Consistent configuration
6. **Regular backups** - Before any changes
7. **Monitor logs** - `/var/log/hardening/` for issues
8. **Gradual hardening** - Start with RUN_FULL_HARDENING=0
9. **Keep safety features enabled** - Never disable SAFETY_MODE in production
10. **Review service list** - Customize DISABLE_SERVICES for your needs

---

## See Also

- [Installation Guide](../installation.md)
- [Ansible Deployment](../ansible-deployment.md)
- [Security Architecture](../architecture/security.md)
- [Troubleshooting Guide](../troubleshooting.md)
- [Recovery Procedures](../recovery.md)

---

## Configuration Reference v1.0 - POSIX Hardening Toolkit
