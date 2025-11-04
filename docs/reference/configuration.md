# Configuration Variable Reference

## Table of Contents

1. [Configuration Overview](#configuration-overview)
2. [Variable Categories](#variable-categories)
3. [Complete Variable Reference](#complete-variable-reference)
   - [Safety Settings](#safety-settings)
   - [Execution Mode](#execution-mode)
   - [SSH Configuration](#ssh-configuration)
   - [Emergency Access](#emergency-access)
   - [Firewall Configuration](#firewall-configuration)
   - [Kernel and System Hardening](#kernel-and-system-hardening)
   - [File Permissions](#file-permissions)
   - [Password and Authentication](#password-and-authentication)
   - [Logging and Auditing](#logging-and-auditing)
   - [Service Hardening](#service-hardening)
   - [Mount Options](#mount-options)
   - [Shell Configuration](#shell-configuration)
   - [Integrity Checking](#integrity-checking)
   - [Validation and Testing](#validation-and-testing)
   - [Backup Configuration](#backup-configuration)
   - [SSHD Configuration](#sshd-configuration)
   - [Advanced Options](#advanced-options)
   - [Deployment Paths](#deployment-paths)
   - [Environment Detection](#environment-detection)
4. [Common Configuration Scenarios](#common-configuration-scenarios)
5. [Configuration Validation](#configuration-validation)
6. [Troubleshooting Configuration Issues](#troubleshooting-configuration-issues)

---

## Configuration Overview

The POSIX Hardening Toolkit uses a hierarchical configuration system with multiple sources and clear precedence rules. Configuration can be managed either through Ansible automation or standalone shell scripts.

### How Configuration Works

The toolkit uses three main configuration mechanisms:

1. **Ansible-Managed Configuration** (Recommended for production)
   - Master defaults in `ansible/group_vars/all.yml`
   - Environment-specific overrides in `ansible/inventory.ini`
   - Auto-generates `config/defaults.conf` on deployment

2. **Standalone Configuration** (For single servers)
   - Manual configuration via `config/defaults.conf`
   - Copy from template: `cp config/defaults.conf.template config/defaults.conf`

3. **Runtime Configuration** (Emergency overrides)
   - Environment variables can override configuration at runtime
   - Useful for testing and troubleshooting

### Variable Precedence

Configuration values are resolved in the following order (highest to lowest priority):

1. **Runtime environment variables** - Set before running scripts
2. **Ansible inventory variables** - Environment-specific in `inventory.ini` `[environment:vars]`
3. **Ansible group variables** - Defaults in `group_vars/all.yml`
4. **Local configuration file** - `config/defaults.conf` (standalone mode)
5. **Built-in defaults** - Hardcoded in shell scripts (deprecated, being removed)

### Configuration File Locations

| File | Purpose | Used By |
|------|---------|---------|
| `/opt/posix-hardening/config/defaults.conf` | Runtime configuration on target servers | Shell scripts |
| `ansible/group_vars/all.yml` | Master defaults for all variables | Ansible |
| `ansible/inventory.ini` | Environment-specific overrides | Ansible |
| `config/defaults.conf.template` | Template for standalone setup | Manual configuration |

### How to Override Defaults

#### Using Ansible (Recommended)

1. Set defaults in `ansible/group_vars/all.yml`
2. Override per environment in `ansible/inventory.ini`:
   ```ini
   [production:vars]
   admin_ip=203.0.113.10
   ssh_port=2222
   enable_emergency_ssh=false
   ```

#### Standalone Mode

1. Copy the template:
   ```bash
   cp config/defaults.conf.template config/defaults.conf
   ```
2. Edit configuration:
   ```bash
   vim config/defaults.conf
   ```

#### Runtime Override

```bash
# Override for a single execution
VERBOSE=1 DRY_RUN=1 ./hardening.sh
```

---

## Variable Categories

Variables are organized into functional categories for easier management:

| Category | Purpose | Risk Level |
|----------|---------|------------|
| **Safety Settings** | Prevent system lockout and enable recovery | CRITICAL |
| **SSH Configuration** | Secure remote access settings | CRITICAL |
| **Emergency Access** | Backup access methods | HIGH |
| **Firewall Configuration** | Network access control | HIGH |
| **Kernel Hardening** | System-level security parameters | MEDIUM |
| **Authentication** | User access and password policies | MEDIUM |
| **Service Management** | Control running services | MEDIUM |
| **Logging/Auditing** | Security event tracking | LOW |
| **File Permissions** | Filesystem security | LOW |

---

## Complete Variable Reference

### Safety Settings

These variables control critical safety mechanisms that prevent system lockout. **NEVER disable these in production.**

#### `SAFETY_MODE` / `safety_mode`
- **Description**: Master switch for all safety features
- **Type**: Boolean (0/1)
- **Default**: `1` (enabled)
- **Valid Values**: `0` (off), `1` (on)
- **Impact**: Disabling bypasses all safety checks, rollback mechanisms, and validation
- **Security**: CRITICAL - Disabling can lead to permanent system lockout
- **Example**:
  ```bash
  SAFETY_MODE=1  # Always keep enabled in production
  ```
- **Related Variables**: `BACKUP_BEFORE_CHANGE`, `ROLLBACK_ENABLED`, `FAIL_FAST`
- **Warning**: ⚠️ Setting to 0 may result in irreversible system damage

#### `BACKUP_BEFORE_CHANGE` / `backup_before_change`
- **Description**: Creates backups of configuration files before modification
- **Type**: Boolean (0/1)
- **Default**: `1` (enabled)
- **Valid Values**: `0` (off), `1` (on)
- **Impact**: When enabled, original configs saved to `/var/backups/hardening/`
- **Security**: HIGH - Enables recovery from misconfigurations
- **Example**:
  ```bash
  BACKUP_BEFORE_CHANGE=1  # Creates timestamped backups
  ```
- **Related Variables**: `BACKUP_DIR`, `BACKUP_RETENTION_DAYS`
- **Storage Required**: ~10MB per backup set

#### `ROLLBACK_ENABLED` / `rollback_enabled`
- **Description**: Automatically reverts changes if connectivity is lost
- **Type**: Boolean (0/1)
- **Default**: `1` (enabled)
- **Valid Values**: `0` (off), `1` (on)
- **Impact**: Auto-restores previous configuration on connection failure
- **Security**: CRITICAL - Primary protection against lockout
- **Example**:
  ```bash
  ROLLBACK_ENABLED=1  # Auto-reverts within timeout period
  ```
- **Related Variables**: `SSH_ROLLBACK_TIMEOUT`, `FIREWALL_TIMEOUT`
- **Mechanism**: Uses systemd timer or cron job to trigger rollback

#### `FAIL_FAST` / `fail_fast`
- **Description**: Stops execution on first error
- **Type**: Boolean (0/1)
- **Default**: `1` (enabled)
- **Valid Values**: `0` (continue on error), `1` (stop on error)
- **Impact**: Prevents cascade failures from partial configurations
- **Security**: MEDIUM - Ensures consistent system state
- **Example**:
  ```bash
  FAIL_FAST=1  # Recommended for production
  ```
- **Related Variables**: `SAFETY_MODE`, `VERBOSE`

### Execution Mode

Control how the hardening scripts execute.

#### `DRY_RUN` / `dry_run`
- **Description**: Simulation mode - shows what would be done without making changes
- **Type**: Boolean (0/1)
- **Default**: `0` (disabled)
- **Valid Values**: `0` (apply changes), `1` (simulation only)
- **Impact**: When enabled, no system modifications are made
- **Security**: None - Safe testing mode
- **Example**:
  ```bash
  DRY_RUN=1 ./hardening.sh  # Test run without changes
  ```
- **Use Cases**: Testing, validation, impact assessment
- **Output**: Shows all commands that would be executed

#### `VERBOSE` / `verbose`
- **Description**: Controls debug output verbosity
- **Type**: Boolean (0/1)
- **Default**: `0` (normal output)
- **Valid Values**: `0` (normal), `1` (detailed debug)
- **Impact**: Enables detailed logging of all operations
- **Security**: LOW - May expose sensitive paths in logs
- **Example**:
  ```bash
  VERBOSE=1  # Shows all commands and their output
  ```
- **Log Location**: `/var/log/hardening/debug.log`
- **Performance Impact**: Minimal, ~5% slower execution

#### `RUN_FULL_HARDENING` / `run_full_hardening`
- **Description**: Controls whether to run all hardening scripts or priority-1 only
- **Type**: Boolean (0/1 in shell, true/false in Ansible)
- **Default**: `1` / `true` (full hardening)
- **Valid Values**: `0`/`false` (priority only), `1`/`true` (all scripts)
- **Impact**: Priority mode only runs critical security scripts (00-09)
- **Security**: MEDIUM - Priority mode provides basic protection
- **Example**:
  ```yaml
  # Ansible
  run_full_hardening: false  # Quick hardening
  ```
- **Scripts Affected**: Scripts 10-20 are skipped in priority mode

### SSH Configuration

**CRITICAL**: These settings control remote access. Misconfiguration will lock you out.

#### `SSH_PORT` / `ssh_port`
- **Description**: SSH daemon listening port
- **Type**: Integer
- **Default**: `22`
- **Valid Values**: 1-65535 (avoid well-known ports)
- **Impact**: Changes SSH listening port system-wide
- **Security**: MEDIUM - Non-standard ports reduce automated attacks
- **Example**:
  ```bash
  SSH_PORT=2222  # Non-standard port
  ```
- **Related Variables**: `EMERGENCY_SSH_PORT`, `SSH_TEST_PORT`
- **Firewall**: Automatically opens in iptables rules
- **Warning**: Update your SSH client configuration after change

#### `ADMIN_IP` / `admin_ip`
- **Description**: Management workstation IP address for firewall whitelist
- **Type**: String (IP address)
- **Default**: "" (empty - MUST BE SET)
- **Valid Values**: Valid IPv4 address or CIDR
- **Impact**: Only this IP can access SSH after hardening
- **Security**: CRITICAL - Restricts SSH access to trusted source
- **Example**:
  ```bash
  ADMIN_IP="203.0.113.10"  # Your static IP
  ADMIN_IP="203.0.113.0/24"  # Subnet range
  ```
- **Required**: YES - deployment fails without this
- **Multiple IPs**: Use `TRUSTED_NETWORKS` for additional IPs

#### `SSH_ALLOW_USERS` / `ssh_allow_users`
- **Description**: Space-separated list of users allowed SSH access
- **Type**: String (space-separated usernames)
- **Default**: `"admin"`
- **Valid Values**: Existing system usernames
- **Impact**: Only listed users can SSH login (AllowUsers directive)
- **Security**: CRITICAL - Empty value locks out all users
- **Example**:
  ```bash
  SSH_ALLOW_USERS="admin john deploy"
  ```
- **Warning**: ⚠️ Must include your username or you'll be locked out
- **Related Variables**: `SSH_ALLOW_GROUPS`
- **Validation**: Script verifies at least one user exists

#### `SSH_ALLOW_GROUPS` / `ssh_allow_groups`
- **Description**: Space-separated list of groups allowed SSH access
- **Type**: String (space-separated group names)
- **Default**: "" (empty - not used)
- **Valid Values**: Existing system groups
- **Impact**: Members of listed groups can SSH login (AllowGroups directive)
- **Security**: MEDIUM - Group-based access control
- **Example**:
  ```bash
  SSH_ALLOW_GROUPS="sshusers admins"
  ```
- **Precedence**: Used in addition to SSH_ALLOW_USERS
- **Best Practice**: Create dedicated ssh-users group

#### `SSH_TEST_PORT` / `ssh_test_port`
- **Description**: Temporary port for connectivity testing during changes
- **Type**: Integer
- **Default**: `2222`
- **Valid Values**: 1024-65535 (different from SSH_PORT)
- **Impact**: Opens temporary SSH for validation
- **Security**: LOW - Automatically closed after testing
- **Example**:
  ```bash
  SSH_TEST_PORT=8822  # Testing port
  ```
- **Duration**: Active for SSH_ROLLBACK_TIMEOUT seconds

#### `SSH_ROLLBACK_TIMEOUT` / `ssh_rollback_timeout`
- **Description**: Seconds to wait before automatic rollback
- **Type**: Integer
- **Default**: `60`
- **Valid Values**: 30-600 (30 seconds to 10 minutes)
- **Impact**: Time window to confirm changes are working
- **Security**: HIGH - Shorter = safer but less time to test
- **Example**:
  ```bash
  SSH_ROLLBACK_TIMEOUT=120  # 2 minutes to verify
  ```
- **Related Variables**: `ROLLBACK_ENABLED`

### Emergency Access

Backup access methods for recovery scenarios.

#### `ENABLE_EMERGENCY_SSH` / `enable_emergency_ssh`
- **Description**: Creates emergency SSH with password authentication
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (disabled), `1`/`true` (enabled)
- **Impact**: Opens alternate SSH port with relaxed authentication
- **Security**: MEDIUM - Temporary backdoor for recovery
- **Example**:
  ```yaml
  enable_emergency_ssh: true  # Keep during initial setup
  ```
- **Best Practice**: Enable for initial deployment, disable after verification

#### `EMERGENCY_SSH_PORT` / `emergency_ssh_port`
- **Description**: Port number for emergency SSH access
- **Type**: Integer
- **Default**: `2222`
- **Valid Values**: 1024-65535 (different from SSH_PORT)
- **Impact**: Secondary SSH daemon on this port
- **Security**: MEDIUM - Uses password authentication
- **Example**:
  ```bash
  EMERGENCY_SSH_PORT=9922
  ```
- **Access**: `ssh -p 2222 user@server`

#### `REMOVE_EMERGENCY_SSH` / `remove_emergency_ssh`
- **Description**: Auto-remove emergency access after successful deployment
- **Type**: Boolean (0/1 or true/false)
- **Default**: `0` / `false`
- **Valid Values**: `0`/`false` (keep), `1`/`true` (auto-remove)
- **Impact**: Automatically disables emergency port after validation
- **Security**: HIGH - Removes potential attack vector
- **Example**:
  ```yaml
  # In staging environment
  remove_emergency_ssh: true
  ```
- **Use Case**: Set to true in staging/test, false in production

### Firewall Configuration

Network access control via iptables.

#### `ENABLE_FIREWALL` / `enable_firewall`
- **Description**: Activates iptables firewall rules
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip firewall), `1`/`true` (configure firewall)
- **Impact**: Blocks all ports except explicitly allowed
- **Security**: HIGH - Essential perimeter defense
- **Example**:
  ```bash
  ENABLE_FIREWALL=1
  ```
- **Default Policy**: DROP all except allowed
- **Warning**: Ensure ADMIN_IP is set before enabling

#### `FIREWALL_TIMEOUT` / `firewall_timeout`
- **Description**: Auto-rollback timer for firewall changes (seconds)
- **Type**: Integer
- **Default**: `300` (5 minutes)
- **Valid Values**: 60-1800 (1-30 minutes)
- **Impact**: Reverts firewall if connection lost
- **Security**: CRITICAL - Prevents permanent lockout
- **Example**:
  ```bash
  FIREWALL_TIMEOUT=600  # 10 minutes
  ```
- **Mechanism**: Uses `at` command or systemd timer

#### `ALLOWED_PORTS` / `allowed_ports`
- **Description**: Additional TCP ports to allow through firewall
- **Type**: String (space-separated) or List (Ansible)
- **Default**: "" (empty) / [] (empty list)
- **Valid Values**: Port numbers 1-65535
- **Impact**: Opens specified ports for all sources
- **Security**: MEDIUM - Each port is potential attack vector
- **Example**:
  ```bash
  # Shell
  ALLOWED_PORTS="80 443 3306"
  # Ansible
  allowed_ports: [80, 443, 3306]
  ```
- **Common Ports**: 80 (HTTP), 443 (HTTPS), 3306 (MySQL), 5432 (PostgreSQL)

#### `TRUSTED_NETWORKS` / `trusted_networks`
- **Description**: CIDR blocks with unrestricted access
- **Type**: String (space-separated) or List (Ansible)
- **Default**: "" (empty) / [] (empty list)
- **Valid Values**: Valid CIDR notation
- **Impact**: Full access from these networks
- **Security**: HIGH - Use sparingly
- **Example**:
  ```bash
  # Shell
  TRUSTED_NETWORKS="10.0.0.0/8 192.168.1.0/24"
  # Ansible
  trusted_networks: ["10.0.0.0/8", "192.168.1.0/24"]
  ```
- **Use Cases**: Management networks, VPN ranges

### Kernel and System Hardening

Low-level security parameters.

#### `ENABLE_KERNEL_HARDENING` / `enable_kernel_hardening`
- **Description**: Applies sysctl security parameters
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (apply)
- **Impact**: Hardens kernel against common attacks
- **Security**: HIGH - Enables ASLR, restricts core dumps, etc.
- **Example**:
  ```bash
  ENABLE_KERNEL_HARDENING=1
  ```
- **Parameters Set**:
  - `kernel.randomize_va_space=2` (ASLR)
  - `kernel.exec-shield=1` (NX bit)
  - `fs.suid_dumpable=0` (No setuid dumps)
  - See `scripts/03-kernel-hardening.sh`

#### `ENABLE_NETWORK_HARDENING` / `enable_network_hardening`
- **Description**: Hardens TCP/IP stack
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (apply)
- **Impact**: Protects against network attacks
- **Security**: HIGH - Prevents IP spoofing, SYN floods
- **Example**:
  ```bash
  ENABLE_NETWORK_HARDENING=1
  ```
- **Parameters Set**:
  - `net.ipv4.tcp_syncookies=1` (SYN flood protection)
  - `net.ipv4.conf.all.rp_filter=1` (Reverse path filtering)
  - `net.ipv4.icmp_echo_ignore_broadcasts=1` (No broadcast pings)

#### `ENABLE_PROCESS_LIMITS` / `enable_process_limits`
- **Description**: Sets resource limits via ulimits
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (apply)
- **Impact**: Prevents resource exhaustion attacks
- **Security**: MEDIUM - Limits fork bombs, memory exhaustion
- **Example**:
  ```bash
  ENABLE_PROCESS_LIMITS=1
  ```
- **Related Variables**: `MAX_USER_PROCESSES`, `CORE_DUMP_LIMIT`

#### `MAX_USER_PROCESSES` / `max_user_processes`
- **Description**: Maximum processes per user
- **Type**: Integer
- **Default**: `1024`
- **Valid Values**: 256-32768
- **Impact**: Limits fork bombs and runaway processes
- **Security**: MEDIUM - Prevents DoS via process exhaustion
- **Example**:
  ```bash
  MAX_USER_PROCESSES=2048  # For busy servers
  ```
- **Calculation**: ~50 per expected concurrent user

#### `CORE_DUMP_LIMIT` / `core_dump_limit`
- **Description**: Maximum core dump file size
- **Type**: Integer (bytes)
- **Default**: `0` (disabled)
- **Valid Values**: 0 (disabled) or size in bytes
- **Impact**: Prevents information leakage via core dumps
- **Security**: MEDIUM - Core dumps may contain passwords
- **Example**:
  ```bash
  CORE_DUMP_LIMIT=0  # Recommended
  ```
- **Debug Mode**: Set to 1073741824 (1GB) for debugging

### File Permissions

Filesystem security settings.

#### `ENABLE_FILE_PERMISSIONS` / `enable_file_permissions`
- **Description**: Fixes permissions on critical system files
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (apply)
- **Impact**: Restricts access to sensitive files
- **Security**: MEDIUM - Prevents unauthorized access
- **Example**:
  ```bash
  ENABLE_FILE_PERMISSIONS=1
  ```
- **Files Affected**: `/etc/passwd`, `/etc/shadow`, `/etc/ssh/*`, etc.

#### `SYSTEM_UMASK` / `system_umask`
- **Description**: Default permission mask for system processes
- **Type**: String (octal)
- **Default**: `"027"` (rwxr-x---)
- **Valid Values**: Octal permission masks
- **Impact**: New system files get restrictive permissions
- **Security**: MEDIUM - Prevents world-readable files
- **Example**:
  ```bash
  SYSTEM_UMASK="027"  # Owner full, group read/exec, others none
  ```
- **Applied To**: `/etc/profile`, `/etc/bash.bashrc`

#### `USER_UMASK` / `user_umask`
- **Description**: Default permission mask for user sessions
- **Type**: String (octal)
- **Default**: `"077"` (rwx------)
- **Valid Values**: Octal permission masks
- **Impact**: New user files are private
- **Security**: LOW - Protects user data
- **Example**:
  ```bash
  USER_UMASK="077"  # Only owner can access
  ```
- **Note**: Users can override in their shell profile

### Password and Authentication

User authentication policies.

#### `PASSWORD_MIN_LENGTH` / `password_min_length`
- **Description**: Minimum password length requirement
- **Type**: Integer
- **Default**: `12`
- **Valid Values**: 8-32
- **Impact**: Enforced for new passwords via PAM
- **Security**: HIGH - Longer passwords resist brute force
- **Example**:
  ```bash
  PASSWORD_MIN_LENGTH=14  # For high security
  ```
- **Enforcement**: `/etc/pam.d/common-password`

#### `PASSWORD_MAX_AGE` / `password_max_age`
- **Description**: Days until password expires
- **Type**: Integer
- **Default**: `90`
- **Valid Values**: 30-365 (0 = never expire)
- **Impact**: Forces periodic password changes
- **Security**: MEDIUM - Limits exposure of compromised passwords
- **Example**:
  ```bash
  PASSWORD_MAX_AGE=60  # Bi-monthly rotation
  ```
- **Applied Via**: `/etc/login.defs`

#### `PASSWORD_WARN_AGE` / `password_warn_age`
- **Description**: Days before expiry to warn user
- **Type**: Integer
- **Default**: `14`
- **Valid Values**: 1-30
- **Impact**: User sees warnings before password expires
- **Security**: LOW - Prevents surprise lockouts
- **Example**:
  ```bash
  PASSWORD_WARN_AGE=7  # One week warning
  ```

#### `ACCOUNT_LOCKOUT_THRESHOLD` / `account_lockout_threshold`
- **Description**: Failed login attempts before lockout
- **Type**: Integer
- **Default**: `5`
- **Valid Values**: 3-10
- **Impact**: Temporary account lock after failures
- **Security**: HIGH - Prevents brute force attacks
- **Example**:
  ```bash
  ACCOUNT_LOCKOUT_THRESHOLD=3  # Strict policy
  ```
- **Mechanism**: pam_faillock module

#### `ACCOUNT_LOCKOUT_DURATION` / `account_lockout_duration`
- **Description**: Account lockout duration in minutes
- **Type**: Integer
- **Default**: `30`
- **Valid Values**: 5-1440 (5 min to 24 hours)
- **Impact**: How long account stays locked
- **Security**: MEDIUM - Balance security vs usability
- **Example**:
  ```bash
  ACCOUNT_LOCKOUT_DURATION=60  # One hour
  ```
- **Manual Unlock**: `faillock --user username --reset`

### Logging and Auditing

Security event tracking.

#### `ENABLE_AUDIT_LOGGING` / `enable_audit_logging`
- **Description**: Enables auditd system auditing
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (enable)
- **Impact**: Tracks security-relevant system events
- **Security**: HIGH - Essential for incident response
- **Example**:
  ```bash
  ENABLE_AUDIT_LOGGING=1
  ```
- **Service**: Requires auditd package

#### `LOG_RETENTION_DAYS` / `log_retention_days`
- **Description**: Days to keep log files
- **Type**: Integer
- **Default**: `90`
- **Valid Values**: 7-3650
- **Impact**: Old logs are rotated/deleted
- **Security**: MEDIUM - Balance forensics vs storage
- **Example**:
  ```bash
  LOG_RETENTION_DAYS=365  # One year for compliance
  ```
- **Affects**: System logs, audit logs, hardening logs

#### `AUDIT_LOG` / `audit_log`
- **Description**: Path to audit log file
- **Type**: String (file path)
- **Default**: `"/var/log/audit/audit.log"`
- **Valid Values**: Writable path
- **Impact**: Location of audit events
- **Security**: LOW - Should be on separate partition
- **Example**:
  ```bash
  AUDIT_LOG="/var/log/audit/audit.log"
  ```
- **Permissions**: 600 (root only)

### Service Hardening

Control running services.

#### `DISABLE_SERVICES` / `disable_services`
- **Description**: Services to disable for security
- **Type**: String (space-separated) or List (Ansible)
- **Default**: `"bluetooth cups avahi-daemon rpcbind nfs-server snmpd"`
- **Valid Values**: Service names from systemctl/service
- **Impact**: Stops and disables listed services
- **Security**: MEDIUM - Reduces attack surface
- **Example**:
  ```bash
  # Shell
  DISABLE_SERVICES="bluetooth cups"
  # Ansible
  disable_services:
    - bluetooth
    - cups
    - avahi-daemon
  ```
- **Warning**: Verify services aren't needed before disabling

#### `REQUIRED_SERVICES` / `required_services`
- **Description**: Services that must remain running
- **Type**: List (Ansible only)
- **Default**: `["ssh"]`
- **Valid Values**: Critical service names
- **Impact**: Prevents disabling of essential services
- **Security**: CRITICAL - Protects against lockout
- **Example**:
  ```yaml
  required_services:
    - ssh
    - networking
  ```
- **Validation**: Script won't disable these services

### Mount Options

Secure temporary filesystems.

#### `ENABLE_MOUNT_HARDENING` / `enable_mount_hardening`
- **Description**: Apply security mount options
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (apply)
- **Impact**: Restricts execution from temp directories
- **Security**: HIGH - Prevents malware execution from /tmp
- **Example**:
  ```bash
  ENABLE_MOUNT_HARDENING=1
  ```

#### `TMP_DIRS` / `tmp_dirs`
- **Description**: Directories to apply secure mount options
- **Type**: String (space-separated) or List (Ansible)
- **Default**: `"/tmp /var/tmp /dev/shm"`
- **Valid Values**: Mountable directories
- **Impact**: Listed directories get security restrictions
- **Security**: HIGH - Common malware staging areas
- **Example**:
  ```bash
  # Shell
  TMP_DIRS="/tmp /var/tmp"
  # Ansible
  tmp_dirs:
    - /tmp
    - /var/tmp
    - /dev/shm
  ```

#### `TMP_MOUNT_OPTIONS` / `tmp_mount_options`
- **Description**: Security flags for temp mounts
- **Type**: String
- **Default**: `"noexec,nosuid,nodev"`
- **Valid Values**: Valid mount options
- **Impact**: Prevents execution, setuid, device files
- **Security**: HIGH - Blocks common attack vectors
- **Example**:
  ```bash
  TMP_MOUNT_OPTIONS="noexec,nosuid,nodev"
  ```
- **Options**:
  - `noexec`: No execution
  - `nosuid`: No setuid binaries
  - `nodev`: No device files

### Shell Configuration

Interactive session security.

#### `SHELL_TIMEOUT` / `shell_timeout`
- **Description**: Auto-logout idle sessions (seconds)
- **Type**: Integer
- **Default**: `900` (15 minutes)
- **Valid Values**: 60-7200 (1 minute to 2 hours)
- **Impact**: Idle sessions are terminated
- **Security**: MEDIUM - Prevents unattended access
- **Example**:
  ```bash
  SHELL_TIMEOUT=1800  # 30 minutes
  ```
- **Implementation**: TMOUT variable in profile

### Integrity Checking

File integrity monitoring.

#### `ENABLE_INTEGRITY_CHECK` / `enable_integrity_check`
- **Description**: Create checksums of critical files
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (enable)
- **Impact**: Baseline for detecting changes
- **Security**: MEDIUM - Detects unauthorized modifications
- **Example**:
  ```bash
  ENABLE_INTEGRITY_CHECK=1
  ```
- **Tool**: Uses sha256sum or similar

#### `INTEGRITY_DIRS` / `integrity_dirs`
- **Description**: Directories to monitor for changes
- **Type**: String (space-separated) or List (Ansible)
- **Default**: `/etc /bin /sbin /usr/bin /usr/sbin`
- **Valid Values**: System directories
- **Impact**: Creates checksums for all files in listed dirs
- **Security**: MEDIUM - Monitors critical system files
- **Example**:
  ```bash
  # Shell
  INTEGRITY_DIRS="/etc /bin /sbin"
  # Ansible
  integrity_dirs:
    - /etc
    - /bin
    - /sbin
    - /usr/bin
    - /usr/sbin
  ```
- **Storage**: Checksums saved to `/var/lib/hardening/integrity/`

### Validation and Testing

Post-hardening verification.

#### `RUN_VALIDATION` / `run_validation`
- **Description**: Run validation tests after hardening
- **Type**: Boolean (0/1 or true/false)
- **Default**: `1` / `true`
- **Valid Values**: `0`/`false` (skip), `1`/`true` (validate)
- **Impact**: Verifies hardening was successful
- **Security**: None - Testing only
- **Example**:
  ```bash
  RUN_VALIDATION=1
  ```
- **Tests**: Port scans, permission checks, service status

#### `TEST_MODE` / `test_mode`
- **Description**: Reserved for future testing features
- **Type**: Integer
- **Default**: `0`
- **Valid Values**: Reserved
- **Impact**: Currently unused
- **Security**: N/A
- **Example**:
  ```bash
  TEST_MODE=0  # Keep default
  ```

### Backup Configuration

Backup management settings.

#### `BACKUP_RETENTION_DAYS`
- **Description**: Days to keep backup files
- **Type**: Integer
- **Default**: `30`
- **Valid Values**: 1-365
- **Impact**: Old backups are deleted
- **Security**: LOW - Balance recovery vs storage
- **Example**:
  ```bash
  BACKUP_RETENTION_DAYS=90  # Three months
  ```
- **Location**: `/var/backups/hardening/`

#### `MAX_BACKUPS`
- **Description**: Maximum number of backup files
- **Type**: Integer
- **Default**: `100`
- **Valid Values**: 10-1000
- **Impact**: Oldest deleted when limit reached
- **Security**: LOW - Prevents disk exhaustion
- **Example**:
  ```bash
  MAX_BACKUPS=200
  ```

### SSHD Configuration

SSH daemon specific settings.

#### `SSHD_CONFIG`
- **Description**: Path to SSH daemon config
- **Type**: String (file path)
- **Default**: `"/etc/ssh/sshd_config"`
- **Valid Values**: Valid config path
- **Impact**: Location of SSH configuration
- **Security**: None
- **Example**:
  ```bash
  SSHD_CONFIG="/etc/ssh/sshd_config"
  ```

#### `SSHD_PERMIT_ROOT_LOGIN`
- **Description**: Allow root SSH login
- **Type**: String
- **Default**: `"no"`
- **Valid Values**: "yes", "no", "without-password"
- **Impact**: Controls root SSH access
- **Security**: CRITICAL - Always use "no"
- **Example**:
  ```bash
  SSHD_PERMIT_ROOT_LOGIN="no"  # Never allow
  ```
- **Best Practice**: Use sudo from regular user

#### `SSHD_PASSWORD_AUTHENTICATION`
- **Description**: Allow password authentication
- **Type**: String
- **Default**: `"no"`
- **Valid Values**: "yes", "no"
- **Impact**: Forces key-based authentication
- **Security**: HIGH - Keys are more secure
- **Example**:
  ```bash
  SSHD_PASSWORD_AUTHENTICATION="no"
  ```
- **Exception**: Emergency port may allow passwords

#### `SSHD_PUBKEY_AUTHENTICATION`
- **Description**: Allow public key authentication
- **Type**: String
- **Default**: `"yes"`
- **Valid Values**: "yes", "no"
- **Impact**: Enables SSH key login
- **Security**: Required for secure access
- **Example**:
  ```bash
  SSHD_PUBKEY_AUTHENTICATION="yes"
  ```

#### `SSHD_PERMIT_EMPTY_PASSWORDS`
- **Description**: Allow empty password login
- **Type**: String
- **Default**: `"no"`
- **Valid Values**: "yes", "no"
- **Impact**: Blank passwords rejected
- **Security**: CRITICAL - Never allow
- **Example**:
  ```bash
  SSHD_PERMIT_EMPTY_PASSWORDS="no"
  ```

#### `SSHD_MAX_AUTH_TRIES`
- **Description**: Max authentication attempts per connection
- **Type**: Integer
- **Default**: `3`
- **Valid Values**: 1-6
- **Impact**: Connection dropped after failures
- **Security**: HIGH - Limits brute force
- **Example**:
  ```bash
  SSHD_MAX_AUTH_TRIES=3
  ```

#### `SSHD_MAX_SESSIONS`
- **Description**: Max sessions per connection
- **Type**: Integer
- **Default**: `10`
- **Valid Values**: 1-100
- **Impact**: Limits multiplexed sessions
- **Security**: LOW
- **Example**:
  ```bash
  SSHD_MAX_SESSIONS=10
  ```

#### `SSHD_CLIENT_ALIVE_INTERVAL`
- **Description**: Seconds between keepalive messages
- **Type**: Integer
- **Default**: `300` (5 minutes)
- **Valid Values**: 0-3600
- **Impact**: Detects dead connections
- **Security**: LOW - Cleans up stale sessions
- **Example**:
  ```bash
  SSHD_CLIENT_ALIVE_INTERVAL=300
  ```

#### `SSHD_CLIENT_ALIVE_COUNT_MAX`
- **Description**: Missed keepalives before disconnect
- **Type**: Integer
- **Default**: `0`
- **Valid Values**: 0-10
- **Impact**: How many keepalives to miss
- **Security**: LOW
- **Example**:
  ```bash
  SSHD_CLIENT_ALIVE_COUNT_MAX=0
  ```

#### `SSHD_LOGIN_GRACE_TIME`
- **Description**: Seconds to complete authentication
- **Type**: Integer
- **Default**: `30`
- **Valid Values**: 10-120
- **Impact**: Drops slow authentication attempts
- **Security**: MEDIUM - Prevents resource exhaustion
- **Example**:
  ```bash
  SSHD_LOGIN_GRACE_TIME=30
  ```

### Advanced Options

Expert-level configuration.

#### `LOG_DROPPED_PACKETS`
- **Description**: Log packets dropped by firewall
- **Type**: Boolean (0/1)
- **Default**: `1`
- **Valid Values**: `0` (off), `1` (on)
- **Impact**: Dropped packets logged to syslog
- **Security**: LOW - Useful for debugging
- **Example**:
  ```bash
  LOG_DROPPED_PACKETS=1
  ```
- **Log Location**: `/var/log/kern.log` or `/var/log/messages`
- **Warning**: Can fill logs on busy networks

#### `ICMP_ENABLED`
- **Description**: Allow ICMP (ping) traffic
- **Type**: Boolean (0/1)
- **Default**: `1`
- **Valid Values**: `0` (block), `1` (allow)
- **Impact**: Server responds to ping
- **Security**: LOW - Hiding doesn't improve security
- **Example**:
  ```bash
  ICMP_ENABLED=1  # Allow ping
  ```

#### `ICMP_RATE_LIMIT`
- **Description**: Rate limit for ICMP packets
- **Type**: String (iptables limit syntax)
- **Default**: `"1/s"`
- **Valid Values**: iptables limit format
- **Impact**: Limits ping flood attacks
- **Security**: MEDIUM - Prevents ICMP DoS
- **Example**:
  ```bash
  ICMP_RATE_LIMIT="2/s"  # 2 pings per second
  ```

#### `SSH_RATE_LIMIT_HITS`
- **Description**: SSH connections before rate limiting
- **Type**: Integer
- **Default**: `4`
- **Valid Values**: 1-10
- **Impact**: Limits rapid SSH attempts
- **Security**: HIGH - Prevents brute force
- **Example**:
  ```bash
  SSH_RATE_LIMIT_HITS=3
  ```

#### `SSH_RATE_LIMIT_SECONDS`
- **Description**: Time window for SSH rate limit
- **Type**: Integer
- **Default**: `60`
- **Valid Values**: 10-300
- **Impact**: Window for counting connections
- **Security**: HIGH - Shorter = stricter
- **Example**:
  ```bash
  SSH_RATE_LIMIT_SECONDS=30
  ```

#### `PARALLEL_EXECUTION`
- **Description**: Run hardening scripts in parallel
- **Type**: Boolean (0/1)
- **Default**: `0`
- **Valid Values**: `0` (sequential), `1` (parallel)
- **Impact**: Faster execution but harder debugging
- **Security**: None - Experimental feature
- **Example**:
  ```bash
  PARALLEL_EXECUTION=0  # Keep sequential
  ```
- **Warning**: May cause race conditions

### Deployment Paths

Where toolkit files are installed.

#### `TOOLKIT_PATH` / `toolkit_path`
- **Description**: Installation directory for toolkit
- **Type**: String (directory path)
- **Default**: `"/opt/posix-hardening"`
- **Valid Values**: Absolute path
- **Impact**: Location of all toolkit scripts
- **Security**: LOW - Should be root-owned
- **Example**:
  ```bash
  TOOLKIT_PATH="/opt/posix-hardening"
  ```

#### `BACKUP_DIR` / `backup_path`
- **Description**: Directory for configuration backups
- **Type**: String (directory path)
- **Default**: `"/var/backups/hardening"`
- **Valid Values**: Writable directory
- **Impact**: Where backups are stored
- **Security**: MEDIUM - Should be protected
- **Example**:
  ```bash
  BACKUP_DIR="/var/backups/hardening"
  ```
- **Permissions**: 700 (root only)

#### `LOG_DIR` / `log_path`
- **Description**: Directory for hardening logs
- **Type**: String (directory path)
- **Default**: `"/var/log/hardening"`
- **Valid Values**: Writable directory
- **Impact**: Execution logs location
- **Security**: LOW
- **Example**:
  ```bash
  LOG_DIR="/var/log/hardening"
  ```

#### `STATE_DIR` / `state_path`
- **Description**: Runtime state storage
- **Type**: String (directory path)
- **Default**: `"/var/lib/hardening"`
- **Valid Values**: Writable directory
- **Impact**: Stores checksums, state files
- **Security**: LOW
- **Example**:
  ```bash
  STATE_DIR="/var/lib/hardening"
  ```

### Environment Detection

Auto-detected values (usually not set manually).

#### `OS_TYPE`
- **Description**: Operating system type
- **Type**: String
- **Default**: "" (auto-detect)
- **Valid Values**: "debian", "ubuntu", "rhel", "centos"
- **Impact**: OS-specific commands
- **Security**: None
- **Example**:
  ```bash
  OS_TYPE=""  # Let toolkit detect
  ```

#### `OS_VERSION`
- **Description**: Operating system version
- **Type**: String
- **Default**: "" (auto-detect)
- **Valid Values**: "11", "12", "20.04", "22.04", etc.
- **Impact**: Version-specific fixes
- **Security**: None
- **Example**:
  ```bash
  OS_VERSION=""  # Let toolkit detect
  ```

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

| Variable | If Not Set | Result |
|----------|------------|--------|
| ADMIN_IP | Empty | **DEPLOYMENT FAILS** - Firewall would lock you out |
| SSH_ALLOW_USERS | Empty | **CRITICAL FAILURE** - No SSH access |
| SSH_PORT | Not set | Defaults to 22 |
| ALLOWED_PORTS | Empty | Only SSH allowed |
| DISABLE_SERVICES | Empty | No services disabled |
| Most others | Not set | Safe defaults applied |

---

## Troubleshooting Configuration Issues

### Common Misconfigurations

#### Problem: Locked out after hardening
**Cause**: ADMIN_IP not set or incorrect
**Solution**:
1. Use emergency SSH port: `ssh -p 2222 user@server`
2. Fix ADMIN_IP in config
3. Re-run hardening

#### Problem: SSH connection refused
**Cause**: User not in SSH_ALLOW_USERS
**Solution**:
1. Use emergency access
2. Add user to SSH_ALLOW_USERS
3. Restart SSH: `systemctl restart sshd`

#### Problem: Firewall blocks legitimate traffic
**Cause**: Port not in ALLOWED_PORTS
**Solution**:
```bash
# Temporarily disable firewall
iptables -F
# Add port to ALLOWED_PORTS
ALLOWED_PORTS="80 443 3306"
# Re-run firewall script
```

#### Problem: Services needed but disabled
**Cause**: Service in DISABLE_SERVICES list
**Solution**:
1. Remove from DISABLE_SERVICES
2. Start service: `systemctl start service-name`
3. Enable service: `systemctl enable service-name`

#### Problem: Can't write to /tmp
**Cause**: noexec mount option
**Solution**:
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

*Configuration Reference v1.0 - POSIX Hardening Toolkit*