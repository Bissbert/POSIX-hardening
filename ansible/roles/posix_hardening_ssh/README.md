# POSIX SSH Hardening Role

## CRITICAL WARNING

**This role modifies SSH configuration with HIGH LOCKOUT RISK.**

Incorrect configuration or missing SSH keys can permanently lock you out of remote systems. Always test in a safe environment with console/KVM access available.

## Overview

Comprehensive SSH hardening role converted from the POSIX hardening shell script (`01-ssh-hardening.sh`). Implements enterprise-grade SSH security with extensive safety mechanisms to prevent lockout.

**Source Script:** `scripts/01-ssh-hardening.sh`

## Safety Mechanisms

This role implements **7 layers of protection** against lockout:

1. **Pre-flight Validation**
   - Verifies SSH keys exist for allowed users
   - Validates SSH service is running
   - Checks required packages installed
   - Confirms user accounts exist

2. **Emergency SSH Daemon**
   - Starts alternate SSH on port 2222 (default)
   - Allows password authentication (for recovery)
   - No user restrictions
   - Automatic cleanup after timeout

3. **Configuration Validation**
   - Every change validated with `sshd -t`
   - Syntax errors caught before reload
   - Invalid settings rejected automatically

4. **Timestamped Backups**
   - Original config backed up before changes
   - Multiple backups retained
   - Easy manual rollback capability

5. **Post-Hardening Tests**
   - Port accessibility check
   - Connection test
   - Authentication verification
   - Settings validation

6. **Automatic Rollback**
   - Triggered on connectivity failure
   - Restores latest backup
   - Reloads SSH daemon
   - Logs rollback event

7. **Idempotent Execution**
   - Marker file prevents re-execution
   - Safe to run multiple times
   - Force option available if needed

## Quick Start

### Minimum Required Configuration

```yaml
# group_vars/all.yml
admin_ip: "203.0.113.10"  # YOUR IP - REQUIRED
ssh_allow_users:
  - root
  - your_username  # REQUIRED - your SSH user

ssh_port: 22
toolkit_path: /opt/posix-hardening
```

### Basic Usage

```bash
# 1. Syntax check
ansible-playbook playbooks/test_ssh_hardening.yml --syntax-check

# 2. Dry-run (check mode)
ansible-playbook playbooks/test_ssh_hardening.yml --check

# 3. Apply hardening (with 10-second pause)
ansible-playbook playbooks/test_ssh_hardening.yml

# 4. Apply without pause
ansible-playbook playbooks/test_ssh_hardening.yml --skip-tags pause
```

## SSH Settings Applied

### Authentication (CRITICAL)
- **PermitRootLogin**: no (root cannot login directly)
- **PasswordAuthentication**: no (only SSH keys)
- **PubkeyAuthentication**: yes (SSH key auth only)
- **PermitEmptyPasswords**: no
- **ChallengeResponseAuthentication**: no

### Connection Limits
- **MaxAuthTries**: 3 (limit login attempts)
- **MaxSessions**: 10 (concurrent sessions per connection)
- **MaxStartups**: 10:30:60 (rate limiting)
- **LoginGraceTime**: 60 seconds
- **ClientAliveInterval**: 300 seconds (5 min keepalive)
- **ClientAliveCountMax**: 2 (disconnect after 10 min idle)

### Security Options
- **X11Forwarding**: no
- **AllowAgentForwarding**: no
- **AllowTcpForwarding**: no
- **PermitUserEnvironment**: no
- **PermitTunnel**: no
- **StrictModes**: yes
- **IgnoreRhosts**: yes
- **HostbasedAuthentication**: no
- **UseDNS**: no (performance)

### Cryptography (Strong Only)
- **Ciphers**: chacha20-poly1305, aes256-gcm, aes128-gcm, aes256-ctr, aes192-ctr, aes128-ctr
- **MACs**: hmac-sha2-512-etm, hmac-sha2-256-etm, hmac-sha2-512, hmac-sha2-256
- **KexAlgorithms**: curve25519-sha256, diffie-hellman-group16-sha512, diffie-hellman-group18-sha512

### Access Control
- **AllowUsers**: Specified in `posix_ssh_allow_users` (REQUIRED)
- **AllowGroups**: Optional, specified in `posix_ssh_allow_groups`

### Logging
- **LogLevel**: VERBOSE (detailed logging)
- **SyslogFacility**: AUTH

### Banner
- Warning banner displayed before authentication
- Configurable via `posix_ssh_banner_text`

## Variables

### Critical Variables (MUST SET)

```yaml
posix_ssh_allow_users:
  - root
  - ansible
  - your_username
# REQUIRED: At least one user must be specified
# These users can SSH after hardening
```

### Port Configuration

```yaml
posix_ssh_port: 22  # Main SSH port
posix_ssh_emergency_port: 2222  # Emergency/recovery port
posix_ssh_enable_emergency_port: true  # Enable emergency SSH
```

### Authentication Settings

```yaml
posix_ssh_permit_root_login: "no"
posix_ssh_password_authentication: "no"
posix_ssh_pubkey_authentication: "yes"
posix_ssh_permit_empty_passwords: "no"
```

### Connection Limits

```yaml
posix_ssh_max_auth_tries: 3
posix_ssh_max_sessions: 10
posix_ssh_client_alive_interval: 300
posix_ssh_client_alive_count_max: 2
posix_ssh_login_grace_time: 60
```

### Security Options

```yaml
posix_ssh_x11_forwarding: "no"
posix_ssh_allow_agent_forwarding: "no"
posix_ssh_allow_tcp_forwarding: "no"
posix_ssh_permit_user_environment: "no"
```

### Banner Configuration

```yaml
posix_ssh_banner_enabled: true
posix_ssh_banner_file: "/etc/ssh/banner"
posix_ssh_banner_text: |
  ###############################################################
  #                      SECURITY WARNING                      #
  ###############################################################
  # Unauthorized access to this system is strictly prohibited. #
  # All access attempts are logged and monitored.              #
  ###############################################################
```

### Control Flags

```yaml
posix_ssh_force_reharden: false  # Re-run even if already hardened
posix_ssh_skip_connectivity_test: false  # Skip post-hardening tests
posix_ssh_backup_config: true  # Create backups
posix_ssh_validate_before_reload: true  # Validate config
```

### File Paths

```yaml
posix_ssh_config_file: "/etc/ssh/sshd_config"
posix_ssh_config_backup_dir: "/var/backups/hardening"
posix_ssh_hardening_marker: "/var/lib/hardening/ssh_hardened"
```

## Dependencies

- **posix_hardening_validation**: Pre-flight validation role
  - Checks SSH keys exist
  - Validates required variables
  - Confirms system requirements

## File Structure

```
posix_hardening_ssh/
├── defaults/
│   └── main.yml              # All default variables (162 lines)
├── handlers/
│   └── main.yml              # Service management handlers (184 lines)
├── meta/
│   └── main.yml              # Role metadata and dependencies
├── tasks/
│   ├── main.yml              # Main orchestration (257 lines)
│   ├── validate_prerequisites.yml    # Pre-flight checks (226 lines)
│   ├── setup_emergency_ssh.yml       # Emergency SSH setup (186 lines)
│   ├── harden_sshd_config.yml        # SSH hardening (500+ lines)
│   ├── fix_ssh_permissions.yml       # File permissions (150+ lines)
│   ├── configure_ssh_banner.yml      # Banner setup (70 lines)
│   └── validate_connectivity.yml     # Post-hardening tests (200+ lines)
└── README.md                 # This file
```

## Execution Phases

The role executes in **7 distinct phases**:

### Phase 1: Pre-flight Validation
- Check if already hardened
- Verify SSH package installed
- Validate allowed users exist
- Check for SSH keys
- Verify SSH service status
- Create backup directories

### Phase 2: Emergency SSH Setup
- Create emergency config from main config
- Set emergency port (2222)
- Enable password auth for recovery
- Start emergency SSH daemon
- Verify emergency SSH listening
- Add firewall rule

### Phase 3: SSH Configuration Hardening (CRITICAL)
- Backup current config
- Apply all security settings using `lineinfile`
- Each change validated with `sshd -t`
- Strong cryptography configured
- Access restrictions applied
- Triggers rollback on failure

### Phase 4: SSH Permissions Hardening
- Fix /etc/ssh directory permissions
- Secure SSH host keys (600)
- Fix root .ssh directory
- Fix user .ssh directories
- Fix authorized_keys permissions
- Validate permissions

### Phase 5: SSH Banner Configuration
- Create banner file
- Configure sshd to use banner
- Set correct permissions

### Phase 6: Post-Hardening Validation (CRITICAL)
- Flush handlers (reload SSH)
- Test SSH port accessibility
- Test SSH connection
- Verify daemon status
- Verify settings applied
- Create hardening marker
- Trigger rollback if tests fail

### Phase 7: Cleanup and Finalization
- Display success message
- Monitor SSH connections
- Show cleanup instructions
- Log completion

## Rollback Procedures

### Automatic Rollback

Triggered automatically if:
- Configuration validation fails (`sshd -t` error)
- SSH connectivity test fails
- Port becomes inaccessible

Rollback process:
1. Find latest backup in `/var/backups/hardening/`
2. Restore backup to `/etc/ssh/sshd_config`
3. Reload SSH daemon
4. Log rollback event

### Manual Rollback

If automatic rollback fails or you need to rollback later:

```bash
# 1. List available backups
ls -lt /var/backups/hardening/sshd_config.*.bak

# 2. Restore specific backup
sudo cp /var/backups/hardening/sshd_config.TIMESTAMP.bak /etc/ssh/sshd_config

# 3. Validate config
sudo /usr/sbin/sshd -t

# 4. Reload SSH
sudo systemctl reload ssh  # or sshd
```

### Emergency SSH Access

If locked out of main SSH:

```bash
# Connect to emergency SSH (port 2222)
ssh -p 2222 user@host

# Then restore config manually
sudo cp /var/backups/hardening/sshd_config.*.bak /etc/ssh/sshd_config
sudo systemctl reload ssh
```

## Testing Recommendations

### Test Environment

1. **Use disposable VMs** for initial testing
2. **Have console/KVM access** available
3. **Test on non-critical systems** first
4. **Deploy SSH keys** before hardening
5. **Verify variables** are set correctly

### Testing Checklist

- [ ] Run `--syntax-check`
- [ ] Run `--check` (dry-run)
- [ ] Verify SSH keys deployed
- [ ] Confirm allowed users exist
- [ ] Test on single host first
- [ ] Have console access ready
- [ ] Verify emergency SSH works
- [ ] Test main SSH after hardening
- [ ] Verify rollback works
- [ ] Test idempotency (run twice)

### Validation Commands

```bash
# Test SSH connection
ssh user@host whoami

# Check SSH settings
ssh user@host 'sudo grep -E "^(PermitRoot|Password|Pubkey)" /etc/ssh/sshd_config'

# Check SSH service
ssh user@host 'sudo systemctl status ssh'

# View hardening logs
ssh user@host 'sudo cat /var/log/hardening/ssh_hardening.log'

# Check marker file
ssh user@host 'sudo cat /var/lib/hardening/ssh_hardened'
```

## Common Issues and Solutions

### Issue: "posix_ssh_allow_users is empty"

**Solution:** Set required variable:
```yaml
posix_ssh_allow_users:
  - root
  - your_username
```

### Issue: "No SSH authorized_keys found"

**Solution:** Deploy SSH keys first using `posix_hardening_users` role or manually.

### Issue: "Locked out after hardening"

**Solutions:**
1. Use emergency SSH: `ssh -p 2222 user@host`
2. Use console/KVM access
3. Restore from backup (see Manual Rollback)

### Issue: "SSH service won't reload"

**Solution:**
```bash
# Check config syntax
sudo /usr/sbin/sshd -t

# Check service status
sudo systemctl status ssh

# Check logs
sudo journalctl -u ssh -n 50
```

### Issue: "Want to re-run hardening"

**Solution:**
```yaml
# Set in playbook or extra-vars
posix_ssh_force_reharden: true
```

## Security Compliance

This role implements security controls from:

- **CIS Benchmarks** (SSH sections)
- **NIST 800-53** (AC-17, IA-2, SC-13)
- **PCI-DSS** (Requirement 2.2)
- **HIPAA** (Technical Safeguards)
- **SOC 2** (CC6.1, CC6.6)

## Performance Impact

- **Configuration reload**: < 1 second
- **Connection overhead**: Minimal (strong crypto)
- **Memory usage**: No significant change
- **CPU usage**: Slightly higher during connection (crypto)

## Compatibility

### Tested Operating Systems

- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Kali Linux (rolling)

### SSH Versions

- OpenSSH 7.9+
- OpenSSH 8.x (recommended)
- OpenSSH 9.x (fully supported)

### Ansible Versions

- Ansible Core 2.9+
- Ansible 2.10+
- Ansible 2.15+ (recommended)

## Tags

Run specific parts of the role:

```bash
# Only validation
ansible-playbook playbooks/test_ssh_hardening.yml --tags validation

# Only hardening (skip validation)
ansible-playbook playbooks/test_ssh_hardening.yml --tags harden

# Only emergency SSH setup
ansible-playbook playbooks/test_ssh_hardening.yml --tags emergency

# Skip the 10-second pause
ansible-playbook playbooks/test_ssh_hardening.yml --skip-tags pause

# Permissions only
ansible-playbook playbooks/test_ssh_hardening.yml --tags permissions

# Banner only
ansible-playbook playbooks/test_ssh_hardening.yml --tags banner
```

## Idempotency

The role is fully idempotent:

- Marker file prevents re-execution
- `lineinfile` module ensures idempotency
- Handlers only fire on changes
- Safe to run multiple times

Force re-execution:
```yaml
posix_ssh_force_reharden: true
```

## Logs and State Files

### Logs
- `/var/log/hardening/ssh_hardening.log` - Main log file
- `journalctl -u ssh` - SSH daemon logs
- `/var/log/auth.log` - Authentication attempts

### State Files
- `/var/lib/hardening/ssh_hardened` - Hardening marker
- `/var/lib/hardening/emergency_ssh_active` - Emergency SSH status

### Backups
- `/var/backups/hardening/sshd_config.*.bak` - Config backups

## Emergency Contact

If you encounter critical issues:

1. **Do not panic** - Multiple recovery options exist
2. **Try emergency SSH** first (port 2222)
3. **Use console/KVM** if available
4. **Check backups** in `/var/backups/hardening/`
5. **Review logs** for error details
6. **Restore manually** if needed

## License

MIT License - See main project LICENSE file

## Authors

POSIX Hardening Team

## Contributing

Improvements welcome! Please:
1. Test thoroughly in safe environment
2. Maintain safety mechanisms
3. Update documentation
4. Add tests for new features

## Acknowledgments

Based on industry best practices from:
- OpenSSH documentation
- CIS Benchmarks
- NIST guidelines
- Mozilla SSL/TLS recommendations
- Community security research
