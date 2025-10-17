#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# orchestrator.sh - Main execution controller
# Manages safe execution of all hardening scripts with dependency management

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source libraries
. "$LIB_DIR/common.sh"
. "$LIB_DIR/backup.sh"
. "$LIB_DIR/rollback.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# ============================================================================
# Script Execution Order and Dependencies
# ============================================================================

# Format: priority:script_name:dependencies (comma-separated)
SCRIPT_ORDER="
1:01-ssh-hardening.sh:none
1:02-firewall-setup.sh:01-ssh-hardening.sh
2:03-kernel-params.sh:none
2:04-network-stack.sh:02-firewall-setup.sh,03-kernel-params.sh
2:05-file-permissions.sh:none
2:06-process-limits.sh:03-kernel-params.sh
3:07-audit-logging.sh:05-file-permissions.sh
3:08-password-policy.sh:none
3:09-account-lockdown.sh:08-password-policy.sh
2:10-sudo-restrictions.sh:09-account-lockdown.sh
3:11-service-disable.sh:02-firewall-setup.sh
3:12-tmp-hardening.sh:05-file-permissions.sh
4:13-core-dump-disable.sh:03-kernel-params.sh
2:14-sysctl-hardening.sh:03-kernel-params.sh,04-network-stack.sh
3:15-cron-restrictions.sh:05-file-permissions.sh
3:16-mount-options.sh:05-file-permissions.sh
4:17-shell-timeout.sh:01-ssh-hardening.sh
4:18-banner-warnings.sh:none
3:19-log-retention.sh:07-audit-logging.sh
4:20-integrity-baseline.sh:all
"

# ============================================================================
# Helper Functions
# ============================================================================

check_script_dependencies() {
    local script="$1"
    local deps="$2"

    [ "$deps" = "none" ] && return 0
    [ "$deps" = "all" ] && return 0  # Special case for final script

    echo "$deps" | tr ',' '\n' | while read -r dep; do
        if ! is_completed "$dep"; then
            log "WARN" "Dependency not met: $dep required for $script"
            return 1
        fi
    done

    return 0
}

get_scripts_by_priority() {
    local priority="$1"

    echo "$SCRIPT_ORDER" | while IFS=: read -r p script deps; do
        [ -z "$p" ] && continue
        [ "$p" = "$priority" ] && echo "$script:$deps"
    done
}

run_script() {
    local script="$1"
    local script_path="$SCRIPT_DIR/scripts/$script"

    if [ ! -f "$script_path" ]; then
        log "ERROR" "Script not found: $script_path"
        return 1
    fi

    show_progress "Executing: $script"

    # Execute script
    if sh "$script_path"; then
        show_success "Completed: $script"
        return 0
    else
        show_error "Failed: $script"
        return 1
    fi
}

# ============================================================================
# Execution Modes
# ============================================================================

run_all_scripts() {
    show_progress "Running all hardening scripts"

    local total_scripts=$(echo "$SCRIPT_ORDER" | grep -c ":")
    local completed=0
    local failed=0

    # Create initial snapshot
    local snapshot_id
    snapshot_id=$(create_system_snapshot "orchestrator_start")
    log "INFO" "Created initial snapshot: $snapshot_id"

    # Process by priority levels
    for priority in 1 2 3 4; do
        show_progress "Processing Priority $priority scripts"

        get_scripts_by_priority "$priority" | while IFS=: read -r script deps; do
            [ -z "$script" ] && continue

            # Check if already completed
            if is_completed "${script%.sh}"; then
                log "INFO" "Already completed: $script"
                completed=$((completed + 1))
                continue
            fi

            # Check dependencies
            if ! check_script_dependencies "$script" "$deps"; then
                log "WARN" "Skipping $script - dependencies not met"
                continue
            fi

            # Run script
            if run_script "$script"; then
                completed=$((completed + 1))
            else
                failed=$((failed + 1))

                if [ "$FAIL_FAST" = "1" ]; then
                    show_error "Stopping execution due to failure"
                    break 2
                fi
            fi

            # Brief pause between scripts
            sleep 2
        done
    done

    # Final report
    echo ""
    echo "====================================="
    echo "Hardening Execution Complete"
    echo "====================================="
    echo "Total Scripts: $total_scripts"
    echo "Completed: $completed"
    echo "Failed: $failed"
    echo "====================================="

    [ "$failed" -eq 0 ] && return 0 || return 1
}

run_priority_level() {
    local level="$1"

    show_progress "Running Priority $level scripts only"

    get_scripts_by_priority "$level" | while IFS=: read -r script deps; do
        [ -z "$script" ] && continue

        if is_completed "${script%.sh}"; then
            log "INFO" "Already completed: $script"
            continue
        fi

        if check_script_dependencies "$script" "$deps"; then
            run_script "$script"
        else
            log "WARN" "Skipping $script - dependencies not met"
        fi
    done
}

run_single_script() {
    local script_name="$1"

    # Find script in order
    local found=0
    echo "$SCRIPT_ORDER" | while IFS=: read -r priority script deps; do
        if [ "$script" = "$script_name" ]; then
            found=1

            if check_script_dependencies "$script" "$deps"; then
                run_script "$script"
            else
                show_error "Dependencies not met for $script"
                return 1
            fi
            break
        fi
    done

    if [ "$found" -eq 0 ]; then
        show_error "Script not found: $script_name"
        return 1
    fi
}

show_status() {
    echo ""
    echo "====================================="
    echo "Hardening Status Report"
    echo "====================================="

    echo "$SCRIPT_ORDER" | while IFS=: read -r priority script deps; do
        [ -z "$script" ] && continue

        if is_completed "${script%.sh}"; then
            printf "[✓] "
        else
            printf "[ ] "
        fi

        printf "P%s - %s\n" "$priority" "$script"
    done

    echo "====================================="
}

# ============================================================================
# Main Menu
# ============================================================================

show_menu() {
    cat <<EOF

POSIX Server Hardening Toolkit - Orchestrator
==============================================

Options:
  1) Run all scripts (recommended)
  2) Run Priority 1 only (SSH + Firewall)
  3) Run Priority 2 only (Core hardening)
  4) Run Priority 3 only (Standard hardening)
  5) Run Priority 4 only (Additional)
  6) Run specific script
  7) Show status
  8) Dry run mode
  9) Create system snapshot
  0) Exit

EOF
}

interactive_mode() {
    while true; do
        show_menu
        printf "Select option: "
        read -r choice

        case "$choice" in
            1)
                run_all_scripts
                ;;
            2)
                run_priority_level 1
                ;;
            3)
                run_priority_level 2
                ;;
            4)
                run_priority_level 3
                ;;
            5)
                run_priority_level 4
                ;;
            6)
                printf "Enter script name (e.g., 01-ssh-hardening.sh): "
                read -r script
                run_single_script "$script"
                ;;
            7)
                show_status
                ;;
            8)
                export DRY_RUN=1
                show_warning "DRY RUN mode enabled"
                ;;
            9)
                create_system_snapshot "manual_$(date +%Y%m%d-%H%M%S)"
                ;;
            0|q|Q)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac

        printf "\nPress Enter to continue..."
        read -r _
    done
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    show_progress "POSIX Server Hardening Orchestrator Starting"

    # Initialize
    init_hardening_environment "orchestrator"

    # Parse arguments
    case "${1:-}" in
        --all|-a)
            run_all_scripts
            ;;
        --priority|-p)
            if [ -n "$2" ]; then
                run_priority_level "$2"
            else
                echo "Error: Priority level required"
                exit 1
            fi
            ;;
        --script|-s)
            if [ -n "$2" ]; then
                run_single_script "$2"
            else
                echo "Error: Script name required"
                exit 1
            fi
            ;;
        --status)
            show_status
            ;;
        --dry-run|-n)
            export DRY_RUN=1
            shift
            main "$@"
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --all, -a              Run all hardening scripts
  --priority, -p LEVEL   Run specific priority level (1-4)
  --script, -s NAME      Run specific script
  --status              Show completion status
  --dry-run, -n         Simulate without making changes
  --help, -h            Show this help

Without options, runs in interactive mode.
EOF
            ;;
        "")
            interactive_mode
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Run main
main "$@"