#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# emergency-rollback.sh - Emergency recovery script
# USE ONLY IN EMERGENCY - Restores system to pre-hardening state

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source only essential functions
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"

# Force safety off for emergency
export SAFETY_MODE=0
export DRY_RUN=0

# ============================================================================
# Emergency Recovery Functions
# ============================================================================

emergency_restore_ssh() {
    echo "[EMERGENCY] Restoring SSH configuration..."

    # Find most recent SSH backup
    latest_ssh_backup=$(ls -t "$BACKUP_DIR"/sshd_config.*.bak 2>/dev/null | head -1)

    if [ -f "$latest_ssh_backup" ]; then
        cp "$latest_ssh_backup" /etc/ssh/sshd_config
        echo "[OK] Restored SSH config from: $latest_ssh_backup"

        # Restart SSH
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        else
            service ssh restart 2>/dev/null || service sshd restart 2>/dev/null
        fi
    else
        echo "[ERROR] No SSH backup found!"
    fi

    # Ensure SSH is running
    if ! pgrep -x sshd >/dev/null; then
        echo "[CRITICAL] Starting SSH daemon..."
        /usr/sbin/sshd
    fi
}

emergency_reset_firewall() {
    echo "[EMERGENCY] Resetting firewall rules..."

    # Flush all rules
    if command -v iptables >/dev/null 2>&1; then
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X

        # Set default policies to ACCEPT
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT

        echo "[OK] IPv4 firewall reset to ACCEPT all"
    fi

    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F
        ip6tables -X
        ip6tables -P INPUT ACCEPT
        ip6tables -P FORWARD ACCEPT
        ip6tables -P OUTPUT ACCEPT

        echo "[OK] IPv6 firewall reset to ACCEPT all"
    fi
}

restore_latest_snapshot() {
    echo "[EMERGENCY] Looking for system snapshots..."

    # Find latest snapshot
    latest_snapshot=$(ls -dt "$SNAPSHOT_DIR"/* 2>/dev/null | head -1)

    if [ -d "$latest_snapshot" ]; then
        snapshot_id=$(basename "$latest_snapshot")
        echo "[OK] Found snapshot: $snapshot_id"

        printf "Restore from this snapshot? (yes/NO): "
        read -r response

        if [ "$response" = "yes" ]; then
            restore_system_snapshot "$snapshot_id"
        fi
    else
        echo "[ERROR] No snapshots found!"
    fi
}

reset_file_permissions() {
    echo "[EMERGENCY] Resetting critical file permissions..."

    # Reset shadow file (make readable by root)
    [ -f /etc/shadow ] && chmod 640 /etc/shadow
    [ -f /etc/gshadow ] && chmod 640 /etc/gshadow

    # Reset SSH directory
    [ -d /etc/ssh ] && chmod 755 /etc/ssh
    [ -f /etc/ssh/sshd_config ] && chmod 644 /etc/ssh/sshd_config

    # Reset sudoers
    [ -f /etc/sudoers ] && chmod 440 /etc/sudoers

    echo "[OK] Critical permissions reset"
}

emergency_create_access() {
    echo "[EMERGENCY] Creating emergency access..."

    # Start emergency SSH on alternate port
    if [ -f /usr/sbin/sshd ]; then
        cat > /tmp/sshd_emergency_config <<EOF
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
PidFile /var/run/sshd_emergency.pid
EOF

        /usr/sbin/sshd -f /tmp/sshd_emergency_config
        echo "[OK] Emergency SSH started on port 2222"
    fi
}

clear_hardening_state() {
    echo "[EMERGENCY] Clearing hardening state..."

    # Clear completed markers
    rm -f "$STATE_DIR"/completed
    rm -f "$STATE_DIR"/current_*
    rm -f "$STATE_DIR"/rollback_*

    echo "[OK] Hardening state cleared"
}

# ============================================================================
# Main Emergency Menu
# ============================================================================

show_emergency_menu() {
    cat <<EOF

========================================
EMERGENCY SYSTEM RECOVERY
========================================
WARNING: These operations bypass safety checks!

1) Restore SSH access
2) Reset firewall (ACCEPT all)
3) Restore from latest snapshot
4) Reset file permissions
5) Create emergency SSH (port 2222)
6) Clear all hardening state
7) FULL EMERGENCY RESET (all above)
0) Exit

========================================
EOF
}

full_emergency_reset() {
    echo ""
    echo "========================================="
    echo "EXECUTING FULL EMERGENCY RESET"
    echo "========================================="

    emergency_restore_ssh
    emergency_reset_firewall
    reset_file_permissions
    emergency_create_access
    clear_hardening_state

    echo ""
    echo "========================================="
    echo "EMERGENCY RESET COMPLETE"
    echo "========================================="
    echo "Actions taken:"
    echo "- SSH configuration restored"
    echo "- Firewall rules cleared (ACCEPT all)"
    echo "- File permissions reset"
    echo "- Emergency SSH on port 2222"
    echo "- Hardening state cleared"
    echo ""
    echo "IMPORTANT: System is now in UNSECURED state!"
    echo "========================================="
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] This script must be run as root!"
        exit 1
    fi

    echo ""
    echo "========================================="
    echo "POSIX HARDENING - EMERGENCY RECOVERY"
    echo "========================================="
    echo "This script will restore system access"
    echo "and undo hardening configurations."
    echo ""

    # Quick mode for critical situations
    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        echo "[EMERGENCY] Force mode - executing full reset"
        full_emergency_reset
        exit 0
    fi

    # Interactive mode
    while true; do
        show_emergency_menu
        printf "Select option: "
        read -r choice

        case "$choice" in
            1)
                emergency_restore_ssh
                ;;
            2)
                emergency_reset_firewall
                ;;
            3)
                restore_latest_snapshot
                ;;
            4)
                reset_file_permissions
                ;;
            5)
                emergency_create_access
                ;;
            6)
                clear_hardening_state
                ;;
            7)
                printf "Execute FULL emergency reset? (yes/NO): "
                read -r confirm
                if [ "$confirm" = "yes" ]; then
                    full_emergency_reset
                fi
                ;;
            0|q|Q)
                echo "Exiting emergency recovery"
                exit 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac

        echo ""
        printf "Press Enter to continue..."
        read -r _
    done
}

# Run main
main "$@"