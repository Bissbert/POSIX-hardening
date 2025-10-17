#!/bin/sh
# POSIX Shell Server Hardening Toolkit - Quick Start Script
# This script provides an interactive setup for first-time users

set -e

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Base directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/defaults.conf"
TEMPLATE_FILE="$SCRIPT_DIR/config/defaults.conf.template"

# Print colored message
print_msg() {
    color=$1
    shift
    printf "${color}%s${NC}\n" "$*"
}

# Print banner
print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     POSIX Shell Server Hardening Toolkit - Quick Start          ║"
    echo "║                   Safety First, Security Always                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    print_msg "$BLUE" "Checking prerequisites..."

    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        print_msg "$RED" "✗ This script must be run as root"
        exit 1
    fi

    # Check OS
    if [ -f /etc/debian_version ]; then
        print_msg "$GREEN" "✓ Debian-based system detected"
    else
        print_msg "$YELLOW" "⚠ Warning: This toolkit is designed for Debian/Ubuntu systems"
        printf "Continue anyway? (y/N): "
        read -r response
        if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
            exit 1
        fi
    fi

    # Check SSH
    if command -v sshd >/dev/null 2>&1; then
        print_msg "$GREEN" "✓ SSH server found"
    else
        print_msg "$RED" "✗ SSH server not found"
        exit 1
    fi

    # Check for existing configuration
    if [ -f "$CONFIG_FILE" ]; then
        print_msg "$YELLOW" "⚠ Configuration file already exists"
        printf "Overwrite existing configuration? (y/N): "
        read -r response
        if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
            print_msg "$BLUE" "Using existing configuration"
            return 0
        fi
    fi

    return 0
}

# Get user input with default value
get_input() {
    prompt=$1
    default=$2
    variable=$3

    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi

    read -r value
    if [ -z "$value" ]; then
        value="$default"
    fi

    eval "$variable='$value'"
}

# Configure basics
configure_basics() {
    print_msg "$BLUE" "\n=== Basic Configuration ==="

    # Get current SSH connection IP
    current_ip=""
    if [ -n "$SSH_CLIENT" ]; then
        current_ip=$(echo "$SSH_CLIENT" | awk '{print $1}')
        print_msg "$GREEN" "Detected your current IP: $current_ip"
    fi

    get_input "Enter your management IP address (CRITICAL!)" "$current_ip" admin_ip

    if [ -z "$admin_ip" ] || [ "$admin_ip" = "YOUR_IP_HERE" ]; then
        print_msg "$RED" "✗ Admin IP is required for safety!"
        exit 1
    fi

    get_input "Enter admin email (optional)" "" admin_email

    # Get current SSH port
    current_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    get_input "SSH port" "$current_port" ssh_port

    # Get current user
    current_user="${SUDO_USER:-root}"
    get_input "Allowed SSH users (space-separated)" "$current_user" ssh_users

    get_input "Enable emergency SSH? (recommended)" "yes" emergency_ssh
    if [ "$emergency_ssh" = "yes" ] || [ "$emergency_ssh" = "y" ]; then
        emergency_enabled=1
        get_input "Emergency SSH port" "2222" emergency_port
    else
        emergency_enabled=0
        emergency_port=2222
    fi
}

# Configure hardening level
configure_level() {
    print_msg "$BLUE" "\n=== Hardening Level ==="
    echo "1) Basic    - Essential hardening only"
    echo "2) Standard - Recommended for most servers (default)"
    echo "3) Paranoid - Maximum security (may break applications)"

    get_input "Select level (1-3)" "2" level_choice

    case "$level_choice" in
        1) hardening_level="basic" ;;
        3) hardening_level="paranoid" ;;
        *) hardening_level="standard" ;;
    esac

    print_msg "$GREEN" "Selected: $hardening_level"
}

# Configure network
configure_network() {
    print_msg "$BLUE" "\n=== Network Configuration ==="

    get_input "Additional allowed ports (e.g., '80 443')" "" allowed_ports
    get_input "Additional allowed networks (CIDR, e.g., '10.0.0.0/8')" "" allowed_networks
}

# Configure safety
configure_safety() {
    print_msg "$BLUE" "\n=== Safety Configuration ==="

    get_input "Enable dry-run mode? (test without applying)" "yes" dry_run
    if [ "$dry_run" = "yes" ] || [ "$dry_run" = "y" ]; then
        dry_run_enabled=1
    else
        dry_run_enabled=0
    fi

    get_input "Enable verbose logging?" "no" verbose
    if [ "$verbose" = "yes" ] || [ "$verbose" = "y" ]; then
        verbose_enabled=1
    else
        verbose_enabled=0
    fi
}

# Write configuration
write_config() {
    print_msg "$BLUE" "\nWriting configuration..."

    # Copy template
    cp "$TEMPLATE_FILE" "$CONFIG_FILE"

    # Update configuration
    sed -i "s|ADMIN_IP=\"YOUR_IP_HERE\"|ADMIN_IP=\"$admin_ip\"|" "$CONFIG_FILE"
    sed -i "s|ADMIN_EMAIL=\"\"|ADMIN_EMAIL=\"$admin_email\"|" "$CONFIG_FILE"
    sed -i "s|SSH_PORT=22|SSH_PORT=$ssh_port|" "$CONFIG_FILE"
    sed -i "s|SSH_ALLOW_USERS=\"\"|SSH_ALLOW_USERS=\"$ssh_users\"|" "$CONFIG_FILE"
    sed -i "s|ENABLE_EMERGENCY_SSH=1|ENABLE_EMERGENCY_SSH=$emergency_enabled|" "$CONFIG_FILE"
    sed -i "s|EMERGENCY_SSH_PORT=2222|EMERGENCY_SSH_PORT=$emergency_port|" "$CONFIG_FILE"
    sed -i "s|HARDENING_LEVEL=\"standard\"|HARDENING_LEVEL=\"$hardening_level\"|" "$CONFIG_FILE"
    sed -i "s|ALLOWED_PORTS=\"\"|ALLOWED_PORTS=\"$allowed_ports\"|" "$CONFIG_FILE"
    sed -i "s|ALLOWED_NETWORKS=\"\"|ALLOWED_NETWORKS=\"$allowed_networks\"|" "$CONFIG_FILE"
    sed -i "s|DRY_RUN=0|DRY_RUN=$dry_run_enabled|" "$CONFIG_FILE"
    sed -i "s|VERBOSE=0|VERBOSE=$verbose_enabled|" "$CONFIG_FILE"

    print_msg "$GREEN" "✓ Configuration saved to $CONFIG_FILE"
}

# Show summary
show_summary() {
    print_msg "$BLUE" "\n=== Configuration Summary ==="
    echo "Admin IP:        $admin_ip"
    echo "SSH Port:        $ssh_port"
    echo "SSH Users:       $ssh_users"
    echo "Emergency SSH:   $([ $emergency_enabled -eq 1 ] && echo "Enabled on port $emergency_port" || echo "Disabled")"
    echo "Hardening Level: $hardening_level"
    echo "Dry Run:         $([ $dry_run_enabled -eq 1 ] && echo "Enabled" || echo "Disabled")"
    echo ""
}

# Run hardening
run_hardening() {
    print_msg "$BLUE" "\n=== Ready to Start Hardening ==="

    if [ $dry_run_enabled -eq 1 ]; then
        print_msg "$YELLOW" "⚠ DRY RUN MODE - No changes will be applied"
    else
        print_msg "$YELLOW" "⚠ WARNING: This will modify system configuration!"
    fi

    printf "\nProceed with hardening? (y/N): "
    read -r response

    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        print_msg "$GREEN" "\nStarting hardening process..."

        # Run orchestrator
        if [ -f "$SCRIPT_DIR/orchestrator.sh" ]; then
            sh "$SCRIPT_DIR/orchestrator.sh"
        else
            print_msg "$RED" "✗ Orchestrator script not found!"
            exit 1
        fi
    else
        print_msg "$YELLOW" "\nHardening cancelled. Configuration has been saved."
        print_msg "$BLUE" "To run hardening later, execute:"
        echo "  sudo sh orchestrator.sh"
    fi
}

# Show next steps
show_next_steps() {
    print_msg "$BLUE" "\n=== Next Steps ==="
    echo "1. Review the configuration:"
    echo "   cat $CONFIG_FILE"
    echo ""
    echo "2. Test with dry-run mode:"
    echo "   sudo sh orchestrator.sh --dry-run"
    echo ""
    echo "3. Run validation tests:"
    echo "   sudo sh tests/validation_suite.sh"
    echo ""
    echo "4. Apply hardening:"
    echo "   sudo sh orchestrator.sh"
    echo ""
    echo "5. In case of emergency:"
    echo "   sudo sh emergency-rollback.sh"
    echo ""

    if [ $emergency_enabled -eq 1 ]; then
        print_msg "$YELLOW" "Remember: Emergency SSH is available on port $emergency_port"
    fi

    print_msg "$GREEN" "\n✓ Quick start complete!"
}

# Main execution
main() {
    print_banner
    check_prerequisites

    if [ ! -f "$CONFIG_FILE" ]; then
        configure_basics
        configure_level
        configure_network
        configure_safety
        write_config
        show_summary
        run_hardening
    fi

    show_next_steps
}

# Run main
main "$@"