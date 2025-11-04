# Security Policy

## Overview

The POSIX Shell Server Hardening Toolkit is designed to improve server security, so we take security vulnerabilities in this project very seriously. This document outlines our security policy and how to report vulnerabilities.

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          | Notes |
| ------- | ------------------ | ----- |
| main    | :white_check_mark: | Latest development version |
| 1.0.x   | :white_check_mark: | Current stable release |
| < 1.0   | :x:                | Please upgrade to 1.0.x |

## Reporting a Vulnerability

**⚠️ IMPORTANT: Do NOT open public issues for security vulnerabilities!**

### For Security Vulnerabilities

Please use **GitHub Security Advisories** to report vulnerabilities privately:

1. Go to: [https://github.com/Bissbert/POSIX-hardening/security/advisories/new](https://github.com/Bissbert/POSIX-hardening/security/advisories/new)
2. Click "New draft security advisory"
3. Provide as much detail as possible (see details below)

### Alternative Reporting Method

If you cannot use Security Advisories, you can:
- Email: <!-- MAINTAINER: Add security contact email -->
- Use PGP encryption if sending sensitive details
- Public PGP key: <!-- MAINTAINER: Add PGP key fingerprint if applicable -->

### What to Include in Your Report

Please include the following information:

**Vulnerability Details:**
- Description of the vulnerability
- Type of vulnerability (see categories below)
- Affected components (scripts, functions, lines of code)
- Affected versions

**Impact Assessment:**
- What can an attacker do with this vulnerability?
- What access or privileges are required to exploit it?
- Estimated severity (Critical/High/Medium/Low)

**Reproduction:**
- Step-by-step instructions to reproduce the issue
- Proof-of-concept code (if applicable)
- Environment details (OS, shell, deployment method)

**Suggested Fix:**
- Your recommended mitigation or fix (if you have one)
- Any workarounds that can be implemented immediately

## Vulnerability Categories

We are particularly interested in the following types of security issues:

### Critical
- Remote code execution
- Authentication bypass
- Privilege escalation leading to root access
- SSH lockout vulnerability (prevents recovery)
- Firewall bypass allowing unrestricted access
- Secrets or credentials in code/logs

### High
- Command injection vulnerabilities
- Path traversal attacks
- Information disclosure of sensitive data
- Denial of service affecting critical services
- Insecure default configurations
- Bypassing safety mechanisms (backups, rollbacks)

### Medium
- Local privilege escalation
- Weak cryptographic algorithms
- Race conditions
- Input validation issues
- Logging sensitive information

### Low
- Information disclosure (non-sensitive)
- Configuration issues with minimal impact
- Minor denial of service
- Outdated dependencies (if no known exploits)

## Response Timeline

Our security response process:

1. **Acknowledgment:** Within 48 hours of receiving your report
2. **Initial Assessment:** Within 5 business days
3. **Status Update:** Every 7 days until resolved
4. **Fix Development:** Depending on severity (Critical: <7 days, High: <14 days, Medium: <30 days)
5. **Security Advisory:** Published when fix is ready
6. **Public Disclosure:** Coordinated with reporter (typically 90 days after fix is available)

## Security Update Process

When we release a security fix:

1. **Private Fix:** Security fixes are developed privately
2. **Advisory Draft:** Security advisory is created
3. **Version Release:** New version with fix is released
4. **Public Advisory:** Advisory is published with CVE (if applicable)
5. **User Notification:** Users are notified via:
   - GitHub Security Advisories
   - GitHub Releases with security tag
   - README security note

## Security Best Practices for Users

When using this toolkit:

### Before Running

1. **Review the Code:**
   - This is a security-focused project - review scripts before execution
   - Check for any modifications if obtained from third parties
   - Verify git signatures (if available)

2. **Test in a Safe Environment:**
   - Always test in a VM or container first
   - Use `DRY_RUN=1` for simulation mode
   - Have console/IPMI access available

3. **Backup Everything:**
   - Full system backup before hardening
   - Verify backups are restorable
   - Document recovery procedures

4. **Set Configuration Carefully:**
   - Review `config/defaults.conf` or `ansible/group_vars/all.yml`
   - Ensure `ADMIN_IP` is set correctly
   - Verify `SSH_ALLOW_USERS` includes your account
   - Enable `SAFETY_MODE=1` (should never be disabled)

### During Execution

1. **Monitor Execution:**
   - Watch for errors in real-time
   - Keep SSH session alive
   - Have emergency access ready (port 2222 if enabled)

2. **Verify SSH Access:**
   - Test SSH connection before and after each critical change
   - Keep an existing SSH session open
   - Have console access ready as backup

3. **Check Logs:**
   - Monitor `/var/log/hardening/` during execution
   - Review rollback logs if issues occur
   - Save logs for troubleshooting

### After Execution

1. **Validate Configuration:**
   - Run `tests/validation_suite.sh`
   - Verify all services are running
   - Test firewall rules carefully
   - Confirm SSH access from all required locations

2. **Security Audit:**
   - Review actual changes made
   - Verify no unintended side effects
   - Check that security controls are active
   - Scan for any configuration issues

3. **Documentation:**
   - Document all changes made
   - Note any custom configurations
   - Record recovery procedures
   - Keep backups accessible

## Known Security Considerations

### By Design

These are intentional behaviors, not vulnerabilities:

1. **Requires Root Access:**
   - Toolkit requires root privileges to modify system configuration
   - This is necessary for security hardening
   - Mitigation: Review code before running with root

2. **Emergency SSH Access:**
   - Creates temporary SSH on port 2222 with password auth (if enabled)
   - Intended for emergency recovery
   - Mitigation: Remove after successful deployment (`REMOVE_EMERGENCY_SSH=1`)

3. **Temporary Firewall Bypass:**
   - 5-minute window during firewall setup
   - Prevents permanent lockout
   - Mitigation: Auto-rollback minimizes exposure window

4. **Backup Contains Sensitive Data:**
   - Backups include SSH configs and potentially sensitive files
   - Necessary for rollback functionality
   - Mitigation: Secure `/var/backups/hardening/` with appropriate permissions

### Dependencies

This toolkit has minimal external dependencies:

**Required:**
- POSIX shell (`sh`, `dash`, or `bash`)
- Standard POSIX utilities (awk, sed, grep, etc.)
- Root access

**Optional:**
- Ansible (for multi-server deployment)
- Docker (for testing)
- nmap (for inventory generation)

We do not use external package managers (npm, pip, etc.) in the core scripts to minimize supply chain risks.

## Security Features

This toolkit includes multiple safety mechanisms:

1. **SSH Preservation:**
   - Parallel SSH testing before changes
   - Automatic rollback if SSH fails
   - Emergency SSH port with password auth (optional)

2. **Automatic Rollback:**
   - Transaction-based operations
   - Automatic rollback on failure
   - 60-second timeout for SSH disconnect
   - 5-minute timeout for firewall changes

3. **Backup System:**
   - Automatic backups before all changes
   - Timestamped snapshots
   - One-command restoration

4. **Validation:**
   - Pre-flight checks before execution
   - Post-execution validation suite
   - Configuration syntax validation

5. **Logging:**
   - Comprehensive execution logs
   - Rollback operation logs
   - Audit trail of all changes

## Responsible Disclosure

We follow coordinated vulnerability disclosure:

1. **Private Reporting:** Vulnerabilities are reported privately
2. **Fix Development:** Fixes are developed without public disclosure
3. **Vendor Notification:** Affected parties are notified before public release
4. **Public Disclosure:** Coordinated release (typically 90 days after fix)
5. **Credit:** Security researchers are credited (if desired)

## Security Hall of Fame

We appreciate security researchers who help us improve this project. Contributors who responsibly disclose vulnerabilities will be listed here (with permission):

<!-- MAINTAINER: Add security researchers who have helped -->

---

## Additional Resources

- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)

---

**Last Updated:** 2025-01-04
**Policy Version:** 1.0
