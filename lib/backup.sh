#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/backup.sh - Comprehensive backup and restore system
# Ensures all changes can be reverted

# Note: common.sh should be sourced before this file
# common.sh sets BACKUP_DIR with fallback defaults if config file doesn't exist

# Backup configuration
readonly BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
readonly BACKUP_MANIFEST="$BACKUP_DIR/manifest"
readonly SNAPSHOT_DIR="$BACKUP_DIR/snapshots"

# Ensure backup directories exist
if ! mkdir -p "$BACKUP_DIR" "$SNAPSHOT_DIR" 2>/dev/null; then
    echo "ERROR: Cannot create backup directories: $BACKUP_DIR, $SNAPSHOT_DIR" >&2
    echo "Check permissions and parent directory exists" >&2
    # Don't exit here, as it might be in dry-run mode or will be created later
fi

# ============================================================================
# Backup Management
# ============================================================================

# Generate backup filename with timestamp
generate_backup_name() {
    _source_file="$1"
    _timestamp=$(date +%Y%m%d-%H%M%S)
    _basename=$(basename "$_source_file")

    echo "${_basename}.${_timestamp}.bak"
}

# Create backup of a single file
backup_file() {
    _source_file="$1"
    _backup_name="${2:-}"

    if [ ! -f "$_source_file" ]; then
        log "ERROR" "Source file does not exist: $_source_file"
        return 1
    fi

    # Generate backup name if not provided
    if [ -z "$_backup_name" ]; then
        _backup_name=$(generate_backup_name "$_source_file")
    fi

    _backup_path="$BACKUP_DIR/$_backup_name"

    # Create backup preserving all attributes
    if cp -p "$_source_file" "$_backup_path" 2>/dev/null; then
        # Record in manifest
        echo "$(date +%Y-%m-%d-%H:%M:%S)|FILE|$_source_file|$_backup_path" >> "$BACKUP_MANIFEST"

        # Store file metadata
        ls -la "$_source_file" > "${_backup_path}.meta"
        sha256sum "$_source_file" 2>/dev/null | cut -d' ' -f1 > "${_backup_path}.sha256"

        log "INFO" "Backed up: $_source_file -> $_backup_path"
        echo "$_backup_path"
        return 0
    else
        log "ERROR" "Failed to backup: $_source_file"
        return 1
    fi
}

# Create backup of a directory
backup_directory() {
    _source_dir="$1"
    _backup_name="${2:-}"

    if [ ! -d "$_source_dir" ]; then
        log "ERROR" "Source directory does not exist: $_source_dir"
        return 1
    fi

    # Generate backup name if not provided
    if [ -z "$_backup_name" ]; then
        _backup_name="$(basename "$_source_dir").$(date +%Y%m%d-%H%M%S).tar"
    fi

    _backup_path="$BACKUP_DIR/$_backup_name"

    # Create tar archive preserving permissions
    if tar -cpf "$_backup_path" -C "$(dirname "$_source_dir")" "$(basename "$_source_dir")" 2>/dev/null; then
        # Record in manifest
        echo "$(date +%Y-%m-%d-%H:%M:%S)|DIR|$_source_dir|$_backup_path" >> "$BACKUP_MANIFEST"

        log "INFO" "Backed up directory: $_source_dir -> $_backup_path"
        echo "$_backup_path"
        return 0
    else
        log "ERROR" "Failed to backup directory: $_source_dir"
        return 1
    fi
}

# ============================================================================
# System Snapshots
# ============================================================================

# Create comprehensive system snapshot
create_system_snapshot() {
    _snapshot_id="${1:-$(date +%Y%m%d-%H%M%S)}"
    _snapshot_path="$SNAPSHOT_DIR/$_snapshot_id"
    _snapshot_manifest="$_snapshot_path/manifest"

    log "INFO" "Creating system snapshot: $_snapshot_id"

    # Create snapshot directory
    mkdir -p "$_snapshot_path"

    # Start manifest
    cat > "$_snapshot_manifest" <<EOF
# System Snapshot: $_snapshot_id
# Date: $(date)
# Hostname: $(hostname)
# Kernel: $(uname -r)
EOF

    # Backup critical configuration files
    _configs="
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

    for _config in $_configs; do
        if [ -f "$_config" ]; then
            _dest_dir="$_snapshot_path$(dirname "$_config")"
            mkdir -p "$_dest_dir"
            cp -p "$_config" "$_dest_dir/" 2>/dev/null && \
                echo "FILE|$_config" >> "$_snapshot_manifest"
        fi
    done

    # Backup PAM configuration
    if [ -d /etc/pam.d ]; then
        mkdir -p "$_snapshot_path/etc"
        tar -cf "$_snapshot_path/etc/pam.d.tar" -C /etc pam.d 2>/dev/null && \
            echo "DIR|/etc/pam.d" >> "$_snapshot_manifest"
    fi

    # Backup network configuration
    if [ -d /etc/network ]; then
        mkdir -p "$_snapshot_path/etc"
        tar -cf "$_snapshot_path/etc/network.tar" -C /etc network 2>/dev/null && \
            echo "DIR|/etc/network" >> "$_snapshot_manifest"
    fi

    # Save current system state
    log "DEBUG" "Capturing system state"

    # Firewall rules
    if command -v iptables >/dev/null 2>&1; then
        iptables-save > "$_snapshot_path/iptables.rules" 2>/dev/null && \
            echo "STATE|iptables" >> "$_snapshot_manifest"
    fi

    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables-save > "$_snapshot_path/ip6tables.rules" 2>/dev/null && \
            echo "STATE|ip6tables" >> "$_snapshot_manifest"
    fi

    # Kernel parameters
    sysctl -a > "$_snapshot_path/sysctl.current" 2>/dev/null && \
        echo "STATE|sysctl" >> "$_snapshot_manifest"

    # Mount points
    mount > "$_snapshot_path/mount.current" && \
        echo "STATE|mount" >> "$_snapshot_manifest"

    # Running services
    if command -v systemctl >/dev/null 2>&1; then
        systemctl list-units --state=running > "$_snapshot_path/services.systemd" && \
            echo "STATE|services-systemd" >> "$_snapshot_manifest"
    else
        service --status-all > "$_snapshot_path/services.sysv" 2>&1 && \
            echo "STATE|services-sysv" >> "$_snapshot_manifest"
    fi

    # Network configuration
    ip addr show > "$_snapshot_path/network.interfaces" 2>/dev/null && \
        echo "STATE|network-interfaces" >> "$_snapshot_manifest"

    ip route show > "$_snapshot_path/network.routes" 2>/dev/null && \
        echo "STATE|network-routes" >> "$_snapshot_manifest"

    # Process list
    ps auxww > "$_snapshot_path/processes.current" && \
        echo "STATE|processes" >> "$_snapshot_manifest"

    # Open ports
    if command -v ss >/dev/null 2>&1; then
        ss -tulpn > "$_snapshot_path/ports.current" 2>/dev/null && \
            echo "STATE|ports" >> "$_snapshot_manifest"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulpn > "$_snapshot_path/ports.current" 2>/dev/null && \
            echo "STATE|ports" >> "$_snapshot_manifest"
    fi

    # Record snapshot in main manifest
    echo "$(date +%Y-%m-%d-%H:%M:%S)|SNAPSHOT|$_snapshot_id|$_snapshot_path" >> "$BACKUP_MANIFEST"

    log "INFO" "System snapshot created: $_snapshot_path"
    echo "$_snapshot_id"
    return 0
}

# ============================================================================
# Restore Functions
# ============================================================================

# Restore a single file from backup
restore_file() {
    _backup_path="$1"
    _target_path="${2:-}"

    if [ ! -f "$_backup_path" ]; then
        log "ERROR" "Backup file not found: $_backup_path"
        return 1
    fi

    # Determine target path if not specified
    if [ -z "$_target_path" ]; then
        # Try to extract original path from manifest
        if [ -f "$BACKUP_MANIFEST" ]; then
            _target_path=$(grep "|$_backup_path$" "$BACKUP_MANIFEST" | tail -1 | cut -d'|' -f3)
        fi

        if [ -z "$_target_path" ]; then
            log "ERROR" "Cannot determine target path for restore"
            return 1
        fi
    fi

    # Backup current file if it exists
    if [ -f "$_target_path" ]; then
        _temp_backup="${_target_path}.restore-backup"
        cp -p "$_target_path" "$_temp_backup"
    fi

    # Restore file
    if cp -p "$_backup_path" "$_target_path"; then
        log "INFO" "Restored: $_backup_path -> $_target_path"

        # Verify checksum if available
        if [ -f "${_backup_path}.sha256" ]; then
            _expected=$(cat "${_backup_path}.sha256")
            _actual=$(sha256sum "$_target_path" 2>/dev/null | cut -d' ' -f1)

            if [ "$_expected" != "$_actual" ]; then
                log "WARN" "Checksum mismatch after restore"
            fi
        fi

        # Remove temporary backup
        rm -f "$_temp_backup"
        return 0
    else
        log "ERROR" "Failed to restore: $_backup_path"

        # Restore from temporary backup if it exists
        if [ -f "$_temp_backup" ]; then
            mv "$_temp_backup" "$_target_path"
        fi
        return 1
    fi
}

# Restore from system snapshot
restore_system_snapshot() {
    _snapshot_id="$1"
    _snapshot_path="$SNAPSHOT_DIR/$_snapshot_id"
    _snapshot_manifest="$_snapshot_path/manifest"

    if [ ! -d "$_snapshot_path" ]; then
        log "ERROR" "Snapshot not found: $_snapshot_id"
        return 1
    fi

    if [ ! -f "$_snapshot_manifest" ]; then
        log "ERROR" "Snapshot manifest not found"
        return 1
    fi

    log "WARN" "Restoring system from snapshot: $_snapshot_id"
    log "WARN" "This will overwrite current configuration!"

    # Confirmation in interactive mode
    if [ -t 0 ]; then
        printf "Are you sure you want to restore from snapshot? (yes/NO): "
        read -r _response
        if [ "$_response" != "yes" ]; then
            log "INFO" "Restore cancelled by user"
            return 1
        fi
    fi

    # Create backup of current state before restore
    _pre_restore_snapshot=$(create_system_snapshot "pre-restore-$(date +%Y%m%d-%H%M%S)")
    log "INFO" "Created pre-restore snapshot: $_pre_restore_snapshot"

    # Process manifest and restore files
    while IFS='|' read -r _type _path; do
        case "$_type" in
            FILE)
                if [ -f "$_snapshot_path$_path" ]; then
                    cp -p "$_snapshot_path$_path" "$_path" && \
                        log "INFO" "Restored file: $_path"
                fi
                ;;
            DIR)
                _tar_file="$_snapshot_path${_path}.tar"
                if [ -f "$_tar_file" ]; then
                    tar -xpf "$_tar_file" -C / && \
                        log "INFO" "Restored directory: $_path"
                fi
                ;;
        esac
    done < "$_snapshot_manifest"

    # Restore firewall rules
    if [ -f "$_snapshot_path/iptables.rules" ]; then
        iptables-restore < "$_snapshot_path/iptables.rules" 2>/dev/null && \
            log "INFO" "Restored iptables rules"
    fi

    if [ -f "$_snapshot_path/ip6tables.rules" ]; then
        ip6tables-restore < "$_snapshot_path/ip6tables.rules" 2>/dev/null && \
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

    log "INFO" "System restore completed from snapshot: $_snapshot_id"
    return 0
}

# ============================================================================
# Backup Maintenance
# ============================================================================

# Clean old backups
cleanup_old_backups() {
    _retention_days="${1:-$BACKUP_RETENTION_DAYS}"

    log "INFO" "Cleaning backups older than $_retention_days days"

    # Find and remove old backup files
    find "$BACKUP_DIR" -type f -name "*.bak" -mtime +"$_retention_days" -exec rm {} \; 2>/dev/null
    find "$BACKUP_DIR" -type f -name "*.tar" -mtime +"$_retention_days" -exec rm {} \; 2>/dev/null

    # Clean old snapshots
    find "$SNAPSHOT_DIR" -maxdepth 1 -type d -mtime +"$_retention_days" -exec rm -rf {} \; 2>/dev/null

    # Clean manifest entries
    if [ -f "$BACKUP_MANIFEST" ]; then
        _temp_manifest="${BACKUP_MANIFEST}.tmp"
        _cutoff_date=$(date -d "$_retention_days days ago" +%Y-%m-%d 2>/dev/null || \
                       date -v -"$_retention_days"d +%Y-%m-%d 2>/dev/null)

        if [ -n "$_cutoff_date" ]; then
            while IFS='|' read -r _date _type _source _backup; do
                if [ "$(echo "$_date" | cut -d- -f1-3)" \> "$_cutoff_date" ]; then
                    echo "$_date|$_type|$_source|$_backup" >> "$_temp_manifest"
                fi
            done < "$BACKUP_MANIFEST"

            mv "$_temp_manifest" "$BACKUP_MANIFEST"
        fi
    fi

    log "INFO" "Backup cleanup completed"
}

# List available backups
list_backups() {
    _filter="${1:-}"

    if [ ! -f "$BACKUP_MANIFEST" ]; then
        log "INFO" "No backups found"
        return 0
    fi

    echo "Available backups:"
    echo "=================="

    if [ -n "$_filter" ]; then
        grep "$_filter" "$BACKUP_MANIFEST" | while IFS='|' read -r _date _type _source _backup; do
            printf "%s | %s | %s\n" "$_date" "$_type" "$_backup"
        done
    else
        while IFS='|' read -r _date _type _source _backup; do
            printf "%s | %s | %s\n" "$_date" "$_type" "$_backup"
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

    for _snapshot in "$SNAPSHOT_DIR"/*; do
        if [ -d "$_snapshot" ]; then
            _id=$(basename "$_snapshot")
            _date=$(stat -c %y "$_snapshot" 2>/dev/null || stat -f %Sm "$_snapshot" 2>/dev/null)
            printf "%s | %s\n" "$_id" "$_date"
        fi
    done
}

# ============================================================================
# Export Functions
# ============================================================================

#export -f generate_backup_name backup_file backup_directory
#export -f create_system_snapshot restore_file restore_system_snapshot
#export -f cleanup_old_backups list_backups list_snapshots
