#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/common.sh - Core functions and logging
# Compatible with: Debian-based systems using POSIX sh
# Safety: Never modifies system without validation

set -e

# Global configuration with safe defaults
readonly VERSION="1.0.0"
readonly TOOLKIT_NAME="POSIX-hardening"

# Safety flags - can be overridden by environment
readonly SAFETY_MODE="${SAFETY_MODE:-1}"
readonly DRY_RUN="${DRY_RUN:-0}"
readonly BACKUP_BEFORE_CHANGE="${BACKUP_BEFORE_CHANGE:-1}"
readonly FAIL_FAST="${FAIL_FAST:-1}"
readonly VERBOSE="${VERBOSE:-0}"

# Critical paths
readonly SSH_PORT="${SSH_PORT:-22}"
readonly ADMIN_IP="${ADMIN_IP:-}"
readonly BACKUP_DIR="${BACKUP_DIR:-/var/backups/hardening}"
readonly LOG_DIR="${LOG_DIR:-/var/log/hardening}"
readonly STATE_DIR="${STATE_DIR:-/var/lib/hardening}"

# Create required directories
for dir in "$BACKUP_DIR" "$LOG_DIR" "$STATE_DIR"; do
    [ ! -d "$dir" ] && mkdir -p "$dir"
done

# Log file with timestamp
readonly LOG_FILE="${LOG_FILE:-$LOG_DIR/hardening-$(date +%Y%m%d-%H%M%S).log}"

# Color codes for terminal output (disabled if not tty)
if [ -t 1 ]; then
    readonly RED=$(printf '\033[31m')
    readonly GREEN=$(printf '\033[32m')
    readonly YELLOW=$(printf '\033[33m')
    readonly BLUE=$(printf '\033[34m')
    readonly RESET=$(printf '\033[0m')
else
    readonly RED=""
    readonly GREEN=""
    readonly YELLOW=""
    readonly BLUE=""
    readonly RESET=""
fi

# ============================================================================
# Core Logging Functions
# ============================================================================

# Log message with severity level
log() {
    level="$1"
    shift
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[$timestamp] [$level] $*" >> "$LOG_FILE"

    # Log to stdout with colors
    case "$level" in
        ERROR)
            printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
            ;;
        WARN)
            printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
            ;;
        INFO)
            printf "${GREEN}[INFO]${RESET} %s\n" "$*"
            ;;
        DEBUG)
            if [ "$VERBOSE" = "1" ]; then
                printf "${BLUE}[DEBUG]${RESET} %s\n" "$*"
            fi
            ;;
        DRY_RUN)
            printf "${YELLOW}[DRY-RUN]${RESET} %s\n" "$*"
            ;;
        *)
            echo "[$level] $*"
            ;;
    esac
}

# Log error and exit
die() {
    log "ERROR" "$*"
    exit 1
}

# ============================================================================
# System Validation Functions
# ============================================================================

# Check if running as root
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root or with sudo"
    fi
}

# Validate we're on a Debian-based system
validate_debian() {
    if [ ! -f /etc/debian_version ]; then
        log "WARN" "This system does not appear to be Debian-based"
        printf "Continue anyway? (y/N): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log "WARN" "Continuing on non-Debian system at user request"
                ;;
            *)
                die "Aborting: System is not Debian-based"
                ;;
        esac
    fi
}

# Check for required commands
check_requirements() {
    missing=""
    for cmd in awk sed grep cp mv mkdir chmod chown cat; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        die "Required commands not found:$missing"
    fi
}

# Check disk space (needs at least 100MB for backups)
check_disk_space() {
    available=$(df "$BACKUP_DIR" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -z "$available" ]; then
        log "WARN" "Could not determine available disk space"
    elif [ "$available" -lt 102400 ]; then
        die "Insufficient disk space for backups (need 100MB, have ${available}KB)"
    fi
}

# ============================================================================
# SSH Connection Validation
# ============================================================================

# Verify SSH connection is still alive (critical for remote servers)
verify_ssh_alive() {
    # Method 1: Check if we're in an SSH session
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        log "DEBUG" "SSH session detected: connection appears alive"
        return 0
    fi

    # Method 2: Check if sshd is running
    if pgrep -x sshd >/dev/null 2>&1; then
        log "DEBUG" "SSH daemon is running"
        return 0
    fi

    # Method 3: Check if we can connect to localhost SSH
    if command -v ssh >/dev/null 2>&1; then
        if timeout 5 sh -c "echo '' | nc localhost $SSH_PORT" >/dev/null 2>&1; then
            log "DEBUG" "SSH port $SSH_PORT is responding"
            return 0
        fi
    fi

    # If we're not in SSH and SSH isn't running, we're probably on console
    if [ -z "$SSH_CONNECTION" ] && [ -z "$SSH_CLIENT" ]; then
        log "DEBUG" "Running from console (not SSH)"
        return 0
    fi

    log "WARN" "Could not verify SSH connectivity"
    return 1
}

# Ensure we don't lock ourselves out
preserve_admin_access() {
    if [ -n "$ADMIN_IP" ]; then
        log "INFO" "Preserving admin access from IP: $ADMIN_IP"

        # Add firewall exception if iptables exists
        if command -v iptables >/dev/null 2>&1; then
            # Check if rule already exists
            if ! iptables -C INPUT -s "$ADMIN_IP" -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null; then
                iptables -I INPUT 1 -s "$ADMIN_IP" -p tcp --dport "$SSH_PORT" -j ACCEPT
                log "INFO" "Added firewall exception for admin IP"
            fi
        fi
    fi
}

# ============================================================================
# File Operations with Safety
# ============================================================================

# Safe file backup before modification
safe_backup_file() {
    source_file="$1"

    if [ ! -f "$source_file" ]; then
        log "ERROR" "File not found for backup: $source_file"
        return 1
    fi

    # Create backup with timestamp
    backup_name="$(basename "$source_file").$(date +%Y%m%d-%H%M%S).bak"
    backup_path="$BACKUP_DIR/$backup_name"

    # Preserve permissions and ownership
    cp -p "$source_file" "$backup_path"

    if [ -f "$backup_path" ]; then
        log "INFO" "Backed up $source_file to $backup_path"
        echo "$backup_path"
        return 0
    else
        log "ERROR" "Failed to create backup: $backup_path"
        return 1
    fi
}

# Safe file modification with automatic backup
safe_modify_file() {
    target_file="$1"

    # Check if file exists
    if [ ! -f "$target_file" ]; then
        log "ERROR" "Target file does not exist: $target_file"
        return 1
    fi

    # Create backup if enabled
    if [ "$BACKUP_BEFORE_CHANGE" = "1" ]; then
        backup_path=$(safe_backup_file "$target_file")
        if [ -z "$backup_path" ]; then
            die "Failed to backup file before modification: $target_file"
        fi
        echo "$backup_path"
    fi

    return 0
}

# Check if a file has been modified
file_modified() {
    file="$1"
    original_hash="$2"

    if [ ! -f "$file" ]; then
        return 1
    fi

    current_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)

    if [ "$original_hash" = "$current_hash" ]; then
        return 1  # Not modified
    else
        return 0  # Modified
    fi
}

# ============================================================================
# Configuration State Management
# ============================================================================

# Save current state of a configuration item
save_state() {
    key="$1"
    value="$2"
    state_file="$STATE_DIR/current_state"

    # Remove old entry if exists
    if [ -f "$state_file" ]; then
        grep -v "^$key=" "$state_file" > "${state_file}.tmp" 2>/dev/null || true
        mv "${state_file}.tmp" "$state_file"
    fi

    # Add new entry
    echo "${key}=${value}" >> "$state_file"
    log "DEBUG" "Saved state: ${key}=${value}"
}

# Get saved state of a configuration item
get_state() {
    key="$1"
    state_file="$STATE_DIR/current_state"

    if [ -f "$state_file" ]; then
        grep "^$key=" "$state_file" 2>/dev/null | cut -d'=' -f2-
    fi
}

# Check if a hardening step has been completed
is_completed() {
    script_name="$1"
    completion_file="$STATE_DIR/completed"

    if [ -f "$completion_file" ]; then
        grep -q "^$script_name$" "$completion_file" 2>/dev/null
    else
        return 1
    fi
}

# Mark a hardening step as completed
mark_completed() {
    script_name="$1"
    completion_file="$STATE_DIR/completed"

    if ! is_completed "$script_name"; then
        echo "$script_name" >> "$completion_file"
        log "INFO" "Marked as completed: $script_name"
    fi
}

# ============================================================================
# Service Management
# ============================================================================

# Safely restart a service
safe_service_restart() {
    service_name="$1"

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^$service_name"; then
        if ! service "$service_name" status >/dev/null 2>&1; then
            log "WARN" "Service not found: $service_name"
            return 1
        fi
    fi

    log "INFO" "Restarting service: $service_name"

    # Try systemctl first (systemd)
    if command -v systemctl >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN" "Would restart: systemctl restart $service_name"
        else
            systemctl restart "$service_name"
        fi
    # Fall back to service command (SysV init)
    elif command -v service >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN" "Would restart: service $service_name restart"
        else
            service "$service_name" restart
        fi
    else
        log "ERROR" "No service management command available"
        return 1
    fi
}

# Reload a service configuration
safe_service_reload() {
    service_name="$1"

    log "INFO" "Reloading service: $service_name"

    if command -v systemctl >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN" "Would reload: systemctl reload $service_name"
        else
            systemctl reload "$service_name" 2>/dev/null || systemctl restart "$service_name"
        fi
    elif command -v service >/dev/null 2>&1; then
        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN" "Would reload: service $service_name reload"
        else
            service "$service_name" reload 2>/dev/null || service "$service_name" restart
        fi
    fi
}

# ============================================================================
# Dry Run Support
# ============================================================================

# Execute command or simulate in dry run mode
execute_or_simulate() {
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN" "Would execute: $*"
        return 0
    else
        log "DEBUG" "Executing: $*"
        "$@"
        return $?
    fi
}

# ============================================================================
# Progress Tracking
# ============================================================================

# Show progress message
show_progress() {
    message="$1"
    printf "\n${BLUE}==>${RESET} %s\n" "$message"
    log "INFO" "$message"
}

# Show success message
show_success() {
    message="$1"
    printf "${GREEN}✓${RESET} %s\n" "$message"
    log "INFO" "SUCCESS: $message"
}

# Show warning message
show_warning() {
    message="$1"
    printf "${YELLOW}⚠${RESET} %s\n" "$message"
    log "WARN" "$message"
}

# Show error message
show_error() {
    message="$1"
    printf "${RED}✗${RESET} %s\n" "$message" >&2
    log "ERROR" "$message"
}

# ============================================================================
# Initialize Environment
# ============================================================================

# Standard initialization for all scripts
init_hardening_environment() {
    script_name="${1:-unknown}"

    # Log script start
    log "INFO" "="
    log "INFO" "Starting: $script_name (v$VERSION)"
    log "INFO" "Timestamp: $(date)"
    log "INFO" "Hostname: $(hostname)"
    log "INFO" "User: $(whoami)"
    log "INFO" "="

    # Check basic requirements
    require_root
    check_requirements
    check_disk_space

    # Validate environment
    if [ "$SAFETY_MODE" = "1" ]; then
        validate_debian
        verify_ssh_alive || die "SSH connection verification failed - aborting for safety"
        preserve_admin_access
    fi

    # Show mode
    if [ "$DRY_RUN" = "1" ]; then
        show_warning "Running in DRY-RUN mode - no changes will be made"
    fi

    if [ "$VERBOSE" = "1" ]; then
        log "INFO" "Verbose mode enabled"
    fi

    # Trap for cleanup on exit
    trap cleanup_on_exit EXIT INT TERM
}

# Cleanup function called on exit
cleanup_on_exit() {
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log "INFO" "Script completed successfully"
    else
        log "ERROR" "Script failed with exit code: $exit_code"
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

# Make functions available to sourcing scripts
#export -f log die require_root validate_debian check_requirements
#export -f check_disk_space verify_ssh_alive preserve_admin_access
#export -f safe_backup_file safe_modify_file file_modified
#export -f save_state get_state is_completed mark_completed
#export -f safe_service_restart safe_service_reload execute_or_simulate
#export -f show_progress show_success show_warning show_error
#export -f init_hardening_environment cleanup_on_exit