#!/bin/sh
# Script: 07-audit-logging.sh - Enable audit logging


SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
esac
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$TOOLKIT_ROOT/lib"
CONFIG_FILE="$TOOLKIT_ROOT/config/defaults.conf"
# Load configuration first (before libraries set readonly variables)
# Environment values win over the file (see lib/config.sh)
. "$LIB_DIR/config.sh"
load_config "$CONFIG_FILE"
. "$LIB_DIR/common.sh"
. "$LIB_DIR/rollback.sh"

SCRIPT_NAME="07-audit-logging"

configure_audit() {
    show_progress "Configuring audit logging"

    # Enable auth logging
    if [ -f /etc/rsyslog.conf ]; then
        # More specific check to avoid duplicates
        if ! grep -q "^auth,authpriv\.\*[[:space:]]*/var/log/auth\.log" /etc/rsyslog.conf; then
            log "INFO" "Adding auth logging to rsyslog.conf"
            track_file /etc/rsyslog.conf
            echo "auth,authpriv.* /var/log/auth.log" >> /etc/rsyslog.conf
        else
            log "INFO" "Auth logging already configured in rsyslog.conf"
        fi
    fi

    # Create audit rules if auditd is available
    if command -v auditctl >/dev/null 2>&1; then
        # On rollback: remove or restore the rules first, then reload
        register_command_rollback "service auditd reload 2>/dev/null || true"
        track_file /etc/audit/rules.d/hardening.rules
        cat > /etc/audit/rules.d/hardening.rules <<'EOF'
# POSIX Hardening Audit Rules
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/ssh/sshd_config -p wa -k sshd_config
-a exit,always -F arch=b64 -S execve -k command_execution
EOF
        service auditd reload 2>/dev/null || true
    fi

    show_success "Audit logging configured"
}

main() {
    init_hardening_environment "$SCRIPT_NAME"
    begin_transaction "audit_logging"

    if [ "$DRY_RUN" != "1" ]; then
        configure_audit
    fi

    mark_completed "$SCRIPT_NAME"
    commit_transaction
    exit 0
}

main "$@"