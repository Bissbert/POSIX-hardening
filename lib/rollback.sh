#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/rollback.sh - Transaction-based rollback system
# Provides atomic operations with automatic rollback on failure

# Note: common.sh should be sourced before this file
# Source POSIX compatibility layer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/posix_compat.sh"

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
    _transaction_name="${1:-unnamed}"
    CURRENT_TRANSACTION="$(date +%Y%m%d-%H%M%S)-$$-$_transaction_name"

    # Clear previous rollback stack
    > "$ROLLBACK_STACK"

    # Record transaction start
    echo "$CURRENT_TRANSACTION" > "$TRANSACTION_ID_FILE"

    log "INFO" "Started transaction: $CURRENT_TRANSACTION ($_transaction_name)"
    echo "$(date)|BEGIN|$CURRENT_TRANSACTION|$_transaction_name" >> "$ROLLBACK_LOG"

    # Set up exit trap for automatic rollback
    trap 'transaction_cleanup' EXIT INT TERM

    unset _transaction_name
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
    _reason="${1:-manual rollback}"

    if [ -z "$CURRENT_TRANSACTION" ] && [ ! -f "$ROLLBACK_STACK" ]; then
        log "WARN" "No active transaction to rollback"
        unset _reason
        return 1
    fi

    log "WARN" "Rolling back transaction: $CURRENT_TRANSACTION (reason: $_reason)"
    echo "$(date)|ROLLBACK|$CURRENT_TRANSACTION|$_reason" >> "$ROLLBACK_LOG"

    # Execute rollback actions in reverse order
    if [ -f "$ROLLBACK_STACK" ] && [ -s "$ROLLBACK_STACK" ]; then
        _temp_stack="${ROLLBACK_STACK}.processing"
        mv "$ROLLBACK_STACK" "$_temp_stack"

        # Read stack in reverse order
        posix_reverse "$_temp_stack" | while IFS='|' read -r action_type action_data; do
            execute_rollback_action "$action_type" "$action_data"
        done

        rm -f "$_temp_stack"
        unset _temp_stack
    fi

    # Clear transaction state
    > "$ROLLBACK_STACK"
    > "$TRANSACTION_ID_FILE"
    CURRENT_TRANSACTION=""

    log "INFO" "Rollback completed"
    unset _reason
    return 0
}

# Transaction cleanup (called on exit)
transaction_cleanup() {
    _exit_code=$?

    if [ -n "$CURRENT_TRANSACTION" ]; then
        if [ $_exit_code -ne 0 ] && [ "$ROLLBACK_ENABLED" = "1" ]; then
            log "ERROR" "Transaction failed with exit code $_exit_code - initiating rollback"
            rollback_transaction "exit_code_$_exit_code"
        elif [ $_exit_code -eq 0 ]; then
            commit_transaction
        fi
    fi

    unset _exit_code
}

# ============================================================================
# Rollback Action Registration
# ============================================================================

# Register a rollback action
register_rollback() {
    _action_type="$1"
    _action_data="$2"

    if [ -z "$_action_type" ] || [ -z "$_action_data" ]; then
        log "ERROR" "Invalid rollback registration: type=$_action_type data=$_action_data"
        unset _action_type _action_data
        return 1
    fi

    echo "${_action_type}|${_action_data}" >> "$ROLLBACK_STACK"
    log "DEBUG" "Registered rollback: $_action_type - $_action_data"

    unset _action_type _action_data
    return 0
}

# Register file restore action
register_file_rollback() {
    _original_file="$1"
    _backup_file="$2"

    register_rollback "FILE_RESTORE" "${_backup_file}:${_original_file}"
    _result=$?

    unset _original_file _backup_file
    return $_result
}

# Register command rollback action
register_command_rollback() {
    _rollback_command="$1"

    register_rollback "COMMAND" "$_rollback_command"
    _result=$?

    unset _rollback_command
    return $_result
}

# Register service rollback action
register_service_rollback() {
    _service_name="$1"
    _action="$2"  # start, stop, restart, reload

    register_rollback "SERVICE" "${_service_name}:${_action}"
    _result=$?

    unset _service_name _action
    return $_result
}

# Register firewall rule rollback
register_firewall_rollback() {
    _rule="$1"

    register_rollback "FIREWALL" "$_rule"
    _result=$?

    unset _rule
    return $_result
}

# Register sysctl rollback
register_sysctl_rollback() {
    _parameter="$1"
    _original_value="$2"

    register_rollback "SYSCTL" "${_parameter}:${_original_value}"
    _result=$?

    unset _parameter _original_value
    return $_result
}

# ============================================================================
# Rollback Action Execution
# ============================================================================

# Execute a rollback action
execute_rollback_action() {
    _action_type="$1"
    _action_data="$2"

    log "DEBUG" "Executing rollback action: $_action_type"

    case "$_action_type" in
        FILE_RESTORE)
            # Restore file from backup
            _backup_file="${_action_data%:*}"
            _original_file="${_action_data#*:}"

            if [ -f "$_backup_file" ]; then
                cp -p "$_backup_file" "$_original_file" && \
                    log "INFO" "Restored file: $_original_file"
            else
                log "ERROR" "Backup file not found: $_backup_file"
            fi
            unset _backup_file _original_file
            ;;

        COMMAND)
            # Execute rollback command
            log "DEBUG" "Executing rollback command: $_action_data"
            eval "$_action_data" || \
                log "ERROR" "Rollback command failed: $_action_data"
            ;;

        SERVICE)
            # Manage service
            _service_name="${_action_data%:*}"
            _action="${_action_data#*:}"

            case "$_action" in
                start|stop|restart|reload)
                    safe_service_${_action} "$_service_name" || \
                        log "ERROR" "Failed to $_action service: $_service_name"
                    ;;
                *)
                    log "ERROR" "Unknown service action: $_action"
                    ;;
            esac
            unset _service_name _action
            ;;

        FIREWALL)
            # Restore firewall rule
            if command -v iptables >/dev/null 2>&1; then
                eval "$_action_data" || \
                    log "ERROR" "Failed to restore firewall rule"
            fi
            ;;

        SYSCTL)
            # Restore sysctl parameter
            _parameter="${_action_data%:*}"
            _value="${_action_data#*:}"

            sysctl -w "$_parameter=$_value" >/dev/null 2>&1 || \
                log "ERROR" "Failed to restore sysctl: $_parameter=$_value"
            unset _parameter _value
            ;;

        *)
            log "ERROR" "Unknown rollback action type: $_action_type"
            ;;
    esac

    unset _action_type _action_data
}

# ============================================================================
# Atomic Operations
# ============================================================================

# Execute operation with automatic rollback on failure
atomic_operation() {
    _operation="$1"
    _rollback="$2"
    _description="${3:-operation}"

    log "DEBUG" "Atomic operation: $_description"

    # Register rollback first
    if [ -n "$_rollback" ]; then
        register_command_rollback "$_rollback"
    fi

    # Execute operation
    if eval "$_operation"; then
        log "DEBUG" "Operation succeeded: $_description"
        unset _operation _rollback _description
        return 0
    else
        log "ERROR" "Operation failed: $_description"

        # Execute rollback if not in transaction
        if [ -z "$CURRENT_TRANSACTION" ] && [ -n "$_rollback" ]; then
            log "INFO" "Executing immediate rollback"
            eval "$_rollback"
        fi

        unset _operation _rollback _description
        return 1
    fi
}

# Atomic file update
atomic_file_update() {
    _target_file="$1"
    _update_function="$2"

    if [ ! -f "$_target_file" ]; then
        log "ERROR" "Target file does not exist: $_target_file"
        unset _target_file _update_function
        return 1
    fi

    # Create backup
    _backup_file=$(safe_backup_file "$_target_file")

    if [ -z "$_backup_file" ]; then
        log "ERROR" "Failed to backup file: $_target_file"
        unset _target_file _update_function _backup_file
        return 1
    fi

    # Register rollback
    register_file_rollback "$_target_file" "$_backup_file"

    # Create working copy
    _work_file="${_target_file}.work"
    cp -p "$_target_file" "$_work_file"

    # Apply updates to working copy
    if $_update_function "$_work_file"; then
        # Move working copy to target
        mv "$_work_file" "$_target_file"
        log "INFO" "Updated file: $_target_file"
        unset _target_file _update_function _backup_file _work_file
        return 0
    else
        # Clean up working copy
        rm -f "$_work_file"
        log "ERROR" "Failed to update file: $_target_file"
        unset _target_file _update_function _backup_file _work_file
        return 1
    fi
}

# ============================================================================
# Checkpoint System
# ============================================================================

# Create a checkpoint in the current transaction
create_checkpoint() {
    _checkpoint_name="${1:-checkpoint}"
    _checkpoint_file="$STATE_DIR/checkpoint_${CURRENT_TRANSACTION}_${_checkpoint_name}"

    if [ -z "$CURRENT_TRANSACTION" ]; then
        log "ERROR" "No active transaction for checkpoint"
        unset _checkpoint_name _checkpoint_file
        return 1
    fi

    # Save current rollback stack
    cp "$ROLLBACK_STACK" "$_checkpoint_file"

    log "DEBUG" "Created checkpoint: $_checkpoint_name"
    unset _checkpoint_name _checkpoint_file
    return 0
}

# Rollback to a checkpoint
rollback_to_checkpoint() {
    _checkpoint_name="${1:-checkpoint}"
    _checkpoint_file="$STATE_DIR/checkpoint_${CURRENT_TRANSACTION}_${_checkpoint_name}"

    if [ ! -f "$_checkpoint_file" ]; then
        log "ERROR" "Checkpoint not found: $_checkpoint_name"
        unset _checkpoint_name _checkpoint_file
        return 1
    fi

    # Get actions added after checkpoint
    _temp_actions="${ROLLBACK_STACK}.temp"
    comm -13 "$_checkpoint_file" "$ROLLBACK_STACK" > "$_temp_actions" 2>/dev/null

    # Execute rollback for actions after checkpoint
    if [ -s "$_temp_actions" ]; then
        tac "$_temp_actions" 2>/dev/null || tail -r "$_temp_actions" 2>/dev/null | while IFS='|' read -r action_type action_data; do
            execute_rollback_action "$action_type" "$action_data"
        done
    fi

    # Restore checkpoint stack
    cp "$_checkpoint_file" "$ROLLBACK_STACK"

    rm -f "$_temp_actions"
    log "INFO" "Rolled back to checkpoint: $_checkpoint_name"
    unset _checkpoint_name _checkpoint_file _temp_actions
    return 0
}

# ============================================================================
# Safety Wrappers
# ============================================================================

# Wrapper for file modifications with rollback
safe_file_operation() {
    _file="$1"
    _operation="$2"

    begin_transaction "file_${_file}"

    if atomic_file_update "$_file" "$_operation"; then
        commit_transaction
        unset _file _operation
        return 0
    else
        rollback_transaction "file_operation_failed"
        unset _file _operation
        return 1
    fi
}

# Wrapper for service changes with rollback
safe_service_operation() {
    _service="$1"
    _operation="$2"

    begin_transaction "service_${_service}"

    # Get current service state
    _current_state="stopped"
    if systemctl is-active "$_service" >/dev/null 2>&1 || \
       service "$_service" status >/dev/null 2>&1; then
        _current_state="running"
    fi

    # Register rollback to restore original state
    if [ "$_current_state" = "running" ]; then
        register_service_rollback "$_service" "start"
    else
        register_service_rollback "$_service" "stop"
    fi

    # Execute operation
    if eval "$_operation"; then
        commit_transaction
        unset _service _operation _current_state
        return 0
    else
        rollback_transaction "service_operation_failed"
        unset _service _operation _current_state
        return 1
    fi
}

# ============================================================================
# Rollback History and Recovery
# ============================================================================

# Show rollback history
show_rollback_history() {
    _limit="${1:-20}"

    if [ ! -f "$ROLLBACK_LOG" ]; then
        log "INFO" "No rollback history found"
        unset _limit
        return 0
    fi

    echo "Recent Rollback History:"
    echo "========================"
    tail -n "$_limit" "$ROLLBACK_LOG" | while IFS='|' read -r date action transaction reason; do
        printf "%s | %-8s | %s\n" "$date" "$action" "$transaction"
        if [ -n "$reason" ]; then
            printf "    Reason: %s\n" "$reason"
        fi
    done

    unset _limit
}

# Clean up old transaction files
cleanup_transactions() {
    _days="${1:-7}"

    log "INFO" "Cleaning up transaction files older than $_days days"

    # Clean checkpoint files
    find "$STATE_DIR" -name "checkpoint_*" -mtime +"$_days" -exec rm {} \; 2>/dev/null

    # Clean old rollback logs
    if [ -f "$ROLLBACK_LOG" ]; then
        _temp_log="${ROLLBACK_LOG}.tmp"
        _cutoff_date=$(date -d "$_days days ago" +%Y-%m-%d 2>/dev/null || \
                       date -v -"$_days"d +%Y-%m-%d 2>/dev/null)

        if [ -n "$_cutoff_date" ]; then
            while IFS='|' read -r date action transaction reason; do
                if [ "$(echo "$date" | cut -d' ' -f1)" \> "$_cutoff_date" ]; then
                    echo "${date}|${action}|${transaction}|${reason}" >> "$_temp_log"
                fi
            done < "$ROLLBACK_LOG"

            mv "$_temp_log" "$ROLLBACK_LOG"
        fi
        unset _temp_log _cutoff_date
    fi

    unset _days
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
