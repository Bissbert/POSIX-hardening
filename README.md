# POSIX Shell Server Hardening Toolkit

A comprehensive, safety-first server hardening toolkit written in pure POSIX shell for maximum compatibility with Debian-based systems accessed remotely via SSH.

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

## Quick Start

### Prerequisites

- Root or sudo access
- Debian-based system (Ubuntu, Debian, etc.)
- SSH key authentication configured (recommended)
- At least 100MB free space for backups

### Basic Usage

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

## Script Priority Order

### Critical Priority (Run First)
1. **01-ssh-hardening.sh** - SSH configuration (preserves access)
2. **02-firewall-setup.sh** - Firewall rules (with SSH protection)

### High Priority
3. **03-kernel-params.sh** - Kernel security parameters
4. **04-network-stack.sh** - Network stack hardening
5. **05-file-permissions.sh** - Critical file permissions

### Medium Priority
6-15. Various security hardening (process limits, audit logging, etc.)

### Low Priority
16-20. Additional hardening (banners, integrity checks, etc.)

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

## Support

For issues or questions:
1. Check logs in `/var/log/hardening/`
2. Review configuration in `config/defaults.conf`
3. Test with DRY_RUN=1 first
4. Ensure backups are available before proceeding

## License

This toolkit is provided as-is for securing Debian-based servers. Always test in a non-production environment first.

## Author

POSIX Shell Server Hardening Toolkit v1.0.0
Designed for maximum safety on remotely-accessed servers.