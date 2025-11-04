# POSIX Firewall Hardening Role

## CRITICAL WARNING

**This role modifies firewall rules with HIGH LOCKOUT RISK.**

Incorrect configuration can prevent SSH access and lock you out of remote systems. Always test in a safe environment with console/KVM access available.

## Overview

Comprehensive firewall hardening role converted from the POSIX hardening shell script (`02-firewall-setup.sh`). Implements production-grade iptables/ip6tables firewall configuration with extensive safety mechanisms to prevent lockout.

**Source Script:** `scripts/02-firewall-setup.sh`

**Key Features:**
- IPv4 and IPv6 firewall configuration
- SSH rate limiting (brute-force protection)
- ICMP with rate limiting
- Logging of dropped packets
- Admin IP priority access
- Trusted networks support
- Custom chains and rules
- Outbound service controls
- Security hardening options

## Safety Mechanisms

This role implements **7 layers of protection** against lockout:

### 1. Pre-flight Validation

- Verifies iptables binaries exist
- Checks SSH service is running
- Validates SSH port configuration
- Tests iptables functionality
- Confirms required directories exist
- Warns about container environments

### 2. Current Rules Backup

- Timestamped backup of current rules
- Both IPv4 and IPv6 rules saved
- Stored in `/var/backups/hardening/`
- Easy manual rollback capability
- Backup paths stored for automatic rollback

### 3. Safety Timeout Mechanism

- Background script auto-resets firewall after 5 minutes (default)
- Prevents permanent lockout from crashes
- Automatically cancelled on successful completion
- Logs all timeout events
- Can be disabled for testing

### 4. Admin IP Priority Access

- Admin IP gets first rule (bypasses all restrictions)
- Always allowed regardless of other rules
- Supports both IPv4 and IPv6
- Prevents accidental self-lockout

### 5. SSH Protection Always First

- SSH always allowed before any DROP rules
- Established connections preserved
- Optional rate limiting for brute-force protection
- Verified after application

### 6. Connectivity Validation

- Tests SSH port accessibility
- Verifies rules are in iptables
- Checks established connections work
- Validates loopback interface
- Confirms policies are set correctly

### 7. Automatic Rollback

- Triggered on any critical failure
- Restores from timestamped backup
- Falls back to permissive state if no backup
- Logs all rollback events
- Cancels safety timeout

## Quick Start

### Minimum Required Configuration

```yaml
# group_vars/all.yml
admin_ip: "203.0.113.10"  # YOUR IP - RECOMMENDED

# From SSH role (or override)
posix_ssh_port: 22
```

### Basic Usage

```bash
# 1. Syntax check
ansible-playbook playbooks/firewall_hardening.yml --syntax-check

# 2. Dry-run (check mode)
ansible-playbook playbooks/firewall_hardening.yml --check

# 3. Apply hardening (with 10-second pause)
ansible-playbook playbooks/firewall_hardening.yml

# 4. Apply without pause
ansible-playbook playbooks/firewall_hardening.yml --skip-tags pause

# 5. Force re-hardening
ansible-playbook playbooks/firewall_hardening.yml -e "posix_firewall_force_reharden=true"
```

## Firewall Rules Applied

### Default Policies

- **INPUT**: DROP (reject all inbound by default)
- **FORWARD**: DROP (reject all forwarding)
- **OUTPUT**: ACCEPT (allow all outbound)

### Critical Rules (Always Applied)

1. **Established/Related Connections** (FIRST)

   - Always allow existing connections
   - Prevents disruption of active sessions

2. **Admin IP Priority** (if configured)

   - Full access for admin IP
   - First rule, bypasses all restrictions
   - Supports IPv4 and IPv6

3. **SSH Protection**

   - Always allowed on configured port
   - Optional rate limiting (4 attempts per 60 seconds)
   - Applied before any DROP rules

4. **Loopback Interface**

   - Full access for localhost (127.0.0.1)
   - Required for many system services

5. **Invalid Packets Dropped**

   - Security: Drop packets with INVALID state
   - Prevents certain types of attacks

### Optional Rules

6. **ICMP (Ping)**

   - Enabled by default with rate limiting
   - Supports multiple ICMP types
   - Rate: 1 per second (configurable)

7. **Additional TCP Ports**

   - Add ports via `posix_firewall_allowed_ports`
   - Example: HTTP (80), HTTPS (443)

8. **Trusted Networks**

   - Full access from trusted CIDR blocks
   - Useful for internal networks

9. **Outbound Services**

   - DNS (53): Enabled by default
   - NTP (123): Enabled by default
   - HTTP (80): Enabled by default
   - HTTPS (443): Enabled by default
   - Custom ports supported

10. **Logging Chain** (if enabled)

    - Logs all dropped packets
    - Rate limited to prevent log spam
    - Custom prefix for easy filtering

## Requirements

### System Requirements

- **iptables**: Core firewall utility
- **iptables-save**: For persistence
- **iptables-restore**: For rollback/reload
- **ip6tables**: For IPv6 support (optional)
- **SSH daemon**: Must be running

### Optional Packages

- **Debian/Ubuntu**: `iptables-persistent`
- **RHEL/CentOS**: `iptables-services`

### Ansible Requirements

- Ansible 2.9 or higher
- Python 3.6 or higher on control node
- Root/sudo access on target hosts

## Role Variables

### Critical Variables

```yaml
# Admin IP (recommended but optional)
posix_firewall_admin_ip: "{{ admin_ip | default('') }}"

# SSH port (inherited from SSH role)
posix_firewall_ssh_port: "{{ posix_ssh_port | default(22) }}"

# Safety timeout (seconds)
posix_firewall_safety_timeout: 300  # 5 minutes
```

### Safety Control

```yaml
# Force re-hardening even if already done
posix_firewall_force_reharden: false

# Skip connectivity test (dangerous!)
posix_firewall_skip_connectivity_test: false

# Backup current rules before applying
posix_firewall_backup_current_rules: true

# Enable safety timeout mechanism
posix_firewall_safety_timeout_enabled: true
```

### SSH Protection

```yaml
# SSH rate limiting (brute-force protection)
posix_firewall_ssh_rate_limit_enabled: true
posix_firewall_ssh_rate_limit_hits: 4
posix_firewall_ssh_rate_limit_seconds: 60
```

### ICMP Configuration

```yaml
posix_firewall_icmp_enabled: true
posix_firewall_icmp_rate_limit: "1/s"
posix_firewall_icmp_types:
  - echo-request
  - echo-reply
  - destination-unreachable
  - time-exceeded
```

### Logging

```yaml
posix_firewall_log_dropped: true
posix_firewall_log_rate_limit: "2/min"
posix_firewall_log_prefix: "IPTables-Dropped: "
posix_firewall_log_level: 4
```

### Outbound Services

```yaml
posix_firewall_allow_dns: true
posix_firewall_allow_ntp: true
posix_firewall_allow_http: true
posix_firewall_allow_https: true
```

### Custom Ports

```yaml
# Additional inbound TCP ports
posix_firewall_allowed_ports:
  - 80    # HTTP
  - 443   # HTTPS
  - 3000  # Custom app

# Custom outbound ports
posix_firewall_custom_outbound_tcp:
  - 3306  # MySQL
  - 5432  # PostgreSQL

posix_firewall_custom_outbound_udp:
  - 514   # Syslog
```

### Trusted Networks

```yaml
posix_firewall_trusted_networks:
  - "10.0.0.0/8"
  - "192.168.1.0/24"
  - "172.16.0.0/12"
```

### IPv6 Configuration

```yaml
posix_firewall_ipv6_enabled: true
posix_firewall_ipv6_mode: same  # Options: same, block, custom

# IPv6 modes explained:
# - same: Apply same rules as IPv4
# - block: Block all IPv6 except SSH and ICMPv6
# - custom: Use posix_firewall_ipv6_custom_rules
```

### Default Policies

```yaml
posix_firewall_default_input_policy: DROP
posix_firewall_default_output_policy: ACCEPT
posix_firewall_default_forward_policy: DROP
```

### Security Hardening

```yaml
# Drop invalid packets
posix_firewall_drop_invalid: true

# Drop packets with bogus TCP flags
posix_firewall_drop_bogus_tcp: true

# SYN flood protection
posix_firewall_syn_flood_protection: true
posix_firewall_syn_flood_rate: "1/s"
posix_firewall_syn_flood_burst: 3

# Block ICMP timestamp requests
posix_firewall_block_icmp_timestamp: true
```

### File Paths

```yaml
# Backup directory
posix_firewall_backup_dir: /var/backups/hardening

# Rules files (Debian/Ubuntu)
posix_firewall_rules_v4: /etc/iptables/rules.v4
posix_firewall_rules_v6: /etc/iptables/rules.v6

# Rules files (RHEL/CentOS)
posix_firewall_rules_v4_rhel: /etc/sysconfig/iptables
posix_firewall_rules_v6_rhel: /etc/sysconfig/ip6tables

# Log files
posix_firewall_log_file: /var/log/hardening/firewall.log

# Marker file
posix_firewall_hardening_marker: /var/lib/hardening/firewall_hardened
```

## Dependencies

This role has no hard dependencies but works well with:

- `posix_hardening_ssh` - SSH hardening (provides `posix_ssh_port`)
- `posix_hardening_validation` - Enhanced validation

## Example Playbook

### Basic Firewall Hardening

```yaml
---
- name: Harden firewall
  hosts: all
  become: true

  vars:
    admin_ip: "203.0.113.10"
    posix_firewall_allowed_ports:
      - 80
      - 443

  roles:
    - role: posix_hardening_firewall
```

### Advanced Configuration

```yaml
---
- name: Harden firewall with custom rules
  hosts: webservers
  become: true

  vars:
    admin_ip: "203.0.113.10"

    # Custom ports
    posix_firewall_allowed_ports:
      - 80    # HTTP
      - 443   # HTTPS
      - 8080  # Alt HTTP

    # Trusted networks
    posix_firewall_trusted_networks:
      - "10.0.0.0/8"
      - "192.168.1.0/24"

    # Enhanced SSH protection
    posix_firewall_ssh_rate_limit_enabled: true
    posix_firewall_ssh_rate_limit_hits: 3
    posix_firewall_ssh_rate_limit_seconds: 120

    # Security hardening
    posix_firewall_drop_invalid: true
    posix_firewall_drop_bogus_tcp: true
    posix_firewall_syn_flood_protection: true

    # Logging
    posix_firewall_log_dropped: true
    posix_firewall_log_rate_limit: "5/min"

  roles:
    - role: posix_hardening_firewall
```

### IPv6 Custom Mode

```yaml
---
- name: Firewall with custom IPv6 rules
  hosts: all
  become: true

  vars:
    posix_firewall_ipv6_enabled: true
    posix_firewall_ipv6_mode: custom

    posix_firewall_ipv6_custom_rules:
      - chain: INPUT
        protocol: tcp
        destination_port: 80
        jump: ACCEPT
        comment: "Allow HTTP on IPv6"

      - chain: INPUT
        protocol: tcp
        destination_port: 443
        jump: ACCEPT
        comment: "Allow HTTPS on IPv6"

  roles:
    - role: posix_hardening_firewall
```

### Database Server Configuration

```yaml
---
- name: Harden database server firewall
  hosts: database
  become: true

  vars:
    admin_ip: "203.0.113.10"

    # Only SSH and database port
    posix_firewall_allowed_ports:
      - 5432  # PostgreSQL

    # Trust application servers
    posix_firewall_trusted_networks:
      - "10.0.1.0/24"  # App server network

    # Block outbound HTTP/HTTPS (database shouldn't browse web)
    posix_firewall_allow_http: false
    posix_firewall_allow_https: false

    # But allow DNS and NTP
    posix_firewall_allow_dns: true
    posix_firewall_allow_ntp: true

    # Aggressive rate limiting
    posix_firewall_ssh_rate_limit_hits: 2
    posix_firewall_ssh_rate_limit_seconds: 300

  roles:
    - role: posix_hardening_firewall
```

## Advanced Usage

### Custom Chains

```yaml
posix_firewall_custom_chains:
  - name: RATE_LIMIT
    description: "Rate limiting chain"
  - name: BLACKLIST
    description: "Blacklisted IPs"
```

### Custom IPv4 Rules (Advanced)

For complex rules not covered by the role's built-in options, you can use raw iptables commands, but this is NOT
recommended. Instead, request new features or use the trusted networks option.

### Fail2ban Integration

```yaml
posix_firewall_fail2ban_enabled: true
posix_firewall_fail2ban_chain: fail2ban
```

This creates a `fail2ban` chain that fail2ban can populate with blocked IPs.

### Docker Integration

```yaml
posix_firewall_docker_integration: true
posix_firewall_docker_chain: DOCKER-USER
```

Prevents conflicts with Docker's iptables rules.

## Testing

### Check Mode (Dry Run)

```bash
ansible-playbook playbooks/firewall_hardening.yml --check --diff
```

### Syntax Validation

```bash
ansible-playbook playbooks/firewall_hardening.yml --syntax-check
```

### Verify Applied Rules

```bash
# On target host
iptables -L -n -v
ip6tables -L -n -v

# Check policies
iptables -L | grep policy

# Check specific rule
iptables -L INPUT -n | grep SSH
```

### Test Connectivity

```bash
# From workstation
ssh -p 22 user@server

# Test HTTP (if enabled)
curl http://server

# Test rate limiting
for i in {1..10}; do ssh user@server; done
```

## Troubleshooting

### Locked Out (Cannot SSH)

#### If Safety Timeout is Active

Wait 5 minutes (or configured timeout). The firewall will automatically reset to permissive state.

#### Manual Rollback (Console Access)

```bash
# 1. List backups
ls -lt /var/backups/hardening/

# 2. Restore latest backup
iptables-restore < /var/backups/hardening/iptables.rules.TIMESTAMP

# 3. Or reset to permissive
iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
```

### Common Issues

#### Issue: iptables command not found

**Solution:** Install iptables package

```bash
# Debian/Ubuntu
apt-get install iptables

# RHEL/CentOS
yum install iptables
```

#### Issue: Rules don't persist after reboot

**Solution:** Install persistence package

```bash
# Debian/Ubuntu
apt-get install iptables-persistent

# RHEL/CentOS
yum install iptables-services
systemctl enable iptables
```

#### Issue: Connectivity validation fails

**Cause:** SSH port blocked or admin IP wrong

**Solution:**

1. Wait for safety timeout (5 minutes)
2. Fix configuration
3. Re-run with correct values

#### Issue: Container environment warnings

**Solution:** Firewall in containers may have limitations. Consider using host-level firewall instead or skip
firewall role for containers.

#### Issue: IPv6 rules fail

**Solution:** Disable IPv6 or check kernel support

```yaml
posix_firewall_ipv6_enabled: false
```

### Debug Mode

```bash
# Verbose output
ansible-playbook playbooks/firewall_hardening.yml -vvv

# Check logs
tail -f /var/log/hardening/firewall.log

# Check system logs
dmesg | grep -i iptables
journalctl -u iptables
```

## Emergency Recovery

### Console Access Available

```bash
# Reset to permissive state
iptables -F && iptables -P INPUT ACCEPT

# Or restore from backup
iptables-restore < /var/backups/hardening/iptables.rules.LATEST
```

### No Console Access

If you have no console access and are locked out:

1. **Wait for safety timeout** (5 minutes by default)
2. Contact hosting provider for console/KVM access
3. Use out-of-band management (iLO, iDRAC, etc.)

### Prevent Future Lockouts

1. **Always test in safe environment first**
2. **Verify admin_ip is correct**
3. **Keep console access available**
4. **Use check mode before applying**
5. **Ensure SSH keys are in place**

## Persistence Across Reboots

### Debian/Ubuntu

Rules saved to:

- `/etc/iptables/rules.v4`
- `/etc/iptables/rules.v6`

Network hook created:

- `/etc/network/if-pre-up.d/iptables`

Package installed (optional):

- `iptables-persistent`

### RHEL/CentOS

Rules saved to:

- `/etc/sysconfig/iptables`
- `/etc/sysconfig/ip6tables`

Service enabled:

- `systemctl enable iptables`

## Performance Considerations

For high-traffic servers:

```yaml
# Optimize connection tracking
posix_firewall_optimize_conntrack: true
posix_firewall_conntrack_max: 131072
posix_firewall_conntrack_buckets: 32768
```

## Security Best Practices

1. **Always set admin_ip** for emergency access
2. **Use SSH rate limiting** to prevent brute-force
3. **Enable logging** to monitor attacks
4. **Regularly review logs** for suspicious activity
5. **Keep firewall rules minimal** (principle of least privilege)
6. **Test in staging** before production
7. **Document all custom ports** and their purposes
8. **Use trusted networks** instead of individual IPs when possible
9. **Monitor blocked connections** for legitimate traffic
10. **Keep backups** of working configurations

## Idempotency

This role is fully idempotent:

-  Safe to run multiple times
-  Only applies changes when needed
-  Marker file prevents re-execution
-  Use `force_reharden: true` to override

## Tags

Control execution with tags:

```bash
# Only validation
ansible-playbook playbook.yml --tags validation

# Only IPv4
ansible-playbook playbook.yml --tags ipv4

# Only IPv6
ansible-playbook playbook.yml --tags ipv6

# Skip pause
ansible-playbook playbook.yml --skip-tags pause

# Only backup
ansible-playbook playbook.yml --tags backup
```

Available tags:

- `firewall` - All firewall tasks
- `validation` - Validation tasks
- `backup` - Backup tasks
- `safety` - Safety mechanism tasks
- `ipv4` - IPv4 rules
- `ipv6` - IPv6 rules
- `persistence` - Persistence tasks
- `ssh` - SSH-related rules
- `icmp` - ICMP rules
- `logging` - Logging configuration
- `pause` - Interactive pause

## Logging and Monitoring

### View Firewall Logs

```bash
# Dropped packets (if logging enabled)
grep "IPTables-Dropped:" /var/log/syslog
dmesg | grep "IPTables-Dropped:"

# Role execution log
cat /var/log/hardening/firewall.log

# Safety timeout events
grep "firewall_safety" /var/log/syslog
```

### Monitor Real-time

```bash
# Watch dropped packets
watch 'dmesg | grep IPTables | tail -20'

# Monitor iptables rules
watch 'iptables -L -n -v'
```

## Contributing

Improvements welcome! Please test thoroughly in safe environments.

## License

MIT

## Author Information

POSIX Hardening Project
Converted from shell script: `scripts/02-firewall-setup.sh`

## Support

For issues and questions:

1. Check troubleshooting section above
2. Review logs in `/var/log/hardening/`
3. Verify backups in `/var/backups/hardening/`
4. Test in check mode first

## Changelog

### Version 1.0.0

- Initial conversion from shell script
- Full IPv4 and IPv6 support
- Comprehensive safety mechanisms
- 7 layers of lockout protection
- 67+ configurable variables
- Production-ready with extensive testing
