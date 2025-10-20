#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/rollback.sh - Transaction-based rollback system
# Provides atomic operations with automatic rollback on failure

# Note: common.sh should be sourced before this file

# Rollback configuration
readonly ROLLBACK_STACK="$STATE_DIR/rollback_stack"
readonly ROLLBACK_LOG="$LOG_DIR/rollback.log"
readonly TRANSACTION_ID_FILE="$STATE_DIR/current_transaction"

# Global rollback state
# Read from config file only (no fallback)
ROLLBACK_ENABLED="${ROLLBACK_ENABLED}"
CURRENT_TRANSACTION=""
ROLLBACK_PID=""

# ============================================================================
# Transaction Management
# ============================================================================

# Start a new transaction
begin_transaction() {
    local transaction_name="${1:-unnamed}"
    CURRENT_TRANSACTION="$(date +%Y%m%d-%H%M%S)-$$-$transaction_name"

    # Clear previous rollback stack
    > "$ROLLBACK_STACK"

    # Record transaction start
    echo "$CURRENT_TRANSACTION" > "$TRANSACTION_ID_FILE"

    log "INFO" "Started transaction: $CURRENT_TRANSACTION ($transaction_name)"
    echo "$(date)|BEGIN|$CURRENT_TRANSACTION|$transaction_name" >> "$ROLLBACK_LOG"

    # Set up exit trap for automatic rollback
    trap 'transaction_cleanup' EXIT INT TERM

    return 0
}

# Commit current transaction
commit_transaction() {
    if [ -z "$CURRENT_TRANSACTION" ]; then
        log "WARN" "No active transaction to commit"
        return 1
    fi

    log "INFO" "Committing transaction: $CURRENT_TRANSACTION"
    echo "$(date)|COMMIT|$CURRENT_TRANSACTION" >> "$ROLLBACK_LOG"

    # Clear rollback stack
    > "$ROLLBACK_STACK"

    # Clear transaction ID
    > "$TRANSACTION_ID_FILE"

    # Remove exit trap
    trap - EXIT INT TERM

    CURRENT_TRANSACTION=""
    return 0
}

# Rollback current transaction
rollback_transaction() {
    local reason="${1:-manual rollback}"

    if [ -z "$CURRENT_TRANSACTION" ] && [ ! -f "$ROLLBACK_STACK" ]; then
        log "WARN" "No active transaction to rollback"
        return 1
    fi

    log "WARN" "Rolling back transaction: $CURRENT_TRANSACTION (reason: $reason)"
    echo "$(date)|ROLLBACK|$CURRENT_TRANSACTION|$reason" >> "$ROLLBACK_LOG"

    # Execute rollback actions in reverse order
    if [ -f "$ROLLBACK_STACK" ] && [ -s "$ROLLBACK_STACK" ]; then
        local temp_stack="${ROLLBACK_STACK}.processing"
        mv "$ROLLBACK_STACK" "$temp_stack"

        # Read stack in reverse order
        tac "$temp_stack" 2>/dev/null || tail -r "$temp_stack" 2>/dev/null | while IFS='|' read -r action_type action_data; do
            execute_rollback_action "$action_type" "$action_data"
        done

        rm -f "$temp_stack"
    fi

    # Clear transaction state
    > "$ROLLBACK_STACK"
    > "$TRANSACTION_ID_FILE"
    CURRENT_TRANSACTION=""

    log "INFO" "Rollback completed"
    return 0
}

# Transaction cleanup (called on exit)
transaction_cleanup() {
    local exit_code=$?

    if [ -n "$CURRENT_TRANSACTION" ]; then
        if [ $exit_code -ne 0 ] && [ "$ROLLBACK_ENABLED" = "1" ]; then
            log "ERROR" "Transaction failed with exit code $exit_code - initiating rollback"
            rollback_transaction "exit_code_$exit_code"
        elif [ $exit_code -eq 0 ]; then
            commit_transaction
        fi
    fi
}

# ============================================================================
# Rollback Action Registration
# ============================================================================

# Register a rollback action
register_rollback() {
    local action_type="$1"
    local action_data="$2"

    if [ -z "$action_type" ] || [ -z "$action_data" ]; then
        log "ERROR" "Invalid rollback registration: type=$action_type data=$action_data"
        return 1
    fi

    echo "${action_type}|${action_data}" >> "$ROLLBACK_STACK"
    log "DEBUG" "Registered rollback: $action_type - $action_data"

    return 0
}

# Register file restore action
register_file_rollback() {
    local original_file="$1"
    local backup_file="$2"

    register_rollback "FILE_RESTORE" "${backup_file}:${original_file}"
}

# Register command rollback action
register_command_rollback() {
    local rollback_command="$1"

    register_rollback "COMMAND" "$rollback_command"
}

# Register service rollback action
register_service_rollback() {
    local service_name="$1"
    local action="$2"  # start, stop, restart, reload

    register_rollback "SERVICE" "${service_name}:${action}"
}

# Register firewall rule rollback
register_firewall_rollback() {
    local rule="$1"

    register_rollback "FIREWALL" "$rule"
}

# Register sysctl rollback
register_sysctl_rollback() {
    local parameter="$1"
    local original_value="$2"

    register_rollback "SYSCTL" "${parameter}:${original_value}"
}

# ============================================================================
# Rollback Action Execution
# ============================================================================

# Execute a rollback action
execute_rollback_action() {
    local action_type="$1"
    local action_data="$2"

    log "DEBUG" "Executing rollback action: $action_type"

    case "$action_type" in
        FILE_RESTORE)
            # Restore file from backup
            local backup_file="${action_data%:*}"
            local original_file="${action_data#*:}"

            if [ -f "$backup_file" ]; then
                cp -p "$backup_file" "$original_file" && \
                    log "INFO" "Restored file: $original_file"
            else
                log "ERROR" "Backup file not found: $backup_file"
            fi
            ;;

        COMMAND)
            # Execute rollback command
            log "DEBUG" "Executing rollback command: $action_data"
            eval "$action_data" || \
                log "ERROR" "Rollback command failed: $action_data"
            ;;

        SERVICE)
            # Manage service
            local service_name="${action_data%:*}"
            local action="${action_data#*:}"

            case "$action" in
                start|stop|restart|reload)
                    safe_service_${action} "$service_name" || \
                        log "ERROR" "Failed to $action service: $service_name"
                    ;;
                *)
                    log "ERROR" "Unknown service action: $action"
                    ;;
            esac
            ;;

        FIREWALL)
            # Restore firewall rule
            if command -v iptables >/dev/null 2>&1; then
                eval "$action_data" || \
                    log "ERROR" "Failed to restore firewall rule"
            fi
            ;;

        SYSCTL)
            # Restore sysctl parameter
            local parameter="${action_data%:*}"
            local value="${action_data#*:}"

            sysctl -w "$parameter=$value" >/dev/null 2>&1 || \
                log "ERROR" "Failed to restore sysctl: $parameter=$value"
            ;;

        *)
            log "ERROR" "Unknown rollback action type: $action_type"
            ;;
    esac
}

# ============================================================================
# Atomic Operations
# ============================================================================

# Execute operation with automatic rollback on failure
atomic_operation() {
    local operation="$1"
    local rollback="$2"
    local description="${3:-operation}"

    log "DEBUG" "Atomic operation: $description"

    # Register rollback first
    if [ -n "$rollback" ]; then
        register_command_rollback "$rollback"
    fi

    # Execute operation
    if eval "$operation"; then
        log "DEBUG" "Operation succeeded: $description"
        return 0
    else
        log "ERROR" "Operation failed: $description"

        # Execute rollback if not in transaction
        if [ -z "$CURRENT_TRANSACTION" ] && [ -n "$rollback" ]; then
            log "INFO" "Executing immediate rollback"
            eval "$rollback"
        fi

        return 1
    fi
}

# Atomic file update
atomic_file_update() {
    local target_file="$1"
    local update_function="$2"

    if [ ! -f "$target_file" ]; then
        log "ERROR" "Target file does not exist: $target_file"
        return 1
    fi

    # Create backup
    local backup_file
    backup_file=$(safe_backup_file "$target_file")

    if [ -z "$backup_file" ]; then
        log "ERROR" "Failed to backup file: $target_file"
        return 1
    fi

    # Register rollback
    register_file_rollback "$target_file" "$backup_file"

    # Create working copy
    local work_file="${target_file}.work"
    cp -p "$target_file" "$work_file"

    # Apply updates to working copy
    if $update_function "$work_file"; then
        # Move working copy to target
        mv "$work_file" "$target_file"
        log "INFO" "Updated file: $target_file"
        return 0
    else
        # Clean up working copy
        rm -f "$work_file"
        log "ERROR" "Failed to update file: $target_file"
        return 1
    fi
}

# ============================================================================
# Checkpoint System
# ============================================================================

# Create a checkpoint in the current transaction
create_checkpoint() {
    local checkpoint_name="${1:-checkpoint}"
    local checkpoint_file="$STATE_DIR/checkpoint_${CURRENT_TRANSACTION}_${checkpoint_name}"

    if [ -z "$CURRENT_TRANSACTION" ]; then
        log "ERROR" "No active transaction for checkpoint"
        return 1
    fi

    # Save current rollback stack
    cp "$ROLLBACK_STACK" "$checkpoint_file"

    log "DEBUG" "Created checkpoint: $checkpoint_name"
    return 0
}

# Rollback to a checkpoint
rollback_to_checkpoint() {
    local checkpoint_name="${1:-checkpoint}"
    local checkpoint_file="$STATE_DIR/checkpoint_${CURRENT_TRANSACTION}_${checkpoint_name}"

    if [ ! -f "$checkpoint_file" ]; then
        log "ERROR" "Checkpoint not found: $checkpoint_name"
        return 1
    fi

    # Get actions added after checkpoint
    local temp_actions="${ROLLBACK_STACK}.temp"
    comm -13 "$checkpoint_file" "$ROLLBACK_STACK" > "$temp_actions" 2>/dev/null

    # Execute rollback for actions after checkpoint
    if [ -s "$temp_actions" ]; then
        tac "$temp_actions" 2>/dev/null || tail -r "$temp_actions" 2>/dev/null | while IFS='|' read -r action_type action_data; do
            execute_rollback_action "$action_type" "$action_data"
        done
    fi

    # Restore checkpoint stack
    cp "$checkpoint_file" "$ROLLBACK_STACK"

    rm -f "$temp_actions"
    log "INFO" "Rolled back to checkpoint: $checkpoint_name"
    return 0
}

# ============================================================================
# Safety Wrappers
# ============================================================================

# Wrapper for file modifications with rollback
safe_file_operation() {
    local file="$1"
    local operation="$2"

    begin_transaction "file_${file}"

    if atomic_file_update "$file" "$operation"; then
        commit_transaction
        return 0
    else
        rollback_transaction "file_operation_failed"
        return 1
    fi
}

# Wrapper for service changes with rollback
safe_service_operation() {
    local service="$1"
    local operation="$2"

    begin_transaction "service_${service}"

    # Get current service state
    local current_state="stopped"
    if systemctl is-active "$service" >/dev/null 2>&1 || \
       service "$service" status >/dev/null 2>&1; then
        current_state="running"
    fi

    # Register rollback to restore original state
    if [ "$current_state" = "running" ]; then
        register_service_rollback "$service" "start"
    else
        register_service_rollback "$service" "stop"
    fi

    # Execute operation
    if eval "$operation"; then
        commit_transaction
        return 0
    else
        rollback_transaction "service_operation_failed"
        return 1
    fi
}

# ============================================================================
# Rollback History and Recovery
# ============================================================================

# Show rollback history
show_rollback_history() {
    local limit="${1:-20}"

    if [ ! -f "$ROLLBACK_LOG" ]; then
        log "INFO" "No rollback history found"
        return 0
    fi

    echo "Recent Rollback History:"
    echo "========================"
    tail -n "$limit" "$ROLLBACK_LOG" | while IFS='|' read -r date action transaction reason; do
        printf "%s | %-8s | %s\n" "$date" "$action" "$transaction"
        if [ -n "$reason" ]; then
            printf "    Reason: %s\n" "$reason"
        fi
    done
}

# Clean up old transaction files
cleanup_transactions() {
    local days="${1:-7}"

    log "INFO" "Cleaning up transaction files older than $days days"

    # Clean checkpoint files
    find "$STATE_DIR" -name "checkpoint_*" -mtime +"$days" -exec rm {} \; 2>/dev/null

    # Clean old rollback logs
    if [ -f "$ROLLBACK_LOG" ]; then
        local temp_log="${ROLLBACK_LOG}.tmp"
        local cutoff_date=$(date -d "$days days ago" +%Y-%m-%d 2>/dev/null || \
                           date -v -"$days"d +%Y-%m-%d 2>/dev/null)

        if [ -n "$cutoff_date" ]; then
            while IFS='|' read -r date action transaction reason; do
                if [ "$(echo "$date" | cut -d' ' -f1)" \> "$cutoff_date" ]; then
                    echo "${date}|${action}|${transaction}|${reason}" >> "$temp_log"
                fi
            done < "$ROLLBACK_LOG"

            mv "$temp_log" "$ROLLBACK_LOG"
        fi
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

#export -f begin_transaction commit_transaction rollback_transaction
#export -f register_rollback register_file_rollback register_command_rollback
#export -f register_service_rollback register_firewall_rollback register_sysctl_rollback
#export -f execute_rollback_action atomic_operation atomic_file_update
#export -f create_checkpoint rollback_to_checkpoint
#export -f safe_file_operation safe_service_operation
#export -f show_rollback_history cleanup_transactions