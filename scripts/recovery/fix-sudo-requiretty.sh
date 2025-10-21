#!/bin/sh
# ==============================================================================
# Emergency Recovery: Fix sudo requiretty lockout
# ==============================================================================
# This script fixes the "sorry, you must have a tty to run sudo" error
# that prevents Ansible from working after sudo hardening.
#
# Usage:
#   1. SSH with a real terminal: ssh -t user@host
#   2. Run this script with sudo: sudo ./fix-sudo-requiretty.sh
#
# Or if you have console/IPMI access:
#   1. Login directly to the server
#   2. Run this script as root: ./fix-sudo-requiretty.sh
# ==============================================================================

set -e

# Check if we're running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo"
    echo "Usage: sudo $0"
    exit 1
fi

SUDOERS_FILE="/etc/sudoers.d/hardening"
BACKUP_FILE="${SUDOERS_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

echo "==================================================================="
echo "Emergency Recovery: Fixing sudo requiretty"
echo "==================================================================="
echo ""

# Check if the hardening file exists
if [ ! -f "$SUDOERS_FILE" ]; then
    echo "ERROR: $SUDOERS_FILE not found"
    echo "The sudo hardening may not have been applied yet."
    exit 1
fi

echo "Current sudo configuration:"
echo "-------------------------------------------------------------------"
grep -E "^Defaults.*requiretty" "$SUDOERS_FILE" || echo "(no requiretty setting found)"
echo "-------------------------------------------------------------------"
echo ""

# Backup the current file
echo "Creating backup: $BACKUP_FILE"
cp "$SUDOERS_FILE" "$BACKUP_FILE"
echo "Backup created successfully"
echo ""

# Fix the requiretty setting
echo "Fixing requiretty setting..."

# Create temporary file
TEMP_FILE=$(mktemp)

# Replace 'Defaults requiretty' with 'Defaults !requiretty'
sed 's/^Defaults requiretty$/Defaults !requiretty/' "$SUDOERS_FILE" > "$TEMP_FILE"

# Validate the new configuration
if visudo -c -f "$TEMP_FILE" >/dev/null 2>&1; then
    echo "✓ New configuration validated successfully"

    # Apply the fix
    cat "$TEMP_FILE" > "$SUDOERS_FILE"
    rm "$TEMP_FILE"

    echo "✓ Configuration updated"
    echo ""
    echo "New sudo configuration:"
    echo "-------------------------------------------------------------------"
    grep -E "^Defaults.*requiretty" "$SUDOERS_FILE" || echo "Defaults !requiretty"
    echo "-------------------------------------------------------------------"
    echo ""
    echo "SUCCESS: sudo is now fixed and Ansible should work!"
    echo ""
    echo "You can now:"
    echo "  1. Test: sudo -n whoami (should work without password if cached)"
    echo "  2. Run Ansible playbooks normally"
    echo ""
    echo "Backup saved to: $BACKUP_FILE"

else
    echo "ERROR: New configuration failed validation"
    echo "This shouldn't happen. Please check manually:"
    echo "  cat $TEMP_FILE"
    rm "$TEMP_FILE"
    exit 1
fi
