# POSIX Shell Server Hardening Toolkit

A comprehensive, safety-first server hardening toolkit written in pure POSIX shell for maximum compatibility with Debian-based systems accessed remotely via SSH.

## 📚 Documentation

- **[Complete Documentation](docs/README.md)** - Full documentation index
- **[Script Documentation](docs/SCRIPTS.md)** - Detailed documentation for all 20 hardening scripts
- **[Implementation Guide](docs/guides/IMPLEMENTATION_GUIDE.md)** - Step-by-step deployment instructions
- **[Ansible Deployment](ansible/README.md)** - Automated deployment for multiple servers

## Critical Features

- **Remote-Safe**: Never locks out SSH access with multiple safety mechanisms
- **Automatic Rollback**: Transaction-based operations with automatic rollback on failure
- **POSIX Compliant**: Works with minimal shell environments (sh, not bash)
- **Comprehensive Backup**: Every change is backed up with easy restoration
- **Idempotent**: Scripts can be run multiple times safely

## Safety Mechanisms

1. **SSH Connection Preservation**
   - Parallel SSH testing on alternate ports
   - 60-second automatic rollback timeout
   - Emergency SSH access creation
   - Connection validation before/after changes

2. **Firewall Safety**
   - ESTABLISHED connections always preserved
   - SSH explicitly whitelisted before DROP rules
   - 5-minute auto-reset timeout for testing
   - Admin IP priority access

3. **Automatic Backups**
   - Timestamped backups of all modified files
   - System snapshots before major changes
   - One-command restoration capability

4. **Transaction Rollback**
   - All operations wrapped in transactions
   - Automatic rollback on script failure
   - Checkpoint system for partial rollbacks

## 🚀 Quick Start

For detailed instructions, see the [Implementation Guide](docs/guides/IMPLEMENTATION_GUIDE.md).

### Prerequisites

- Root or sudo access
- Debian-based system (Ubuntu, Debian, etc.)
- **SSH key authentication configured (REQUIRED for automated deployment)**
- At least 100MB free space for backups

### SSH Key Management (Important!)

After SSH hardening, password authentication will be disabled. To prevent lockout:

**Option 1: For Ansible Deployment (Recommended)**

```sh
# Generate centralized SSH keys for team access
cd ansible/team_keys
./generate_keys.sh

# This creates two keys:
# - ansible_ed25519: For Ansible automation
# - team_shared_ed25519: For team member access to ALL hardened servers

# During generation, you'll be prompted:
# "Install team key on this machine? (y/N):"
# Answer 'y' to automatically install the key for immediate use

# After installation (if you chose 'y'):
ssh root@server-hostname  # Works automatically, no -i flag needed!

# The keys are automatically deployed before hardening
# Team members can install with: ./install_team_key.sh team_shared_ed25519
```

**Option 2: Manual SSH Key Setup**

```sh
# On your local machine, generate an SSH key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy your public key to the server
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@your-server

# Verify key-based access works
ssh -i ~/.ssh/id_ed25519 root@your-server

# ONLY THEN proceed with hardening
```

**Emergency Access**: Port 2222 provides emergency SSH access with password authentication if you get locked out.

### Interactive Setup (Recommended)

```sh
# Run the interactive quick-start script
sudo sh quick-start.sh
```

### Manual Setup

1. **Configure your settings**:
```sh
# Edit config/defaults.conf
vi config/defaults.conf

# Important settings:
# - Set ADMIN_IP to your management IP
# - Verify SSH_PORT (default: 22)
# - Set SSH_ALLOW_USERS or SSH_ALLOW_GROUPS
```

2. **Test in dry-run mode**:
```sh
# Test without making changes
DRY_RUN=1 sudo sh scripts/01-ssh-hardening.sh
```

3. **Run individual scripts**:
```sh
# Run SSH hardening (most critical)
sudo sh scripts/01-ssh-hardening.sh

# Setup firewall
sudo sh scripts/02-firewall-setup.sh

# Apply kernel hardening
sudo sh scripts/03-kernel-params.sh
```

4. **Run with orchestrator** (when available):
```sh
# Run all hardening scripts in safe order
sudo sh orchestrator.sh
```

## Directory Structure

```
/POSIX-hardening/
├── lib/                    # Core safety libraries
│   ├── common.sh          # Logging, validation, utilities
│   ├── ssh_safety.sh      # SSH preservation mechanisms
│   ├── backup.sh          # Backup and restore system
│   └── rollback.sh        # Transaction-based rollback
├── scripts/               # Individual hardening scripts
│   ├── 01-ssh-hardening.sh
│   ├── 02-firewall-setup.sh
│   └── ... (20 scripts total)
├── config/
│   └── defaults.conf      # Configuration settings
├── backups/              # Automatic backups (created at runtime)
├── logs/                 # Execution logs
└── tests/                # Validation tests
```

## 📋 Script Overview

See [Script Documentation](docs/SCRIPTS.md) for detailed information about each script.

### Critical Priority (Run First)
1. **[01-ssh-hardening.sh](docs/SCRIPTS.md#01-ssh-hardening)** - SSH configuration (preserves access)
2. **[02-firewall-setup.sh](docs/SCRIPTS.md#02-firewall-setup)** - Firewall rules (with SSH protection)

### High Priority
3-5. Core system hardening (kernel, network, permissions)

### Standard Priority
6-15. Service hardening and access controls

### Additional Security
16-20. Optional hardening measures

Full script listing and details in [SCRIPTS.md](docs/SCRIPTS.md).

## Configuration Options

Key settings in `config/defaults.conf`:

- `SAFETY_MODE=1` - Never disable this on production
- `DRY_RUN=0` - Set to 1 for testing without changes
- `ADMIN_IP=""` - Your management IP for priority access
- `SSH_PORT=22` - Your SSH port
- `SSH_ALLOW_USERS=""` - Restrict SSH to specific users
- `BACKUP_RETENTION_DAYS=30` - How long to keep backups

## Emergency Recovery

### If SSH access is lost:

1. **Wait 60 seconds** - Automatic rollback will trigger
2. **Use emergency SSH port** (if enabled):
   ```sh
   ssh -p 2222 user@server
   ```
3. **From console access**:
   ```sh
   sh emergency-rollback.sh
   ```

### Restore from backup:

```sh
# List available snapshots
ls -la /var/backups/hardening/snapshots/

# Restore specific snapshot
sh lib/backup.sh restore_system_snapshot 20240101-120000
```

### Manual rollback:

```sh
# View rollback history
cat /var/log/hardening/rollback.log

# Restore specific file
cp /var/backups/hardening/sshd_config.20240101-120000.bak /etc/ssh/sshd_config
systemctl reload ssh
```

## Testing

### Dry Run Mode
```sh
DRY_RUN=1 sudo sh scripts/01-ssh-hardening.sh
```

### Verbose Mode
```sh
VERBOSE=1 sudo sh scripts/01-ssh-hardening.sh
```

### Test Mode (Extra Safety)
```sh
TEST_MODE=1 VERBOSE=1 sudo sh scripts/01-ssh-hardening.sh
```

## Monitoring

### Check logs:
```sh
# View latest hardening log
tail -f /var/log/hardening/hardening-*.log

# Check rollback history
cat /var/log/hardening/rollback.log
```

### Verify hardening status:
```sh
# Check completed scripts
cat /var/lib/hardening/completed

# View current state
cat /var/lib/hardening/current_state
```

## Best Practices

1. **Always test in dry-run mode first**
2. **Ensure SSH key authentication is working before disabling passwords**
3. **Set ADMIN_IP for priority access**
4. **Run scripts one at a time initially**
5. **Monitor logs during execution**
6. **Keep emergency console access available**
7. **Create manual snapshot before major changes**

## Troubleshooting

### SSH Connection Issues
- Script automatically rolls back after 60 seconds
- Emergency SSH runs on port 2222 (if enabled)
- Check `/var/log/hardening/` for detailed logs

### Firewall Blocks Access
- Rules auto-reset after 5 minutes
- SSH is explicitly allowed before DROP rules
- Admin IP gets priority access

### Script Fails
- Automatic rollback restores previous state
- Check logs for specific error
- Run with VERBOSE=1 for detailed output

## Security Features Implemented

### SSH Hardening
- Disables root login
- Disables password authentication
- Enforces key-based authentication
- Restricts cipher suites to strong ones
- Sets connection limits
- Configures timeouts

### Firewall Rules
- Default deny with explicit allows
- Rate limiting on connections
- SSH brute-force protection
- Stateful connection tracking

### Kernel Security
- Enables SYN cookies
- Disables IP forwarding
- Prevents IP spoofing
- Disables ICMP redirects

### File Permissions
- Secures sensitive files
- Sets appropriate umask
- Restricts world-writable directories

## 📖 Additional Resources

- **[Testing Framework](docs/guides/TESTING_FRAMEWORK.md)** - Comprehensive testing procedures
- **[Hardening Requirements](docs/guides/HARDENING_REQUIREMENTS.md)** - Security standards and compliance
- **[Quick Reference](docs/guides/QUICK_REFERENCE.md)** - Command reference and cheat sheet
- **[Contributing](docs/development/CONTRIBUTING.md)** - How to contribute to the project

## Support

For issues or questions:
1. Check the **[Documentation Index](docs/README.md)**
2. Review **[Script Documentation](docs/SCRIPTS.md)** for script-specific help
3. Check logs in `/var/log/hardening/`
4. Test with DRY_RUN=1 first

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Version

Current Version: **1.0.0** - See [Changelog](docs/releases/CHANGELOG.md) for release history.