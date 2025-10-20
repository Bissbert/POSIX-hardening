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
