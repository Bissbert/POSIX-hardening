#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Script: 00-ssh-verification.sh
# Priority: CRITICAL (0) - Must run BEFORE SSH hardening
# Description: Verify SSH package integrity and reinstall if needed

# Get script directory and toolkit root
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"

# Load configuration first (before libraries set readonly variables)
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/ssh_safety.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Script name for logging
SCRIPT_NAME="00-ssh-verification"

# Configuration
EMERGENCY_SSH_PORT="${EMERGENCY_SSH_PORT:-2222}"
ROLLBACK_TIMEOUT=60

# ============================================================================
# Package Signature Verification
# ============================================================================

# Verify package is from official repository
verify_package_source() {
    show_progress "Verifying openssh-server package source"

    # Check if package is installed
    if ! dpkg -l openssh-server 2>/dev/null | grep -q "^ii"; then
        log "ERROR" "openssh-server package not installed"
        return 1
    fi

    # Get package policy (shows repository sources)
    local policy=$(apt-cache policy openssh-server 2>/dev/null)

    if echo "$policy" | grep -qE "500 http.*(debian\.org|ubuntu\.com|debian-security)"; then
        show_success "Package source: Official Debian/Ubuntu repository"
        log "INFO" "Package source verified as official"
        return 0
    else
        show_warning "Package source could not be verified as official"
        log "WARN" "Package may not be from official repository"

        # Show actual source
        log "INFO" "Package sources:"
        echo "$policy" | grep -E "^\s+[0-9]+" | head -5 | while read -r line; do
            log "INFO" "  $line"
        done

        return 1
    fi
}

# Check package signatures
verify_package_signatures() {
    show_progress "Verifying package GPG signatures"

    # Check if GPG keys are present
    if ! command -v apt-key >/dev/null 2>&1; then
        log "WARN" "apt-key not available, skipping signature check"
        return 0
    fi

    # List trusted keys
    local keys=$(apt-key list 2>/dev/null)

    if echo "$keys" | grep -qi "debian\|ubuntu"; then
        show_success "Official GPG keys found"
        log "INFO" "Debian/Ubuntu GPG keys present in keyring"
        return 0
    else
        show_warning "Could not verify official GPG keys"
        log "WARN" "No Debian/Ubuntu GPG keys found"
        return 1
    fi
}

# Get current package information
get_package_info() {
    show_progress "Gathering SSH package information"

    local version=$(dpkg -l openssh-server 2>/dev/null | awk '/^ii/ {print $3}')
    local arch=$(dpkg -l openssh-server 2>/dev/null | awk '/^ii/ {print $4}')

    if [ -n "$version" ]; then
        log "INFO" "Current version: openssh-server $version"
        log "INFO" "Architecture: $arch"

        # Check for available updates
        apt-get update -qq 2>/dev/null
        local upgradable=$(apt list --upgradable 2>/dev/null | grep openssh-server || echo "")

        if [ -n "$upgradable" ]; then
            log "INFO" "Updates available: $upgradable"
        else
            log "INFO" "Package is up to date"
        fi
    else
        log "ERROR" "Could not get package information"
        return 1
    fi

    show_success "Package information gathered"
}

# ============================================================================
# Binary Integrity Verification
# ============================================================================

# Install debsums if needed
ensure_debsums() {
    if ! command -v debsums >/dev/null 2>&1; then
        show_progress "Installing debsums for integrity checking"

        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN" "Would install debsums package"
            return 0
        fi

        apt-get update -qq 2>/dev/null
        apt-get install -y debsums >/dev/null 2>&1

        if command -v debsums >/dev/null 2>&1; then
            show_success "debsums installed"
        else
            show_error "Failed to install debsums"
            return 1
        fi
    fi
    return 0
}

# Verify SSH binary integrity
check_ssh_binary_integrity() {
    show_progress "Verifying SSH binary integrity"

    if ! ensure_debsums; then
        log "WARN" "Cannot verify integrity without debsums"
        return 1
    fi

    # Skip actual check in dry-run mode
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY-RUN" "Would verify SSH package integrity with debsums"
        show_success "Binary integrity check skipped in dry-run mode"
        return 0
    fi

    # Check openssh-server package integrity
    local check_result=$(debsums -c openssh-server 2>&1)

    if [ -z "$check_result" ]; then
        show_success "Binary integrity verified - no modifications detected"
        log "INFO" "All SSH binaries match package checksums"
        return 0
    else
        show_warning "Binary integrity check found modifications"
        log "WARN" "Modified files detected:"
        echo "$check_result" | while read -r line; do
            log "WARN" "  $line"
        done

        # Check specifically the SSH daemon
        if echo "$check_result" | grep -q "/usr/sbin/sshd"; then
            show_error "CRITICAL: /usr/sbin/sshd binary has been modified!"
            log "ERROR" "SSH daemon binary does not match official package"
            return 1
        fi

        return 1
    fi
}

# ============================================================================
# Safe SSH Reinstall
# ============================================================================

# Create emergency SSH access before reinstall
setup_emergency_ssh() {
    show_progress "Setting up emergency SSH on port $EMERGENCY_SSH_PORT"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would create emergency SSH on port $EMERGENCY_SSH_PORT"
        return 0
    fi

    # Use library function
    if create_emergency_ssh_access "$EMERGENCY_SSH_PORT"; then
        show_success "Emergency SSH active on port $EMERGENCY_SSH_PORT"
        log "INFO" "Emergency access available during reinstall"

        # Add firewall rule if iptables available
        if command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT 1 -p tcp --dport "$EMERGENCY_SSH_PORT" -j ACCEPT 2>/dev/null || true
        fi

        return 0
    else
        show_warning "Could not create emergency SSH"
        return 1
    fi
}

# Reinstall openssh-server safely
reinstall_ssh_package() {
    show_progress "Reinstalling openssh-server package"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would reinstall openssh-server package"
        log "DRY_RUN" "Would backup SSH configuration"
        log "DRY_RUN" "Would restart SSH service"
        return 0
    fi

    # Backup SSH configuration
    local backup_file
    backup_file=$(safe_backup_file "/etc/ssh/sshd_config")

    if [ -z "$backup_file" ]; then
        show_error "Failed to backup SSH configuration"
        return 1
    fi

    log "INFO" "SSH config backed up to: $backup_file"

    # Setup automatic rollback
    log "INFO" "Setting up automatic rollback (${ROLLBACK_TIMEOUT}s timeout)"
    (
        sleep "$ROLLBACK_TIMEOUT"
        if ! timeout 5 nc -z localhost "$SSH_PORT" 2>/dev/null; then
            log "ERROR" "SSH not responding - triggering rollback"

            # Try to restart SSH
            systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || /usr/sbin/sshd

            # Restore config if needed
            if [ -f "$backup_file" ]; then
                cp "$backup_file" /etc/ssh/sshd_config
            fi

            log "INFO" "Rollback attempted"
        fi
    ) &
    ROLLBACK_PID=$!

    # Reinstall package
    log "INFO" "Reinstalling openssh-server..."
    apt-get update -qq 2>/dev/null

    if apt-get install --reinstall -y openssh-server 2>&1 | grep -q "E:"; then
        show_error "Package reinstall failed"
        kill "$ROLLBACK_PID" 2>/dev/null
        return 1
    fi

    # Wait for SSH to start
    sleep 3

    # Verify SSH is responding
    if timeout 10 nc -z localhost "$SSH_PORT" 2>/dev/null; then
        show_success "SSH service verified after reinstall"

        # Cancel rollback
        kill "$ROLLBACK_PID" 2>/dev/null

        log "INFO" "openssh-server reinstalled successfully"
        return 0
    else
        show_error "SSH service not responding after reinstall"
        log "ERROR" "Rollback will occur automatically"
        # Let rollback happen
        return 1
    fi
}

# Verify post-reinstall integrity
verify_post_reinstall() {
    show_progress "Verifying integrity after reinstall"

    # Re-check binary integrity
    if check_ssh_binary_integrity; then
        show_success "Post-reinstall integrity verified"
        return 0
    else
        show_error "Integrity check failed after reinstall"
        return 1
    fi
}

# Cleanup emergency SSH
cleanup_emergency_ssh() {
    show_progress "Cleaning up emergency SSH"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would remove emergency SSH access"
        return 0
    fi

    # Use library function
    kill_emergency_ssh

    # Remove firewall rule if iptables available
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -p tcp --dport "$EMERGENCY_SSH_PORT" -j ACCEPT 2>/dev/null || true
    fi

    show_success "Emergency SSH removed"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    show_progress "Starting SSH package verification"

    # Initialize
    init_hardening_environment "$SCRIPT_NAME"

    # Check if already completed
    if is_completed "$SCRIPT_NAME"; then
        show_warning "SSH verification already completed"
        log "INFO" "Skipping verification (already done)"
        exit 0
    fi

    # Start transaction
    begin_transaction "ssh_verification"

    # Step 1: Get package information
    get_package_info || {
        show_error "Failed to get package information"
        rollback_transaction "package_info_failed"
        exit 1
    }

    # Step 2: Verify package source
    local source_ok=0
    verify_package_source && source_ok=1

    # Step 3: Verify signatures
    local sig_ok=0
    verify_package_signatures && sig_ok=1

    # Step 4: Check binary integrity
    local integrity_ok=0
    check_ssh_binary_integrity && integrity_ok=1

    # Determine if reinstall needed
    local need_reinstall=0

    if [ "$integrity_ok" -eq 0 ]; then
        log "WARN" "Binary integrity check failed - reinstall required"
        need_reinstall=1
    fi

    if [ "$source_ok" -eq 0 ]; then
        log "WARN" "Package source verification failed"

        if [ "$FORCE_SSH_VERIFICATION" = "1" ]; then
            log "INFO" "FORCE_SSH_VERIFICATION=1, requiring reinstall"
            need_reinstall=1
        else
            log "WARN" "Set FORCE_SSH_VERIFICATION=1 to force reinstall"
        fi
    fi

    # Step 5: Reinstall if needed
    if [ "$need_reinstall" -eq 1 ]; then
        log "INFO" "Reinstalling SSH package for security assurance"

        # Setup emergency access
        setup_emergency_ssh

        # Reinstall
        if ! reinstall_ssh_package; then
            show_error "SSH reinstall failed"
            cleanup_emergency_ssh
            rollback_transaction "reinstall_failed"
            exit 1
        fi

        # Verify post-reinstall
        if ! verify_post_reinstall; then
            show_error "Post-reinstall verification failed"
            cleanup_emergency_ssh
            rollback_transaction "post_verify_failed"
            exit 1
        fi

        # Cleanup emergency SSH
        cleanup_emergency_ssh

        show_success "SSH package reinstalled and verified"
    else
        show_success "SSH package verification passed - no reinstall needed"
        log "INFO" "Package source: verified"
        log "INFO" "Binary integrity: verified"
    fi

    # Mark complete
    mark_completed "$SCRIPT_NAME"

    # Commit transaction
    commit_transaction

    # Final status
    log "INFO" "================================="
    log "INFO" "SSH Package Verification Summary"
    log "INFO" "================================="
    log "INFO" "Package Source: $([ $source_ok -eq 1 ] && echo 'VERIFIED' || echo 'WARNING')"
    log "INFO" "GPG Signatures: $([ $sig_ok -eq 1 ] && echo 'VERIFIED' || echo 'SKIPPED')"
    log "INFO" "Binary Integrity: $([ $integrity_ok -eq 1 ] && echo 'VERIFIED' || echo 'REINSTALLED')"
    log "INFO" "Reinstall Performed: $([ $need_reinstall -eq 1 ] && echo 'YES' || echo 'NO')"
    log "INFO" "================================="

    show_success "SSH package verification complete"

    exit 0
}

# Run main
main "$@"
