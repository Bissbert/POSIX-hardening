#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/backup.sh - Comprehensive backup and restore system
# Ensures all changes can be reverted

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"

# Backup configuration
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
readonly BACKUP_MANIFEST="$BACKUP_DIR/manifest"
readonly SNAPSHOT_DIR="$BACKUP_DIR/snapshots"

# Ensure backup directories exist
mkdir -p "$BACKUP_DIR" "$SNAPSHOT_DIR"

# ============================================================================
# Backup Management
# ============================================================================

# Generate backup filename with timestamp
generate_backup_name() {
    local source_file="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local basename=$(basename "$source_file")

    echo "${basename}.${timestamp}.bak"
}

# Create backup of a single file
backup_file() {
    local source_file="$1"
    local backup_name="${2:-}"

    if [ ! -f "$source_file" ]; then
        log "ERROR" "Source file does not exist: $source_file"
        return 1
    fi

    # Generate backup name if not provided
    if [ -z "$backup_name" ]; then
        backup_name=$(generate_backup_name "$source_file")
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    # Create backup preserving all attributes
    if cp -p "$source_file" "$backup_path" 2>/dev/null; then
        # Record in manifest
        echo "$(date +%Y-%m-%d-%H:%M:%S)|FILE|$source_file|$backup_path" >> "$BACKUP_MANIFEST"

        # Store file metadata
        ls -la "$source_file" > "${backup_path}.meta"
        sha256sum "$source_file" 2>/dev/null | cut -d' ' -f1 > "${backup_path}.sha256"

        log "INFO" "Backed up: $source_file -> $backup_path"
        echo "$backup_path"
        return 0
    else
        log "ERROR" "Failed to backup: $source_file"
        return 1
    fi
}

# Create backup of a directory
backup_directory() {
    local source_dir="$1"
    local backup_name="${2:-}"

    if [ ! -d "$source_dir" ]; then
        log "ERROR" "Source directory does not exist: $source_dir"
        return 1
    fi

    # Generate backup name if not provided
    if [ -z "$backup_name" ]; then
        backup_name="$(basename "$source_dir").$(date +%Y%m%d-%H%M%S).tar"
    fi

    local backup_path="$BACKUP_DIR/$backup_name"

    # Create tar archive preserving permissions
    if tar -cpf "$backup_path" -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null; then
        # Record in manifest
        echo "$(date +%Y-%m-%d-%H:%M:%S)|DIR|$source_dir|$backup_path" >> "$BACKUP_MANIFEST"

        log "INFO" "Backed up directory: $source_dir -> $backup_path"
        echo "$backup_path"
        return 0
    else
        log "ERROR" "Failed to backup directory: $source_dir"
        return 1
    fi
}

# ============================================================================
# System Snapshots
# ============================================================================

# Create comprehensive system snapshot
create_system_snapshot() {
    local snapshot_id="${1:-$(date +%Y%m%d-%H%M%S)}"
    local snapshot_path="$SNAPSHOT_DIR/$snapshot_id"
    local snapshot_manifest="$snapshot_path/manifest"

    log "INFO" "Creating system snapshot: $snapshot_id"

    # Create snapshot directory
    mkdir -p "$snapshot_path"

    # Start manifest
    cat > "$snapshot_manifest" <<EOF
# System Snapshot: $snapshot_id
# Date: $(date)
# Hostname: $(hostname)
# Kernel: $(uname -r)
EOF

    # Backup critical configuration files
    local configs="
        /etc/ssh/sshd_config
        /etc/sysctl.conf
        /etc/security/limits.conf
        /etc/fstab
        /etc/hosts
        /etc/hostname
        /etc/resolv.conf
        /etc/nsswitch.conf
        /etc/sudoers
        /etc/group
        /etc/passwd
        /etc/shadow
        /etc/gshadow
    "

    for config in $configs; do
        if [ -f "$config" ]; then
            local dest_dir="$snapshot_path$(dirname "$config")"
            mkdir -p "$dest_dir"
            cp -p "$config" "$dest_dir/" 2>/dev/null && \
                echo "FILE|$config" >> "$snapshot_manifest"
        fi
    done

    # Backup PAM configuration
    if [ -d /etc/pam.d ]; then
        mkdir -p "$snapshot_path/etc"
        tar -cf "$snapshot_path/etc/pam.d.tar" -C /etc pam.d 2>/dev/null && \
            echo "DIR|/etc/pam.d" >> "$snapshot_manifest"
    fi

    # Backup network configuration
    if [ -d /etc/network ]; then
        mkdir -p "$snapshot_path/etc"
        tar -cf "$snapshot_path/etc/network.tar" -C /etc network 2>/dev/null && \
            echo "DIR|/etc/network" >> "$snapshot_manifest"
    fi

    # Save current system state
    log "DEBUG" "Capturing system state"

    # Firewall rules
    if command -v iptables >/dev/null 2>&1; then
        iptables-save > "$snapshot_path/iptables.rules" 2>/dev/null && \
            echo "STATE|iptables" >> "$snapshot_manifest"
    fi

    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables-save > "$snapshot_path/ip6tables.rules" 2>/dev/null && \
            echo "STATE|ip6tables" >> "$snapshot_manifest"
    fi

    # Kernel parameters
    sysctl -a > "$snapshot_path/sysctl.current" 2>/dev/null && \
        echo "STATE|sysctl" >> "$snapshot_manifest"

    # Mount points
    mount > "$snapshot_path/mount.current" && \
        echo "STATE|mount" >> "$snapshot_manifest"

    # Running services
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --state=running > "$snapshot_path/services.systemd" && \
            echo "STATE|services-systemd" >> "$snapshot_manifest"
    else
        service --status-all > "$snapshot_path/services.sysv" 2>&1 && \
            echo "STATE|services-sysv" >> "$snapshot_manifest"
    fi

    # Network configuration
    ip addr show > "$snapshot_path/network.interfaces" 2>/dev/null && \
        echo "STATE|network-interfaces" >> "$snapshot_manifest"

    ip route show > "$snapshot_path/network.routes" 2>/dev/null && \
        echo "STATE|network-routes" >> "$snapshot_manifest"

    # Process list
    ps auxww > "$snapshot_path/processes.current" && \
        echo "STATE|processes" >> "$snapshot_manifest"

    # Open ports
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn > "$snapshot_path/ports.current" 2>/dev/null && \
            echo "STATE|ports" >> "$snapshot_manifest"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn > "$snapshot_path/ports.current" 2>/dev/null && \
            echo "STATE|ports" >> "$snapshot_manifest"
    fi

    # Record snapshot in main manifest
    echo "$(date +%Y-%m-%d-%H:%M:%S)|SNAPSHOT|$snapshot_id|$snapshot_path" >> "$BACKUP_MANIFEST"

    log "INFO" "System snapshot created: $snapshot_path"
    echo "$snapshot_id"
    return 0
}

# ============================================================================
# Restore Functions
# ============================================================================

# Restore a single file from backup
restore_file() {
    local backup_path="$1"
    local target_path="${2:-}"

    if [ ! -f "$backup_path" ]; then
        log "ERROR" "Backup file not found: $backup_path"
        return 1
    fi

    # Determine target path if not specified
    if [ -z "$target_path" ]; then
        # Try to extract original path from manifest
        if [ -f "$BACKUP_MANIFEST" ]; then
            target_path=$(grep "|$backup_path$" "$BACKUP_MANIFEST" | tail -1 | cut -d'|' -f3)
        fi

        if [ -z "$target_path" ]; then
            log "ERROR" "Cannot determine target path for restore"
            return 1
        fi
    fi

    # Backup current file if it exists
    if [ -f "$target_path" ]; then
        local temp_backup="${target_path}.restore-backup"
        cp -p "$target_path" "$temp_backup"
    fi

    # Restore file
    if cp -p "$backup_path" "$target_path"; then
        log "INFO" "Restored: $backup_path -> $target_path"

        # Verify checksum if available
        if [ -f "${backup_path}.sha256" ]; then
            local expected=$(cat "${backup_path}.sha256")
            local actual=$(sha256sum "$target_path" 2>/dev/null | cut -d' ' -f1)

            if [ "$expected" != "$actual" ]; then
                log "WARN" "Checksum mismatch after restore"
            fi
        fi

        # Remove temporary backup
        rm -f "$temp_backup"
        return 0
    else
        log "ERROR" "Failed to restore: $backup_path"

        # Restore from temporary backup if it exists
        if [ -f "$temp_backup" ]; then
            mv "$temp_backup" "$target_path"
        fi
        return 1
    fi
}

# Restore from system snapshot
restore_system_snapshot() {
    local snapshot_id="$1"
    local snapshot_path="$SNAPSHOT_DIR/$snapshot_id"
    local snapshot_manifest="$snapshot_path/manifest"

    if [ ! -d "$snapshot_path" ]; then
        log "ERROR" "Snapshot not found: $snapshot_id"
        return 1
    fi

    if [ ! -f "$snapshot_manifest" ]; then
        log "ERROR" "Snapshot manifest not found"
        return 1
    fi

    log "WARN" "Restoring system from snapshot: $snapshot_id"
    log "WARN" "This will overwrite current configuration!"

    # Confirmation in interactive mode
    if [ -t 0 ]; then
        printf "Are you sure you want to restore from snapshot? (yes/NO): "
        read -r response
        if [ "$response" != "yes" ]; then
            log "INFO" "Restore cancelled by user"
            return 1
        fi
    fi

    # Create backup of current state before restore
    local pre_restore_snapshot
    pre_restore_snapshot=$(create_system_snapshot "pre-restore-$(date +%Y%m%d-%H%M%S)")
    log "INFO" "Created pre-restore snapshot: $pre_restore_snapshot"

    # Process manifest and restore files
    while IFS='|' read -r type path; do
        case "$type" in
            FILE)
                if [ -f "$snapshot_path$path" ]; then
                    cp -p "$snapshot_path$path" "$path" && \
                        log "INFO" "Restored file: $path"
                fi
                ;;
            DIR)
                local tar_file="$snapshot_path${path}.tar"
                if [ -f "$tar_file" ]; then
                    tar -xpf "$tar_file" -C / && \
                        log "INFO" "Restored directory: $path"
                fi
                ;;
        esac
    done < "$snapshot_manifest"

    # Restore firewall rules
    if [ -f "$snapshot_path/iptables.rules" ]; then
        iptables-restore < "$snapshot_path/iptables.rules" 2>/dev/null && \
            log "INFO" "Restored iptables rules"
    fi

    if [ -f "$snapshot_path/ip6tables.rules" ]; then
        ip6tables-restore < "$snapshot_path/ip6tables.rules" 2>/dev/null && \
            log "INFO" "Restored ip6tables rules"
    fi

    # Reload affected services
    log "INFO" "Reloading services"

    # SSH
    if [ -f /etc/ssh/sshd_config ]; then
        safe_service_reload "ssh" || safe_service_reload "sshd"
    fi

    # Sysctl
    if [ -f /etc/sysctl.conf ]; then
        sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    fi

    log "INFO" "System restore completed from snapshot: $snapshot_id"
    return 0
}

# ============================================================================
# Backup Maintenance
# ============================================================================

# Clean old backups
cleanup_old_backups() {
    local retention_days="${1:-$BACKUP_RETENTION_DAYS}"

    log "INFO" "Cleaning backups older than $retention_days days"

    # Find and remove old backup files
    find "$BACKUP_DIR" -type f -name "*.bak" -mtime +"$retention_days" -exec rm {} \; 2>/dev/null
    find "$BACKUP_DIR" -type f -name "*.tar" -mtime +"$retention_days" -exec rm {} \; 2>/dev/null

    # Clean old snapshots
    find "$SNAPSHOT_DIR" -maxdepth 1 -type d -mtime +"$retention_days" -exec rm -rf {} \; 2>/dev/null

    # Clean manifest entries
    if [ -f "$BACKUP_MANIFEST" ]; then
        local temp_manifest="${BACKUP_MANIFEST}.tmp"
        local cutoff_date=$(date -d "$retention_days days ago" +%Y-%m-%d 2>/dev/null || \
                           date -v -"$retention_days"d +%Y-%m-%d 2>/dev/null)

        if [ -n "$cutoff_date" ]; then
            while IFS='|' read -r date type source backup; do
                if [ "$(echo "$date" | cut -d- -f1-3)" \> "$cutoff_date" ]; then
                    echo "$date|$type|$source|$backup" >> "$temp_manifest"
                fi
            done < "$BACKUP_MANIFEST"

            mv "$temp_manifest" "$BACKUP_MANIFEST"
        fi
    fi

    log "INFO" "Backup cleanup completed"
}

# List available backups
list_backups() {
    local filter="${1:-}"

    if [ ! -f "$BACKUP_MANIFEST" ]; then
        log "INFO" "No backups found"
        return 0
    fi

    echo "Available backups:"
    echo "=================="

    if [ -n "$filter" ]; then
        grep "$filter" "$BACKUP_MANIFEST" | while IFS='|' read -r date type source backup; do
            printf "%s | %s | %s\n" "$date" "$type" "$backup"
        done
    else
        while IFS='|' read -r date type source backup; do
            printf "%s | %s | %s\n" "$date" "$type" "$backup"
        done < "$BACKUP_MANIFEST"
    fi
}

# List available snapshots
list_snapshots() {
    if [ ! -d "$SNAPSHOT_DIR" ]; then
        log "INFO" "No snapshots found"
        return 0
    fi

    echo "Available snapshots:"
    echo "==================="

    for snapshot in "$SNAPSHOT_DIR"/*; do
        if [ -d "$snapshot" ]; then
            local id=$(basename "$snapshot")
            local date=$(stat -c %y "$snapshot" 2>/dev/null || stat -f %Sm "$snapshot" 2>/dev/null)
            printf "%s | %s\n" "$id" "$date"
        fi
    done
}

# ============================================================================
# Export Functions
# ============================================================================

#export -f generate_backup_name backup_file backup_directory
#export -f create_system_snapshot restore_file restore_system_snapshot
#export -f cleanup_old_backups list_backups list_snapshots