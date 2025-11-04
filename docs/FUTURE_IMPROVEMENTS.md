# Future Improvements for POSIX Hardening Toolkit

This document tracks planned enhancements and feature requests for future releases.

---

## Firewall: Support for Alternative Firewall Tools

**Priority:** Medium
**Complexity:** High
**Status:** Planned

### Overview
Enhance the firewall setup script (02-firewall-setup.sh) to automatically detect and use alternative firewall management tools when iptables is not available.

### Current Behavior
- Only supports iptables
- When iptables is missing, skips firewall configuration entirely
- Users on systems with UFW, firewalld, or nftables must configure manually

### Proposed Solution
Implement automatic detection and configuration for multiple firewall backends:
- **iptables** (current - highest priority)
- **UFW** (Uncomplicated Firewall - Ubuntu/Debian)
- **firewalld** (Red Hat/CentOS/Fedora)
- **nftables** (modern replacement for iptables)

### Implementation Plan

#### 1. Firewall Detection
Add `detect_firewall()` function:
```sh
detect_firewall() {
    if command -v iptables >/dev/null 2>&1; then
        echo "iptables"
        return 0
    elif command -v ufw >/dev/null 2>&1; then
        echo "ufw"
        return 0
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewalld"
        return 0
    elif command -v nft >/dev/null 2>&1; then
        echo "nftables"
        return 0
    else
        return 1
    fi
}
```

#### 2. UFW Implementation
Key commands needed:
```sh
# Enable and set defaults
ufw --force enable
ufw default deny incoming
ufw default allow outgoing

# Allow SSH with rate limiting
ufw limit $SSH_PORT/tcp

# Allow admin IP
ufw allow from $ADMIN_IP

# Allow additional ports
ufw allow $PORT/tcp

# Status
ufw status numbered
```

**Safety timeout:** `ufw --force disable && ufw default allow incoming`

#### 3. firewalld Implementation
Key commands needed:
```sh
# Start service
systemctl start firewalld

# Add SSH
firewall-cmd --permanent --add-port=$SSH_PORT/tcp

# Add admin IP rich rule
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="$ADMIN_IP" accept'

# Add ports
firewall-cmd --permanent --add-port=$PORT/tcp

# Reload
firewall-cmd --reload
```

**Safety timeout:** `firewall-cmd --panic-on` (blocks all traffic) or `firewall-cmd --set-default-zone=trusted`

#### 4. nftables Implementation
Key commands needed:
```sh
# Create table and chains
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }

# Add rules
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input iif lo accept
nft add rule inet filter input tcp dport $SSH_PORT accept
nft add rule inet filter input ip saddr $ADMIN_IP accept

# Save
nft list ruleset > /etc/nftables.conf
systemctl enable nftables
```

**Safety timeout:** `nft flush ruleset && nft add table inet filter && nft add chain inet filter input { type filter hook input priority 0 \; policy accept \; }`

#### 5. Unified Interface
Create abstraction layer:
```sh
apply_firewall_rules() {
    local fw_type="$1"

    case "$fw_type" in
        iptables)
            apply_firewall_rules_iptables
            ;;
        ufw)
            apply_firewall_rules_ufw
            ;;
        firewalld)
            apply_firewall_rules_firewalld
            ;;
        nftables)
            apply_firewall_rules_nftables
            ;;
    esac
}
```

### Security Policy (Consistent Across All Backends)
All implementations must enforce:
- ✅ SSH port allowed (with rate limiting if possible)
- ✅ Admin IP priority access
- ✅ Established/related connections allowed
- ✅ Loopback interface allowed
- ✅ ICMP (ping) with rate limiting
- ✅ Additional configured ports
- ✅ Default deny incoming
- ✅ Default allow outgoing
- ✅ Dropped packet logging

### Backup/Rollback Requirements
Each backend needs backup functions:
- **UFW:** `ufw status numbered > backup.txt`
- **firewalld:** `firewall-cmd --list-all-zones > backup.txt`
- **nftables:** `nft list ruleset > backup.nft`
- **iptables:** `iptables-save > backup.rules` (current)

### Safety Timeout Requirements
Critical for preventing lockout:
- Must work with all backends
- Must reset firewall to permissive state after timeout
- Should preserve SSH access during timeout
- Timeout value: 300 seconds (configurable)

### Distribution Compatibility

| Firewall   | Common On                    | Status          |
|------------|------------------------------|-----------------|
| iptables   | Legacy/Traditional Linux     | ✅ Implemented  |
| UFW        | Ubuntu, Debian, Mint         | 📋 Planned      |
| firewalld  | RHEL, CentOS, Fedora, Rocky  | 📋 Planned      |
| nftables   | Modern Linux (kernel 3.13+)  | 📋 Planned      |

### Testing Requirements
- [ ] Test UFW on Ubuntu 22.04/24.04
- [ ] Test firewalld on RHEL 8/9, Rocky 9
- [ ] Test nftables on Debian 12
- [ ] Test iptables (regression testing)
- [ ] Test dry-run mode for all backends
- [ ] Test safety timeout for all backends
- [ ] Test rollback for all backends
- [ ] Test with no firewall available (graceful skip)

### Benefits
- ✅ Broader Linux distribution support
- ✅ Automatic detection and configuration
- ✅ Same security policy regardless of backend
- ✅ Maintains safety mechanisms (timeout, rollback)
- ✅ No manual configuration needed
- ✅ Graceful fallback when no firewall available

### Challenges
- 🔴 **Complexity:** Each firewall has different syntax
- 🟡 **Testing:** Requires multiple test environments
- 🟡 **Maintenance:** Must keep pace with firewall tool updates
- 🟡 **Feature parity:** Not all features available in all tools
- 🟡 **Safety:** Must ensure lockout prevention works for all

### Resources Needed
- Test VMs for each distribution type
- Documentation for each firewall tool
- Community testing and feedback
- Time for thorough testing

### Estimated Effort
- Research and design: 4 hours
- Implementation: 8-12 hours
- Testing: 6-8 hours
- Documentation: 2 hours
- **Total: ~20-26 hours**

### Migration Path
1. Implement UFW support first (most common alternative)
2. Add firewalld support (RHEL/CentOS users)
3. Add nftables support (future-proofing)
4. Gather community feedback
5. Refine and stabilize

### Related Issues
- Current script skips firewall on systems without iptables
- Users must manually configure alternative firewalls
- Inconsistent security posture across different systems

### Contributors Welcome
This is a great feature for community contribution! If you have experience with UFW, firewalld, or nftables, please consider contributing.

---

## Other Future Improvements

### 1. IPv6 Complete Support
**Priority:** Medium
**Status:** Partial (iptables only)

Ensure all firewall backends have full IPv6 support matching IPv4 policies.

### 2. Custom Port Ranges
**Priority:** Low
**Status:** Planned

Allow configuration like `ALLOWED_PORTS="8000-8100"` for port ranges.

### 3. Dynamic Firewall Updates
**Priority:** Low
**Status:** Planned

Allow adding/removing firewall rules without full reconfiguration.

### 4. Firewall Testing Mode
**Priority:** Medium
**Status:** Planned

Add `--test-firewall` flag to validate rules without applying them.

### 5. Integration with fail2ban
**Priority:** Medium
**Status:** Planned

Coordinate with fail2ban for enhanced brute-force protection.

---

**Last Updated:** 2025-10-20
**Maintainer:** POSIX Hardening Team
