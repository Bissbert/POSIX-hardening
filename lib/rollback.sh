#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# lib/rollback.sh - Transaction-based rollback system
# Provides atomic operations with automatic rollback on failure

# Note: common.sh should be sourced before this file
# Source POSIX compatibility layer from the caller-provided library directory.
. "${LIB_DIR}/posix_compat.sh"

# Rollback configuration
readonly ROLLBACK_STACK="$STATE_DIR/rollback_stack"
readonly ROLLBACK_LOG="$LOG_DIR/rollback.log"
readonly TRANSACTION_ID_FILE="$STATE_DIR/current_transaction"
# What the track_* helpers already registered in this transaction
readonly ROLLBACK_TRACKED="$STATE_DIR/rollback_tracked"
# Copies of tracked files, one directory per transaction
readonly ROLLBACK_COPY_DIR="$BACKUP_DIR/transactions"

# Global rollback state
# On unless switched off explicitly with ROLLBACK_ENABLED=0
ROLLBACK_ENABLED="${ROLLBACK_ENABLED:-1}"
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
    > "$ROLLBACK_TRACKED"

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
    > "$ROLLBACK_TRACKED"

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
        _reversed_stack="${_temp_stack}.reversed"
        _failed_stack="${ROLLBACK_STACK}.failed"

        if ! mv "$ROLLBACK_STACK" "$_temp_stack"; then
            log "ERROR" "Could not prepare rollback stack"
            unset _reason _temp_stack _reversed_stack _failed_stack
            return 1
        fi

        : > "$_failed_stack"
        if ! posix_reverse "$_temp_stack" > "$_reversed_stack"; then
            mv "$_temp_stack" "$ROLLBACK_STACK"
            rm -f "$_failed_stack" "$_reversed_stack"
            unset _reason _temp_stack _reversed_stack _failed_stack
            return 1
        fi

        _rollback_failed=0
        while IFS='|' read -r action_type action_data; do
            if ! execute_rollback_action "$action_type" "$action_data"; then
                printf '%s|%s\n' "$action_type" "$action_data" >> "$_failed_stack"
                _rollback_failed=1
            fi
        done < "$_reversed_stack"

        rm -f "$_temp_stack" "$_reversed_stack"

        if [ "$_rollback_failed" -ne 0 ]; then
            if ! mv "$_failed_stack" "$ROLLBACK_STACK"; then
                log "ERROR" "Could not preserve failed rollback actions"
            fi
            > "$TRANSACTION_ID_FILE"
            > "$ROLLBACK_TRACKED"
            CURRENT_TRANSACTION=""
            log "ERROR" "Rollback completed with failures; failed actions were retained"
            unset _reason _temp_stack _reversed_stack _failed_stack _rollback_failed
            return 1
        fi

        rm -f "$_failed_stack"
        unset _temp_stack _reversed_stack _failed_stack _rollback_failed
    fi

    # Clear transaction state
    > "$ROLLBACK_STACK"
    > "$ROLLBACK_TRACKED"
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
# Its variable names are its own: callers such as update_ssh_config_safe keep
# using their own $_backup_file afterwards.
register_file_rollback() {
    _rfr_original="$1"
    _rfr_backup="$2"

    register_rollback "FILE_RESTORE" "${_rfr_backup}:${_rfr_original}"
    _rfr_result=$?

    unset _rfr_original _rfr_backup
    return $_rfr_result
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
# Change Tracking
# ============================================================================
#
# Every script calls one of these before it changes something, inside a
# transaction. Each records the current state and registers the action that
# puts it back. Only the first call for an object in a transaction registers
# anything, so a rollback returns to the state before the script started.
# In dry-run mode nothing changes, so nothing is recorded.

# _track_first KIND OBJECT: true the first time OBJECT is tracked as KIND
_track_first() {
    if [ "$DRY_RUN" = "1" ]; then
        return 1
    fi
    if [ -z "$CURRENT_TRANSACTION" ]; then
        log "DEBUG" "No transaction; not tracking $1 $2"
        return 1
    fi
    if [ -f "$ROLLBACK_TRACKED" ] && grep -qxF "$1 $2" "$ROLLBACK_TRACKED"; then
        return 1
    fi
    printf '%s %s\n' "$1" "$2" >> "$ROLLBACK_TRACKED"
    return 0
}

# track_file PATH
# Before PATH's contents are replaced, edited or deleted: an existing file is
# copied and restored from the copy (with its mode and owner); a path that
# does not exist yet is removed again. A symlink is put back as a symlink.
track_file() {
    _tf_path="$1"
    _track_first FILE "$_tf_path" || { unset _tf_path; return 0; }

    if [ -L "$_tf_path" ]; then
        register_rollback "LINK" "${_tf_path}:$(readlink "$_tf_path")" || return 1
        # Writing to a symlink changes its target, so keep that as well
        _tf_target=$(readlink -f "$_tf_path")
        [ -f "$_tf_target" ] && track_file "$_tf_target"
        unset _tf_path _tf_target
        return 0
    fi

    if [ -e "$_tf_path" ]; then
        _tf_copy="$ROLLBACK_COPY_DIR/$CURRENT_TRANSACTION$_tf_path"
        mkdir -p "$(dirname "$_tf_copy")" || return 1
        if ! cp -p "$_tf_path" "$_tf_copy"; then
            log "ERROR" "Could not copy $_tf_path for rollback"
            unset _tf_path _tf_copy
            return 1
        fi
        register_file_rollback "$_tf_path" "$_tf_copy"
    else
        register_rollback "FILE_REMOVE" "$_tf_path"
    fi
    _tf_rc=$?
    unset _tf_path _tf_copy
    return $_tf_rc
}

# track_dir PATH
# Before creating directory PATH: removes it again if it did not exist and is
# empty by then (files tracked inside it are removed first).
track_dir() {
    _track_first DIR "$1" || return 0
    [ -d "$1" ] && return 0
    register_rollback "DIR_REMOVE" "$1"
}

# track_mode PATH
# Before chmod or chown on PATH: restores the mode, owner and group.
track_mode() {
    [ -e "$1" ] || return 0
    _track_first MODE "$1" || return 0
    _tm_state=$(stat -c '%a:%u:%g' "$1") || return 1
    register_rollback "MODE" "${_tm_state}:$1"
    _tm_rc=$?
    unset _tm_state
    return $_tm_rc
}

# track_sysctl NAME
# Before changing a live kernel parameter, given as a dotted sysctl name or
# a /proc/sys path: restores the current value. Unknown names are skipped,
# since writing them fails too.
track_sysctl() {
    case "$1" in
        /*) [ -f "$1" ] || return 0
            _ts_value=$(cat "$1" 2>/dev/null) || return 0 ;;
        *)  _ts_value=$(sysctl -n "$1" 2>/dev/null) || return 0 ;;
    esac
    _track_first SYSCTL "$1" || { unset _ts_value; return 0; }
    register_sysctl_rollback "$1" "$_ts_value"
    _ts_rc=$?
    unset _ts_value
    return $_ts_rc
}

# track_sysctl_file FILE
# Before "sysctl -p FILE": tracks every parameter FILE sets.
track_sysctl_file() {
    [ -f "$1" ] || return 0
    for _tsf_name in $(sed -n 's/^[[:space:]]*\([A-Za-z0-9_.\/-]*\)[[:space:]]*=.*/\1/p' "$1"); do
        track_sysctl "$_tsf_name" || return 1
    done
    unset _tsf_name
    return 0
}

# track_service NAME
# Before stopping or disabling a service: enables and starts it again if it
# was enabled or running.
track_service() {
    _track_first SERVICE "$1" || return 0
    if command -v systemctl >/dev/null 2>&1; then
        _tsv_enabled=$(systemctl is-enabled "$1" 2>/dev/null || true)
        _tsv_active=$(systemctl is-active "$1" 2>/dev/null || true)
    else
        _tsv_enabled=disabled
        ls /etc/rc[2-5].d/S*"$1" >/dev/null 2>&1 && _tsv_enabled=enabled
        _tsv_active=inactive
        service "$1" status >/dev/null 2>&1 && _tsv_active=active
    fi
    register_rollback "SERVICE_STATE" "${1}:${_tsv_enabled}:${_tsv_active}"
    _tsv_rc=$?
    unset _tsv_enabled _tsv_active
    return $_tsv_rc
}

# track_mount MOUNTPOINT
# Before "mount -o remount": remounts with the current options. Flags that
# are off now (exec, suid, dev, no hidepid) are named explicitly, because a
# remount keeps any option it is not given.
track_mount() {
    _tmt_line=$(awk -v m="$1" '$2 == m { l = $3 " " $4 } END { print l }' /proc/mounts)
    [ -n "$_tmt_line" ] || { unset _tmt_line; return 0; }
    _track_first MOUNT "$1" || { unset _tmt_line; return 0; }
    _tmt_type=${_tmt_line%% *}
    _tmt_opts=${_tmt_line#* }
    for _tmt_flag in exec suid dev; do
        case ",$_tmt_opts," in
            *",no$_tmt_flag,"*) ;;
            *) _tmt_opts="$_tmt_opts,$_tmt_flag" ;;
        esac
    done
    if [ "$_tmt_type" = "proc" ]; then
        case ",$_tmt_opts," in
            *,hidepid=*) ;;
            *) _tmt_opts="$_tmt_opts,hidepid=0" ;;
        esac
    fi
    register_rollback "MOUNT" "${1}:${_tmt_opts}"
    _tmt_rc=$?
    unset _tmt_line _tmt_type _tmt_opts _tmt_flag
    return $_tmt_rc
}

# track_account USER
# Before usermod -L or -s: restores the login shell, the password field and
# the date of the last password change exactly as they were, so a lock is
# undone without guessing and without restarting password ageing.
track_account() {
    id "$1" >/dev/null 2>&1 || return 0
    _track_first ACCOUNT "$1" || return 0
    _tac_shell=$(awk -F: -v u="$1" '$1 == u { print $7 }' /etc/passwd)
    _tac_hash=$(awk -F: -v u="$1" '$1 == u { print $2 }' /etc/shadow)
    _tac_changed=$(awk -F: -v u="$1" '$1 == u { print $3 }' /etc/shadow)
    register_rollback "ACCOUNT" "${1}:${_tac_shell}:${_tac_changed}:${_tac_hash}"
    _tac_rc=$?
    unset _tac_shell _tac_hash _tac_changed
    return $_tac_rc
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
                if cp -p "$_backup_file" "$_original_file"; then
                    log "INFO" "Restored file: $_original_file"
                else
                    log "ERROR" "Failed to restore file: $_original_file"
                    unset _backup_file _original_file _action_type _action_data
                    return 1
                fi
            else
                log "ERROR" "Backup file not found: $_backup_file"
                unset _backup_file _original_file _action_type _action_data
                return 1
            fi
            unset _backup_file _original_file
            ;;

        FILE_REMOVE)
            # The file did not exist before the transaction
            if ! rm -f "$_action_data"; then
                log "ERROR" "Failed to remove: $_action_data"
                unset _action_type _action_data
                return 1
            fi
            log "INFO" "Removed file created by the transaction: $_action_data"
            ;;

        DIR_REMOVE)
            if [ -d "$_action_data" ] && ! rmdir "$_action_data"; then
                log "ERROR" "Failed to remove directory: $_action_data"
                unset _action_type _action_data
                return 1
            fi
            ;;

        LINK)
            _link_path="${_action_data%%:*}"
            _link_target="${_action_data#*:}"
            if ! ln -sfn "$_link_target" "$_link_path"; then
                log "ERROR" "Failed to restore symlink: $_link_path"
                unset _link_path _link_target _action_type _action_data
                return 1
            fi
            unset _link_path _link_target
            ;;

        MODE)
            _mode="${_action_data%%:*}"; _rest="${_action_data#*:}"
            _uid="${_rest%%:*}"; _rest="${_rest#*:}"
            _gid="${_rest%%:*}"; _path="${_rest#*:}"
            if ! chmod "$_mode" "$_path" || ! chown "$_uid:$_gid" "$_path"; then
                log "ERROR" "Failed to restore mode of $_path"
                unset _mode _rest _uid _gid _path _action_type _action_data
                return 1
            fi
            unset _mode _rest _uid _gid _path
            ;;

        SERVICE_STATE)
            _service_name="${_action_data%%:*}"; _rest="${_action_data#*:}"
            _enabled="${_rest%%:*}"; _active="${_rest#*:}"
            _svc_failed=0
            if [ "$_enabled" = "enabled" ]; then
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable "$_service_name" >/dev/null 2>&1 || _svc_failed=1
                elif command -v update-rc.d >/dev/null 2>&1; then
                    update-rc.d "$_service_name" enable >/dev/null 2>&1 || _svc_failed=1
                elif command -v chkconfig >/dev/null 2>&1; then
                    chkconfig "$_service_name" on >/dev/null 2>&1 || _svc_failed=1
                fi
            fi
            if [ "$_active" = "active" ]; then
                systemctl start "$_service_name" >/dev/null 2>&1 || \
                    service "$_service_name" start >/dev/null 2>&1 || _svc_failed=1
            fi
            if [ "$_svc_failed" -ne 0 ]; then
                log "ERROR" "Failed to restore service $_service_name ($_enabled, $_active)"
                unset _service_name _rest _enabled _active _svc_failed _action_type _action_data
                return 1
            fi
            unset _service_name _rest _enabled _active _svc_failed
            ;;

        MOUNT)
            _mount_point="${_action_data%%:*}"
            _mount_opts="${_action_data#*:}"
            if ! mount -o "remount,$_mount_opts" "$_mount_point"; then
                log "ERROR" "Failed to remount $_mount_point with $_mount_opts"
                unset _mount_point _mount_opts _action_type _action_data
                return 1
            fi
            unset _mount_point _mount_opts
            ;;

        ACCOUNT)
            _user="${_action_data%%:*}"; _rest="${_action_data#*:}"
            _shell="${_rest%%:*}"; _rest="${_rest#*:}"
            _changed="${_rest%%:*}"; _hash="${_rest#*:}"
            # usermod -p resets the last-change date, so put it back after
            if ! usermod -s "$_shell" -p "$_hash" "$_user" ||
                { [ -n "$_changed" ] && ! chage -d "$_changed" "$_user"; }; then
                log "ERROR" "Failed to restore account: $_user"
                unset _user _rest _shell _hash _changed _action_type _action_data
                return 1
            fi
            unset _user _rest _shell _hash _changed
            ;;

        COMMAND)
            # Execute rollback command
            log "DEBUG" "Executing rollback command: $_action_data"
            if ! eval "$_action_data"; then
                log "ERROR" "Rollback command failed: $_action_data"
                unset _action_type _action_data
                return 1
            fi
            ;;

        SERVICE)
            # Manage service
            _service_name="${_action_data%:*}"
            _action="${_action_data#*:}"

            case "$_action" in
                start|stop|restart|reload)
                    if ! safe_service_${_action} "$_service_name"; then
                        log "ERROR" "Failed to $_action service: $_service_name"
                        unset _service_name _action _action_type _action_data
                        return 1
                    fi
                    ;;
                *)
                    log "ERROR" "Unknown service action: $_action"
                    unset _service_name _action _action_type _action_data
                    return 1
                    ;;
            esac
            unset _service_name _action
            ;;

        FIREWALL)
            # Restore firewall rule
            if ! command -v iptables >/dev/null 2>&1; then
                log "ERROR" "iptables is unavailable; cannot restore firewall rule"
                unset _action_type _action_data
                return 1
            elif ! eval "$_action_data"; then
                log "ERROR" "Failed to restore firewall rule"
                unset _action_type _action_data
                return 1
            fi
            ;;

        SYSCTL)
            # Restore sysctl parameter
            _parameter="${_action_data%%:*}"
            _value="${_action_data#*:}"

            # A /proc/sys path is written directly (interface names may
            # contain dots, which a sysctl name cannot express)
            case "$_parameter" in
                /*) _sysctl_ok=0
                    printf '%s\n' "$_value" > "$_parameter" 2>/dev/null && _sysctl_ok=1 ;;
                *)  _sysctl_ok=0
                    sysctl -w "$_parameter=$_value" >/dev/null 2>&1 && _sysctl_ok=1 ;;
            esac
            if [ "$_sysctl_ok" -ne 1 ]; then
                log "ERROR" "Failed to restore sysctl: $_parameter=$_value"
                unset _parameter _value _action_type _action_data
                return 1
            fi
            unset _parameter _value
            ;;

        *)
            log "ERROR" "Unknown rollback action type: $_action_type"
            unset _action_type _action_data
            return 1
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

    # Checkpoint stacks are ordered prefixes, so preserve duplicates and
    # chronology instead of treating the stacks as sorted sets.
    _temp_actions="${ROLLBACK_STACK}.temp"
    _checkpoint_prefix="${_temp_actions}.prefix"
    _reversed_actions="${_temp_actions}.reversed"
    _checkpoint_lines=$(wc -l < "$_checkpoint_file")
    _stack_lines=$(wc -l < "$ROLLBACK_STACK")

    if [ "$_stack_lines" -lt "$_checkpoint_lines" ]; then
        log "ERROR" "Rollback stack predates checkpoint: $_checkpoint_name"
        unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines
        return 1
    fi

    awk -v limit="$_checkpoint_lines" 'NR <= limit {print}' "$ROLLBACK_STACK" > "$_checkpoint_prefix"
    if ! cmp -s "$_checkpoint_file" "$_checkpoint_prefix"; then
        log "ERROR" "Rollback stack does not contain checkpoint prefix: $_checkpoint_name"
        rm -f "$_temp_actions" "$_checkpoint_prefix" "$_reversed_actions"
        unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines
        return 1
    fi

    _first_new_line=$((_checkpoint_lines + 1))
    awk -v start="$_first_new_line" 'NR >= start {print}' "$ROLLBACK_STACK" > "$_temp_actions"

    _checkpoint_failed=0
    if [ -s "$_temp_actions" ]; then
        if ! posix_reverse "$_temp_actions" > "$_reversed_actions"; then
            rm -f "$_temp_actions" "$_checkpoint_prefix" "$_reversed_actions"
            unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines _first_new_line _checkpoint_failed
            return 1
        fi

        while IFS='|' read -r action_type action_data; do
            if ! execute_rollback_action "$action_type" "$action_data"; then
                _checkpoint_failed=1
            fi
        done < "$_reversed_actions"
    fi

    rm -f "$_temp_actions" "$_checkpoint_prefix" "$_reversed_actions"

    if [ "$_checkpoint_failed" -ne 0 ]; then
        log "ERROR" "Rollback to checkpoint failed; current stack retained"
        unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines _first_new_line _checkpoint_failed
        return 1
    fi

    # Restore checkpoint stack only after every appended action succeeds.
    if ! cp "$_checkpoint_file" "$ROLLBACK_STACK"; then
        log "ERROR" "Could not restore checkpoint stack: $_checkpoint_name"
        unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines _first_new_line _checkpoint_failed
        return 1
    fi

    log "INFO" "Rolled back to checkpoint: $_checkpoint_name"
    unset _checkpoint_name _checkpoint_file _temp_actions _checkpoint_prefix _reversed_actions _checkpoint_lines _stack_lines _first_new_line _checkpoint_failed
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
