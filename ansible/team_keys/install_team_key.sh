#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# Team SSH Key Installation Script
# Purpose: Install team shared key on local machine for automatic SSH access
# Usage: ./install_team_key.sh <path_to_team_shared_ed25519>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SSH_DIR="$HOME/.ssh"
KEY_NAME="team_shared_ed25519"
INSTALL_PATH="$SSH_DIR/$KEY_NAME"

# Helper functions
print_header() {
    echo ""
    echo "${BLUE}============================================${NC}"
    echo "${BLUE}  Team SSH Key Installation${NC}"
    echo "${BLUE}============================================${NC}"
    echo ""
}

print_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Check if SSH directory exists
ensure_ssh_directory() {
    if [ ! -d "$SSH_DIR" ]; then
        print_info "Creating .ssh directory..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        print_success "Created $SSH_DIR"
    fi

    # Verify permissions
    current_perms=$(stat -f "%A" "$SSH_DIR" 2>/dev/null || stat -c "%a" "$SSH_DIR" 2>/dev/null)
    if [ "$current_perms" != "700" ]; then
        print_warning ".ssh directory has insecure permissions ($current_perms), fixing..."
        chmod 700 "$SSH_DIR"
    fi
}

# Install the key
install_key() {
    local source_key="$1"

    if [ ! -f "$source_key" ]; then
        print_error "Key file not found: $source_key"
        return 1
    fi

    # Check if it's a private key (not .pub)
    if echo "$source_key" | grep -q "\.pub$"; then
        print_error "This appears to be a public key (.pub file)"
        print_error "Please provide the private key file (without .pub extension)"
        return 1
    fi

    # Verify key format
    if ! ssh-keygen -l -f "$source_key" >/dev/null 2>&1; then
        print_error "File does not appear to be a valid SSH key"
        return 1
    fi

    # Check if key already installed
    if [ -f "$INSTALL_PATH" ]; then
        local existing_fp=$(ssh-keygen -lf "$INSTALL_PATH" 2>/dev/null | awk '{print $2}')
        local new_fp=$(ssh-keygen -lf "$source_key" 2>/dev/null | awk '{print $2}')

        if [ "$existing_fp" = "$new_fp" ]; then
            print_warning "Key already installed with same fingerprint"
            return 0
        else
            print_warning "Different key already exists at $INSTALL_PATH"
            printf "Overwrite? (y/N): "
            read -r response
            case "$response" in
                [yY][eE][sS]|[yY])
                    print_info "Overwriting existing key..."
                    ;;
                *)
                    print_info "Keeping existing key"
                    return 1
                    ;;
            esac
        fi
    fi

    # Copy key
    print_info "Installing key to $INSTALL_PATH..."
    cp "$source_key" "$INSTALL_PATH"
    chmod 600 "$INSTALL_PATH"
    print_success "Key installed"

    # Show fingerprint
    local fingerprint=$(ssh-keygen -lf "$INSTALL_PATH" | awk '{print $2}')
    print_info "Fingerprint: $fingerprint"
}

# Add key to SSH agent
add_to_agent() {
    print_info "Adding key to ssh-agent..."

    # Check if ssh-agent is running
    if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
        print_warning "ssh-agent not running, starting..."
        eval "$(ssh-agent -s)"
        print_success "Started ssh-agent"
    fi

    # Add key to agent
    if ssh-add "$INSTALL_PATH" 2>/dev/null; then
        print_success "Key added to ssh-agent"
    else
        print_warning "Could not add key to ssh-agent (may require passphrase)"
        print_info "Try manually: ssh-add $INSTALL_PATH"
    fi

    # Verify key is loaded
    if ssh-add -l 2>/dev/null | grep -q "$KEY_NAME"; then
        print_success "Key verified in agent"
    fi
}

# Configure shell to auto-load key
configure_shell_autoload() {
    print_info "Configuring shell to auto-load key on login..."

    local ssh_add_cmd="ssh-add -q $INSTALL_PATH 2>/dev/null || true"
    local added_to_shell=0

    # Detect shell and configure appropriate profile
    if [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
        local bashrc="$HOME/.bashrc"
        if ! grep -q "$KEY_NAME" "$bashrc" 2>/dev/null; then
            echo "" >> "$bashrc"
            echo "# Auto-load team SSH key for hardened servers" >> "$bashrc"
            echo "$ssh_add_cmd" >> "$bashrc"
            print_success "Added to ~/.bashrc"
            added_to_shell=1
        fi
    fi

    if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
        local zshrc="$HOME/.zshrc"
        if ! grep -q "$KEY_NAME" "$zshrc" 2>/dev/null; then
            echo "" >> "$zshrc"
            echo "# Auto-load team SSH key for hardened servers" >> "$zshrc"
            echo "$ssh_add_cmd" >> "$zshrc"
            print_success "Added to ~/.zshrc"
            added_to_shell=1
        fi
    fi

    # Fallback to .profile
    if [ $added_to_shell -eq 0 ]; then
        local profile="$HOME/.profile"
        if ! grep -q "$KEY_NAME" "$profile" 2>/dev/null; then
            echo "" >> "$profile"
            echo "# Auto-load team SSH key for hardened servers" >> "$profile"
            echo "$ssh_add_cmd" >> "$profile"
            print_success "Added to ~/.profile"
            added_to_shell=1
        fi
    fi

    if [ $added_to_shell -eq 0 ]; then
        print_warning "Could not detect shell profile"
        print_info "Add this to your shell profile manually:"
        print_info "  $ssh_add_cmd"
    fi
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."

    local checks_passed=0
    local checks_total=3

    # Check 1: Key file exists with correct permissions
    if [ -f "$INSTALL_PATH" ]; then
        local perms=$(stat -f "%A" "$INSTALL_PATH" 2>/dev/null || stat -c "%a" "$INSTALL_PATH" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            print_success "✓ Key file exists with correct permissions (600)"
            checks_passed=$((checks_passed + 1))
        else
            print_error "✗ Key file has incorrect permissions ($perms)"
        fi
    else
        print_error "✗ Key file not found at $INSTALL_PATH"
    fi

    # Check 2: Key loaded in agent
    if ssh-add -l 2>/dev/null | grep -q "$KEY_NAME"; then
        print_success "✓ Key loaded in ssh-agent"
        checks_passed=$((checks_passed + 1))
    else
        print_warning "✗ Key not loaded in ssh-agent"
        print_info "  Load manually: ssh-add $INSTALL_PATH"
    fi

    # Check 3: Shell profile configured
    if grep -q "$KEY_NAME" "$HOME/.bashrc" 2>/dev/null || \
       grep -q "$KEY_NAME" "$HOME/.zshrc" 2>/dev/null || \
       grep -q "$KEY_NAME" "$HOME/.profile" 2>/dev/null; then
        print_success "✓ Shell profile configured for auto-load"
        checks_passed=$((checks_passed + 1))
    else
        print_warning "✗ Shell profile not configured"
    fi

    echo ""
    if [ $checks_passed -eq $checks_total ]; then
        print_success "All checks passed! ($checks_passed/$checks_total)"
        return 0
    else
        print_warning "Some checks failed ($checks_passed/$checks_total)"
        return 1
    fi
}

# Show usage instructions
show_usage() {
    print_header
    echo "Usage: $0 <path_to_team_shared_ed25519>"
    echo ""
    echo "This script installs the team shared SSH key on your local machine"
    echo "and configures automatic loading via ssh-agent."
    echo ""
    echo "What it does:"
    echo "  1. Copies key to ~/.ssh/$KEY_NAME"
    echo "  2. Sets correct permissions (600)"
    echo "  3. Adds key to ssh-agent"
    echo "  4. Configures shell to auto-load key on login"
    echo ""
    echo "After installation, you can SSH to hardened servers without -i flag:"
    echo "  ssh root@server-hostname"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/team_shared_ed25519"
    echo "  $0 ./team_shared_ed25519"
    echo ""
}

# Main execution
main() {
    # Check arguments
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    local source_key="$1"

    print_header

    print_info "Installing team SSH key for automatic access to hardened servers"
    echo ""

    # Ensure SSH directory exists
    ensure_ssh_directory

    # Install the key
    if ! install_key "$source_key"; then
        print_error "Key installation failed"
        exit 1
    fi

    # Add to SSH agent
    add_to_agent

    # Configure shell auto-load
    configure_shell_autoload

    # Verify installation
    echo ""
    verify_installation

    # Final instructions
    print_header
    echo "${GREEN}Installation Complete!${NC}"
    echo ""
    echo "The team SSH key is now installed and configured."
    echo ""
    echo "What this means:"
    echo "  ✓ Key stored at: $INSTALL_PATH"
    echo "  ✓ Key loaded in ssh-agent (current session)"
    echo "  ✓ Key will auto-load in new terminal sessions"
    echo ""
    echo "You can now SSH to hardened servers without -i flag:"
    echo "  ${BLUE}ssh root@server-hostname${NC}"
    echo ""
    echo "To verify key is loaded:"
    echo "  ${BLUE}ssh-add -l${NC}"
    echo ""
    echo "To test SSH connection:"
    echo "  ${BLUE}ssh -o PasswordAuthentication=no root@server-hostname${NC}"
    echo ""

    print_info "Key fingerprint for verification:"
    ssh-keygen -lf "$INSTALL_PATH"
    echo ""
}

# Run main
main "$@"
