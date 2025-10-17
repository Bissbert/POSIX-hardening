# POSIX Shell Hardening Scripts - Implementation Guide

## Script Development Principles

### POSIX Compliance Rules
```sh
# ALLOWED in POSIX:
- test or [ ]  (single brackets only)
- case statements
- for/while/until loops
- functions: name() { commands; }
- parameter expansion: ${var}, ${var:-default}
- command substitution: $(command) or `command`

# NOT ALLOWED (bash-specific):
- [[ ]] double brackets
- arrays: arr=(item1 item2)
- (( )) arithmetic
- <() >() process substitution
- function keyword
- local variables (use namespace prefix instead)
```

## Detailed Implementation for Each Script

### 01_ssh_config_hardening.sh
```sh
#!/bin/sh
# Harden SSH daemon configuration

CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Critical settings that won't lock out admins
apply_ssh_hardening() {
    cp "$CONFIG" "$BACKUP"

    # Disable root login (keep PermitRootLogin prohibit-password for key access)
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$CONFIG"

    # Disable password authentication (ONLY if keys are setup!)
    # sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$CONFIG"

    # Protocol and crypto hardening
    grep -q "^Protocol" "$CONFIG" || echo "Protocol 2" >> "$CONFIG"
    sed -i 's/^#*Protocol.*/Protocol 2/' "$CONFIG"

    # Limit authentication attempts
    sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$CONFIG"

    # Disable empty passwords
    sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' "$CONFIG"

    # Set strong ciphers (Debian default compatibility)
    grep -q "^Ciphers" "$CONFIG" || \
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> "$CONFIG"

    # Validate config before reload
    /usr/sbin/sshd -t -f "$CONFIG" || {
        cp "$BACKUP" "$CONFIG"
        return 1
    }

    # Reload SSH daemon
    kill -HUP $(cat /var/run/sshd.pid)
}
```

### 02_ssh_key_management.sh
```sh
#!/bin/sh
# Manage and harden SSH keys

check_ssh_keys() {
    for home in /home/* /root; do
        [ -d "$home/.ssh" ] || continue

        # Fix permissions
        chmod 700 "$home/.ssh"
        [ -f "$home/.ssh/authorized_keys" ] && chmod 600 "$home/.ssh/authorized_keys"

        # Check for weak keys (RSA < 2048 bits)
        if [ -f "$home/.ssh/authorized_keys" ]; then
            while IFS= read -r line; do
                case "$line" in
                    ssh-rsa*)
                        # Extract and check key length
                        key=$(echo "$line" | awk '{print $2}')
                        # Would need base64 decode and check - mark for review
                        echo "Review RSA key in $home/.ssh/authorized_keys"
                        ;;
                esac
            done < "$home/.ssh/authorized_keys"
        fi
    done
}
```

### 03_firewall_ssh_protection.sh
```sh
#!/bin/sh
# Implement SSH brute force protection with iptables

setup_ssh_firewall() {
    # Check if iptables is available
    command -v iptables >/dev/null 2>&1 || {
        echo "iptables not found"
        return 1
    }

    # Create SSH rate limiting chain
    iptables -N SSH_LIMIT 2>/dev/null || true

    # Rate limit SSH connections (max 3 per minute per IP)
    iptables -F SSH_LIMIT
    iptables -A SSH_LIMIT -m recent --set --name SSH
    iptables -A SSH_LIMIT -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
    iptables -A SSH_LIMIT -j ACCEPT

    # Apply to INPUT chain (check if rule exists first)
    iptables -C INPUT -p tcp --dport 22 -m state --state NEW -j SSH_LIMIT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport 22 -m state --state NEW -j SSH_LIMIT

    # Ensure established connections are allowed (critical!)
    iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -m state --state ESTABLISHED,RELATED -j ACCEPT
}
```

### 04_user_account_hardening.sh
```sh
#!/bin/sh
# Harden user accounts and remove unnecessary users

harden_user_accounts() {
    # Lock unnecessary system accounts
    for user in games news uucp proxy www-data list irc gnats nobody; do
        if getent passwd "$user" >/dev/null 2>&1; then
            usermod -L "$user" 2>/dev/null || true
            usermod -s /usr/sbin/nologin "$user" 2>/dev/null || true
        fi
    done

    # Check for accounts with UID 0 besides root
    awk -F: '($3 == 0 && $1 != "root") {print "WARNING: UID 0 account found: " $1}' /etc/passwd

    # Set password aging for human users (UID >= 1000)
    awk -F: '($3 >= 1000 && $1 != "nobody") {print $1}' /etc/passwd | while read -r user; do
        chage -M 90 -m 7 -W 14 "$user" 2>/dev/null || true
    done

    # Ensure no users have empty passwords
    awk -F: '($2 == "" || $2 == "!") {print "WARNING: User with empty password: " $1}' /etc/shadow
}
```

### 05_sudo_configuration.sh
```sh
#!/bin/sh
# Harden sudo configuration

configure_sudo() {
    SUDOERS="/etc/sudoers"
    SUDOERS_D="/etc/sudoers.d"

    # Backup
    cp "$SUDOERS" "$SUDOERS.backup.$(date +%Y%m%d_%H%M%S)"

    # Create secure defaults file
    cat > "$SUDOERS_D/99_hardening" <<'EOF'
# Sudo hardening settings
Defaults    requiretty
Defaults    use_pty
Defaults    logfile="/var/log/sudo.log"
Defaults    lecture="always"
Defaults    passwd_tries=3
Defaults    insults=false
Defaults    env_reset
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults    timestamp_timeout=15
EOF

    # Validate sudoers
    visudo -c -f "$SUDOERS_D/99_hardening" || {
        rm -f "$SUDOERS_D/99_hardening"
        return 1
    }

    chmod 440 "$SUDOERS_D/99_hardening"
}
```

### 06_file_permissions.sh
```sh
#!/bin/sh
# Set secure file permissions on critical system files

secure_file_permissions() {
    # Critical system files
    chmod 644 /etc/passwd
    chmod 640 /etc/shadow
    chmod 644 /etc/group
    chmod 640 /etc/gshadow

    # SSH files
    chmod 600 /etc/ssh/sshd_config

    # Cron files
    [ -f /etc/crontab ] && chmod 600 /etc/crontab
    [ -d /etc/cron.d ] && chmod 700 /etc/cron.d
    [ -d /etc/cron.daily ] && chmod 700 /etc/cron.daily
    [ -d /etc/cron.hourly ] && chmod 700 /etc/cron.hourly
    [ -d /etc/cron.monthly ] && chmod 700 /etc/cron.monthly
    [ -d /etc/cron.weekly ] && chmod 700 /etc/cron.weekly

    # Find and report world-writable files
    echo "World-writable files in /etc:"
    find /etc -type f -perm -002 2>/dev/null

    # Find and report SUID/SGID files
    echo "SUID files:"
    find / -type f -perm -4000 2>/dev/null | head -20
}
```

### 07_kernel_parameters.sh
```sh
#!/bin/sh
# Harden kernel parameters via sysctl

apply_kernel_hardening() {
    SYSCTL_CONF="/etc/sysctl.d/99-hardening.conf"

    cat > "$SYSCTL_CONF" <<'EOF'
# Network Security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# IPv6 Security (disable if not used)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Memory Protection
kernel.randomize_va_space = 2
kernel.exec-shield = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1

# Core Dumps
fs.suid_dumpable = 0
kernel.core_uses_pid = 1
EOF

    # Apply settings
    sysctl -p "$SYSCTL_CONF"
}
```

### 08_process_limits.sh
```sh
#!/bin/sh
# Configure process and resource limits

set_process_limits() {
    LIMITS_CONF="/etc/security/limits.d/99-hardening.conf"

    cat > "$LIMITS_CONF" <<'EOF'
# Prevent fork bombs
*    hard    nproc    10000
*    soft    nproc    10000
root hard    nproc    unlimited
root soft    nproc    unlimited

# Core dumps
*    hard    core    0
*    soft    core    0

# Maximum file size (1GB)
*    hard    fsize   1048576

# Maximum number of open files
*    hard    nofile  65536
*    soft    nofile  4096

# Maximum locked memory (KB)
*    hard    memlock 64
EOF
}
```

### 09_audit_logging.sh
```sh
#!/bin/sh
# Configure comprehensive audit logging

setup_audit_logging() {
    # Configure rsyslog for authentication logging
    cat >> /etc/rsyslog.d/50-hardening.conf <<'EOF'
# Authentication logging
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          -/var/log/syslog
kern.*                          -/var/log/kern.log

# Sudo logging
:programname, isequal, "sudo"   /var/log/sudo.log
& stop

# SSH logging
:programname, isequal, "sshd"   /var/log/sshd.log
& stop
EOF

    # Restart rsyslog
    service rsyslog restart

    # If auditd is available, configure it
    if command -v auditctl >/dev/null 2>&1; then
        # Monitor authentication files
        auditctl -w /etc/passwd -p wa -k passwd_changes
        auditctl -w /etc/shadow -p wa -k shadow_changes
        auditctl -w /etc/group -p wa -k group_changes
        auditctl -w /etc/sudoers -p wa -k sudoers_changes
        auditctl -w /etc/ssh/sshd_config -p wa -k sshd_config
    fi
}
```

### 10_network_services.sh
```sh
#!/bin/sh
# Disable unnecessary network services

disable_network_services() {
    # List of services to check and potentially disable
    SERVICES="avahi-daemon cups bluetooth rpcbind nfs-client"

    for service in $SERVICES; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            echo "Found enabled service: $service"
            # systemctl disable "$service" --now
            # Only report, don't auto-disable without confirmation
        fi
    done

    # Check for listening services
    echo "Currently listening services:"
    ss -tlnp 2>/dev/null | grep LISTEN

    # Disable IPv6 if not needed (via sysctl instead of service)
    if ! ip -6 addr show | grep -q "inet6"; then
        echo "IPv6 appears unused, consider disabling"
    fi
}
```

### 11_tcp_wrappers.sh
```sh
#!/bin/sh
# Configure TCP wrappers for additional access control

configure_tcp_wrappers() {
    # Backup existing files
    cp /etc/hosts.allow /etc/hosts.allow.backup 2>/dev/null || true
    cp /etc/hosts.deny /etc/hosts.deny.backup 2>/dev/null || true

    # Default deny all
    echo "ALL: ALL" > /etc/hosts.deny

    # Allow SSH from specific networks (customize as needed)
    cat > /etc/hosts.allow <<'EOF'
# Allow SSH from anywhere (customize for your environment)
sshd: ALL
# For specific IPs/networks use:
# sshd: 192.168.1.0/24
# sshd: 10.0.0.0/8

# Allow local connections
ALL: 127.0.0.1
ALL: ::1
EOF
}
```

### 12_cron_hardening.sh
```sh
#!/bin/sh
# Restrict cron access to authorized users

harden_cron() {
    # Create cron.allow file (only listed users can use cron)
    touch /etc/cron.allow
    chmod 600 /etc/cron.allow

    # Add root and specific admin users
    echo "root" > /etc/cron.allow

    # Remove cron.deny if it exists
    rm -f /etc/cron.deny

    # Set proper permissions on cron files
    chmod 600 /etc/crontab

    # Check for user crontabs
    echo "Existing user crontabs:"
    ls -la /var/spool/cron/crontabs/ 2>/dev/null || true
}
```

### 13_mount_hardening.sh
```sh
#!/bin/sh
# Harden mount points with restrictive options

secure_mount_points() {
    # Check if separate partitions exist
    MOUNTS="/tmp /var/tmp /dev/shm"

    for mount_point in $MOUNTS; do
        if mount | grep -q " $mount_point "; then
            # Remount with secure options
            mount -o remount,noexec,nosuid,nodev "$mount_point"

            # Add to fstab for persistence
            if ! grep -q "$mount_point.*noexec" /etc/fstab; then
                echo "Add noexec,nosuid,nodev to $mount_point in /etc/fstab"
            fi
        fi
    done

    # Secure shared memory
    if mount | grep -q "/run/shm"; then
        mount -o remount,noexec,nosuid,nodev /run/shm
    fi
}
```

### 14_core_dump_disable.sh
```sh
#!/bin/sh
# Disable core dumps system-wide

disable_core_dumps() {
    # Disable in limits
    echo "* hard core 0" > /etc/security/limits.d/no-coredumps.conf
    echo "* soft core 0" >> /etc/security/limits.d/no-coredumps.conf

    # Disable via sysctl
    echo "fs.suid_dumpable = 0" > /etc/sysctl.d/50-coredump.conf
    sysctl -p /etc/sysctl.d/50-coredump.conf

    # Disable systemd coredump if present
    if [ -f /etc/systemd/coredump.conf ]; then
        sed -i 's/^#*Storage=.*/Storage=none/' /etc/systemd/coredump.conf
        systemctl daemon-reload
    fi
}
```

### 15_login_banner.sh
```sh
#!/bin/sh
# Configure login warning banners

set_login_banners() {
    BANNER_TEXT="*****************************************************************************
UNAUTHORIZED ACCESS TO THIS SYSTEM IS PROHIBITED

This system is for authorized use only. By accessing this system, you agree
that your actions may be monitored and recorded. Unauthorized attempts to
access, modify, or delete information on this system is strictly prohibited
and will be prosecuted to the fullest extent of the law.

*****************************************************************************"

    # Set banner for SSH
    echo "$BANNER_TEXT" > /etc/ssh/banner
    sed -i 's/^#*Banner.*/Banner \/etc\/ssh\/banner/' /etc/ssh/sshd_config

    # Set issue files
    echo "$BANNER_TEXT" > /etc/issue
    echo "$BANNER_TEXT" > /etc/issue.net

    # Set MOTD
    echo "$BANNER_TEXT" > /etc/motd

    # Reload SSH
    kill -HUP $(cat /var/run/sshd.pid)
}
```

### 16_session_timeout.sh
```sh
#!/bin/sh
# Configure session timeout for idle connections

set_session_timeout() {
    # SSH idle timeout (30 minutes)
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config

    # Shell timeout via profile
    cat > /etc/profile.d/timeout.sh <<'EOF'
# Set shell timeout to 30 minutes
TMOUT=1800
readonly TMOUT
export TMOUT
EOF

    chmod 644 /etc/profile.d/timeout.sh

    # Reload SSH
    /usr/sbin/sshd -t && kill -HUP $(cat /var/run/sshd.pid)
}
```

### 17_password_aging.sh
```sh
#!/bin/sh
# Configure password aging policies

set_password_policies() {
    # Set default password aging in login.defs
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

    # Set minimum password length
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs

    # Apply to existing users (UID >= 1000)
    awk -F: '($3 >= 1000 && $3 != 65534) {print $1}' /etc/passwd | while read -r user; do
        chage -M 90 -m 7 -W 14 "$user"
    done

    # Set password complexity via PAM (if pam_pwquality is available)
    if [ -f /etc/pam.d/common-password ]; then
        grep -q "pam_pwquality.so" /etc/pam.d/common-password || \
            echo "Consider installing libpam-pwquality for password complexity"
    fi
}
```

### 18_shared_memory_security.sh
```sh
#!/bin/sh
# Secure shared memory

secure_shared_memory() {
    # Secure /dev/shm
    if mount | grep -q "/dev/shm"; then
        mount -o remount,noexec,nosuid,nodev /dev/shm
    fi

    # Secure /run/shm
    if mount | grep -q "/run/shm"; then
        mount -o remount,noexec,nosuid,nodev /run/shm
    fi

    # Add to fstab for persistence
    if ! grep -q "/dev/shm.*noexec" /etc/fstab; then
        echo "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
    fi

    # Set proper permissions
    chmod 1777 /dev/shm 2>/dev/null || true
    chmod 1777 /run/shm 2>/dev/null || true
}
```

### 19_kernel_module_blacklist.sh
```sh
#!/bin/sh
# Blacklist unnecessary kernel modules

blacklist_kernel_modules() {
    BLACKLIST_CONF="/etc/modprobe.d/blacklist-hardening.conf"

    cat > "$BLACKLIST_CONF" <<'EOF'
# Blacklist rare network protocols
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false

# Blacklist filesystems
install cramfs /bin/false
install freevxfs /bin/false
install jffs2 /bin/false
install hfs /bin/false
install hfsplus /bin/false
install udf /bin/false

# Blacklist USB storage (if not needed)
# install usb-storage /bin/false

# Blacklist firewire
install firewire-core /bin/false
install firewire-ohci /bin/false
install firewire-sbp2 /bin/false

# Bluetooth (if not needed)
# install bluetooth /bin/false
EOF

    # Update initramfs
    update-initramfs -u
}
```

### 20_log_rotation_hardening.sh
```sh
#!/bin/sh
# Configure secure log rotation

secure_log_rotation() {
    # Create logrotate configuration for security logs
    cat > /etc/logrotate.d/security-logs <<'EOF'
/var/log/auth.log
/var/log/sshd.log
/var/log/sudo.log
{
    daily
    rotate 365
    compress
    delaycompress
    missingok
    notifempty
    create 600 root adm
    sharedscripts
    postrotate
        service rsyslog rotate >/dev/null 2>&1 || true
    endscript
}

/var/log/kern.log
{
    weekly
    rotate 52
    compress
    delaycompress
    missingok
    notifempty
    create 600 root adm
}
EOF

    # Set proper permissions on log files
    chmod 600 /var/log/auth.log* 2>/dev/null || true
    chmod 600 /var/log/sshd.log* 2>/dev/null || true
    chmod 600 /var/log/sudo.log* 2>/dev/null || true
}
```

## Master Orchestration Script

### run_hardening.sh
```sh
#!/bin/sh
# Master script to run all hardening scripts

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="/var/log/hardening_$(date +%Y%m%d_%H%M%S).log"

# Function to run a script safely
run_script() {
    script_name="$1"
    priority="$2"

    echo "[$priority] Running $script_name..." | tee -a "$LOG_FILE"

    if [ -x "$SCRIPT_DIR/$script_name" ]; then
        if "$SCRIPT_DIR/$script_name" >> "$LOG_FILE" 2>&1; then
            echo "[$priority] $script_name completed successfully" | tee -a "$LOG_FILE"
            return 0
        else
            echo "[$priority] WARNING: $script_name failed" | tee -a "$LOG_FILE"
            return 1
        fi
    else
        echo "[$priority] ERROR: $script_name not found or not executable" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Create backup of critical files
echo "Creating system backup..." | tee -a "$LOG_FILE"
tar czf "/root/pre-hardening-backup-$(date +%Y%m%d_%H%M%S).tar.gz" \
    /etc/ssh/sshd_config \
    /etc/sudoers \
    /etc/sysctl.conf \
    /etc/fstab \
    /etc/security/limits.conf \
    2>/dev/null || true

# Run scripts in priority order
echo "Starting hardening process..." | tee -a "$LOG_FILE"

# Critical scripts that could affect access
run_script "01_ssh_config_hardening.sh" 1
run_script "02_ssh_key_management.sh" 2
run_script "03_firewall_ssh_protection.sh" 3
run_script "04_user_account_hardening.sh" 4
run_script "05_sudo_configuration.sh" 5

# System security scripts
run_script "06_file_permissions.sh" 6
run_script "07_kernel_parameters.sh" 7
run_script "08_process_limits.sh" 8
run_script "09_audit_logging.sh" 9
run_script "10_network_services.sh" 10

# Additional hardening
run_script "11_tcp_wrappers.sh" 11
run_script "12_cron_hardening.sh" 12
run_script "13_mount_hardening.sh" 13
run_script "14_core_dump_disable.sh" 14
run_script "15_login_banner.sh" 15
run_script "16_session_timeout.sh" 16
run_script "17_password_aging.sh" 17
run_script "18_shared_memory_security.sh" 18
run_script "19_kernel_module_blacklist.sh" 19
run_script "20_log_rotation_hardening.sh" 20

echo "Hardening complete. Review log at $LOG_FILE" | tee -a "$LOG_FILE"

# Final validation
echo "Running validation checks..." | tee -a "$LOG_FILE"
/usr/sbin/sshd -t && echo "SSH configuration valid" | tee -a "$LOG_FILE"