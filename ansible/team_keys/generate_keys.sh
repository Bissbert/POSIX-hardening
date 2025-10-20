#!/bin/sh
# POSIX Shell Server Hardening Toolkit
# SSH Key Generation Script
# Purpose: Generate Ansible automation key and shared team key
# Security: NEVER commit private keys to git!

set -e

# Configuration
KEYS_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_KEY="ansible_ed25519"
TEAM_KEY="team_shared_ed25519"
KEY_TYPE="ed25519"
KEY_BITS=""  # ed25519 has fixed size, no bits parameter needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo ""
    echo "${BLUE}============================================${NC}"
    echo "${BLUE}  SSH Key Generation for POSIX Hardening${NC}"
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

# Check if key exists
key_exists() {
    local key_name="$1"
    if [ -f "$KEYS_DIR/$key_name" ] || [ -f "$KEYS_DIR/${key_name}.pub" ]; then
        return 0
    fi
    return 1
}

# Generate a key pair
generate_key() {
    local key_name="$1"
    local key_comment="$2"
    local key_path="$KEYS_DIR/$key_name"

    print_info "Generating $key_name..."

    # Check if already exists
    if key_exists "$key_name"; then
        print_warning "Key $key_name already exists, skipping generation"
        print_warning "To regenerate, delete: $key_path and ${key_path}.pub"
        return 1
    fi

    # Generate key
    ssh-keygen -t "$KEY_TYPE" \
        -f "$key_path" \
        -C "$key_comment" \
        -N "" \
        -q

    # Set proper permissions
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    print_success "Generated $key_name"

    # Show fingerprint
    local fingerprint=$(ssh-keygen -lf "$key_path" | awk '{print $2}')
    print_info "Fingerprint: $fingerprint"

    return 0
}

# Display key information
display_key_info() {
    local key_name="$1"
    local key_path="$KEYS_DIR/$key_name"

    if [ ! -f "$key_path" ]; then
        print_error "Key not found: $key_path"
        return 1
    fi

    echo ""
    echo "${GREEN}Key: $key_name${NC}"
    echo "  Location: $key_path"
    echo "  Fingerprint: $(ssh-keygen -lf "$key_path" | awk '{print $2}')"
    echo "  Public Key: ${key_path}.pub"

    # Show permissions
    local perms=$(ls -l "$key_path" | awk '{print $1}')
    echo "  Permissions: $perms"
}

# Create README with distribution instructions
create_readme() {
    local readme_path="$KEYS_DIR/README.md"

    print_info "Creating distribution README..."

    cat > "$readme_path" <<'EOF'
# SSH Key Management for POSIX Hardening Toolkit

This directory contains SSH keys for accessing hardened servers.

## Key Types

### 1. Ansible Automation Key (`ansible_ed25519`)
**Purpose:** Used by Ansible controller for automated deployment and hardening.

**Usage:**
- Stored on Ansible controller machine
- Used in `ansible.cfg` or via `--private-key` parameter
- Should NOT be distributed to team members

**Security:**
- Private key NEVER leaves the Ansible controller
- Used only for automation, not human access

### 2. Shared Team Key (`team_shared_ed25519`)
**Purpose:** Shared among authorized team members for accessing ALL hardened servers.

**Distribution Process:**
1. Admin generates keys using `./generate_keys.sh`
2. Admin securely distributes `team_shared_ed25519` (private key) to team members
3. Team members store key securely and set permissions:
   ```bash
   chmod 600 team_shared_ed25519
   ```

**Usage by Team Members:**
```bash
# Connect to any hardened server
ssh -i ~/.ssh/team_shared_ed25519 root@server-hostname

# Or add to SSH config (~/.ssh/config):
Host hardened-*
    IdentityFile ~/.ssh/team_shared_ed25519
    User root
```

## Security Best Practices

### For Administrators

1. **Generate Keys Once:**
   ```bash
   cd ansible/team_keys
   ./generate_keys.sh
   ```

2. **Verify .gitignore Blocks Private Keys:**
   ```bash
   git status  # Should NOT show *_ed25519 files (only *.pub)
   ```

3. **Distribute Team Key Securely:**
   - Use encrypted channels (PGP, password-protected archives)
   - Use secure file sharing (not email/Slack)
   - Verify recipient identity before sending
   - Track who has received the key

4. **Rotate Keys Periodically:**
   - Recommended: Every 6-12 months
   - After team member departure
   - After suspected compromise

### For Team Members

1. **Protect Your Private Key:**
   ```bash
   chmod 600 ~/.ssh/team_shared_ed25519
   ```

2. **Never Share Your Private Key:**
   - Don't email it
   - Don't commit to git
   - Don't upload to cloud storage
   - Don't copy to untrusted machines

3. **Verify Key Fingerprint:**
   ```bash
   ssh-keygen -lf ~/.ssh/team_shared_ed25519
   ```
   Compare with fingerprint provided by admin.

4. **Use SSH Agent:**
   ```bash
   ssh-add ~/.ssh/team_shared_ed25519
   ssh root@server-hostname  # No -i needed
   ```

## Key Files in This Directory

### Safe to Commit to Git:
- ✅ `generate_keys.sh` - Key generation script
- ✅ `README.md` - This documentation
- ✅ `*.pub` - Public keys (safe to share)
- ✅ `.gitkeep` - Directory structure marker

### NEVER Commit to Git:
- ❌ `ansible_ed25519` - Ansible private key
- ❌ `team_shared_ed25519` - Team private key
- ❌ `*_rsa` - Any RSA private keys
- ❌ `*.pem` - Any PEM private keys

**Protection:** `.gitignore` is configured to block these files.

## Verification

### Check Key Fingerprints
```bash
# Ansible key
ssh-keygen -lf ansible_ed25519

# Team key
ssh-keygen -lf team_shared_ed25519
```

### Test Key Authentication
```bash
# Test Ansible key
ssh -i ansible_ed25519 -o PasswordAuthentication=no root@test-server

# Test team key
ssh -i team_shared_ed25519 -o PasswordAuthentication=no root@test-server
```

### Verify Git Ignores Private Keys
```bash
cd ../../  # Go to repo root
git status
# Should NOT show:
#   - ansible_ed25519
#   - team_shared_ed25519
```

## Troubleshooting

### "Permission denied (publickey)"

**Cause:** Key not deployed to server or wrong permissions.

**Solution:**
1. Verify key is in server's `~/.ssh/authorized_keys`
2. Check key permissions: `chmod 600 private_key`
3. Check authorized_keys permissions: `chmod 600 ~/.ssh/authorized_keys`
4. Use verbose mode: `ssh -vvv -i key_file user@host`

### "WARNING: UNPROTECTED PRIVATE KEY FILE!"

**Cause:** Private key permissions too open.

**Solution:**
```bash
chmod 600 team_shared_ed25519
```

### Keys Not Working After Hardening

**Cause:** SSH hardening disabled password authentication.

**Solution:**
1. Use emergency SSH port: `ssh -p 2222 root@server`
2. Manually add public key to authorized_keys
3. Exit and reconnect on port 22 with key

### Git Showing Private Keys

**Cause:** `.gitignore` not configured correctly.

**Solution:**
```bash
# Check .gitignore in repo root
cat ../../.gitignore | grep team_keys

# Should contain patterns blocking private keys
# If missing, update .gitignore
```

## Emergency Access

If you lose access to a hardened server:

1. **Emergency SSH Port (2222):**
   ```bash
   ssh -p 2222 root@server
   # This port allows password auth temporarily
   ```

2. **Console Access:**
   - Physical console
   - IPMI/iLO/iDRAC
   - Cloud provider console

3. **Recovery Script:**
   ```bash
   /opt/posix-hardening/emergency-rollback.sh
   ```

## Key Rotation Procedure

When rotating keys (recommended every 6-12 months):

1. **Generate New Keys:**
   ```bash
   # Backup old keys
   mv ansible_ed25519 ansible_ed25519.old
   mv team_shared_ed25519 team_shared_ed25519.old

   # Generate new keys
   ./generate_keys.sh
   ```

2. **Deploy New Keys:**
   - Run Ansible playbook to deploy new team key
   - Update Ansible controller with new automation key
   - Distribute new team key to members

3. **Remove Old Keys:**
   - Remove old public keys from all servers
   - Securely delete old private keys
   - Notify team of key rotation

4. **Verify Access:**
   - Test new keys work on all servers
   - Confirm old keys no longer work
   - Update documentation

## Support

For issues or questions:
- Check troubleshooting section above
- Review `/var/log/hardening/` on servers
- Consult main project documentation
- Open issue on GitHub repository

---

**Last Updated:** $(date +%Y-%m-%d)
**Key Type:** ed25519
**Key Size:** 256-bit (fixed for ed25519)
**Recommended Rotation:** Every 6-12 months
EOF

    print_success "Created README.md with distribution instructions"
}

# Main execution
main() {
    print_header

    print_info "Keys will be generated in: $KEYS_DIR"
    print_info "Key type: $KEY_TYPE (modern, secure)"
    echo ""

    # Warning about security
    print_warning "SECURITY REMINDER:"
    print_warning "- Private keys (*_ed25519) must NEVER be committed to git"
    print_warning "- .gitignore is configured to block them"
    print_warning "- Only public keys (*.pub) should be in version control"
    echo ""

    # Generate Ansible automation key
    print_header
    echo "${BLUE}Step 1: Ansible Automation Key${NC}"
    echo "This key is used by the Ansible controller for automated deployment."
    echo ""

    if generate_key "$ANSIBLE_KEY" "ansible-automation@posix-hardening"; then
        display_key_info "$ANSIBLE_KEY"
    fi

    # Generate shared team key
    print_header
    echo "${BLUE}Step 2: Shared Team Access Key${NC}"
    echo "This key will be shared among authorized team members."
    echo "One key grants access to ALL hardened servers."
    echo ""

    if generate_key "$TEAM_KEY" "team-access@posix-hardening"; then
        display_key_info "$TEAM_KEY"
    fi

    # Create README
    print_header
    create_readme

    # Create .gitkeep
    touch "$KEYS_DIR/.gitkeep"

    # Final summary
    print_header
    echo "${GREEN}Key Generation Complete!${NC}"
    echo ""
    echo "Generated Keys:"
    echo "  1. ${BLUE}$ANSIBLE_KEY${NC} - For Ansible automation"
    echo "  2. ${BLUE}$TEAM_KEY${NC} - For team member access"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "  ${YELLOW}1. Verify .gitignore blocks private keys:${NC}"
    echo "     cd ../.."
    echo "     git status  # Should NOT show *_ed25519 files"
    echo ""
    echo "  ${YELLOW}2. Commit public keys to git:${NC}"
    echo "     git add ansible/team_keys/*.pub"
    echo "     git add ansible/team_keys/README.md"
    echo "     git add ansible/team_keys/.gitkeep"
    echo "     git commit -m 'feat: add SSH team keys for centralized access'"
    echo ""
    echo "  ${YELLOW}3. Configure Ansible to use automation key:${NC}"
    echo "     # Add to ansible/ansible.cfg:"
    echo "     # private_key_file = team_keys/ansible_ed25519"
    echo ""
    echo "  ${YELLOW}4. Distribute team key securely:${NC}"
    echo "     # Send $TEAM_KEY to authorized team members"
    echo "     # Use encrypted channels (PGP, secure file sharing)"
    echo "     # See README.md for distribution guide"
    echo ""
    echo "  ${YELLOW}5. Deploy to servers:${NC}"
    echo "     # Run Ansible playbook to deploy team public key"
    echo "     ansible-playbook -i inventory.ini site.yml"
    echo ""

    print_warning "REMEMBER: Private keys must NEVER be committed to git!"
    print_info "Documentation: $KEYS_DIR/README.md"
    echo ""

    # Show what's safe to commit
    print_header
    echo "${GREEN}Safe to Commit (Public Keys):${NC}"
    ls -lh "$KEYS_DIR"/*.pub 2>/dev/null || echo "  (No public keys found)"
    echo ""
    echo "${RED}NEVER Commit (Private Keys):${NC}"
    ls -lh "$KEYS_DIR"/*_ed25519 2>/dev/null | grep -v ".pub" || echo "  (No private keys found)"
    echo ""

    # Prompt for local installation (optional)
    prompt_local_installation
}

# ============================================================================
# Local Installation Functions
# ============================================================================

# Install team key on local machine
install_team_key_locally() {
    local ssh_dir="$HOME/.ssh"
    local install_path="$ssh_dir/$TEAM_KEY"

    print_header
    echo "${BLUE}Installing Team Key Locally${NC}"
    echo ""

    # Ensure .ssh directory exists
    if [ ! -d "$ssh_dir" ]; then
        print_info "Creating .ssh directory..."
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi

    # Copy key
    print_info "Copying key to $install_path..."
    cp "$KEYS_DIR/$TEAM_KEY" "$install_path"
    chmod 600 "$install_path"
    print_success "Key installed to $install_path"

    # Add to ssh-agent
    print_info "Adding key to ssh-agent..."

    # Check if ssh-agent is running
    if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
        print_warning "ssh-agent not running, starting..."
        eval "$(ssh-agent -s)"
    fi

    # Add key to agent
    if ssh-add "$install_path" 2>/dev/null; then
        print_success "Key added to ssh-agent"
    else
        print_warning "Could not add key to ssh-agent (may require passphrase)"
    fi

    # Configure shell auto-load
    configure_shell_autoload "$install_path"

    # Show fingerprint
    local fingerprint=$(ssh-keygen -lf "$install_path" | awk '{print $2}')
    print_success "Key loaded with fingerprint: $fingerprint"

    echo ""
    print_success "Local installation complete!"
    echo ""
    print_info "You can now SSH to hardened servers without -i flag:"
    echo "  ${GREEN}ssh root@server-hostname${NC}"
    echo ""
}

# Configure shell to auto-load key on login
configure_shell_autoload() {
    local key_path="$1"
    local ssh_add_cmd="ssh-add -q $key_path 2>/dev/null || true"
    local added=0

    print_info "Configuring shell to auto-load key..."

    # Check for bash
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "$TEAM_KEY" "$HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$HOME/.bashrc"
            echo "# Auto-load team SSH key for hardened servers" >> "$HOME/.bashrc"
            echo "$ssh_add_cmd" >> "$HOME/.bashrc"
            print_success "Added to ~/.bashrc"
            added=1
        fi
    fi

    # Check for zsh
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q "$TEAM_KEY" "$HOME/.zshrc" 2>/dev/null; then
            echo "" >> "$HOME/.zshrc"
            echo "# Auto-load team SSH key for hardened servers" >> "$HOME/.zshrc"
            echo "$ssh_add_cmd" >> "$HOME/.zshrc"
            print_success "Added to ~/.zshrc"
            added=1
        fi
    fi

    # Fallback to .profile
    if [ $added -eq 0 ] && [ -f "$HOME/.profile" ]; then
        if ! grep -q "$TEAM_KEY" "$HOME/.profile" 2>/dev/null; then
            echo "" >> "$HOME/.profile"
            echo "# Auto-load team SSH key for hardened servers" >> "$HOME/.profile"
            echo "$ssh_add_cmd" >> "$HOME/.profile"
            print_success "Added to ~/.profile"
            added=1
        fi
    fi

    if [ $added -eq 0 ]; then
        print_warning "Could not detect shell profile for auto-load"
        print_info "Add this to your shell profile manually:"
        print_info "  $ssh_add_cmd"
    fi
}

# Prompt user for local installation
prompt_local_installation() {
    print_header
    echo "${YELLOW}[OPTIONAL] Install Team Key Locally?${NC}"
    echo ""
    echo "This will install the team key on THIS machine for automatic SSH access."
    echo ""
    echo "What it does:"
    echo "  ✓ Copy $TEAM_KEY to ~/.ssh/"
    echo "  ✓ Add to ssh-agent for automatic use"
    echo "  ✓ Configure shell to load key on login"
    echo "  ✓ Enable SSH access without -i flag"
    echo ""
    echo "After installation, you can connect to hardened servers:"
    echo "  ${GREEN}ssh root@server-hostname${NC}  ${BLUE}# No -i flag needed!${NC}"
    echo ""
    printf "${YELLOW}Install team key on this machine? (y/N): ${NC}"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            install_team_key_locally
            return 0
            ;;
        *)
            print_info "Skipping local installation"
            echo ""
            print_info "To install later:"
            echo "  ${BLUE}./install_team_key.sh $TEAM_KEY${NC}"
            echo ""
            print_info "Or manually:"
            echo "  cp $TEAM_KEY ~/.ssh/"
            echo "  chmod 600 ~/.ssh/$TEAM_KEY"
            echo "  ssh-add ~/.ssh/$TEAM_KEY"
            echo ""
            return 1
            ;;
    esac
}

# Run main function
main "$@"
