#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 03-kernel-params.sh
# Priority: HIGH - Kernel security parameters
# Description: Hardens kernel parameters via sysctl

# Get script directory and toolkit root
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Load configuration
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Script name
SCRIPT_NAME="03-kernel-params"

# ============================================================================
# Kernel Parameters
# ============================================================================

apply_kernel_hardening() {
    show_progress "Applying kernel security parameters"

    # Backup current sysctl settings
    sysctl -a > "$BACKUP_DIR/sysctl.backup.$(date +%Y%m%d-%H%M%S)" 2>/dev/null

    # Create or backup sysctl.conf
    if [ -f /etc/sysctl.conf ]; then
        backup_file /etc/sysctl.conf
    fi

    # Apply kernel parameters
    cat >> /etc/sysctl.conf <<'EOF'

# === POSIX Hardening Toolkit - Kernel Parameters ===

# Network Security
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TCP/IP Stack Hardening
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_congestion_control = htcp
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Memory Protection
kernel.randomize_va_space = 2
# kernel.exec-shield = 1  # Deprecated - only for older RHEL/CentOS kernels
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# Core Dumps
fs.suid_dumpable = 0
kernel.core_uses_pid = 1

# Process Security
kernel.pid_max = 65536
kernel.panic = 60
kernel.panic_on_oops = 1

# Shared Memory
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

# File Descriptors
fs.file-max = 65535

# SysRq
kernel.sysrq = 0

# === End POSIX Hardening ===
EOF

    # Apply settings
    sysctl -p /etc/sysctl.conf >/dev/null 2>&1

    show_success "Kernel parameters hardened"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    show_progress "Starting kernel parameter hardening"

    # Initialize
    init_hardening_environment "$SCRIPT_NAME"

    # Start transaction
    begin_transaction "kernel_params"

    # Apply hardening
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would apply kernel hardening parameters"
    else
        apply_kernel_hardening
    fi

    # Mark complete
    mark_completed "$SCRIPT_NAME"

    # Commit transaction
    commit_transaction

    show_success "Kernel parameter hardening completed"
    exit 0
}

main "$@"