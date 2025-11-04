# POSIX Hardening Banner Role

Configure security warning banners for console and network logins.

## Description

This role configures login banners that display security warnings to users before and after authentication. It manages:

- `/etc/issue` - Console login banner (pre-authentication)
- `/etc/issue.net` - Network login banner (SSH, telnet - pre-authentication)
- `/etc/motd` - Message of the day (post-authentication)

## Converted From

Original shell script: `scripts/18-banner-warnings.sh`

## Features

- Configurable warning messages with legal disclaimers
- Organization and contact information in banners
- Removes OS/version information (security best practice)
- Customizable banner appearance (decorations, width)
- Backup of existing banners before changes
- Validation of banner content and permissions
- Idempotent - safe to run multiple times

## Requirements

- Ansible 2.9 or higher
- Root/sudo access on target hosts
- Supported OS: Debian, Ubuntu, RedHat, CentOS, Rocky, AlmaLinux, Kali

## Role Variables

### Control Flags

```yaml
posix_banner_force_reharden: false # Force re-apply even if already done
posix_banner_backup_before_changes: true # Backup existing banners
posix_banner_validate_after_apply: true # Validate after applying
```

### Banner Control

```yaml
posix_banner_enable_issue: true # Console login banner
posix_banner_enable_issue_net: true # Network login banner (SSH)
posix_banner_enable_motd: true # Message of the day
```

### Organization Info

```yaml
posix_banner_organization: "Your Organization"
posix_banner_contact: "security@example.com"
```

### Warning Text

```yaml
posix_banner_warning_title: "AUTHORIZED ACCESS ONLY"

posix_banner_warning_text: |
  Unauthorized access to this system is strictly prohibited.
  All activities are monitored and logged.

posix_banner_warning_footer: |
  By continuing to use this system you indicate your awareness of and
  consent to these terms and conditions of use. LOG OFF IMMEDIATELY if
  you do not agree to the conditions stated in this warning.
```

### Security Settings

```yaml
posix_banner_remove_os_info: true # Remove OS/kernel info from banners
posix_banner_file_mode: "0644" # Banner file permissions
```

### Appearance

```yaml
posix_banner_use_decorations: true # Use decorative borders
posix_banner_decoration_char: "#" # Border character
posix_banner_decoration_width: 63 # Banner width
posix_banner_include_org_info: true # Include org/contact info
```

### Custom Text

```yaml
posix_banner_custom_text: "" # Additional text to append
posix_banner_custom_motd: "" # Override default MOTD entirely
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
```

### Custom Organization

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_organization: "Acme Corporation"
        posix_banner_contact: "security@acme.com"
```

### Custom Warning Text

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_warning_text: |
          This system contains confidential information.
          Unauthorized access is prohibited and will be prosecuted.
          All access is logged and monitored.
        posix_banner_custom_text: |
          For access issues, contact: helpdesk@example.com
```

### Disable MOTD

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_enable_motd: false
```

### Simple Banners (No Decorations)

```yaml
- hosts: all
  become: true
  roles:
    - role: posix_hardening_banner
      vars:
        posix_banner_use_decorations: false
```

## Example Banner Output

### /etc/issue and /etc/issue.net

```text
###############################################################
#              AUTHORIZED ACCESS ONLY                        #
###############################################################

Unauthorized access to this system is strictly prohibited.
All activities are monitored and logged.

By continuing to use this system you indicate your awareness of and
consent to these terms and conditions of use. LOG OFF IMMEDIATELY if
you do not agree to the conditions stated in this warning.

Organization: Your Organization
Contact: security@example.com
###############################################################
```

### /etc/motd

```text
WARNING: This system is for authorized use only.
All activities are subject to monitoring and logging.
Disconnect immediately if you are not an authorized user.

Organization: Your Organization
Contact: security@example.com
```

## What Gets Backed Up

Before making changes, the role backs up:

- `/etc/issue` → `/var/backups/hardening/issue.backup.<timestamp>`
- `/etc/issue.net` → `/var/backups/hardening/issue.net.backup.<timestamp>`
- `/etc/motd` → `/var/backups/hardening/motd.backup.<timestamp>`

## Validation

The role validates:

1. Banner files exist
2. Correct permissions (0644, root:root)
3. Files contain warning text
4. No OS information leaked (when `posix_banner_remove_os_info: true`)

## Tags

- `banner` - All banner tasks
- `warning` - Display warning messages
- `check` - Check if already applied
- `preparation` - Phase 1 tasks
- `apply` - Phase 2 tasks (apply changes)
- `validate` - Phase 3 tasks (validation)
- `finalization` - Phase 4 tasks (marker file)
- `issue` - Console banner tasks
- `issue_net` - Network banner tasks
- `motd` - MOTD tasks

### Tag Usage Examples

```bash
# Apply only issue banner
ansible-playbook site.yml --tags issue

# Apply all banners but skip validation
ansible-playbook site.yml --tags apply --skip-tags validate

# Only validate (if already applied)
ansible-playbook site.yml --tags validate
```

## Security Considerations

1. **No OS Information**: By default, banners do NOT include OS name, version, kernel info, or hostname. This prevents
   information disclosure to attackers.

2. **Legal Protection**: The warning text establishes that users have no expectation of privacy and that all activity is
   monitored. Consult your legal team for appropriate language.

3. **Permissions**: Banner files are world-readable (0644) as required by the system, but owned by root to prevent
   tampering.

4. **Pre-Authentication**: `issue` and `issue.net` are shown BEFORE login, so they apply even to unauthorized access
   attempts.

5. **Post-Authentication**: `motd` is shown AFTER login, reminding authorized users of their responsibilities.

## Compliance

This role helps meet requirements from:

- **CIS Benchmark**: 1.7.1 Ensure message of the day is configured properly
- **CIS Benchmark**: 1.7.2 Ensure local login warning banner is configured properly
- **CIS Benchmark**: 1.7.3 Ensure remote login warning banner is configured properly
- **STIG**: Banner requirements for authorized use warnings

## Troubleshooting

### Banner not showing on SSH

Check `/etc/ssh/sshd_config`:

```bash
grep Banner /etc/ssh/sshd_config
```

Should show:

```text
Banner /etc/issue.net
```

Restart SSH if needed:

```bash
systemctl restart sshd
```

### MOTD not showing

Some distributions use dynamic MOTD generation. Check:

```bash
ls -la /etc/update-motd.d/
```

You may need to disable dynamic MOTD scripts to see your custom MOTD.

### Banner shows OS information

If you still see OS info, check:

```bash
cat /etc/issue
```

The role should have removed escape sequences like `\S`, `\n`, `\r`, etc. If they remain, set:

```yaml
posix_banner_remove_os_info: true
posix_banner_force_reharden: true
```

## File Locations

- Templates: `templates/issue.j2`, `templates/issue.net.j2`, `templates/motd.j2`
- Backups: `/var/backups/hardening/`
- Logs: `/var/log/hardening/banner-hardening.log`
- Marker: `/var/lib/hardening/banner_hardened`

## License

MIT

## Author Information

POSIX Hardening Team - Security Operations
